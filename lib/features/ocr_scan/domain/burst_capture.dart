import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:image/image.dart' as im;

/// Small holder instead of using tuple-like structures.
class _Candidate {
  final String path;
  final double score;
  _Candidate(this.path, this.score);
}

/// Capture a short burst, compute a sharpness score for each frame,
/// and return the path of the sharpest image. Returns `null` if we
/// couldn’t capture or decode any frame.
///
/// - [count]: number of frames in the burst
/// - [gap]: small delay between frames to let AF settle a bit
Future<String?> captureBurstAndPickSharpest(
    CameraController controller, {
      int count = 3,
      Duration gap = const Duration(milliseconds: 120),
    }) async {
  if (!controller.value.isInitialized) return null;

  final List<_Candidate> frames = [];

  for (var i = 0; i < count; i++) {
    final XFile xf = await controller.takePicture();
    final file = File(xf.path);

    try {
      final bytes = await file.readAsBytes();
      final img = im.decodeImage(bytes);
      if (img != null) {
        final score = _sharpnessScoreTenengrad(img);
        frames.add(_Candidate(xf.path, score));
      } else {
        // If decode failed, still keep the frame with a tiny score
        frames.add(_Candidate(xf.path, 0));
      }
    } catch (_) {
      // If anything goes wrong, ignore this frame
    }

    if (i + 1 < count) {
      await Future.delayed(gap);
    }
  }

  if (frames.isEmpty) return null;

  // Pick the highest score
  frames.sort((a, b) => b.score.compareTo(a.score));
  return frames.first.path;
}

/// Tenengrad sharpness (gradient magnitude) on a downscaled, grayscale image.
/// This avoids using advanced filters from the image package and works
/// with plain pixel reads.
double _sharpnessScoreTenengrad(im.Image src) {
  // Downscale to speed up (and reduce noise sensitivity)
  final int targetW = 320;
  final im.Image small = (src.width > targetW)
      ? im.copyResize(src, width: targetW)
      : im.Image.from(src); // copy

  final im.Image gray = im.grayscale(small);

  double sum = 0;
  int n = 0;

  // Skip borders; sample every 2px to save time
  for (int y = 1; y < gray.height - 1; y += 2) {
    for (int x = 1; x < gray.width - 1; x += 2) {
      final double gx = _lum(gray, x + 1, y) - _lum(gray, x - 1, y);
      final double gy = _lum(gray, x, y + 1) - _lum(gray, x, y - 1);
      final double mag2 = gx * gx + gy * gy; // magnitude^2
      sum += mag2;
      n++;
    }
  }

  if (n == 0) return 0;
  return sum / n; // average gradient energy
}

/// Luminance of pixel at (x, y) using simple RGB weights.
/// Works with image 4.x Pixel API (r/g/b ints 0..255).
double _lum(im.Image img, int x, int y) {
  final px = img.getPixel(x, y);
  final r = px.r.toDouble();
  final g = px.g.toDouble();
  final b = px.b.toDouble();
  return 0.299 * r + 0.587 * g + 0.114 * b;
}
