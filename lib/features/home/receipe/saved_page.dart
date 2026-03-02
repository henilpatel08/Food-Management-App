import 'package:flutter/material.dart';
import '../../../services/inventory_service.dart';
import '../../../widgets/recipe_card.dart';

class SavedPage extends StatefulWidget {
  const SavedPage({super.key});

  @override
  State<SavedPage> createState() => _SavedPageState();
}

class _SavedPageState extends State<SavedPage> {
  final InventoryService _service = InventoryService();

  bool _loading = true;
  List<Map<String, dynamic>> _recipes = [];

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    final data = await _service.fetchSavedRecipes();
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
        child: Text("📌 You haven't saved any recipes yet"),
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

          // ❤️ Liking has NO effect on saved list
          onLikeChanged: (liked) {
            // do nothing
          },

          // 🔖 ONLY remove item when user un-saves
          onSaveChanged: (saved) {
            if (!saved) {
              final id = recipe['id'];
              setState(() {
                _recipes.removeWhere((r) => r['id'] == id);
              });
            }
          },
        );
      },
    );
  }
}
