import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sust_ai_n/features/home/receipe/favorites_page.dart';
import 'package:sust_ai_n/features/home/receipe/saved_page.dart';

import '../../../services/notification_service.dart';
import '../../../widgets/bottom_nav_bar.dart';
import '../../../widgets/inventory_tab_selector.dart';
import 'grocery_list_page.dart';
import 'recipes_page.dart';

class ReceipeBasePage extends StatefulWidget {
  const ReceipeBasePage({super.key});

  @override
  State<ReceipeBasePage> createState() => _ReceipeBasePageState();
}

class _ReceipeBasePageState extends State<ReceipeBasePage> {
  int _selectedTabIndex = 0;
  final TextEditingController _searchController = TextEditingController();

  List<String> _inventoryItems = [];
  bool _isLoadingInventory = true;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
    _listenToInventoryChanges();

  }

  /// 🔹 Real-time listener for Firestore inventory
  void _listenToInventoryChanges() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('inventory')
        .snapshots()
        .listen((snapshot) {
      final updatedItems = snapshot.docs
          .map((doc) => doc['name']?.toString() ?? '')
          .where((name) => name.isNotEmpty)
          .toList();

      setState(() {
        _inventoryItems = updatedItems;
        _isLoadingInventory = false;
      });

      if (_selectedTabIndex == 0) {
        recipesPageKey.currentState?.refreshWithNewInventory(updatedItems);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final height = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: Colors.white,

      // ---------- App Bar ----------
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          _selectedTabIndex == 0 ? "Recipes" : "My Grocery List",
          style: const TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
      ),

      // ---------- Body ----------
      body: Padding(
        padding: EdgeInsets.symmetric(horizontal: width * 0.05),
        child: _isLoadingInventory
            ? const Center(child: CircularProgressIndicator())
            : Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 🔍 Shared Search Bar
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: width * 0.04,
                vertical: height * 0.012,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  const Icon(Icons.search, color: Colors.grey),
                  SizedBox(width: width * 0.02),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      onChanged: (value) {
                        final query = value.trim();
                        if (_selectedTabIndex == 0) {
                          recipesPageKey.currentState
                              ?.searchRecipes(query);
                        } else if (_selectedTabIndex == 1) {
                          groceryListPageKey.currentState
                              ?.searchGrocery(query);
                        }
                        setState(() {});
                      },
                      decoration: InputDecoration(
                        hintText: _selectedTabIndex == 0
                            ? "Search recipes"
                            : "Search grocery list",
                        border: InputBorder.none,
                        hintStyle:
                        const TextStyle(color: Colors.grey),
                      ),
                    ),
                  ),
                  if (_searchController.text.isNotEmpty)
                    GestureDetector(
                      onTap: () {
                        _searchController.clear();
                        if (_selectedTabIndex == 0) {
                          recipesPageKey.currentState?.clearSearch();
                        } else if (_selectedTabIndex == 1) {
                          groceryListPageKey.currentState?.clearSearch();
                        }
                        setState(() {});
                      },
                      child: const Icon(Icons.close, color: Colors.grey),
                    ),
                ],
              ),
            ),
            SizedBox(height: height * 0.03),

            // 📋 Section Heading
            Text(
              _selectedTabIndex == 0
                  ? "Your Recipes"
                  : "Your Grocery List",
              style: const TextStyle(
                  fontSize: 20, fontWeight: FontWeight.bold),
            ),

            SizedBox(height: height * 0.015),

            // 🔘 Tab Selector (Top Level: Recipes / List)
            InventoryTabSelector(
              selectedIndex: _selectedTabIndex,
              onTabSelected: (index) {
                setState(() {
                  _selectedTabIndex = index;
                  _searchController.clear();
                  if (index == 0) {
                    recipesPageKey.currentState?.clearSearch();
                  } else if (index == 1) {
                    groceryListPageKey.currentState?.clearSearch();
                  }
                });
              },
            ),
            SizedBox(height: height * 0.02),

            // 🧩 Tabbed Content
            Expanded(
              child: IndexedStack(
                index: _selectedTabIndex,
                children: [
                  // 🍽️ Recipes Section with horizontal filter chips
                  RecipesContainer(inventoryItems: _inventoryItems),

                  // 🛒 Grocery List
                  GroceryListPage(
                    key: groceryListPageKey,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),

      // ---------- Bottom Navigation ----------
      bottomNavigationBar: BottomNavBar(
        currentIndex: 1,
        onTap: (index) {
          if (index == 0) {
            Navigator.pushNamed(context, '/inventory');
          } else if (index == 1) {
            // Already on recipes
          } else if (index == 2) {
            Navigator.pushNamed(context, '/userinventory');
          } else if (index == 3) {
            Navigator.pushNamed(context, '/profile');
          }
        },
      ),
    );
  }
}

// 🌍 Global keys for state access
final GlobalKey<RecipesPageState> recipesPageKey = GlobalKey<RecipesPageState>();
final GlobalKey<GroceryListPageState> groceryListPageKey =
GlobalKey<GroceryListPageState>();

// --------------------------------------------------------
// 🍔 RecipesContainer — McDonald’s-style filter layout
// --------------------------------------------------------
class RecipesContainer extends StatefulWidget {
  final List<String> inventoryItems;
  const RecipesContainer({super.key, required this.inventoryItems});

  @override
  State<RecipesContainer> createState() => _RecipesContainerState();
}

class _RecipesContainerState extends State<RecipesContainer> {
  int _selectedFilter = 0;
  final List<String> _filters = ["Suggested", "Favorites", "Added"];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 🔹 Horizontal filter bar
        SizedBox(
          height: 45,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: _filters.length,
            itemBuilder: (context, index) {
              final isSelected = _selectedFilter == index;
              return Padding(
                padding: const EdgeInsets.only(right: 12.0),
                child: GestureDetector(
                  onTap: () => setState(() => _selectedFilter = index),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFF23C483)
                          : const Color(0xFFF2F2F2),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Text(
                      _filters[index],
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.black87,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),

        // 🔄 Dynamic content area
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: _selectedFilter == 0
                ? RecipesPage(
              key: recipesPageKey,
              inventoryItems: widget.inventoryItems,
            )
                : _selectedFilter == 1
                ? const FavoritesPage()
                : const SavedPage(),
          ),
        ),
      ],
    );
  }
}
