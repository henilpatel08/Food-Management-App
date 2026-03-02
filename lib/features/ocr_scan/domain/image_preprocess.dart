import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as im;

/// Int-only rectangle to avoid double→int warnings everywhere.
class IntRect {
  final int left;
  final int top;
  final int width;
  final int height;

  const IntRect({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  int get right => left + width;
  int get bottom => top + height;
  bool get isValid => width > 0 && height > 0;
}

/// Preprocess an image for OCR and return a JPEG as bytes.
/// - [cropRectInImage] must be in **image pixels** (ints).
/// - Steps: optional crop → resize → grayscale → contrast stretch → unsharp.
Future<Uint8List?> preprocessForOcr(
    String srcPath, {
      IntRect? cropRectInImage,
      int maxDim = 1600,
    }) async {
  try {
    final bytes = await File(srcPath).readAsBytes();
    final input = im.decodeImage(bytes);
    if (input == null) return null;

    // 1) Crop (int rect)
    im.Image work = input;
    if (cropRectInImage != null && cropRectInImage.isValid) {
      final r = _clampIntRectToImage(cropRectInImage, input.width, input.height);
      if (r.isValid) {
        work = im.copyCrop(
          input,
          x: r.left,
          y: r.top,
          width: r.width,
          height: r.height,
        );
      }
    }

    // 2) Resize (ints only)
    final int w = work.width;
    final int h = work.height;
    final int longer = (w > h) ? w : h;
    if (longer > maxDim) {
      final int targetW = ((w * maxDim) / longer).round();
      work = im.copyResize(work, width: targetW); // keeps aspect ratio
    }

    // 3) Grayscale
    work = im.grayscale(work);

    // 4) Contrast stretch (1% clip)
    _contrastStretchInPlace(work, clipPercent: 1);

    // 5) Gentle unsharp: int radius, cast amount safely when used
    work = _unsharp(work, radius: 1, amount: 0.85);

    final out = im.encodeJpg(work, quality: 90);
    return Uint8List.fromList(out);
  } catch (_) {
    return null;
  }
}

/// Same as [preprocessForOcr] but writes a temp jpg and returns the path.
Future<String?> preprocessForOcrToTemp(
    String srcPath, {
      IntRect? cropRectInImage,
      int maxDim = 1600,
    }) async {
  final data = await preprocessForOcr(
    srcPath,
    cropRectInImage: cropRectInImage,
    maxDim: maxDim,
  );
  if (data == null) return null;

  final String outPath =
      '${Directory.systemTemp.path}/ocr_${DateTime.now().microsecondsSinceEpoch}.jpg';
  await File(outPath).writeAsBytes(data, flush: true);
  return outPath;
}

// ----------------------- helpers -----------------------

IntRect _clampIntRectToImage(IntRect r, int w, int h) {
  int left = r.left;
  int top = r.top;
  int right = r.right;
  int bottom = r.bottom;

  if (left < 0) left = 0;
  if (top < 0) top = 0;
  if (right > w) right = w;
  if (bottom > h) bottom = h;

  final int width = right - left;
  final int height = bottom - top;

  if (width <= 0 || height <= 0) {
    return IntRect(left: 0, top: 0, width: w, height: h);
  }
  return IntRect(left: left, top: top, width: width, height: height);
}

/// Contrast stretch with tail clipping (clipPercent as whole percent).
void _contrastStretchInPlace(im.Image img, {int clipPercent = 1}) {
  final List<int> hist = List<int>.filled(256, 0);

  for (int y = 0; y < img.height; y++) {
    for (int x = 0; x < img.width; x++) {
      final p = img.getPixel(x, y);
      // getLuminance returns num on some versions; force int
      final int lum = im.getLuminance(p).toInt();
      hist[lum] += 1;
    }
  }

  final int total = img.width * img.height;
  final int clip = ((total * clipPercent) / 100).round();

  // low
  int acc = 0;
  int low = 0;
  for (int i = 0; i < 256; i++) {
    acc += hist[i];
    if (acc >= clip) {
      low = i;
      break;
    }
  }
  // high
  acc = 0;
  int high = 255;
  for (int i = 255; i >= 0; i--) {
    acc += hist[i];
    if (acc >= clip) {
      high = i;
      break;
    }
  }
  if (high <= low) return;

  final double scale = 255.0 / (high - low);

  for (int y = 0; y < img.height; y++) {
    for (int x = 0; x < img.width; x++) {
      final p = img.getPixel(x, y);
      final int lum = im.getLuminance(p).toInt();

      int v = lum - low;
      if (v < 0) v = 0;
      if (v > 255) v = 255;

      int nv = (v * scale).round();
      if (nv < 0) nv = 0;
      if (nv > 255) nv = 255;

      img.setPixelRgba(x, y, nv, nv, nv, p.a);
    }
  }
}

/// Unsharp via blur-subtract.
/// [radius] is **int** (to match your `image` package signature).
im.Image _unsharp(im.Image src, {required int radius, required double amount}) {
  final im.Image blurred = im.gaussianBlur(src, radius: radius);
  final im.Image out = im.Image.from(src);

  for (int y = 0; y < src.height; y++) {
    for (int x = 0; x < src.width; x++) {
      final a = src.getPixel(x, y);
      final b = blurred.getPixel(x, y);

      final int aLum = im.getLuminance(a).toInt();
      final int bLum = im.getLuminance(b).toInt();

      final double hp = (aLum - bLum).toDouble();
      int v = (aLum + hp * amount).round();
      if (v < 0) v = 0;
      if (v > 255) v = 255;

      out.setPixelRgba(x, y, v, v, v, a.a);
    }
  }
  return out;
}
