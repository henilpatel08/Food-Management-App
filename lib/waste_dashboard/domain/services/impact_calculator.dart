// lib/waste_dashboard/domain/services/impact_calculator.dart
//
// Final calculator for Waste Dashboard counters.
//
// What it does
// ------------
// - Aggregates CO2, Water, Energy (kWh), and Money ($) SAVED from items consumed.
// - Computes "Missed Savings" CO2 from items expired (positive framing).
// - Computes simple Waste Diverted % = consumed_mass / (consumed + expired) * 100
// - Resolves factors by exact key (e.g., "veg.tomato") or by leaf fallback ("tomato").
//
// Inputs
// ------
// - ConsumedItem { name, kg }  : things the user actually used/cooked
// - ExpiredItem  { name, kg }  : things that expired (not used)
// - Map<String, ImpactFactor>  : factor table (usually loaded from CSV)
//
// Notes
// -----
// - Energy saved (kWh) prefers factor.energyKwhPerKg when present.
//   If not present, we derive kWh from CO2 using EquivalencyMapper.co2KgToKwhFromGrid().
// - Money saved uses factor.pricePerKg. If null, contributes $0 for that item.
// - All functions are null-safe and skip rows with missing/0 values.

import 'equivalency_mapper.dart';
import '../models/impact_factor.dart';

/// Placeholder types for wiring before inventory/recipe flows arrive.
class ConsumedItem {
  final String name; // e.g., "tomatoes" or "veg.tomato"
  final double kg;   // e.g., 0.2 for 200g
  const ConsumedItem({required this.name, required this.kg});
}

class ExpiredItem {
  final String name;
  final double kg;
  const ExpiredItem({required this.name, required this.kg});
}

/// Aggregated outputs for counters.
class ImpactTotals {
  final double co2SavedKg;
  final double waterSavedL;
  final double energySavedKwh;
  final double moneySaved;

  /// Positive framing for expired items.
  final double missedSavingsCo2Kg;

  /// 0..100
  final double wasteDivertedPct;

  const ImpactTotals({
    this.co2SavedKg = 0,
    this.waterSavedL = 0,
    this.energySavedKwh = 0,
    this.moneySaved = 0,
    this.missedSavingsCo2Kg = 0,
    this.wasteDivertedPct = 0,
  });

  ImpactTotals copyWith({
    double? co2SavedKg,
    double? waterSavedL,
    double? energySavedKwh,
    double? moneySaved,
    double? missedSavingsCo2Kg,
    double? wasteDivertedPct,
  }) {
    return ImpactTotals(
      co2SavedKg: co2SavedKg ?? this.co2SavedKg,
      waterSavedL: waterSavedL ?? this.waterSavedL,
      energySavedKwh: energySavedKwh ?? this.energySavedKwh,
      moneySaved: moneySaved ?? this.moneySaved,
      missedSavingsCo2Kg: missedSavingsCo2Kg ?? this.missedSavingsCo2Kg,
      wasteDivertedPct: wasteDivertedPct ?? this.wasteDivertedPct,
    );
  }
}

class ImpactCalculator {
  /// Calculates SAVED impact from consumed items.
  ///
  /// - Looks up per-kg factors by exact key or leaf fallback.
  /// - Sums CO2 (kg), Water (L), Energy (kWh), Money ($).
  /// - If energy_kWh_per_kg is missing, derives kWh from CO2 using grid factor.
  ImpactTotals calcSaved({
    required List<ConsumedItem> consumed,
    required Map<String, ImpactFactor> factorsByKey,
  }) {
    double co2 = 0, water = 0, kwhFromFactor = 0, money = 0;

    for (final item in consumed) {
      if (item.kg <= 0) continue;

      final f = _resolveFactor(item.name, factorsByKey);
      if (f == null) continue;

      final c = (f.co2ePerKg ?? 0) * item.kg;
      final w = (f.waterLPerKg ?? 0) * item.kg;
      final e = (f.energyKwhPerKg ?? 0) * item.kg;
      final $ = (f.pricePerKg ?? 0) * item.kg;

      co2 += c;
      water += w;
      kwhFromFactor += e;
      money += $;
    }

    // If no energy factor provided, derive kWh from CO2 via grid intensity.
    final totalKwh = kwhFromFactor > 0
        ? kwhFromFactor
        : EquivalencyMapper.co2KgToKwhFromGrid(co2);

    return ImpactTotals(
      co2SavedKg: co2,
      waterSavedL: water,
      energySavedKwh: totalKwh,
      moneySaved: money,
      missedSavingsCo2Kg: 0,
      wasteDivertedPct: 0, // filled by computeWasteDivertedPct() separately
    );
  }

  /// Calculates "Missed Savings" for EXPIRED items (CO2 only by default).
  ///
  /// We keep this separate so UI can frame it positively:
  /// "Cooking these would have saved X kg CO₂".
  ImpactTotals calcMissed({
    required List<ExpiredItem> expired,
    required Map<String, ImpactFactor> factorsByKey,
  }) {
    double missedCo2 = 0;

    for (final item in expired) {
      if (item.kg <= 0) continue;

      final f = _resolveFactor(item.name, factorsByKey);
      if (f == null) continue;

      missedCo2 += (f.co2ePerKg ?? 0) * item.kg;
    }

    return ImpactTotals(missedSavingsCo2Kg: missedCo2);
  }

  /// Computes simple Waste Diverted % from consumed vs expired mass.
  ///
  /// diversion% = consumed_mass / (consumed_mass + expired_mass) * 100
  double computeWasteDivertedPct({
    required List<ConsumedItem> consumed,
    required List<ExpiredItem> expired,
  }) {
    final consumedKg = consumed.fold<double>(0, (s, e) => s + (e.kg > 0 ? e.kg : 0));
    final expiredKg  = expired.fold<double>(0, (s, e) => s + (e.kg > 0 ? e.kg : 0));
    final denom = consumedKg + expiredKg;
    if (denom <= 0) return 0;
    return (consumedKg / denom) * 100.0;
  }

  // -------------------------
  // Factor resolution helpers
  // -------------------------

  ImpactFactor? _resolveFactor(
      String nameOrKey,
      Map<String, ImpactFactor> factorsByKey,
      ) {
    // Try exact key first.
    final exact = factorsByKey[_normKey(nameOrKey)];
    if (exact != null) return exact;

    // Fallback: try the leaf token (e.g., "tomato" from "veg.tomato")
    final leaf = _leafOf(nameOrKey);
    return factorsByKey[_normKey(leaf)];
  }

  String _normKey(String s) =>
      s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '_');

  String _leafOf(String nameOrKey) {
    final norm = _normKey(nameOrKey);
    final parts = norm.split('.');
    return parts.isEmpty ? norm : parts.last;
  }
}
