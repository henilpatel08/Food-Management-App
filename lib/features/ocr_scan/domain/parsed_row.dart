class ParsedRow {
  String name;
  double qty;
  String unit;           // pcs | kg | g | lb | oz | l | ml | pack
  double? unitPrice;
  double? lineTotal;
  bool needsReview;
  String raw;

  ParsedRow({
    required this.name,
    this.qty = 1,
    this.unit = 'pcs',
    this.unitPrice,
    this.lineTotal,
    this.needsReview = false,
    this.raw = '',
  });
}
