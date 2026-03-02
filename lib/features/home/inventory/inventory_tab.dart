import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../services/grocery_service.dart';
import '../../../services/inventory_service.dart';
import '../../../widgets/bottom_nav_bar.dart';
import '../receipe/recipe_detail_page.dart';
import '/features/chatbot/chat_page.dart';

class InventoryTab extends StatefulWidget {
  const InventoryTab({super.key});

  @override
  State<InventoryTab> createState() => _InventoryTabState();
}

class _InventoryTabState extends State<InventoryTab> {
  final InventoryService _inventoryService = InventoryService();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  late final String _apiKey;
  Timer? _debounceTimer;

  bool _isLoadingRecipes = false;

  late StreamSubscription _inventorySub;
  late StreamSubscription _lastPurchasedSub;
  late StreamSubscription _likedSub;
  late StreamSubscription _savedSub;

  /// LIVE ICON STATES
  Set<int> _likedRecipeIds = {};
  Set<int> _savedRecipeIds = {};

  Map<String, int> _categoryCounts = {};
  List<Map<String, dynamic>> _recipes = [];
  List<Map<String, dynamic>> _lastPurchased = [];
  final GroceryService _groceryService = GroceryService();
  final Map<String, Color> _categoryColorMap = {};

  @override
  void initState() {
    super.initState();

    _apiKey = dotenv.env['SpoonacularapiKey'] ?? '';

    // 🔥 Load random recipes ONCE while real inventory loads
    _fetchFallbackRandom();

    // 🔥 Inventory listener → handles main recipe fetch automatically
    _listenToInventory();

    _listenToLastPurchased();
    _listenToLikedRecipes();
    _listenToSavedRecipes();
  }

  void _showIngredientStatusDialog(
      BuildContext context,
      List<String> have,
      List<String> missing,
      ) {
    showDialog(
      context: context,
      builder: (_) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text("Ingredient Check",
              style: TextStyle(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (have.isNotEmpty)
                  const Text("✔ You already have:",
                      style: TextStyle(fontWeight: FontWeight.w600)),
                ...have.map((i) => Padding(
                  padding: const EdgeInsets.only(left: 6, top: 4),
                  child:
                  Text("• $i", style: const TextStyle(color: Colors.green)),
                )),

                const SizedBox(height: 16),

                if (missing.isNotEmpty)
                  const Text("❌ Missing ingredients:",
                      style: TextStyle(fontWeight: FontWeight.w600)),
                ...missing.map((i) => Padding(
                  padding: const EdgeInsets.only(left: 6, top: 4),
                  child:
                  Text("• $i", style: const TextStyle(color: Colors.red)),
                )),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Close"),
            ),

            if (missing.isNotEmpty)
              ElevatedButton(
                onPressed: () async {
                  for (final m in missing) {
                    await _groceryService.addCategorizedItem(m, "1");
                  }

                  Navigator.pop(context);

                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text("Missing ingredients added to grocery!")),
                  );
                },
                child: const Text("Add to Grocery"),
              ),
          ],
        );
      },
    );
  }



  // ---------------------------------------------------------
  // 🔴 LISTEN FOR LIKED RECIPES
  // ---------------------------------------------------------
  void _listenToLikedRecipes() {
    final user = _auth.currentUser;
    if (user == null) return;

    _likedSub = _firestore
        .collection("users")
        .doc(user.uid)
        .collection("recipe")
        .doc("liked")
        .collection("items")
        .snapshots()
        .listen((snap) {
      final ids = snap.docs.map((d) => int.parse(d.id)).toSet();

      if (mounted) {
        setState(() => _likedRecipeIds = ids);
      }
    });
  }

  // ---------------------------------------------------------
  // 🔖 LISTEN FOR SAVED RECIPES
  // ---------------------------------------------------------
  void _listenToSavedRecipes() {
    final user = _auth.currentUser;
    if (user == null) return;

    _savedSub = _firestore
        .collection("users")
        .doc(user.uid)
        .collection("recipe")
        .doc("saved")
        .collection("items")
        .snapshots()
        .listen((snap) {
      final ids = snap.docs.map((d) => int.parse(d.id)).toSet();

      if (mounted) {
        setState(() => _savedRecipeIds = ids);
      }
    });
  }

  // ---------------------------------------------------------
  // 📦 INVENTORY LISTENER
  // ---------------------------------------------------------
  void _listenToInventory() {
    final user = _auth.currentUser;
    if (user == null) return;

    _inventorySub = _firestore
        .collection('users')
        .doc(user.uid)
        .collection('inventory')
        .snapshots()
        .listen((snapshot) async {

      final Map<String, int> categoryCounts = {};

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final rawCategory = (data['category'] ?? '').toString().trim().toLowerCase();
        final rawAisle = (data['aisle'] ?? '').toString().trim().toLowerCase();

        final category = (rawCategory.isEmpty ||
            rawCategory == 'general' ||
            rawCategory == 'misc' ||
            rawCategory == 'other')
            ? (rawAisle.isNotEmpty ? _capitalize(rawAisle) : 'Uncategorized')
            : _capitalize(rawCategory);

        categoryCounts[category] = (categoryCounts[category] ?? 0) + 1;
      }

      if (!mounted) return;

      setState(() => _categoryCounts = categoryCounts);

      // 🔥 Avoid spamming API — debounce to 1 fetch
      _debounceTimer?.cancel();

      _debounceTimer = Timer(const Duration(seconds: 1), () {
        if (!mounted) return;

        if (snapshot.docs.isEmpty) {
          // 🔥 No inventory → keep random recipes only ONCE
          print("⚠ No inventory → keep random recipes.");
          return;
        }

        print("🍳 Inventory updated → loading recipes...");
        _fetchTopRecipes();
      });
    });
  }

  // ---------------------------------------------------------
  // 🛒 LAST PURCHASED LISTENER
  // ---------------------------------------------------------
  void _listenToLastPurchased() {
    final user = _auth.currentUser;
    if (user == null) return;

    _lastPurchasedSub = _firestore
        .collection('users')
        .doc(user.uid)
        .collection('inventory')
        .orderBy('timestamp', descending: true)
        .limit(10)
        .snapshots()
        .listen((snapshot) {
      final items = snapshot.docs.map((d) {
        final data = d.data();
        data['id'] = d.id;
        return data;
      }).toList();

      if (!mounted) return;

      setState(() => _lastPurchased = items);
    });
  }

  // ---------------------------------------------------------
  // 🍳 FETCH RECIPES
  // ---------------------------------------------------------
  Future<void> _fetchTopRecipes() async {
    if (_apiKey.isEmpty) return;
    // NEW — small delay to ensure inventory is loaded
    await Future.delayed(const Duration(milliseconds: 600));
    final ingredients = await _inventoryService.fetchInventoryItems();

    print("🔥 Ingredients fetched: $ingredients");

    if (mounted) setState(() => _isLoadingRecipes = true);

    try {
      // =====================================================
      // CASE 1: Inventory is EMPTY → Fetch random recipes
      // =====================================================
      if (ingredients.isEmpty) {
        print("⚠ Inventory empty → loading random recipes...");

        final randRes = await http.get(
          Uri.https(
            'api.spoonacular.com',
            '/recipes/random',
            {'number': '8', 'apiKey': _apiKey},
          ),
        );

        if (randRes.statusCode == 200) {
          final data = jsonDecode(randRes.body);
          final List recipes = data['recipes'] ?? [];

          final parsed = recipes.map<Map<String, dynamic>>((r) {
            return {
              "id": r["id"],
              "title": r["title"],
              "image": r["image"],
              "servings": r["servings"],
              "extendedIngredients": r["extendedIngredients"] ?? [],
            };
          }).toList();

          if (mounted) setState(() => _recipes = parsed);
        }

        return; // important
      }

      // =====================================================
      // CASE 2: Inventory exists → Fetch ingredient-based recipes
      // =====================================================

      final cleanIngredients = ingredients
          .map((e) => e.toLowerCase().replaceAll(RegExp(r'[^a-z ]'), '').trim())
          .where((e) => e.length > 2)
          .toList();

      print("🔍 Ingredients sent to Spoonacular:");
      cleanIngredients.forEach((e) => print(" - $e"));

      // STEP 1 — findByIngredients
      final findRes = await http.get(
        Uri.https(
          'api.spoonacular.com',
          '/recipes/findByIngredients',
          {
            'ingredients': cleanIngredients.join(','),
            'number': '20',
            'ranking': '2',
            'apiKey': _apiKey,
          },
        ),
      );

      if (findRes.statusCode != 200) {
        print("❌ findByIngredients error: ${findRes.body}");
        return;
      }

      final List findData = jsonDecode(findRes.body);

      if (findData.isEmpty) {
        print("⚠ No match recipes → fallback to random recipes");

        return _fetchFallbackRandom(); // << fallback
      }

      final ids = findData.map((r) => r['id'].toString()).toList();

      // STEP 2 — Bulk info
      final bulk = await http.get(
        Uri.https(
          'api.spoonacular.com',
          '/recipes/informationBulk',
          {
            'ids': ids.join(','),
            'includeIngredients': 'true',
            'includeNutrition': 'false',
            'apiKey': _apiKey,
          },
        ),
      );

      if (bulk.statusCode != 200) {
        print("❌ informationBulk error → random fallback");
        return _fetchFallbackRandom();
      }

      final List infoData = jsonDecode(bulk.body);

      final List<Map<String, dynamic>> parsed = [];
      for (final recipe in infoData) {
        final img = recipe['image'] ?? "";

        if (!img.startsWith("http")) continue;

        parsed.add({
          "id": recipe["id"],
          "title": recipe["title"],
          "image": img,
          "servings": recipe["servings"],
          "extendedIngredients": recipe["extendedIngredients"] ?? [],
        });

        if (parsed.length >= 8) break;
      }

      if (mounted) setState(() => _recipes = parsed);

    } catch (e) {
      print("❌ Recipe fetch error: $e");
      _fetchFallbackRandom();
    } finally {
      if (mounted) setState(() => _isLoadingRecipes = false);
    }
  }
  Future<void> _fetchFallbackRandom() async {
    print("🔁 Fetching fallback random recipes...");

    final randRes = await http.get(
      Uri.https(
        'api.spoonacular.com',
        '/recipes/random',
        {'number': '8', 'apiKey': _apiKey},
      ),
    );

    if (randRes.statusCode != 200) return;

    final data = jsonDecode(randRes.body);
    final List recipes = data['recipes'] ?? [];

    final parsed = recipes.map<Map<String, dynamic>>((r) {
      return {
        "id": r["id"],
        "title": r["title"],
        "image": r["image"],
        "servings": r["servings"],
        "extendedIngredients": r["extendedIngredients"] ?? [],
      };
    }).toList();

    if (mounted) setState(() => _recipes = parsed);
  }


  // ---------------------------------------------------------
  @override
  void dispose() {
    try {
      _inventorySub.cancel();
      _lastPurchasedSub.cancel();
      _likedSub.cancel();
      _savedSub.cancel();
    } catch (_) {}
    super.dispose();
  }

  // ---------------------------------------------------------
  String _capitalize(String v) => v.isEmpty
      ? v
      : v[0].toUpperCase() + v.substring(1);

  Color _getColor(String category) {
    if (_categoryColorMap.containsKey(category)) {
      return _categoryColorMap[category]!;
    }

    final random = Random();
    Color newColor;

    do {
      newColor = Color.fromARGB(
        255,
        100 + random.nextInt(155),
        100 + random.nextInt(155),
        100 + random.nextInt(155),
      );
    } while (_categoryColorMap.values.contains(newColor));

    _categoryColorMap[category] = newColor;
    return newColor;
  }

  String emoji(String name) {
    name = name.toLowerCase();
    if (name.contains('milk')) return '🥛';
    if (name.contains('banana')) return '🍌';
    if (name.contains('apple')) return '🍎';
    return '🛒';
  }

  // ---------------------------------------------------------
  // UI STARTS HERE
  // ---------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final fullName = _auth.currentUser?.displayName ?? "there";
    final userName = fullName.split(" ").first;

    return Scaffold(
      backgroundColor: const Color(0xFFF9F9F9),

      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(width * 0.045),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // HEADER
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "Hi $userName,\nHere’s what you have!",
                    style: TextStyle(
                      fontSize: width * 0.055,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  IconButton(
                    onPressed: _fetchTopRecipes,
                    icon: const Icon(Icons.refresh, size: 26),
                  ),
                ],
              ),


              SizedBox(height: width * 0.05),

              // SEARCH BAR
InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ChatPage(), 
                    ),
                  );
                },
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: width * 0.04,
                    vertical: width * 0.03,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(25),
                    boxShadow: [
                      BoxShadow(color: Colors.black12, blurRadius: 6),
                    ],
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.search, color: Colors.grey),
                      SizedBox(width: width * 0.02),
                      const Expanded(
                        child: Text(
                          "Ask my AI",
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              SizedBox(height: width * 0.05),

              // INVENTORY OVERVIEW
              const Text("Inventory Overview", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              SizedBox(height: width * 0.05),

              _categoryCounts.isEmpty
                  ? const Center(child: Text("🧺 No items in your inventory"))
                  : Row(
                children: [
                  Expanded(
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: PieChart(
                        PieChartData(
                          centerSpaceRadius: width * 0.08,
                          sections: _categoryCounts.entries.map((e) {
                            return PieChartSectionData(
                              color: _getColor(e.key),
                              value: e.value.toDouble(),
                              title: "",
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: width * 0.04),
                  Expanded(
                    child: Column(
                      children: _categoryCounts.entries
                          .map(
                            (e) => _CategoryTile(
                          color: _getColor(e.key),
                          name: e.key,
                          count: e.value,
                        ),
                      )
                          .toList(),
                    ),
                  ),
                ],
              ),

              SizedBox(height: width * 0.1),

// ==============================
// LAST PURCHASED 🛒
// ==============================
              const Text(
                "Last Purchased 🛒",
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(height: width * 0.04),

              if (_lastPurchased.isEmpty)
                const Text("No recent purchases found.")
              else
                SizedBox(
                  height: width * 0.34,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    itemCount: _lastPurchased.length,
                    padding: EdgeInsets.only(right: width * 0.03),
                    itemBuilder: (context, i) {
                      final item = _lastPurchased[i];
                      final name = item['name'] ?? 'Unnamed';
                      final qty  = item['qty'] ?? '-';
                      final unit = item['unit'] ?? '';

                      return Padding(
                        padding: EdgeInsets.only(left: width * 0.04),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [

                            // -----------------------------
                            // ⭐ IMAGE (NO WHITE BACKGROUND)
                            // slightly larger
                            // -----------------------------
                            FutureBuilder<String?>(
                              future: _inventoryService.fetchIngredientImage(name),
                              builder: (context, snapshot) {
                                final imgUrl = snapshot.data;

                                return SizedBox(
                                  height: width * 0.16,     // bigger image
                                  width:  width * 0.16,
                                  child: imgUrl != null
                                      ? Image.network(
                                    imgUrl,
                                    fit: BoxFit.contain,
                                    errorBuilder: (_, __, ___) =>
                                        Image.asset(
                                          'assets/images/diet.png',
                                          fit: BoxFit.contain,
                                        ),
                                  )
                                      : Image.asset(
                                    'assets/images/diet.png',
                                    fit: BoxFit.contain,
                                  ),
                                );
                              },
                            ),

                            SizedBox(height: width * 0.015),

                            // -----------------------------
                            // FULL NAME (NO ELLIPSIS)
                            // -----------------------------
                            SizedBox(
                              width: width * 0.24,
                              child: Text(
                                name,
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                softWrap: true,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: width * 0.030,
                                ),
                              ),
                            ),

                            SizedBox(height: width * 0.005),

                            // -----------------------------
                            // QUANTITY
                            // -----------------------------
                            Text(
                              "$qty $unit",
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: width * 0.028,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),

              // FOR YOU RECIPES
              const Text("For You 🍳", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              SizedBox(height: width * 0.04),

              if (_isLoadingRecipes)
                const Center(child: CircularProgressIndicator())
              else if (_recipes.isEmpty)
                const Text("No recipe suggestions yet — add items 🧺", style: TextStyle(color: Colors.grey))
              else
                SizedBox(
                  height: width * 0.70,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    itemCount: _recipes.length,
                    itemBuilder: (context, i) {
                      final recipe = _recipes[i];
                      final id = recipe['id'];
                      final title = recipe['title'] ?? 'Untitled';
                      final img = recipe['image'] ?? '';

                      final isLiked = _likedRecipeIds.contains(id);
                      final isSaved = _savedRecipeIds.contains(id);

                      return GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => RecipeDetailPage(recipeId: id, title: title),
                            ),
                          );
                        },
                        child: Container(
                          width: width * 0.58,
                          margin: EdgeInsets.only(right: width * 0.04),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8)],
                          ),
                          child: Column(
                            children: [
                              Stack(
                                children: [
                                  ClipRRect(
                                    borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                                    child: img.isNotEmpty
                                        ? Image.network(
                                      img,
                                      width: double.infinity,
                                      height: width * 0.35,
                                      fit: BoxFit.cover,
                                    )
                                        : Container(
                                      height: width * 0.35,
                                      color: Colors.grey[200],
                                      child: Center(
                                        child: Text(emoji(title), style: TextStyle(fontSize: width * 0.15)),
                                      ),
                                    ),
                                  ),

                                  Positioned(
                                    right: 10,
                                    top: 10,
                                    child: Row(
                                      children: [
                                        // ❤️ LIKE BUTTON
                                        InkWell(
                                          onTap: () async {
                                            final info = await http.get(
                                              Uri.https(
                                                "api.spoonacular.com",
                                                "/recipes/$id/information",
                                                {"apiKey": _apiKey},
                                              ),
                                            );

                                            if (info.statusCode == 200) {
                                              final data = json.decode(info.body);

                                              if (isLiked) {
                                                await _inventoryService.unlikeRecipe(id);
                                              } else {
                                                await _inventoryService.likeRecipe(data);
                                              }
                                            }
                                          },
                                          child: Container(
                                            padding: const EdgeInsets.all(6),
                                            decoration: BoxDecoration(
                                              color: Colors.white.withOpacity(0.7),
                                              shape: BoxShape.circle,
                                            ),
                                            child: Icon(
                                              isLiked ? Icons.favorite : Icons.favorite_border,
                                              color: Colors.red,
                                            ),
                                          ),
                                        ),

                                        const SizedBox(width: 12),

                                        // 🔖 SAVE BUTTON
                                        InkWell(
                                          onTap: () async {
                                            final info = await http.get(
                                              Uri.https(
                                                "api.spoonacular.com",
                                                "/recipes/$id/information",
                                                {"apiKey": _apiKey},
                                              ),
                                            );

                                            if (info.statusCode != 200) return;

                                            final data = json.decode(info.body);

                                            // ----- UNSAVE -----
                                            if (isSaved) {
                                              await _inventoryService.unsaveRecipe(id);
                                              return;
                                            }

                                            // ----- SAVE -----
                                            await _inventoryService.saveRecipe(data);

                                            // ----- Extract ingredient names -----
                                            final List ext = data["extendedIngredients"] ?? [];
                                            final List<String> ingredientNames =
                                            ext.map<String>((e) => e["name"].toString()).toList();

                                            // ----- Check have/missing -----
                                            final status =
                                            await _inventoryService.getIngredientStatus(ingredientNames);

                                            final have = List<String>.from(status["have"] ?? []);
                                            final missing = List<String>.from(status["missing"] ?? []);

                                            if (!mounted) return;

                                            // ----- Show popup -----
                                            _showIngredientStatusDialog(context, have, missing);
                                          },

                                          child: Container(
                                            padding: const EdgeInsets.all(6),
                                            decoration: BoxDecoration(
                                              color: Colors.white.withOpacity(0.7),
                                              shape: BoxShape.circle,
                                            ),
                                            child: Icon(
                                              isSaved ? Icons.bookmark : Icons.bookmark_border,
                                              color: Colors.black,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),

                              Padding(
                                padding: EdgeInsets.all(width * 0.03),
                                child: Column(
                                  children: [
                                    Text(
                                      title,
                                      maxLines: 2,
                                      textAlign: TextAlign.center,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: width * 0.04,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),

                                    SizedBox(height: width * 0.02),

                                    Text(
                                      "Servings: ${recipe['servings'] ?? '-'}",
                                      style: TextStyle(color: Colors.grey, fontSize: width * 0.03),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),

      bottomNavigationBar: BottomNavBar(
        currentIndex: 0,
        onTap: (index) {
          if (index == 1) Navigator.pushNamed(context, '/recipes');
          if (index == 2) Navigator.pushNamed(context, '/userinventory');
          if (index == 3) Navigator.pushNamed(context, '/profile');
        },
      ),
    );
  }
}


// ---------------------------------------------------------
// CATEGORY TILE WIDGET
// ---------------------------------------------------------
class _CategoryTile extends StatelessWidget {
  final Color color;
  final String name;
  final int count;

  const _CategoryTile({
    required this.color,
    required this.name,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: width * 0.01),
      child: Row(
        children: [
          CircleAvatar(radius: width * 0.015, backgroundColor: color),
          SizedBox(width: width * 0.03),
          Expanded(child: Text(name, style: TextStyle(fontSize: width * 0.035))),
          Text("$count", style: TextStyle(fontWeight: FontWeight.bold, fontSize: width * 0.035)),
        ],
      ),
    );
  }
}
