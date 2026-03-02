import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

class RecipeDetailPage extends StatefulWidget {
  final int recipeId;
  final String title;

  const RecipeDetailPage({
    super.key,
    required this.recipeId,
    required this.title,
  });

  @override
  State<RecipeDetailPage> createState() => _RecipeDetailPageState();
}

class _RecipeDetailPageState extends State<RecipeDetailPage> {
  bool _isLoading = true;
  Map<String, dynamic>? _recipe;
  late final String _apiKey;
  @override
  void initState() {
    super.initState();
    _apiKey = dotenv.env['SpoonacularapiKey'] ?? '';

    _fetchRecipeDetails(); // ❗ Now safe
  }


  Future<void> _fetchRecipeDetails() async {
    try {
      final uri = Uri.https(
        'api.spoonacular.com',
        '/recipes/${widget.recipeId}/information',
        {'includeNutrition': 'true', 'apiKey': _apiKey},
      );
      final res = await http.get(uri);
      if (res.statusCode == 200) {
        setState(() {
          _recipe = json.decode(res.body);
          _isLoading = false;
        });
      } else {
        debugPrint('⚠️ Failed to fetch details: ${res.body}');
        setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('❌ Error fetching recipe: $e');
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_recipe == null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: const Center(child: Text('Recipe details not available')),
      );
    }

    final recipe = _recipe!;
    final ingredients = (recipe['extendedIngredients'] as List?)
        ?.map((e) => (e['originalString'] ?? e['name'] ?? '') as String)
        .where((s) => s.isNotEmpty)
        .toList() ??
        [];


    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: Text(
          recipe['title'] ?? widget.title,
          style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w600),
        ),
        iconTheme: const IconThemeData(color: Colors.black),
        elevation: 0,
      ),
      backgroundColor: Colors.white,
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 🖼 Image
            if (recipe['image'] != null)
              ClipRRect(
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
                child: Image.network(
                  recipe['image'],
                  height: 240,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    height: 240,
                    color: Colors.grey[200],
                    child: const Icon(Icons.fastfood, size: 64, color: Colors.grey),
                  ),
                ),
              ),

            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    recipe['title'] ?? widget.title,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "🍽 ${recipe['servings']} servings  |  🔥 ${_extractCalories(recipe)} kcal",
                    style: const TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                  const SizedBox(height: 16),

                  // 🧾 Summary
                  if (recipe['summary'] != null)
                    Text(
                      _removeHtml(recipe['summary']),
                      style: const TextStyle(fontSize: 15, height: 1.5),
                    ),

                  const SizedBox(height: 20),
                  const Text(
                    "Ingredients",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  for (final i in ingredients)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text("• $i"),
                    ),

                  const SizedBox(height: 24),

                  // 🌐 View full recipe link
                  if (recipe['sourceUrl'] != null)
                    TextButton.icon(
                      onPressed: () {
                        // optional: use url_launcher to open external page
                      },
                      icon: const Icon(Icons.open_in_new),
                      label: const Text("View full recipe"),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 🔹 Helper: get calories from nutrition block
  String _extractCalories(Map<String, dynamic> recipe) {
    final nutrients = (recipe['nutrition']?['nutrients'] as List?) ?? [];
    final calRow = nutrients.cast<Map>().firstWhere(
          (n) => n['name'] == 'Calories',
      orElse: () => {},
    );
    if (calRow.isEmpty) return 'N/A';
    return calRow['amount'].round().toString();
  }

  // 🔹 Helper: strip HTML tags from summary
  String _removeHtml(String htmlText) {
    final regex = RegExp(r'<[^>]*>');
    return htmlText.replaceAll(regex, '');
  }
}
