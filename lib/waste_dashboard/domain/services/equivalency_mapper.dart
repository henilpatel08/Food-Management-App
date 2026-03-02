// lib/waste_dashboard/domain/services/equivalency_mapper.dart
//
// EquivalencyMapper converts raw impact totals into friendly comparisons
// and also derives "Energy Saved" from CO2 via a grid intensity factor.
//
// All constants are centralized and easy to tweak later (region-specific).
// No external packages required.

import 'dart:math';

class EquivalencyMapper {
  // ==============================
  // Tunable reference constants
  // ==============================

  /// Passenger vehicle tailpipe emissions (kg CO2e per km).
  /// Source ballpark: ~0.18–0.21 kg CO2e/km for typical gasoline cars.
  static const double kgCo2PerKmDriving = 0.192;

  /// Liters used per standard shower.
  /// Typical range ~65–80 L; using 80 L for conservative equivalence.
  static const double litersPerShower = 80.0;

  /// Average household electricity consumption per day (kWh).
  /// Canada ballpark ~30 kWh/day (varies by province and season).
  static const double kwhPerHomePerDay = 30.0;

  /// Grid emission intensity (kg CO2e per kWh).
  /// Canada average is low vs. world (~0.10–0.15). Using 0.12 here.
  /// If you know province-specific values, override in method calls.
  static const double gridKgCo2PerKwh = 0.12;

  // ==============================
  // Core conversions
  // ==============================

  /// Convert CO2 saved (kg) to "km of driving avoided".
  static double co2KgToKmDriving(double co2Kg,
      {double kgPerKm = kgCo2PerKmDriving}) {
    if (co2Kg <= 0 || kgPerKm <= 0) return 0;
    return co2Kg / kgPerKm;
  }

  /// Convert liters to "number of showers".
  static double litersToShowers(double liters,
      {double litersPerStdShower = litersPerShower}) {
    if (liters <= 0 || litersPerStdShower <= 0) return 0;
    return liters / litersPerStdShower;
  }

  /// Convert kWh to "homes powered for a day".
  static double kwhToHomesPerDay(double kwh,
      {double kwhPerHomeDay = kwhPerHomePerDay}) {
    if (kwh <= 0 || kwhPerHomeDay <= 0) return 0;
    return kwh / kwhPerHomeDay;
  }

  /// Derive kWh from CO2 saved using grid intensity (kg CO2e per kWh).
  /// Example: if grid = 0.12 kg/kWh and you saved 12 kg CO2e, that's ~100 kWh.
  static double co2KgToKwhFromGrid(double co2Kg,
      {double gridKgPerKwh = gridKgCo2PerKwh}) {
    if (co2Kg <= 0 || gridKgPerKwh <= 0) return 0;
    return co2Kg / gridKgPerKwh;
  }

  // ==============================
  // Helper: rounded formatting
  // ==============================

  /// Round to a sensible number of decimals for UI.
  static double roundSmart(num value) {
    final v = value.toDouble();
    if (v == 0) return 0;
    final absV = v.abs();

    if (absV >= 1000) return _round(v, 0);
    if (absV >= 100) return _round(v, 1);
    if (absV >= 10) return _round(v, 1);
    if (absV >= 1) return _round(v, 2);
    return _round(v, 3);
  }

  static double _round(double v, int places) {
    final p = pow(10, places).toDouble();
    return (v * p).roundToDouble() / p;
  }

  /// Format with unit (e.g., "12.3 km") using roundSmart.
  static String fmt(num value, String unit) =>
      '${roundSmart(value)} $unit';

  // ==============================
  // UI-friendly summary strings
  // ==============================

  /// Example: "That's like skipping 12.4 km of driving"
  static String co2ToDrivingLine(double co2Kg,
      {double kgPerKm = kgCo2PerKmDriving}) {
    final km = co2KgToKmDriving(co2Kg, kgPerKm: kgPerKm);
    return "That's like skipping ${fmt(km, 'km')} of driving";
    // If you prefer days without a car:
    // final days = km / 40.0; // assume 40 km/day typical driving
    // return "That's like taking a car off the road for ${fmt(days, 'day(s)')}";
  }

  /// Example: "2,000 liters saved = 25 showers"
  static String waterToShowersLine(double liters,
      {double litersPerStdShower = litersPerShower}) {
    final showers =
    litersToShowers(liters, litersPerStdShower: litersPerStdShower);
    return "${fmt(liters, 'L')} saved ≈ ${fmt(showers, 'showers')}";
  }

  /// Example: "Enough to power 15 homes for a day"
  static String kwhToHomesLine(double kwh,
      {double kwhPerHomeDay = kwhPerHomePerDay}) {
    final homes = kwhToHomesPerDay(kwh, kwhPerHomeDay: kwhPerHomeDay);
    return "Enough to power ${fmt(homes, 'home(s)')} for a day";
  }

  /// If you only have CO2, derive kWh first, then map to homes/day.
  static String co2ToHomesFromGridLine(double co2Kg,
      {double gridKgPerKwh = gridKgCo2PerKwh,
        double kwhPerHomeDay = kwhPerHomePerDay}) {
    final kwh = co2KgToKwhFromGrid(co2Kg, gridKgPerKwh: gridKgPerKwh);
    final homes = kwhToHomesPerDay(kwh, kwhPerHomeDay: kwhPerHomeDay);
    return "Energy equivalent: ${fmt(kwh, 'kWh')} (~${roundSmart(homes)} home(s) for a day)";
  }
}