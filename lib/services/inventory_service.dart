import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

import '../utils/ingredient_utils.dart';

/// InventoryService — combines Spoonacular metadata + USDA FoodKeeper shelf-life estimation.
class InventoryService {
  late final String _spoonacularKey;

  InventoryService() {
    _spoonacularKey = dotenv.env['SpoonacularapiKey'] ?? '';
  }


  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final Map<String, Map<String, String>> _categoryCache = {};

  // ----------------------------------------------------------
  // 🧠 Get Shelf Life (FoodKeeper API + debug output)
  // ----------------------------------------------------------

  /// 🔹 Fetch shelf life for a product from the USDA FoodKeeper dataset (online only)
  /// 🔹 Fetch shelf life for a product from the USDA FoodKeeper dataset (v128 schema)
  /// 🔹 Fetch shelf life for a product from the USDA FoodKeeper dataset (v128 schema)
  Future<int?> getShelfLifeDays(String productName) async {
    try {
      final response = await http.get(
        Uri.parse('https://www.fsis.usda.gov/shared/data/EN/foodkeeper.json'),
      );
      print('🌐 HTTP ${response.statusCode}, size: ${response.body.length} bytes');

      if (response.statusCode != 200) {
        throw Exception('Failed to fetch FoodKeeper data');
      }

      final decoded = json.decode(response.body);

      // ✅ Navigate to "sheets" → sheet with name "Product"
      if (decoded is! Map || !decoded.containsKey('sheets')) {
        print('⚠️ Unexpected USDA JSON structure (no "sheets")');
        return null;
      }

      final sheets = decoded['sheets'] as List<dynamic>;
      final productSheet = sheets.firstWhere(
            (sheet) => (sheet['name'] ?? '').toString().toLowerCase() == 'product',
        orElse: () => {},
      );

      if (productSheet.isEmpty || productSheet['data'] == null) {
        print('⚠️ No "Product" sheet found in USDA data');
        return null;
      }

      final List<dynamic> data = productSheet['data'];
      final query = productName.toLowerCase().trim();

      // 🔍 Each entry is a list of maps like [{"Name":"Bacon"},{"Name_subtitle":...}]
      Map<String, dynamic>? rowMap;
      for (final row in data) {
        if (row is List) {
          final flat = {
            for (final cell in row)
              if (cell is Map && cell.isNotEmpty) cell.keys.first: cell.values.first
          };
          final name = (flat['Name'] ?? '').toString().toLowerCase();
          if (name.contains(query)) {
            rowMap = flat.cast<String, dynamic>();

            break;
          }
        }
      }

      if (rowMap == null) {
        print('⚠️ No matching product found for "$productName"');
        return null;
      }

      print('🔍 Matched entry for $productName: ${rowMap['Name']}');

      // 🧠 Extract numeric fields
      double? minValue;
      double? maxValue;
      String? metric;

      for (final prefix in [
        'DOP_Refrigerate',
        'Refrigerate',
        'DOP_Pantry',
        'Pantry',
        'DOP_Freeze',
        'Freeze'
      ]) {
        if (rowMap['${prefix}_Min'] != null &&
            rowMap['${prefix}_Metric'] != null) {
          minValue = (rowMap['${prefix}_Min'] as num).toDouble();
          maxValue = (rowMap['${prefix}_Max'] as num?)?.toDouble() ?? minValue;
          metric = rowMap['${prefix}_Metric']?.toString();
          print('🧩 Found $prefix → $minValue–$maxValue $metric');
          break;
        }
      }

      if (minValue == null || metric == null) {
        print('⚠️ No numeric shelf life info for "$productName"');
        return null;
      }

      final avg = (minValue + maxValue!) / 2;
      final days = _convertMetricToDays(avg, metric);

      print('📅 $productName lasts ≈ $days days ($avg $metric)');
      return days;
    } catch (e, st) {
      print('❌ Shelf life lookup failed for "$productName": $e');
      print(st);
      return null;
    }
  }

  int _convertMetricToDays(double value, String metric) {
    switch (metric.toLowerCase()) {
      case 'day':
      case 'days':
        return value.round();
      case 'week':
      case 'weeks':
        return (value * 7).round();
      case 'month':
      case 'months':
        return (value * 30).round();
      case 'year':
      case 'years':
        return (value * 365).round();
      default:
        return value.round();
    }
  }



  Future<void> likeRecipe(Map<String, dynamic> recipe) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final uid = user.uid;

    // Path for liked recipe
    final path = "users/$uid/recipe/liked/${recipe['id']}";
    print("📌 Writing liked recipe to -> $path");

    final data = {
      'id': recipe['id'],
      'title': recipe['title'],
      'image': recipe['image'],
      'servings': recipe['servings'],
      'timestamp': FieldValue.serverTimestamp(),
    };

    try {
      await _firestore
          .collection('users')
          .doc(uid)
          .collection('recipe')
          .doc('liked')       // parent doc
          .collection('items') // subcollection
          .doc(recipe['id'].toString())
          .set(data);

      print("❤️ SUCCESS: Liked recipe saved → ${recipe['id']}");
    } catch (e) {
      print("❌ FIRESTORE WRITE FAILED → $e");
    }
  }

  // ================================================================
// REMOVE ONLY ONE ITEM + LOG IT AS CONSUMED
// ================================================================
  Future<void> removeIngredientsFromInventory(List<String> recipeIngredients) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final ref = FirebaseFirestore.instance
        .collection("users")
        .doc(user.uid)
        .collection("inventory");

    final snapshot = await ref.get();

    for (final recipeItem in recipeIngredients) {
      final recipeName = recipeItem.toLowerCase();

      // Find matches
      final matches = snapshot.docs.where((d) {
        final invName = d['name'].toString().toLowerCase();
        return recipeName.contains(invName) || invName.contains(recipeName);
      }).toList();

      if (matches.isEmpty) continue;

      // Sort by expiry
      matches.sort((a, b) {
        final da = (a['expiryDate'] as Timestamp).toDate();
        final db = (b['expiryDate'] as Timestamp).toDate();
        return da.compareTo(db);
      });

      final doc = matches.first; // earliest-expiring
      final data = doc.data();

      final name = data['name'];
      final qty = data['qty'] ?? 1;
      final unit = data['unit'] ?? 'pcs';
      final category = data['category'] ?? 'other';

      // 1️⃣ LOG AS CONSUMED
      await logItemConsumed(
        name: name,
        category: category,
        qty: qty,
        unit: unit,
      );

      // 2️⃣ DELETE FROM INVENTORY
      print("🗑 Removing INVENTORY → $name (logged as consumed)");
      await doc.reference.delete();
    }
  }
// =============================================================
// REMOVE ONE SPECIFIC INVENTORY ITEM BY DOC ID (manual delete)
// =============================================================
  Future<void> removeSingleItemById(String docId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final ref = FirebaseFirestore.instance
        .collection("users")
        .doc(user.uid)
        .collection("inventory")
        .doc(docId);

    final snap = await ref.get();
    if (!snap.exists) return;

    final data = snap.data()!;
    final name = data['name'];
    final qty = data['qty'] ?? 1;
    final unit = data['unit'] ?? 'pcs';
    final category = data['category'] ?? 'other';

    // log to waste dashboard
    await logItemConsumed(
      name: name,
      category: category,
      qty: qty,
      unit: unit,
    );

    // delete actual item
    await ref.delete();

    print("🗑 Manually removed $name (ID: $docId)");
  }





  Future<void> saveRecipe(Map<String, dynamic> recipe) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final uid = user.uid;

    final data = {
      'id': recipe['id'],
      'title': recipe['title'],
      'image': recipe['image'],
      'servings': recipe['servings'],
      'timestamp': FieldValue.serverTimestamp(),
    };

    try {
      await _firestore
          .collection('users')
          .doc(uid)
          .collection('recipe')
          .doc('saved')
          .collection('items')
          .doc(recipe['id'].toString())
          .set(data);

      print("📌 SUCCESS: Saved recipe → ${recipe['id']}");
    } catch (e) {
      print("❌ FIRESTORE WRITE FAILED → $e");
    }
  }






  Future<List<Map<String, dynamic>>> fetchLikedRecipes() async {
    final uid = _auth.currentUser!.uid;

    final snap = await _firestore
        .collection('users')
        .doc(uid)
        .collection('recipe')
        .doc('liked')
        .collection('items')
        .orderBy('timestamp', descending: true)
        .get();

    return snap.docs.map((d) => d.data()).toList();
  }

  Future<List<Map<String, dynamic>>> fetchSavedRecipes() async {
    final uid = _auth.currentUser!.uid;

    final snap = await _firestore
        .collection('users')
        .doc(uid)
        .collection('recipe')
        .doc('saved')
        .collection('items')
        .orderBy('timestamp', descending: true)
        .get();

    return snap.docs.map((d) => d.data()).toList();
  }

  Future<bool> isRecipeLiked(int id) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return false;

    final snap = await _firestore
        .collection('users')
        .doc(uid)
        .collection('recipe')
        .doc('liked')
        .collection('items')
        .doc(id.toString())
        .get();

    return snap.exists;
  }

  Future<bool> isRecipeSaved(int id) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return false;

    final snap = await _firestore
        .collection('users')
        .doc(uid)
        .collection('recipe')
        .doc('saved')
        .collection('items')
        .doc(id.toString())
        .get();

    return snap.exists;
  }
  Future<void> unlikeRecipe(int id) async {
    final uid = _auth.currentUser!.uid;

    await _firestore
        .collection('users')
        .doc(uid)
        .collection('recipe')
        .doc('liked')
        .collection('items')
        .doc(id.toString())
        .delete();
  }

  Future<void> unsaveRecipe(int id) async {
    final uid = _auth.currentUser!.uid;

    await _firestore
        .collection('users')
        .doc(uid)
        .collection('recipe')
        .doc('saved')
        .collection('items')
        .doc(id.toString())
        .delete();
  }
  String normalizeName(String name) {
    return coreIngredient(
        name
            .trim()
            .toLowerCase()
            .replaceAll(RegExp(r'[^a-z ]'), '') // remove punctuation
            .replaceAll(RegExp(r'\s+'), ' ')   // remove double spaces
    );
  }




  /// 🔸 Convert human-readable durations like "3-5 days" or "2 weeks" to integer days
  int? _parseShelfLifeToDays(String shelfLife) {
    if (shelfLife.isEmpty || shelfLife.toLowerCase().contains('varies')) return null;

    final regex = RegExp(
      r'(\d+)(?:\s*(?:-|–|to)\s*(\d+))?\s*(day|week|month|year)',
      caseSensitive: false,
    );

    final match = regex.firstMatch(shelfLife);
    if (match == null) return null;

    final minValue = int.parse(match.group(1)!);
    final maxValue = match.group(2) != null ? int.parse(match.group(2)!) : minValue;
    final avg = (minValue + maxValue) / 2;
    final unit = match.group(3)!.toLowerCase();

    switch (unit) {
      case 'day':
      case 'days':
        return avg.round();
      case 'week':
      case 'weeks':
        return (avg * 7).round();
      case 'month':
      case 'months':
        return (avg * 30).round();
      case 'year':
      case 'years':
        return (avg * 365).round();
      default:
        return null;
    }
  }

  /// 🔹 Default multi-storage expiry options (for notification and reminders)
  Map<String, int> _getDefaultShelfLifeOptions() {
    return {
      'pantry': 7,          // 1 week
      'refrigerator': 20,   // 3 weeks
      'freezer': 90,        // 3 months
    };
  }

  // ----------------------------------------------------------
// ----------------------------------------------------------
// 🔹 Add Single Item
  Future<void> addItem({
    required String name,
    required num qty,
    required String unit,
    String sourceType = 'Manual',
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('User not signed in');

    final lowerName = name.toLowerCase().trim();

    // 🍽 Get Spoonacular category + aisle
    final catData = await _getCategoryAndAisle(lowerName);
    final aisle = catData['aisle'] ?? 'General';
    final category = catData['category'] ?? 'General';

    // 🧠 Get estimated shelf life (FoodKeeper)
    final shelfLifeDays = await getShelfLifeDays(lowerName) ?? 7;

    // 📅 Date added (local)
    final dateAdded = DateTime.now();

    // ⏳ **expiry = dateAdded + shelf-life days**
    final expiryDate = dateAdded.add(Duration(days: shelfLifeDays));

    final ref = _firestore
        .collection('users')
        .doc(user.uid)
        .collection('inventory')
        .doc();

    await ref.set({
      'name': lowerName,
      'qty': qty,
      'unit': unit,
      'category': category,
      'aisle': aisle,
      'approxExpiryDays': shelfLifeDays,
      'dateAdded': Timestamp.fromDate(dateAdded),
      'expiryDate': Timestamp.fromDate(expiryDate),
      'sourceType': sourceType,
      'timestamp': FieldValue.serverTimestamp(),
    });

    debugPrint(
        '✅ Added $lowerName → $category | Shelf: $shelfLifeDays days | Expiry: ${expiryDate.toLocal()}');
  }


// ----------------------------------------------------------
// 🔹 Add Multiple Items (Batch Add)
// ----------------------------------------------------------
  // ----------------------------------------------------------
// 🔹 Add Multiple Items (SAFE VERSION - waits for each API)
// ----------------------------------------------------------
  Future<void> addItems(List<Map<String, dynamic>> items) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('User not signed in');

    final ref = _firestore
        .collection('users')
        .doc(user.uid)
        .collection('inventory');

    debugPrint("🟦 Adding ${items.length} scanned items (with API validation)...");

    for (final item in items) {
      final rawName = (item['name'] ?? '').toString().trim().toLowerCase();
      if (rawName.isEmpty) continue;

      debugPrint("🔍 Processing → $rawName");

      // 1️⃣ CATEGORY + AISLE LOOKUP (WAIT)
      final catData = await _getCategoryAndAisle(rawName);
      final aisle = catData['aisle'] ?? 'General';
      final category = catData['category'] ?? 'General';

      debugPrint("📌 Category = $category | Aisle = $aisle");

      // 2️⃣ Shelf life lookup (WAIT)
      final shelfLifeDays = await getShelfLifeDays(rawName) ?? 7;
      final dateAdded = DateTime.now();
      final expiry = dateAdded.add(Duration(days: shelfLifeDays));

      // 3️⃣ WRITE to Firestore sequentially
      await ref.add({
        'name': rawName,
        'qty': item['qty'] ?? 1,
        'unit': item['unit'] ?? 'pcs',
        'category': category,
        'aisle': aisle,
        'approxExpiryDays': shelfLifeDays,
        'dateAdded': Timestamp.fromDate(dateAdded),
        'expiryDate': Timestamp.fromDate(expiry),
        'sourceType': item['sourceType'] ?? 'Scan',
        'timestamp': FieldValue.serverTimestamp(),
      });

      debugPrint("✅ Added → $rawName | Exp: $expiry");
    }

    debugPrint("🎉 DONE: Added ${items.length} scanned items safely.");
  }

  Future<List<String>> getMissingIngredients(List<String> ingredients) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return [];

    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('inventory')
        .get();

    final inventoryNames = snap.docs
        .map((d) => d['name'].toString().toLowerCase())
        .toList();

    final missing = <String>[];

    for (final ing in ingredients) {
      if (!inventoryNames.contains(ing.toLowerCase())) {
        missing.add(ing);
      }
    }

    return missing;
  }
  Future<Map<String, List<String>>> getIngredientStatus(List<String> ingredients) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return {"have": [], "missing": []};

    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('inventory')
        .get();

    final inventoryCoreNames = snap.docs
        .map((d) => coreIngredient(d['name'].toString()))
        .toList();

    final have = <String>[];
    final missing = <String>[];

    for (final ing in ingredients) {
      final core = coreIngredient(ing);

      if (inventoryCoreNames.contains(core)) {
        have.add(ing);
      } else {
        missing.add(ing);
      }
    }

    return {"have": have, "missing": missing};
  }


  Future<void> addToGroceryList(String name) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('groceryList')
        .add({
      'name': name,
      'qty': 1,
      'addedAt': DateTime.now(),
    });
  }

  // ================================================================
// 📌 LOG AN ITEM AS CONSUMED (for Waste Dashboard)
// ================================================================
  Future<void> logItemConsumed({
    required String name,
    required String category,
    required num qty,
    required String unit,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final userDoc = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid);

    // 1️⃣ Convert qty + unit → kg
    final double kg = _convertToKg(qty, unit);

    // 2️⃣ Canonical keys
    final leaf = _norm(name);
    final cat = _norm(category);
    final key = "$cat.$leaf";

    // 3️⃣ Add to Firestore consumption_logs
    await userDoc.collection('consumption_logs').add({
      'name': name,
      'key': key,
      'leafKey': leaf,
      'category': category,
      'kg': kg,
      'at': Timestamp.now(),
    });

    print("📗 Logged consumed → $name  |  $kg kg");
  }

// simple helpers:
  String _norm(String v) =>
      v.toLowerCase().trim().replaceAll(RegExp(r'\s+'), '_');

// convert qty to kg (common-use logic)
  double _convertToKg(num qty, String unit) {
    unit = unit.toLowerCase().trim();

    if (unit == "kg") return qty.toDouble();
    if (unit == "g" || unit == "gram" || unit == "grams") return qty / 1000;
    if (unit == "lb" || unit == "lbs") return qty * 0.453592;
    if (unit == "oz" || unit == "ounce" || unit == "ounces") return qty * 0.0283495;

    // default fallback: assume 1 item ≈ 0.15kg
    return (qty * 0.15).toDouble();
  }





  // ----------------------------------------------------------
  // 🔹 Get Category + Aisle from Spoonacular
  // ----------------------------------------------------------
  Future<Map<String, String>> _getCategoryAndAisle(String name) async {
    final lower = name.toLowerCase().trim();

    // 🔹 Cached result? → Return instantly
    if (_categoryCache.containsKey(lower)) {
      return _categoryCache[lower]!;
    }

    // 🔹 Retry up to 3 times
    for (int attempt = 1; attempt <= 3; attempt++) {
      try {
        final searchUri = Uri.https(
          'api.spoonacular.com',
          '/food/ingredients/search',
          {
            'query': lower,
            'number': '1',
            'apiKey': _spoonacularKey,
          },
        );

        final searchRes = await http.get(searchUri);

        // ⭐ Check for rate limit issues
        if (searchRes.statusCode == 402 || searchRes.statusCode == 429) {
          print("⏳ Spoonacular RATE-LIMIT (attempt $attempt). Retrying…");
          await Future.delayed(const Duration(milliseconds: 500));
          continue;
        }

        if (searchRes.statusCode != 200) break;

        final searchData = json.decode(searchRes.body);

        if (searchData['results'] == null || searchData['results'].isEmpty) break;

        final id = searchData['results'][0]['id'].toString();

        // ============================
        // Fetch ingredient information
        // ============================
        final infoUri = Uri.https(
          'api.spoonacular.com',
          '/food/ingredients/$id/information',
          {'amount': '1', 'apiKey': _spoonacularKey},
        );

        final infoRes = await http.get(infoUri);

        if (infoRes.statusCode == 402 || infoRes.statusCode == 429) {
          print("⏳ RATE-LIMIT for info (attempt $attempt). Retrying...");
          await Future.delayed(const Duration(milliseconds: 600));
          continue;
        }

        if (infoRes.statusCode != 200) break;

        final infoData = json.decode(infoRes.body);

        // Extract aisle/category properly
        final aisle = (infoData['aisle'] ?? 'General');
        String category = 'General';

        if (infoData['categoryPath'] != null &&
            infoData['categoryPath'] is List &&
            (infoData['categoryPath'] as List).isNotEmpty) {
          category = (infoData['categoryPath'] as List).last.toString();
        }

        final result = {
          'aisle': aisle.toString(),
          'category': category.toString(),
        };

        _categoryCache[lower] = result; // ⭐ cache it
        return result;
      } catch (e) {
        print("❌ Spoonacular lookup failed (attempt $attempt): $e");
        await Future.delayed(const Duration(milliseconds: 400));
      }
    }

    // Default fallback (only reached if ALL retries fail)
    print("⚠️ Falling back to general category for '$name'");
    return {'aisle': 'General', 'category': 'General'};
  }

  String _capitalize(String v) => v.isEmpty
      ? v
      : v
      .split(' ')
      .map((w) => w.isNotEmpty
      ? '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}'
      : '')
      .join(' ');

  // ----------------------------------------------------------
  // 🔹 Ingredient Image via Spoonacular
  // ----------------------------------------------------------
  Future<String?> fetchIngredientImage(String name) async {
    try {
      final cleaned = name.toLowerCase().trim();
      final searchUri = Uri.https(
        'api.spoonacular.com',
        '/food/ingredients/search',
        {'query': cleaned, 'number': '5', 'apiKey': _spoonacularKey},
      );

      final res = await http.get(searchUri);
      if (res.statusCode != 200) return null;

      final data = json.decode(res.body);
      if (data['results'] == null || data['results'].isEmpty) return null;

      final result = (data['results'] as List)[0];
      if (result['image'] != null) {
        return 'https://spoonacular.com/cdn/ingredients_250x250/${result['image']}';
      }
      return null;
    } catch (e) {
      debugPrint('❌ Failed to fetch ingredient image for $name: $e');
      return null;
    }
  }

  // ----------------------------------------------------------
  // 🔹 Firestore Helpers
  // ----------------------------------------------------------
  Stream<List<Map<String, dynamic>>> getItems() {
    final user = _auth.currentUser;
    if (user == null) throw Exception('User not signed in');
    return _firestore
        .collection('users')
        .doc(user.uid)
        .collection('inventory')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) {
      final data = d.data();
      data['id'] = d.id;
      return data;
    }).toList());
  }

  Future<List<String>> fetchInventoryItems() async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('User not signed in');
    final snapshot = await _firestore
        .collection('users')
        .doc(user.uid)
        .collection('inventory')
        .get();
    return snapshot.docs
        .map((d) => (d.data()['name'] ?? '').toString().trim().toLowerCase())
        .where((n) => n.isNotEmpty)
        .toList();
  }
}
