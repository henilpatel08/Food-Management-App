import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'detection_result.dart';

class DetectorService {
  final TextRecognizer _text = TextRecognizer(script: TextRecognitionScript.latin);
  final BarcodeScanner _barcodes = BarcodeScanner(formats: [
    BarcodeFormat.qrCode,
    BarcodeFormat.aztec,
    BarcodeFormat.dataMatrix,
    BarcodeFormat.ean13,
    BarcodeFormat.ean8,
    BarcodeFormat.upca,
    BarcodeFormat.upce,
    BarcodeFormat.code128,
    BarcodeFormat.code39,
    BarcodeFormat.code93,
    BarcodeFormat.pdf417,
  ]);

  Future<DetectionResult> detectFromFile(String path) async {
    final input = InputImage.fromFilePath(path);

    // 1) Try barcode first (cheap & fast)
    final codes = await _barcodes.processImage(input);
    if (codes.isNotEmpty) {
      final c = codes.first;
      return DetectionResult.barcode(
        c.rawValue ?? '',
        c.format.name,
      );
    }

    // 2) OCR text
    final r = await _text.processImage(input);
    final raw = r.text.trim();

    if (raw.isEmpty) return const DetectionResult.none();

    // Heuristic: if we see lots of price/qty lines ⇒ call it receipt, else note
    final lines = raw.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    final priceLike = RegExp(r'\$\s*\d+(?:\s*\.\s*\d{2})?');
    final weightLike = RegExp(r'\b(?:kg|g|lb|lbs|oz|l|ml)\b', caseSensitive: false);
    int score = 0;
    for (final l in lines.take(40)) {
      if (priceLike.hasMatch(l)) score++;
      if (weightLike.hasMatch(l)) score++;
      if (l.contains('@')) score++;
    }
    final DetectedType t = score >= 3 ? DetectedType.receipt : DetectedType.note;
    return DetectionResult.text(raw, t);
  }

  Future<void> dispose() async {
    await _text.close();
    await _barcodes.close();
  }
}
