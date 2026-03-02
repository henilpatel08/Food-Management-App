import 'package:flutter/material.dart';
import '../../../services/inventory_service.dart';
import '../../../widgets/recipe_card.dart';

class FavoritesPage extends StatefulWidget {
  const FavoritesPage({super.key});

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  final InventoryService _service = InventoryService();
  bool _loading = true;

  List<Map<String, dynamic>> _recipes = [];

  @override
  void initState() {
    super.initState();
    _loadFavorites();
  }

  Future<void> _loadFavorites() async {
    final data = await _service.fetchLikedRecipes();
    setState(() {
      _recipes = data;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_recipes.isEmpty) {
      return const Center(
        child: Text("❤️ No favorite recipes yet"),
      );
    }

    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      itemCount: _recipes.length,
      itemBuilder: (context, index) {
        final recipe = _recipes[index];

        return RecipeCard(
          key: ValueKey(recipe['id']),
          recipe: recipe,

          // ❤️ ONLY remove when user un-likes
          onLikeChanged: (liked) {
            if (!liked) {
              final id = recipe['id'];
              setState(() {
                _recipes.removeWhere((r) => r['id'] == id);
              });
            }
          },

          // 🔖 Saving/unsaving DOES NOT remove from favorites
          onSaveChanged: (saved) {
            // do nothing
          },
        );
      },
    );
  }
}
