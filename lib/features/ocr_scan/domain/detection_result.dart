enum DetectedType { none, barcode, receipt, note }

class DetectionResult {
  final DetectedType type;
  final String? text;      // for receipt/note (OCR)
  final String? barcode;   // raw barcode content
  final String? symbology; // QR_CODE, EAN_13, etc.

  const DetectionResult.none() : type = DetectedType.none, text = null, barcode = null, symbology = null;

  const DetectionResult.barcode(this.barcode, this.symbology)
      : type = DetectedType.barcode, text = null;

  const DetectionResult.text(this.text, this.type)
      : assert(type == DetectedType.receipt || type == DetectedType.note),
        barcode = null, symbology = null;
}
