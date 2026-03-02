// lib/app/features/ocr_scan/presentation/widgets/finder_overlay.dart
import 'package:flutter/material.dart';

enum ScanMode { receipt, note, barcode, text }

class FinderOverlay extends StatelessWidget {
  const FinderOverlay({super.key, required this.mode});
  final ScanMode mode;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: true,
      child: CustomPaint(painter: _FinderPainter(mode)),
    );
  }
}

class _FinderPainter extends CustomPainter {
  _FinderPainter(this.mode);
  final ScanMode mode;

  @override
  void paint(Canvas canvas, Size size) {
    late double w, h;
    switch (mode) {
      case ScanMode.receipt:
        w = size.width * 0.94; h = size.height * 0.76; break; // taller (your request)
      case ScanMode.note:
        w = size.width * 0.94; h = size.height * 0.70; break; // slightly smaller
      case ScanMode.barcode:
        w = size.width * 0.82; final targetH = w / 1.8; final maxH = size.height * 0.32; h = targetH.clamp(80.0, maxH); break;
      case ScanMode.text:
        return;
    }

    // shift up a bit to keep captions visible
    double x = (size.width - w) / 2;
    double y = (size.height - h) / 2 - size.height * 0.04;
    if (y < 12) y = 12;

    final r = RRect.fromRectAndRadius(Rect.fromLTWH(x, y, w, h),
        Radius.circular(mode == ScanMode.barcode ? 12 : 22));

    final glow = Paint()..style = PaintingStyle.stroke..strokeWidth = 6
      ..color = Colors.black.withValues(alpha: 0.25);
    final stroke = Paint()..style = PaintingStyle.stroke..strokeWidth = 3
      ..color = Colors.white.withValues(alpha: 0.95);

    canvas.drawRRect(r, glow);
    canvas.drawRRect(r, stroke);
  }

  @override
  bool shouldRepaint(covariant _FinderPainter old) => old.mode != mode;
}
