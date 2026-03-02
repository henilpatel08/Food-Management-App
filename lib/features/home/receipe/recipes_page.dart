import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../services/notification_manager.dart';
import '../../../widgets/recipe_card.dart';
import '../../../services/inventory_service.dart';
import 'package:sust_ai_n/main.dart';

class RecipesPage extends StatefulWidget {
  final List<String> inventoryItems;

  const RecipesPage({super.key, required this.inventoryItems});

  @override
  RecipesPageState createState() => RecipesPageState();
}

class RecipesPageState extends State<RecipesPage> with RouteAware {
  bool _isLoading = false;
  List<Map<String, dynamic>> _recipes = [];

  final String _apiKey = dotenv.env['SpoonacularapiKey'] ?? '';

  /// ⭐ Stores survey data: diet + intolerance + cuisine
  Map<String, dynamic>? _userPreferences;

  @override
  void initState() {
    super.initState();

    _loadUserPreferences().then((_) {
      _fetchRecipes(widget.inventoryItems);
    });

    NotificationManager().checkExpiringItems();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    routeObserver.subscribe(this, ModalRoute.of(context)!);
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPopNext() async {
    final updatedItems = await InventoryService().fetchInventoryItems();
    _fetchRecipes(updatedItems);
  }

  // ============================================================
  // 🔥 Load Survey Preferences
  // ============================================================
  Future<void> _loadUserPreferences() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final doc = await FirebaseFirestore.instance
        .collection("users")
        .doc(user.uid)
        .get();

    final survey = doc.data()?["profile"]?["survey"];
    if (survey != null) {
      setState(() => _userPreferences = survey);
    }

    print("🔥 Loaded survey prefs → $_userPreferences");
  }

  void searchRecipes(String query) {
    if (query.isEmpty) {
      _fetchRecipes(widget.inventoryItems);
    } else {
      _fetchRecipes([query]);
    }
  }

  void clearSearch() {
    _fetchRecipes(widget.inventoryItems);
  }

  void refreshWithNewInventory(List<String> updatedItems) {
    if (!mounted) return;
    _fetchRecipes(updatedItems);
  }

  // ============================================================
  // 🔥 Fetch Recipes with Diet / Intolerance / Cuisine Filters
  // ============================================================
  Future<void> _fetchRecipes(List<String> ingredients) async {
    if (ingredients.isEmpty) return;
    setState(() => _isLoading = true);

    try {
      // -----------------------------
      // Read user preferences
      // -----------------------------
      final dietaryRaw = List<String>.from(_userPreferences?['dietaryRestrictions'] ?? []);
      final intoleranceRaw = List<String>.from(_userPreferences?['intolerances'] ?? []);
      final cuisinesRaw = List<String>.from(_userPreferences?['preferredCuisines'] ?? []);

      // Remove “None”
      final dietary = dietaryRaw.contains("None") ? [] : dietaryRaw.map(_normalize).toList();
      final intolerances = intoleranceRaw.contains("None") ? [] : intoleranceRaw.map(_normalize).toList();
      final cuisines = cuisinesRaw.contains("None") ? [] : cuisinesRaw;

      print("⭐ Filters applied →");
      print("   Diet = $dietary");
      print("   Intolerances = $intolerances");
      print("   Cuisines = $cuisines");

      // -----------------------------
      // Spoonacular Query Params
      // -----------------------------
      final params = {
        'apiKey': _apiKey,
        'number': '15',                     // directly get 15
        'addRecipeNutrition': 'true',
        'addRecipeInformation': 'true',
        if (dietary.isNotEmpty) 'diet': dietary.join(','),
        if (intolerances.isNotEmpty) 'intolerances': intolerances.join(','),
        if (cuisines.isNotEmpty) 'cuisine': cuisines.join(','),
      };

      print("🔗 ComplexSearch Params: $params");

      // -----------------------------
      // API CALL
      // -----------------------------
      final searchRes = await http.get(
        Uri.https("api.spoonacular.com", "/recipes/complexSearch", params),
      );

      if (searchRes.statusCode != 200) {
        print("❌ ComplexSearch failed → ${searchRes.statusCode}");
        return;
      }

      final jsonBody = json.decode(searchRes.body);
      final List results = jsonBody["results"] ?? [];

      print("🍽 Found ${results.length} filtered recipes");

      // -----------------------------
      // Build final list (NO INVENTORY MATCHING)
      // -----------------------------
      final List<Map<String, dynamic>> finalRecipes = [];

      for (final r in results) {
        final nutrition = r["nutrition"];
        final calories = nutrition?["nutrients"]?.firstWhere(
              (n) => n["name"] == "Calories",
          orElse: () => null,
        )?["amount"];

        final ingredientsList = (nutrition?["ingredients"] ?? [])
            .map((e) => {
          "name": (e["name"] ?? "").toString(),
        })
            .toList();

        finalRecipes.add({
          "id": r["id"],
          "title": r["title"],
          "image": r["image"],
          "servings": r["servings"],
          "calories": calories,
          "extendedIngredients": ingredientsList,  // ✅ back to List<Map<String,dynamic>>
        });

      }

      if (!mounted) return;
      setState(() => _recipes = finalRecipes);

    } catch (e) {
      print("❌ ERROR in _fetchRecipes → $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }


  // Utility: Normalize filter words
  String _normalize(String v) =>
      v.toLowerCase().replaceAll(" ", "").trim();

  // ============================================================
  // UI
  // ============================================================
  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_recipes.isEmpty) {
      return const Center(child: Text("No recipes found"));
    }

    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      itemCount: _recipes.length,
      itemBuilder: (context, index) {
        final recipe = _recipes[index];
        return RecipeCard(
          key: ValueKey(recipe['id']),
          recipe: recipe,
          onLikeChanged: (liked) {},
          onSaveChanged: (saved) {},
        );
      },
    );
  }
}
