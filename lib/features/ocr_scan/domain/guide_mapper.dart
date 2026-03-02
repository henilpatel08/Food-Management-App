// lib/app/features/ocr_scan/domain/guide_mapper.dart
import 'dart:ui';

/// Map the white guide rect (drawn on the CameraPreview) to the
/// actual image pixel rect (BoxFit.cover math).
Rect mapGuideToImageRect({
  required Size previewWidgetSize,
  required Size imageSize,
  required Rect guideInPreview,
}) {
  final scale = (previewWidgetSize.width / imageSize.width) >
      (previewWidgetSize.height / imageSize.height)
      ? previewWidgetSize.width / imageSize.width
      : previewWidgetSize.height / imageSize.height;

  final fittedW = imageSize.width * scale;
  final fittedH = imageSize.height * scale;
  final dx = (previewWidgetSize.width - fittedW) / 2;
  final dy = (previewWidgetSize.height - fittedH) / 2;

  final gx = (guideInPreview.left - dx).clamp(0.0, fittedW);
  final gy = (guideInPreview.top  - dy).clamp(0.0, fittedH);
  final gw = guideInPreview.width.clamp(0.0, fittedW);
  final gh = guideInPreview.height.clamp(0.0, fittedH);

  final sx = gx / scale;
  final sy = gy / scale;
  final sw = gw / scale;
  final sh = gh / scale;
  return Rect.fromLTWH(sx, sy, sw, sh);
}
