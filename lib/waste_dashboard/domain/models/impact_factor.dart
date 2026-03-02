// Domain model: a single per-kg factor row.
class ImpactFactor {
  final String foodOrCategory;   // e.g., "veg.tomato"
  final double? co2ePerKg;       // kg CO2e per kg
  final double? waterLPerKg;     // liters per kg
  final double? energyKwhPerKg;  // kWh per kg (optional)
  final double? pricePerKg;      // currency per kg
  final String? sourceMeta;      // e.g., "OWID 2023"
  final String? version;         // e.g., "v1.0"

  const ImpactFactor({
    required this.foodOrCategory,
    this.co2ePerKg,
    this.waterLPerKg,
    this.energyKwhPerKg,
    this.pricePerKg,
    this.sourceMeta,
    this.version,
  });
}