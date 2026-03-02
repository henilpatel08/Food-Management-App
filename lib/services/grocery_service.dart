import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import '../utils/ingredient_utils.dart';

class GroceryService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  late final String _spoonacularKey;

  GroceryService() {
    _spoonacularKey = dotenv.env['SpoonacularapiKey'] ?? '';
  }

  // ---------------------------------------------------------------------------
  // REMOVE from grocery list → fuzzy delete (potatoes, potato, peeled potato…)
  // ---------------------------------------------------------------------------
  // ================================================================
// REMOVE INGREDIENTS FROM GROCERY LIST (simple substring match)
// ================================================================
  Future<void> removeIngredientsFromGrocery(List<String> recipeIngredients) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final ref = _firestore
        .collection("users")
        .doc(user.uid)
        .collection("groceryList");

    final snapshot = await ref.get();

    print("\n======== GROCERY DELETE SIMPLE MATCH ========");

    for (final doc in snapshot.docs) {
      final groceryName = (doc['name'] ?? '').toString().toLowerCase().trim();

      for (final recipeItem in recipeIngredients) {
        final recipeName = recipeItem.toLowerCase();

        // SIMPLE MATCH RULE:
        // recipeIngredient contains groceryName → delete
        // OR groceryName contains recipeIngredient → delete
        if (recipeName.contains(groceryName) || groceryName.contains(recipeName)) {
          print("🗑 Removing GROCERY item: '$groceryName' (matched with '$recipeName')");
          await doc.reference.delete();
          break; // move to next grocery item
        }
      }
    }

    print("======== DONE GROCERY DELETE ========\n");
  }

  // ---------------------------------------------------------------------------
  // CATEGORY LOOKUP USING Spoonacular
  // ---------------------------------------------------------------------------
  Future<String> determineCategory(String name) async {
    try {
      final searchUri = Uri.https(
        'api.spoonacular.com',
        '/food/ingredients/search',
        {
          'query': name,
          'number': '1',
          'apiKey': _spoonacularKey,
        },
      );

      final searchRes = await http.get(searchUri);
      if (searchRes.statusCode != 200) return "Other";

      final searchData = json.decode(searchRes.body);
      if (searchData['results'] == null ||
          searchData['results'].isEmpty) return "Other";

      final id = searchData['results'][0]['id'].toString();

      final infoUri = Uri.https(
        'api.spoonacular.com',
        '/food/ingredients/$id/information',
        {'amount': '1', 'apiKey': _spoonacularKey},
      );

      final infoRes = await http.get(infoUri);
      if (infoRes.statusCode != 200) return "Other";

      final infoData = json.decode(infoRes.body);

      final aisle = (infoData['aisle'] ?? "").toString();
      final categoryPath = infoData['categoryPath'];

      String category = "Other";

      if (categoryPath is List && categoryPath.isNotEmpty) {
        category = categoryPath.last.toString();
      } else if (aisle.isNotEmpty) {
        category = aisle;
      }

      return _capitalize(category);
    } catch (_) {
      return "Other";
    }
  }

  String _capitalize(String v) {
    if (v.isEmpty) return v;
    return v[0].toUpperCase() + v.substring(1);
  }

  // ---------------------------------------------------------------------------
  // ADD grocery item with automatic category
  // ---------------------------------------------------------------------------
  Future<void> addCategorizedItem(String name, String qty) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception("User not signed in");

    final cleanLower = name.trim().toLowerCase();

    // Prevent duplicates
    final check = await _firestore
        .collection('users')
        .doc(user.uid)
        .collection('groceryList')
        .where('nameLower', isEqualTo: cleanLower)
        .limit(1)
        .get();

    if (check.docs.isNotEmpty) return;

    final category = await determineCategory(name);

    await _firestore
        .collection('users')
        .doc(user.uid)
        .collection('groceryList')
        .add({
      'name': name,
      'nameLower': cleanLower,
      'qty': qty,
      'category': category,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  // ---------------------------------------------------------------------------
  // DELETE a single item manually
  // ---------------------------------------------------------------------------
  Future<void> deleteItem(String docId) async {
    final user = _auth.currentUser;
    if (user == null) return;

    await _firestore
        .collection('users')
        .doc(user.uid)
        .collection('groceryList')
        .doc(docId)
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

  // ---------------------------------------------------------------------------
  // STREAM grocery items by category → ALWAYS includes doc.id
  // ---------------------------------------------------------------------------
  Stream<Map<String, List<Map<String, dynamic>>>> streamGroceryItems() {
    final user = _auth.currentUser;
    if (user == null) throw Exception("User not signed in");

    return _firestore
        .collection('users')
        .doc(user.uid)
        .collection('groceryList')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) {
      final Map<String, List<Map<String, dynamic>>> grouped = {};

      for (var doc in snapshot.docs) {
        final data = doc.data();

        final category = (data['category'] ?? 'Other').toString();

        grouped.putIfAbsent(category, () => []);
        grouped[category]!.add({
          'id': doc.id,
          'name': data['name'],
          'nameLower': data['nameLower'],
          'qty': data['qty'],
        });
      }

      return grouped;
    });
  }
}
