import 'package:flutter/material.dart';

// Firebase
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// data + services + model
import 'package:sust_ai_n/waste_dashboard/data/impact_factors/impact_factors.dart';
import 'package:sust_ai_n/waste_dashboard/domain/models/impact_factor.dart';
import 'package:sust_ai_n/waste_dashboard/domain/services/impact_calculator.dart';
import 'package:sust_ai_n/waste_dashboard/domain/services/equivalency_mapper.dart';

/// ===============================
///  THEME TOKENS (local to page)
/// ===============================
class _T {
  // Brand
  static const green700 = Color(0xFF0EA669);
  static const green600 = Color(0xFF10B981);
  static const green500 = Color(0xFF22C55E);
  static const green400 = Color(0xFF34D399);

  // Accents
  static const blue500 = Color(0xFF3B82F6);
  static const amber500 = Color(0xFFF59E0B);
  static const rose500 = Color(0xFFF43F5E);

  // Neutrals
  static const ink900 = Color(0xFF0B1320);
  static const ink800 = Color(0xFF1F2937);
  static const ink700 = Color(0xFF374151);
  static const ink500 = Color(0xFF6B7280);
  static const ink400 = Color(0xFF9CA3AF);

  // Surfaces
  static const bg = Color(0xFFF7FAFC);
  static const white = Colors.white;

  // Radii / spacing
  static const rLg = 24.0;
  static const pad = 16.0;
}

// helper to avoid withOpacity deprecation hints on some SDKs
Color _alpha(Color c, double t) =>
    c.withAlpha((t.clamp(0.0, 1.0) * 255).round());

/// ===============================
///  PAGE
/// ===============================
class WasteDashboardPage extends StatefulWidget {
  const WasteDashboardPage({super.key});
  @override
  State<WasteDashboardPage> createState() => _WasteDashboardPageState();
}

class _WasteDashboardPageState extends State<WasteDashboardPage> {
  String _range = '7d'; // '7d' | '30d' | '90d'

  @override
  Widget build(BuildContext context) {
    // Require a signed-in user for personalized dashboard
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Scaffold(
        backgroundColor: _T.bg,
        body: const Center(
          child: Text(
            'Sign in to see your Waste Dashboard',
            style: TextStyle(fontSize: 16),
          ),
        ),
      );
    }
    final userId = user.uid;

    return Scaffold(
      backgroundColor: _T.bg,
      body: FutureBuilder<ImpactFactorsStore>(
        future: ImpactFactorsStore.load(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
                child: Text('Failed to load impact data: ${snap.error}'));
          }
          final store = snap.data;
          if (store == null) {
            return const Center(child: Text('No impact factors found.'));
          }

          // Second-stage: load Firestore logs for selected range
          return FutureBuilder<_LogsBundle>(
            key: ValueKey(_range), // refetch when range changes
            future: _loadLogsForRange(userId: userId, range: _range),
            builder: (context, logsSnap) {
              if (logsSnap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (logsSnap.hasError) {
                return Center(
                    child:
                    Text('Failed to load usage data: ${logsSnap.error}'));
              }
              final logs = logsSnap.data ?? const _LogsBundle.empty();

              // Lookup map (exact + leaf) with price overrides applied
              final factorsByKey =
              _buildFactorsWithOverrides(store, logs.priceOverrides);

              final calc = ImpactCalculator();
              final saved = calc.calcSaved(
                consumed: logs.consumed,
                factorsByKey: factorsByKey,
              );
              final missed = calc.calcMissed(
                expired: logs.expired,
                factorsByKey: factorsByKey,
              );
              final divertedPct = calc.computeWasteDivertedPct(
                consumed: logs.consumed,
                expired: logs.expired,
              );

              // Equivalency lines
              final drivingLine =
              EquivalencyMapper.co2ToDrivingLine(saved.co2SavedKg);
              final showersLine =
              EquivalencyMapper.waterToShowersLine(saved.waterSavedL);
              final homesLine =
              EquivalencyMapper.kwhToHomesLine(saved.energySavedKwh);

              // tiny demo sparkline (we don't have timeseries yet)
              final trend = <double>[
                2.2,
                3.4,
                2.9,
                4.1,
                3.6,
                3.9,
                saved.co2SavedKg.clamp(0, 6)
              ];

              // simple category view
              final catRows = _buildCategoryRows(logs.consumed, factorsByKey);

              // Missing-factor mass note
              final _MissingInfo missingInfo = _computeMissingImpactMass(
                  logs.consumed, logs.expired, factorsByKey);

              final rangeLabel = _rangeLabel(_range);

              final missedSavingsText =
                  'Cooking the expired items would have saved ~${_fmt(missed.missedSavingsCo2Kg, 'kg CO₂')}.';
              final suggestionText = logs.consumed.isEmpty &&
                  logs.expired.isEmpty
                  ? 'Start logging what you use or waste to see smart suggestions here.'
                  : 'Use your soon-to-expire items first. Try a quick recipe with what you already have in your fridge 🍅';

              return CustomScrollView(
                slivers: [
                  _HeroAppBar(
                    range: _range,
                    rangeLabel: rangeLabel,
                    onRangeChanged: (r) => setState(() => _range = r),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                          _T.pad, 0, _T.pad, _T.pad),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: 16),

                          // ===== SUMMARY IMPACT CARD =====
                          _SummaryImpactCard(
                            saved: saved,
                            drivingLine: drivingLine,
                            showersLine: showersLine,
                            homesLine: homesLine,
                            trend: trend,
                            onCo2Info: () => _showCo2InfoSheet(
                              context: context,
                              saved: saved,
                              catRows: catRows,
                              rangeLabel: rangeLabel,
                              missingInfo: missingInfo,
                            ),
                            onWaterInfo: () => _showWaterInfoSheet(
                              context: context,
                              saved: saved,
                              catRows: catRows,
                              rangeLabel: rangeLabel,
                              missingInfo: missingInfo,
                            ),
                            onEnergyInfo: () => _showEnergyInfoSheet(
                              context: context,
                              saved: saved,
                              rangeLabel: rangeLabel,
                            ),
                            onMoneyInfo: () => _showMoneyInfoSheet(
                              context: context,
                              saved: saved,
                              rangeLabel: rangeLabel,
                            ),
                          ),

                          const SizedBox(height: 16),

                          // ===== QUICK ACTIONS =====
                          _QuickActionsRow(
                            onScan: () {},
                            onAdd: () {},
                          ),

                          const SizedBox(height: 20),

                          // ===== WASTE DIVERTED DETAIL =====
                          const _SectionTitle('Waste diverted'),
                          _DivertCard(
                            percent: divertedPct,
                            onInfo: () => _showDiversionInfoSheet(
                              context: context,
                              divertedPct: divertedPct,
                              consumed: logs.consumed,
                              expired: logs.expired,
                              rangeLabel: rangeLabel,
                            ),
                          ),

                          if (missingInfo.totalKg > 0) ...[
                            const SizedBox(height: 8),
                            Text(
                              'Note: ~${_roundSmart(missingInfo.totalKg)} kg of items '
                                  "didn't have impact data yet, so they’re not counted here.",
                              style: const TextStyle(
                                fontSize: 12,
                                color: _T.ink500,
                              ),
                            ),
                          ],

                          const SizedBox(height: 20),

                          // ===== TOP CONTRIBUTORS =====
                          const _SectionTitle('Top contributors'),
                          _CategoryRowList(rows: catRows),

                          const SizedBox(height: 20),

                          // ===== INSIGHTS & TIPS =====
                          const _SectionTitle('Insights & tips'),
                          _InsightsRow(
                            missedSavingsText: missedSavingsText,
                            suggestionText: suggestionText,
                          ),

                          const SizedBox(height: 12),

                          // ===== FUN COMPARISON =====
                          _InfoCard(
                            icon: Icons.insights,
                            title: "Your impact in everyday terms",
                            body: "• $drivingLine\n• $showersLine\n• $homesLine",
                          ),

                          const SizedBox(height: 20),

                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  // ---------- Firestore loader ----------

  Future<_LogsBundle> _loadLogsForRange({
    required String userId,
    required String range,
  }) async {
    final firestore = FirebaseFirestore.instance;
    final now = DateTime.now();
    final days = switch (range) {
      '30d' => 30,
      '90d' => 90,
      _ => 7,
    };
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

    // 3) Price overrides (optional, so we swallow errors and just treat as null)
    QuerySnapshot<Map<String, dynamic>>? priceSnap;
    try {
      priceSnap = await userDoc.collection('price_overrides').get();
    } catch (_) {
      priceSnap = null;
    }

    // ---- Aggregate to ConsumedItem / ExpiredItem ----

    final consumedMap = <String, double>{};
    final expiredMap = <String, double>{};

    // Aggregate consumption by canonical key
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

    // Aggregate waste by canonical key
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
          // doc.id should be the canonical key (e.g. veg.tomato)
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

  static String _buildCanonicalKey({
    String? key,
    required String leafKey,
    String? category,
  }) {
    // 1️. If full key exists (e.g. "veg.tomato", "pantry.sugar")
    if (key != null && key.trim().isNotEmpty) {
      return _normKey(key);
    }

    // Normalize the leaf (e.g. "tomato", "chocolate")
    final leaf = _normKey(leafKey);

    // 2️. If category exists from DB (aisle/category saved earlier)
    if (category != null && category.trim().isNotEmpty) {
      final cat = _normKey(category);
      return '$cat.$leaf';
    }

    // 3️. AUTO-GUESS category if none provided
    final autoCat = _guessCategoryFromLeaf(leaf);

    // 4️. Final canonical key returned
    return '$autoCat.$leaf';
  }
  static String _guessCategoryFromLeaf(String leaf) {
    // ============================
    // VEGETABLES
    // ============================
    const veg = {
      "tomato","onion","potato","spinach","cucumber","carrot","broccoli",
      "lettuce","cabbage","pepper","cauliflower","mushroom","sweet_potato",
      "beetroot","green_bean","zucchini","brussels_sprout","asparagus",
      "eggplant","peas"
    };
    if (veg.contains(leaf)) return "veg";

    // ============================
    // FRUITS
    // ============================
    const fruit = {
      "apple","banana","orange","strawberry","grapes","blueberry",
      "pineapple","mango","watermelon","pear","peach","kiwi","avocado",
      "lemon","lime"
    };
    if (fruit.contains(leaf)) return "fruit";

    // ============================
    // GRAINS
    // ============================
    const grain = {
      "rice","wheat_bread","pasta","noodles","flour","corn","oats",
      "barley","quinoa","tortilla","cereal"
    };
    if (grain.contains(leaf)) return "grain";

    // ============================
    // PROTEIN
    // ============================
    const protein = {
      "chicken","beef","pork","egg","lamb","turkey","tofu","tempeh",
      "seitan","sausage","ham","bacon","burger_patty_beef",
      "burger_patty_plant"
    };
    if (protein.contains(leaf)) return "protein";

    // ============================
    // DAIRY
    // ============================
    const dairy = {
      "milk","cheese","butter","yogurt","cream","ice_cream",
      "milk_plant_soy","milk_plant_oat"
    };
    if (dairy.contains(leaf)) return "dairy";

    // ============================
    // LEGUMES
    // ============================
    const legumes = {
      "lentils","chickpeas","beans","peas_dried","soybeans"
    };
    if (legumes.contains(leaf)) return "legume";

    // ============================
    // FISH & SEAFOOD
    // ============================
    const fish = {
      "white_fish","salmon","tuna","sardine","prawn"
    };
    if (fish.contains(leaf)) return "fish";

    // ============================
    // PANTRY ITEMS
    // ============================
    const pantry = {
      "cooking_oil","olive_oil","sunflower_oil","sugar","salt","honey",
      "ketchup","mayonnaise","peanut_butter","jam","chocolate",
      "chocolate_spread","cocoa_powder","chips","biscuits","crackers",
      "tortilla_wrap","soy_sauce","tomato_sauce","pasta_sauce",
      "stock_cube","bouillon_powder"
    };
    if (pantry.contains(leaf)) return "pantry";

    // ============================
    // NUTS
    // ============================
    const nuts = {
      "almond","walnut","cashew","hazelnut"
    };
    if (nuts.contains(leaf)) return "nut";

    // ============================
    // SEEDS
    // ============================
    const seeds = {
      "sunflower_seed","chia_seed","flaxseed"
    };
    if (seeds.contains(leaf)) return "seed";

    // ============================
    // BEVERAGE
    // ============================
    const beverages = {
      "coffee_ground","tea","soft_drink","juice","milkshake",
      "energy_drink","beer","wine"
    };
    if (beverages.contains(leaf)) return "beverage";

    // ============================
    // FROZEN FOODS
    // ============================
    const frozen = {
      "pizza","french_fries","ice_cream_tub","veggie_burger"
    };
    if (frozen.contains(leaf)) return "frozen";

    // ============================
    // DESSERT
    // ============================
    const dessert = {
      "cake","cookie","brownie","donut","muffin","ice_cream_bar"
    };
    if (dessert.contains(leaf)) return "dessert";

    // ============================
    // PREPARED FOODS
    // ============================
    const prepared = {
      "sandwich_ham_cheese","sandwich_veggie","ready_meal_pasta",
      "ready_meal_curry","burger_meal_beef","burger_meal_chicken"
    };
    if (prepared.contains(leaf)) return "prepared";

    // fallback
    return "pantry";
  }


  static Map<String, ImpactFactor> _buildFactorsWithOverrides(
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

  static _MissingInfo _computeMissingImpactMass(
      List<ConsumedItem> consumed,
      List<ExpiredItem> expired,
      Map<String, ImpactFactor> factorsByKey,
      ) {
    double missingConsumed = 0;
    double missingExpired = 0;

    for (final item in consumed) {
      final f = _resolveFactorLikeCalculator(item.name, factorsByKey);
      if (f == null) missingConsumed += item.kg;
    }
    for (final item in expired) {
      final f = _resolveFactorLikeCalculator(item.name, factorsByKey);
      if (f == null) missingExpired += item.kg;
    }
    return _MissingInfo(
      consumedKg: missingConsumed,
      expiredKg: missingExpired,
    );
  }

  static ImpactFactor? _resolveFactorLikeCalculator(
      String nameOrKey,
      Map<String, ImpactFactor> factorsByKey,
      ) {
    final exact = factorsByKey[_normKey(nameOrKey)];
    if (exact != null) return exact;
    final leaf = _leafOf(nameOrKey);
    return factorsByKey[_normKey(leaf)];
  }

  // ---------- KPI Info Sheets ----------

  void _showCo2InfoSheet({
    required BuildContext context,
    required ImpactTotals saved,
    required List<_CatRow> catRows,
    required String rangeLabel,
    required _MissingInfo missingInfo,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _T.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final topItems = catRows.take(3).toList();
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.eco, color: _T.green600),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'CO₂ Saved – $rangeLabel',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: _T.ink900,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _fmt(saved.co2SavedKg, 'kg CO₂e'),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: _T.ink900,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'How this is calculated',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: _T.ink800,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  '• We look at foods you logged as used in this period.\n'
                      '• For each food, we multiply the amount (kg) by its CO₂ factor per kg from our dataset.\n'
                      '• Then we add everything up to get your total CO₂ saved.',
                  style: TextStyle(fontSize: 13, color: _T.ink700),
                ),
                const SizedBox(height: 12),
                if (topItems.isNotEmpty) ...[
                  const Text(
                    'Top contributors (by CO₂ saved)',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: _T.ink800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ...topItems.map((e) {
                    final factor =
                    e.kgUsed > 0 ? e.co2Saved / e.kgUsed : 0;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        '• ${e.label}: ${_roundSmart(e.kgUsed)} kg × '
                            '${_roundSmart(factor)} kg CO₂/kg ≈ ${_roundSmart(e.co2Saved)} kg CO₂',
                        style: const TextStyle(
                            fontSize: 13, color: _T.ink700),
                      ),
                    );
                  }),
                  const SizedBox(height: 8),
                ],
                Text(
                  'Time window: $rangeLabel.',
                  style: const TextStyle(fontSize: 12, color: _T.ink500),
                ),
                if (missingInfo.totalKg > 0) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Note: ~${_roundSmart(missingInfo.totalKg)} kg of logged items '
                        "didn't have impact data yet, so they’re not counted here.",
                    style:
                    const TextStyle(fontSize: 12, color: _T.ink500),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  void _showWaterInfoSheet({
    required BuildContext context,
    required ImpactTotals saved,
    required List<_CatRow> catRows,
    required String rangeLabel,
    required _MissingInfo missingInfo,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _T.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.water_drop, color: _T.blue500),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Water Saved – $rangeLabel',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: _T.ink900,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _fmt(saved.waterSavedL, 'L'),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: _T.ink900,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'How this is calculated',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: _T.ink800,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Each food in your logs has an estimated water footprint (litres per kg). '
                      'We multiply the amount you used by that number and add it up.',
                  style: TextStyle(fontSize: 13, color: _T.ink700),
                ),
                const SizedBox(height: 8),
                Text(
                  'Time window: $rangeLabel.',
                  style: const TextStyle(fontSize: 12, color: _T.ink500),
                ),
                if (missingInfo.totalKg > 0) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Note: ~${_roundSmart(missingInfo.totalKg)} kg of logged items '
                        "didn't have water data yet, so they’re not counted here.",
                    style:
                    const TextStyle(fontSize: 12, color: _T.ink500),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  void _showEnergyInfoSheet({
    required BuildContext context,
    required ImpactTotals saved,
    required String rangeLabel,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _T.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.bolt, color: _T.amber500),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Energy Equivalent – $rangeLabel',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: _T.ink900,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _fmt(saved.energySavedKwh, 'kWh'),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: _T.ink900,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'How this is calculated',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: _T.ink800,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'If a food has an energy factor (kWh per kg), we use it directly. '
                      'If not, we convert CO₂ saved into kWh using an average grid intensity, '
                      'then convert that into “homes powered for a day”.',
                  style: TextStyle(fontSize: 13, color: _T.ink700),
                ),
                const SizedBox(height: 8),
                Text(
                  'Time window: $rangeLabel.',
                  style: const TextStyle(fontSize: 12, color: _T.ink500),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showMoneyInfoSheet({
    required BuildContext context,
    required ImpactTotals saved,
    required String rangeLabel,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _T.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.savings, color: _T.green600),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Money Saved – $rangeLabel',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: _T.ink900,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _money(saved.moneySaved),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: _T.ink900,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'How this is calculated',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: _T.ink800,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'We multiply the amount of each food (kg) by its price per kg. '
                      'If you set a price override for a specific food, we use that first. '
                      'Otherwise we fall back to the default price in our dataset.',
                  style: TextStyle(fontSize: 13, color: _T.ink700),
                ),
                const SizedBox(height: 8),
                Text(
                  'Time window: $rangeLabel.',
                  style: const TextStyle(fontSize: 12, color: _T.ink500),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showDiversionInfoSheet({
    required BuildContext context,
    required double divertedPct,
    required List<ConsumedItem> consumed,
    required List<ExpiredItem> expired,
    required String rangeLabel,
  }) {
    final consumedKg =
    consumed.fold<double>(0, (s, e) => s + (e.kg > 0 ? e.kg : 0));
    final expiredKg =
    expired.fold<double>(0, (s, e) => s + (e.kg > 0 ? e.kg : 0));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _T.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.pie_chart, color: _T.green600),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Waste Diverted – $rangeLabel',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: _T.ink900,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '${_roundSmart(divertedPct)} %',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: _T.ink900,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'How this is calculated',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: _T.ink800,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'We compare how much food you used vs how much you logged as wasted in this period.\n\n'
                      'waste diverted % = used kg / (used kg + wasted kg) × 100',
                  style: TextStyle(fontSize: 13, color: _T.ink700),
                ),
                const SizedBox(height: 8),
                Text(
                  'Used: ${_roundSmart(consumedKg)} kg   •   Wasted: ${_roundSmart(expiredKg)} kg',
                  style: const TextStyle(fontSize: 13, color: _T.ink700),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ---------- small helpers ----------

  static String _fmt(num v, String unit) => '${_roundSmart(v)} $unit';

  static String _money(num v) => '\$${_roundSmart(v)}';

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

  static String _normKey(String s) =>
      s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '_');

  static String _leafOf(String key) {
    final cleaned = key.trim().toLowerCase();

    // 1. First split using dot (dataset uses dots)
    if (cleaned.contains('.')) return cleaned.split('.').last;

    // 2. If user enters "chocolate" → return chocolate
    final leaf = cleaned.replaceAll(RegExp(r'\s+'), '_');
    return leaf;
  }

  static String _titleCase(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1).replaceAll('_', ' ');
  }

  static String _rangeLabel(String range) {
    switch (range) {
      case '30d':
        return 'Last 30 days';
      case '90d':
        return 'Last 90 days';
      default:
        return 'Last 7 days';
    }
  }

  static List<_CatRow> _buildCategoryRows(
      List<ConsumedItem> consumed,
      Map<String, ImpactFactor> factors,
      ) {
    final map = <String, _CatRow>{};
    for (final c in consumed) {
      final leaf = _leafOf(c.name);
      final f = factors[_normKey(c.name)] ?? factors[_normKey(leaf)];
      final co2 = (f?.co2ePerKg ?? 0) * c.kg;
      final entry = map.putIfAbsent(
        leaf,
            () => _CatRow(
          label: _titleCase(leaf),
          co2Saved: 0,
          kgUsed: 0,
          color: _pickColor(leaf),
        ),
      );
      map[leaf] = entry.copyWith(
        co2Saved: entry.co2Saved + co2,
        kgUsed: entry.kgUsed + c.kg,
      );
    }
    final rows = map.values.toList()
      ..sort((a, b) => b.co2Saved.compareTo(a.co2Saved));
    return rows.take(4).toList();
  }

  static Color _pickColor(String key) {
    final h = key.hashCode;
    final palette = [
      _T.green600,
      _T.blue500,
      _T.amber500,
      _T.rose500,
      const Color(0xFF6366F1),
      const Color(0xFF14B8A6),
    ];
    return palette[h % palette.length];
  }
}

/// Simple bundle for logs + price overrides
class _LogsBundle {
  final List<ConsumedItem> consumed;
  final List<ExpiredItem> expired;
  final Map<String, double> priceOverrides;

  const _LogsBundle({
    required this.consumed,
    required this.expired,
    required this.priceOverrides,
  });

  const _LogsBundle.empty()
      : consumed = const [],
        expired = const [],
        priceOverrides = const {};
}

class _MissingInfo {
  final double consumedKg;
  final double expiredKg;

  const _MissingInfo({
    required this.consumedKg,
    required this.expiredKg,
  });

  double get totalKg => consumedKg + expiredKg;
}

/// ===============================
///  HERO APP BAR (gradient header)
/// ===============================
class _HeroAppBar extends StatelessWidget {
  final String range;
  final String rangeLabel;
  final ValueChanged<String> onRangeChanged;
  const _HeroAppBar({
    required this.range,
    required this.rangeLabel,
    required this.onRangeChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      pinned: true,
      expandedHeight: 190,
      elevation: 0,
      backgroundColor: _T.white,
      automaticallyImplyLeading: false,
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [_T.green700, _T.green500],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.only(
              bottomLeft: Radius.circular(32),
              bottomRight: Radius.circular(32),
            ),
          ),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(_T.pad, 12, _T.pad, 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Back button row
                  Row(
                    children: [
                      _CircleIconButton(
                        icon: Icons.arrow_back,
                        onTap: () => Navigator.of(context).maybePop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Waste Dashboard',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    rangeLabel,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                    ),
                  ),
                  const Spacer(),
                  _RangeChips(value: range, onChanged: onRangeChanged),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CircleIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: _alpha(Colors.white, 0.18),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Icon(
          icon,
          color: Colors.white,
          size: 20,
        ),
      ),
    );
  }
}

/// ===============================
///  RANGE CHIPS
/// ===============================
class _RangeChips extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const _RangeChips({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final items = ['7d', '30d', '90d'];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _alpha(Colors.white, 0.22),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: items.map((it) {
          final selected = it == value;
          return GestureDetector(
            onTap: () => onChanged(it),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: selected ? Colors.white : Colors.transparent,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                it.toUpperCase(),
                style: TextStyle(
                  color: selected ? _T.green700 : Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// ===============================
///  SECTION TITLE
/// ===============================
class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w800,
          color: _T.ink900,
        ),
      ),
    );
  }
}

/// ===============================
///  SUMMARY IMPACT CARD
/// ===============================
class _SummaryImpactCard extends StatelessWidget {
  final ImpactTotals saved;
  final String drivingLine;
  final String showersLine;
  final String homesLine;
  final List<double> trend;
  final VoidCallback onCo2Info;
  final VoidCallback onWaterInfo;
  final VoidCallback onEnergyInfo;
  final VoidCallback onMoneyInfo;

  const _SummaryImpactCard({
    required this.saved,
    required this.drivingLine,
    required this.showersLine,
    required this.homesLine,
    required this.trend,
    required this.onCo2Info,
    required this.onWaterInfo,
    required this.onEnergyInfo,
    required this.onMoneyInfo,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _T.white,
        borderRadius: BorderRadius.circular(_T.rLg),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 12,
            offset: Offset(0, 4),
          )
        ],
      ),
      padding: const EdgeInsets.all(_T.pad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Your impact at a glance',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: _T.ink900,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Based on what you used and wasted this period.',
            style: TextStyle(fontSize: 12, color: _T.ink500),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _MiniStatTile(
                  title: 'CO₂ saved',
                  value: _WasteDashboardPageState._fmt(
                      saved.co2SavedKg, 'kg'),
                  subtitle: drivingLine,
                  icon: Icons.eco,
                  iconBg: _T.green600,
                  onInfo: onCo2Info,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MiniStatTile(
                  title: 'Water saved',
                  value: _WasteDashboardPageState._fmt(
                      saved.waterSavedL, 'L'),
                  subtitle: showersLine,
                  icon: Icons.water_drop,
                  iconBg: _T.blue500,
                  onInfo: onWaterInfo,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _MiniStatTile(
                  title: 'Energy (equiv.)',
                  value: _WasteDashboardPageState._fmt(
                      saved.energySavedKwh, 'kWh'),
                  subtitle: homesLine,
                  icon: Icons.bolt,
                  iconBg: _T.amber500,
                  onInfo: onEnergyInfo,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MiniStatTile(
                  title: 'Money saved',
                  value:
                  _WasteDashboardPageState._money(saved.moneySaved),
                  subtitle: 'Based on price/kg factors',
                  icon: Icons.savings,
                  iconBg: _T.green500,
                  onInfo: onMoneyInfo,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            'CO₂ trend',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _T.ink500,
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 60,
            width: double.infinity,
            child: CustomPaint(
              painter: _SparklinePainter(
                data: trend,
                color: _T.green600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniStatTile extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color iconBg;
  final VoidCallback onInfo;

  const _MiniStatTile({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.iconBg,
    required this.onInfo,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _T.bg,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: iconBg,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 16, color: Colors.white),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.info_outline,
                    size: 16, color: _T.ink400),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: onInfo,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: _T.ink900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _T.ink700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, color: _T.ink400),
          ),
        ],
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  final List<double> data;
  final Color color;
  _SparklinePainter({required this.data, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;
    final maxV =
    (data.reduce((a, b) => a > b ? a : b)).clamp(1, 9999).toDouble();
    final minV = data.reduce((a, b) => a < b ? a : b).toDouble();

    final path = Path();
    for (int i = 0; i < data.length; i++) {
      final x = (i / (data.length - 1)) * size.width;
      final y = size.height -
          ((data[i] - minV) / (maxV - minV + 0.0001)) * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    final fillPaint = Paint()
      ..shader = LinearGradient(
        colors: [_alpha(color, 0.22), _alpha(color, 0.02)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(fill, fillPaint);

    final stroke = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) =>
      oldDelegate.data != data || oldDelegate.color != color;
}

/// ===============================
///  DIVERTED RING CARD
/// ===============================
class _DivertCard extends StatelessWidget {
  final double percent; // 0..100
  final VoidCallback? onInfo;
  const _DivertCard({required this.percent, this.onInfo});

  @override
  Widget build(BuildContext context) {
    final pct = percent.clamp(0, 100);
    return Container(
      decoration: BoxDecoration(
        color: _T.white,
        borderRadius: BorderRadius.circular(_T.rLg),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 12,
            offset: Offset(0, 4),
          )
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: pct / 100),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOut,
            builder: (context, value, _) => SizedBox(
              width: 60,
              height: 60,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CircularProgressIndicator(
                    value: value,
                    strokeWidth: 7,
                    backgroundColor: _alpha(_T.green500, .14),
                    valueColor:
                    const AlwaysStoppedAnimation(_T.green600),
                  ),
                  Center(
                    child: Text(
                      '${(value * 100).round()}%',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  )
                ],
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Waste diverted',
                        style: TextStyle(
                          fontSize: 13,
                          color: _T.ink700,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (onInfo != null)
                      IconButton(
                        icon: const Icon(Icons.info_outline,
                            size: 18, color: _T.ink400),
                        onPressed: onInfo,
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'How much food you used vs how much was wasted in this period.',
                  style: TextStyle(fontSize: 12, color: _T.ink400),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// ===============================
///  CATEGORY ROW LIST
/// ===============================
class _CatRow {
  final String label;
  final double co2Saved;
  final double kgUsed;
  final Color color;
  _CatRow({
    required this.label,
    required this.co2Saved,
    required this.kgUsed,
    required this.color,
  });

  _CatRow copyWith({double? co2Saved, double? kgUsed}) => _CatRow(
    label: label,
    co2Saved: co2Saved ?? this.co2Saved,
    kgUsed: kgUsed ?? this.kgUsed,
    color: color,
  );
}

class _CategoryRowList extends StatelessWidget {
  final List<_CatRow> rows;
  const _CategoryRowList({required this.rows});

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _T.white,
          borderRadius: BorderRadius.circular(_T.rLg),
        ),
        child: const Text(
          'Cook a recipe or log what you used to see category breakdown 🎉',
        ),
      );
    }

    final max =
    rows.map((e) => e.co2Saved).reduce((a, b) => a > b ? a : b);
    return Container(
      decoration: BoxDecoration(
        color: _T.white,
        borderRadius: BorderRadius.circular(_T.rLg),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        children: rows.map((e) {
          final pct = max > 0 ? (e.co2Saved / max) : 0.0;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: e.color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    e.label,
                    style:
                    const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Text(
                  '${e.kgUsed.toStringAsFixed(2)} kg',
                  style:
                  const TextStyle(fontSize: 12, color: _T.ink500),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 140,
                  height: 10,
                  child: Stack(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: _T.bg,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      FractionallySizedBox(
                        widthFactor: pct.clamp(0, 1),
                        child: Container(
                          decoration: BoxDecoration(
                            color: e.color,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// ===============================
///  INFO CARDS
/// ===============================
class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _InfoCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _T.white,
        borderRadius: BorderRadius.circular(_T.rLg),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 10,
            offset: Offset(0, 3),
          )
        ],
      ),
      padding: const EdgeInsets.all(_T.pad),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient:
              LinearGradient(colors: [_T.green600, _T.green400]),
            ),
            child: Icon(icon, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: _T.ink900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  body,
                  style: const TextStyle(color: _T.ink700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// ===============================
///  QUICK ACTIONS ROW
/// ===============================
class _QuickActionsRow extends StatelessWidget {
  final VoidCallback onScan;
  final VoidCallback onAdd;

  const _QuickActionsRow({
    required this.onScan,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onScan,
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: _alpha(_T.ink400, 0.5)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
              ),
              padding: const EdgeInsets.symmetric(vertical: 10),
            ),
            icon: const Icon(Icons.document_scanner, size: 18),
            label: const Text(
              'Scan item',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onAdd,
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: _alpha(_T.ink400, 0.5)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
              ),
              padding: const EdgeInsets.symmetric(vertical: 10),
            ),
            icon: const Icon(Icons.add, size: 18),
            label: const Text(
              'Add log',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }
}

/// ===============================
///  INSIGHTS ROW (HORIZONTAL CARDS)
/// ===============================
class _InsightsRow extends StatelessWidget {
  final String missedSavingsText;
  final String suggestionText;

  const _InsightsRow({
    required this.missedSavingsText,
    required this.suggestionText,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          SizedBox(
            width: 260,
            child: _InfoCard(
              icon: Icons.lightbulb,
              title: "Missed savings",
              body: missedSavingsText,
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 260,
            child: _InfoCard(
              icon: Icons.tips_and_updates,
              title: "Suggestion",
              body: suggestionText,
            ),
          ),
        ],
      ),
    );
  }
}

