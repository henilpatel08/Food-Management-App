import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import '../../../services/inventory_service.dart';
import '../features/home/receipe/recipe_detail_page.dart';
import '../services/grocery_service.dart';
import '../utils/ingredient_utils.dart';

class RecipeCard extends StatefulWidget {
  final Map<String, dynamic> recipe;

  final void Function(bool liked)? onLikeChanged;
  final void Function(bool saved)? onSaveChanged;

  const RecipeCard({
    super.key,
    required this.recipe,
    this.onLikeChanged,
    this.onSaveChanged,
  });

  @override
  State<RecipeCard> createState() => _RecipeCardState();
}

class _RecipeCardState extends State<RecipeCard> {
  final InventoryService _service = InventoryService();

  bool isLiked = false;
  bool isSaved = false;

  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  Future<void> _checkStatus() async {
    final id = widget.recipe['id'];
    final liked = await _service.isRecipeLiked(id);
    final saved = await _service.isRecipeSaved(id);

    if (!mounted) return;

    setState(() {
      isLiked = liked;
      isSaved = saved;
    });
  }

  // ================================================================
  // POPUP FOR INGREDIENT CHECK
  // ================================================================
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
                      style:
                      TextStyle(fontWeight: FontWeight.w600)),
                if (have.isNotEmpty)
                  ...have.map((i) => Padding(
                    padding: const EdgeInsets.only(left: 6, top: 4),
                    child: Text("• $i", style: const TextStyle(color: Colors.green)),
                  )),

                const SizedBox(height: 16),

                if (missing.isNotEmpty)
                  const Text("❌ Missing ingredients:",
                      style:
                      TextStyle(fontWeight: FontWeight.w600)),
                if (missing.isNotEmpty)
                  ...missing.map((i) => Padding(
                    padding: const EdgeInsets.only(left: 6, top: 4),
                    child: Text("• $i", style: const TextStyle(color: Colors.red)),
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
                  for (final item in missing) {
                    await GroceryService().addCategorizedItem(item, "1");
                  }

                  Navigator.pop(context);

                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text("Missing ingredients added to grocery list!")),
                  );
                },
                child: const Text("Add to List"),
              ),
          ],
        );
      },
    );
  }

  // ================================================================
  // REMOVE INGREDIENTS WHEN USER CLICKS TICK
  // ================================================================
  // ================================================================
// TICK BUTTON — DO EVERYTHING THAT "YES" USED TO DO (NO POPUP)
// ================================================================
  // ================================================================
// TICK BUTTON — REMOVE INGREDIENTS (simple matching, NO normalization)
// ================================================================
  Future<void> _handleTickAction(BuildContext context) async {
    final recipeId = widget.recipe['id'];
    if (recipeId == null) {
      print("❌ No recipe ID found.");
      return;
    }

    print("\nFetching FULL recipe info for ID: $recipeId");

    // Fetch recipe info
    final url = Uri.https(
      "api.spoonacular.com",
      "/recipes/$recipeId/information",
      {"apiKey": dotenv.env['SpoonacularapiKey']},
    );

    final response = await http.get(url);

    if (response.statusCode != 200) {
      print("❌ Failed to fetch full recipe details.");
      return;
    }

    final data = jsonDecode(response.body);

    // SAFELY extract extendedIngredients
    final rawList = data["extendedIngredients"];
    if (rawList is! List) {
      print("❌ ERROR: extendedIngredients is not a List");
      return;
    }

    // Bulletproof extraction — only take valid Maps
    final ingredientNames = <String>[];

    for (final item in rawList) {
      if (item is Map && item.containsKey("name")) {
        final name = item["name"]
            .toString()
            .toLowerCase()
            .trim();

        if (name.isNotEmpty) {
          ingredientNames.add(name);
        }
      }
    }

    print("=====================================");
    print("🟩 RAW Recipe Ingredient Names:");
    ingredientNames.forEach((i) => print(" → $i"));
    print("=====================================");

    if (ingredientNames.isEmpty) {
      print("❌ No ingredient names extracted from API.");
      return;
    }

    // DELETE inventory + grocery items
    await InventoryService().removeIngredientsFromInventory(ingredientNames);
    await GroceryService().removeIngredientsFromGrocery(ingredientNames);

    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("✔ Ingredients removed from inventory & grocery."),
      ),
    );
  }



  // ================================================================
  @override
  Widget build(BuildContext context) {
    final r = widget.recipe;

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => RecipeDetailPage(
              recipeId: r['id'],
              title: r['title'],
            ),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),

        // ================================================================
        // MAIN STACK: IMAGE + LIKE/SAVE + TICK
        // ================================================================
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                // IMAGE
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                  child: Image.network(
                    r['image'] ?? "",
                    height: 150,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),

                // LIKE + SAVE TOP RIGHT
                Positioned(
                  right: 10,
                  top: 10,
                  child: Row(
                    children: [
                      // LIKE BUTTON
                      _circleButton(
                        icon: isLiked ? Icons.favorite : Icons.favorite_border,
                        color: Colors.red,
                        onTap: () async {
                          final id = r['id'];

                          if (isLiked) {
                            await _service.unlikeRecipe(id);
                          } else {
                            await _service.likeRecipe(r);
                          }

                          setState(() => isLiked = !isLiked);
                          widget.onLikeChanged?.call(isLiked);
                        },
                      ),

                      const SizedBox(width: 10),

                      // SAVE BUTTON + POPUP
                      _circleButton(
                        icon: isSaved ? Icons.bookmark : Icons.bookmark_border,
                        color: Colors.black87,
                        onTap: () async {
                          final id = r['id'];

                          if (isSaved) {
                            await _service.unsaveRecipe(id);
                            setState(() => isSaved = false);
                            widget.onSaveChanged?.call(false);
                            return;
                          }

                          // SAVE RECIPE
                          await _service.saveRecipe(r);
                          setState(() => isSaved = true);
                          widget.onSaveChanged?.call(true);

                          // SHOW POPUP
                          if (r['extendedIngredients'] != null) {
                            final ingredients = (r['extendedIngredients'] as List)
                                .map((e) => (e['name'] ?? '').toString())
                                .toList();

                            final status = await _service.getIngredientStatus(ingredients);
                            final have = status["have"] ?? [];
                            final missing = status["missing"] ?? [];

                            if (context.mounted) {
                              _showIngredientStatusDialog(context, have, missing);
                            }
                          }
                        },
                      ),
                    ],
                  ),
                ),

                // TICK BUTTON BOTTOM RIGHT
                Positioned(
                  right: 10,
                  bottom: 10,
                  child: _circleButton(
                    icon: Icons.check_circle_outline,
                    color: Colors.green,
                    onTap: () => _handleTickAction(context),
                  ),
                ),
              ],
            ),

            // TITLE + SERVINGS
            Padding(
              padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    r['title'] ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "🍽 ${r['servings']} servings",
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ================================================================
  // ROUND ICON BUTTON WIDGET
  // ================================================================
  Widget _circleButton({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(28),
      child: Container(
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.9),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 5,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(
          icon,
          size: 22,
          color: color,
        ),
      ),
    );
  }
}
