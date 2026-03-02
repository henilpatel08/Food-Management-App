import 'package:flutter/material.dart';

// Firebase
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// Impact data + services
import '../../data/impact_factors/impact_factors.dart';
import '../../domain/services/impact_calculator.dart';
import '../../domain/services/equivalency_mapper.dart';

// We use ImpactFactor + same key logic as the WasteDashboard
import 'package:sust_ai_n/waste_dashboard/domain/models/impact_factor.dart';

/// Small DTO for the summary data we need on this card
class _SummaryData {
  final ImpactTotals saved;
  final double divertedPct;
  final String drivingLine;

  const _SummaryData({
    required this.saved,
    required this.divertedPct,
    required this.drivingLine,
  });
}

/// ===============================
///  WASTE IMPACT SUMMARY CARD
/// ===============================
class WasteImpactSummaryCard extends StatelessWidget {
  final VoidCallback onOpenDetails;

  const WasteImpactSummaryCard({
    super.key,
    required this.onOpenDetails,
  });

  // ---------- Loader that mirrors WasteDashboard (fixed to 7 days) ----------

  Future<_SummaryData?> _loadSummaryForLast7Days() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      // You could return null and show a "sign in" message instead if you prefer
      throw StateError('User not signed in');
    }

    // 1) Load impact factors (CSV)
    final store = await ImpactFactorsStore.load();

    // 2) Load Firestore logs for last 7 days
    final logs = await _loadLogsForLastNDays(
      userId: user.uid,
      days: 7,
    );

    // If there are no used or wasted items in this window,
    // we deliberately return null so the UI can show an empty state.
    if (logs.consumed.isEmpty && logs.expired.isEmpty) {
      return null;
    }

    // 3) Build factors map with price overrides, same as dashboard
    final factorsByKey =
    _buildFactorsWithOverrides(store, logs.priceOverrides);

    // 4) Run same calculator as dashboard
    final calc = ImpactCalculator();
    final saved = calc.calcSaved(
      consumed: logs.consumed,
      factorsByKey: factorsByKey,
    );
    final divertedPct = calc.computeWasteDivertedPct(
      consumed: logs.consumed,
      expired: logs.expired,
    );

    // 5) Driving-line equivalency
    final drivingLine =
    EquivalencyMapper.co2ToDrivingLine(saved.co2SavedKg);

    return _SummaryData(
      saved: saved,
      divertedPct: divertedPct,
      drivingLine: drivingLine,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_SummaryData?>(
      future: _loadSummaryForLast7Days(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return _buildLoadingCard();
        }

        if (snap.hasError) {
          debugPrint('WasteImpactSummaryCard error: ${snap.error}');
          return _buildErrorCard();
        }

        final data = snap.data;
        if (data == null) {
          // Either no snapshot yet or we deliberately returned null
          // because there are no logs in the last 7 days.
          return _buildNoDataCard();
        }

        return _buildCardContent(
          context: context,
          saved: data.saved,
          divertedPct: data.divertedPct,
          drivingLine: data.drivingLine,
        );
      },
    );
  }

  // ------------ UI builders ------------

  Widget _buildLoadingCard() {
    return _BaseCard(
      onTap: null,
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          children: [
            CircularProgressIndicator(strokeWidth: 2),
            SizedBox(width: 12),
            Text('Loading waste impact…'),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorCard() {
    return _BaseCard(
      onTap: null,
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          'Waste impact summary is unavailable right now.',
          style: TextStyle(fontSize: 14),
        ),
      ),
    );
  }

  Widget _buildNoDataCard() {
    return _BaseCard(
      onTap: null,
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          'No data yet.\n'
              'You have not logged any items as used or expired in the last 7 days.',
          style: TextStyle(fontSize: 14),
        ),
      ),
    );
  }

  Widget _buildCardContent({
    required BuildContext context,
    required ImpactTotals saved,
    required double divertedPct,
    required String drivingLine,
  }) {
    return _BaseCard(
      onTap: onOpenDetails,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              children: const [
                Expanded(
                  child: Text(
                    'Your Waste Impact (summary)',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  'Last 7 days',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Metrics
            _metricRow('CO₂ saved', _fmt(saved.co2SavedKg, 'kg')),
            _metricRow('Water saved', _fmt(saved.waterSavedL, 'L')),
            _metricRow('Energy (equiv.)', _fmt(saved.energySavedKwh, 'kWh')),
            _metricRow('Money saved', _money(saved.moneySaved)),
            _metricRow('Waste diverted', '${_round(divertedPct, 1)}%'),

            const SizedBox(height: 8),
            Text(
              drivingLine,
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 8),

            // CTA line
            Row(
              children: const [
                Spacer(),
                Text(
                  'View detailed dashboard  ›',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.green,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static Widget _metricRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  // ------------ Formatting helpers ------------

  static String _fmt(num v, String unit) => '${_roundSmart(v)} $unit';

  static String _money(num v) => '\$${v.toStringAsFixed(2)} CAD';

  static double _roundSmart(num value) {
    final v = value.toDouble().abs();
    if (v >= 1000) return _round(value, 0);
    if (v >= 100) return _round(value, 1);
    if (v >= 10) return _round(value, 1);
    if (v >= 1) return _round(value, 2);
    return _round(value, 3);
  }

  static double _round(num value, int places) {
    var p = 1.0;
    for (var i = 0; i < places; i++) {
      p *= 10.0;
    }
    return (value * p).roundToDouble() / p;
  }
}

// Base card with tap ripple
class _BaseCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;

  const _BaseCard({required this.child, this.onTap});

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(16);
    return Material(
      color: Colors.white,
      elevation: 0.8,
      borderRadius: radius,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: child,
      ),
    );
  }
}

/// ===============================
///  SHARED LOGIC (copied from dashboard)
/// ===============================

class _LogsBundle {
  final List<ConsumedItem> consumed;
  final List<ExpiredItem> expired;
  final Map<String, double> priceOverrides;

  const _LogsBundle({
    required this.consumed,
    required this.expired,
    required this.priceOverrides,
  });
}

// Load Firestore logs for the last [days] days for a user
Future<_LogsBundle> _loadLogsForLastNDays({
  required String userId,
  required int days,
}) async {
  final firestore = FirebaseFirestore.instance;
  final now = DateTime.now();
  final start = now.subtract(Duration(days: days));

  final userDoc = firestore.collection('users').doc(userId);

  // 1) Consumption logs
  final consSnap = await userDoc
      .collection('consumption_logs')
      .where('at', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
      .where('at', isLessThanOrEqualTo: Timestamp.fromDate(now))
      .get();

  // 2) Waste logs
  final wasteSnap = await userDoc
      .collection('waste_logs')
      .where('at', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
      .where('at', isLessThanOrEqualTo: Timestamp.fromDate(now))
      .get();

  // 3) Price overrides (optional)
  QuerySnapshot<Map<String, dynamic>>? priceSnap;
  try {
    priceSnap = await userDoc.collection('price_overrides').get();
  } catch (_) {
    priceSnap = null;
  }

  final consumedMap = <String, double>{};
  final expiredMap = <String, double>{};

  // Aggregate consumption
  for (final doc in consSnap.docs) {
    final data = doc.data();
    final leaf = (data['leafKey'] as String?) ?? '';
    final kg = (data['kg'] as num?)?.toDouble() ?? 0;
    if (leaf.isEmpty || kg <= 0) continue;

    final key = (data['key'] as String?)?.trim();
    final category = (data['category'] as String?)?.trim();

    final canonicalKey =
    _buildCanonicalKey(key: key, leafKey: leaf, category: category);

    consumedMap.update(
      canonicalKey,
          (v) => v + kg,
      ifAbsent: () => kg,
    );
  }

  // Aggregate waste
  for (final doc in wasteSnap.docs) {
    final data = doc.data();
    final leaf = (data['leafKey'] as String?) ?? '';
    final kg = (data['kg'] as num?)?.toDouble() ?? 0;
    if (leaf.isEmpty || kg <= 0) continue;

    final key = (data['key'] as String?)?.trim();
    final category = (data['category'] as String?)?.trim();

    final canonicalKey =
    _buildCanonicalKey(key: key, leafKey: leaf, category: category);

    expiredMap.update(
      canonicalKey,
          (v) => v + kg,
      ifAbsent: () => kg,
    );
  }

  final consumed = consumedMap.entries
      .map((e) => ConsumedItem(name: e.key, kg: e.value))
      .toList();
  final expired = expiredMap.entries
      .map((e) => ExpiredItem(name: e.key, kg: e.value))
      .toList();

  final priceOverrides = <String, double>{};
  if (priceSnap != null) {
    for (final doc in priceSnap.docs) {
      final data = doc.data();
      final price = (data['pricePerKg'] as num?)?.toDouble();
      if (price != null && price > 0) {
        priceOverrides[_normKey(doc.id)] = price;
      }
    }
  }

  return _LogsBundle(
    consumed: consumed,
    expired: expired,
    priceOverrides: priceOverrides,
  );
}

String _buildCanonicalKey({
  String? key,
  required String leafKey,
  String? category,
}) {
  if (key != null && key.trim().isNotEmpty) {
    return _normKey(key);
  }
  final leaf = _normKey(leafKey);
  if (category != null && category.trim().isNotEmpty) {
    final cat = _normKey(category);
    return '$cat.$leaf';
  }
  return leaf;
}

Map<String, ImpactFactor> _buildFactorsWithOverrides(
    ImpactFactorsStore store,
    Map<String, double> priceOverrides,
    ) {
  final byKey = <String, ImpactFactor>{};

  // Start with CSV rows, apply price overrides if present
  for (final f in store.rows) {
    final normKey = _normKey(f.foodOrCategory);
    final override = priceOverrides[normKey];
    byKey[normKey] = ImpactFactor(
      foodOrCategory: f.foodOrCategory,
      co2ePerKg: f.co2ePerKg,
      waterLPerKg: f.waterLPerKg,
      energyKwhPerKg: f.energyKwhPerKg,
      pricePerKg: override ?? f.pricePerKg,
      sourceMeta: f.sourceMeta,
      version: f.version,
    );
  }

  // Also index by leaf for fallback lookups
  for (final f in store.rows) {
    final leaf = _leafOf(f.foodOrCategory);
    final normLeaf = _normKey(leaf);
    byKey.putIfAbsent(normLeaf, () => byKey[_normKey(f.foodOrCategory)]!);
  }

  return byKey;
}

String _normKey(String s) =>
    s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '_');

String _leafOf(String nameOrKey) {
  final norm = _normKey(nameOrKey);
  final parts = norm.split('.');
  return parts.isEmpty ? norm : parts.last;
}