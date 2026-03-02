// lib/waste_dashboard/data/impact_factors/impact_factors.dart
//
// Loads and indexes per-kg impact factors from the CSV asset:
//   lib/waste_dashboard/data/impact_factors/impact_factors.csv
//
// Exposes:
//   ImpactFactorsStore.load()     // loads + indexes rows
//   store.getExact('veg.tomato')  // exact key
//   store.findBest('Tomatoes')    // best-effort by leaf token

import 'package:flutter/services.dart' show rootBundle;
import '../../domain/models/impact_factor.dart';

const String kImpactCsvAssetPath =
    'lib/waste_dashboard/data/impact_factors/impact_factors.csv';

class ImpactFactorsStore {
  ImpactFactorsStore._({
    required this.byKey,
    required this.byLeaf,
    required this.rows,
  });

  /// full key -> factor (e.g., "veg.tomato")
  final Map<String, ImpactFactor> byKey;

  /// leaf token -> factor (e.g., "tomato")
  final Map<String, ImpactFactor> byLeaf;

  /// all rows in file order
  final List<ImpactFactor> rows;

  ImpactFactor? getExact(String key) => byKey[_normKey(key)];

  ImpactFactor? findBest(String nameOrKey) {
    final exact = getExact(nameOrKey);
    if (exact != null) return exact;
    return byLeaf[_normKey(_leafOf(nameOrKey))];
  }

  // ---------- Loading ----------

  static Future<ImpactFactorsStore> load({
    String assetPath = kImpactCsvAssetPath,
  }) async {
    final csvText = await rootBundle.loadString(assetPath);

    final lines = _splitNonEmptyLines(csvText);
    if (lines.isEmpty) {
      return ImpactFactorsStore._(byKey: {}, byLeaf: {}, rows: []);
    }

    final header = _splitCsvLine(lines.first);
    final fi = _FieldIndex.fromHeader(header);

    final byKey = <String, ImpactFactor>{};
    final byLeaf = <String, ImpactFactor>{};
    final rows = <ImpactFactor>[];

    for (var i = 1; i < lines.length; i++) {
      final cols = _splitCsvLine(lines[i]);
      if (cols.isEmpty) continue;

      final item = _rowToImpactFactor(cols, fi);
      if (item == null) continue;

      rows.add(item);

      final key = _normKey(item.foodOrCategory);
      byKey.putIfAbsent(key, () => item);

      final leafKey = _normKey(_leafOf(item.foodOrCategory));
      byLeaf.putIfAbsent(leafKey, () => item);
    }

    return ImpactFactorsStore._(byKey: byKey, byLeaf: byLeaf, rows: rows);
  }
}

// ---------- CSV parsing helpers ----------

class _FieldIndex {
  final int foodOrCategory;
  final int co2ePerKg;
  final int waterLPerKg;
  final int energyKwhPerKg;
  final int pricePerKg;
  final int sourceMeta;
  final int version;

  _FieldIndex({
    required this.foodOrCategory,
    required this.co2ePerKg,
    required this.waterLPerKg,
    required this.energyKwhPerKg,
    required this.pricePerKg,
    required this.sourceMeta,
    required this.version,
  });

  static _FieldIndex fromHeader(List<String> header) {
    String norm(String s) => s.trim().toLowerCase();
    int idx(String name) => header.indexWhere((h) => norm(h) == norm(name));

    return _FieldIndex(
      foodOrCategory: idx('food_or_category'),
      co2ePerKg: idx('co2e_per_kg'),
      waterLPerKg: idx('water_l_per_kg'),
      energyKwhPerKg: idx('energy_kwh_per_kg'),
      pricePerKg: idx('price_per_kg'),
      sourceMeta: idx('source_meta'),
      version: idx('version'),
    );
  }
}

ImpactFactor? _rowToImpactFactor(List<String> cols, _FieldIndex fi) {
  try {
    final name = _getString(cols, fi.foodOrCategory);
    if (name == null || name.isEmpty) return null;

    double? d(int i) => _parseDoubleSafe(_getString(cols, i));
    String? s(int i) => _getString(cols, i);

    return ImpactFactor(
      foodOrCategory: _normKey(name),
      co2ePerKg: d(fi.co2ePerKg),
      waterLPerKg: d(fi.waterLPerKg),
      energyKwhPerKg: d(fi.energyKwhPerKg),
      pricePerKg: d(fi.pricePerKg),
      sourceMeta: s(fi.sourceMeta),
      version: s(fi.version),
    );
  } catch (_) {
    return null;
  }
}

double? _parseDoubleSafe(String? raw) {
  if (raw == null) return null;
  final t = raw.trim();
  if (t.isEmpty) return null;
  return double.tryParse(t);
}

String? _getString(List<String> cols, int index) {
  if (index < 0 || index >= cols.length) return null;
  return cols[index].trim();
}

List<String> _splitNonEmptyLines(String text) =>
    text.split(RegExp(r'\r?\n'))
        .map((s) => s.trimRight())
        .where((s) => s.isNotEmpty)
        .toList();

List<String> _splitCsvLine(String line) => line.split(',');

// ---------- Normalization helpers ----------

String _normKey(String s) =>
    s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '_');

String _leafOf(String nameOrKey) {
  final norm = _normKey(nameOrKey);
  final parts = norm.split('.');
  return parts.isEmpty ? norm : parts.last;
}