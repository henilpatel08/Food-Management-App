import 'package:flutter/material.dart';

class CategoriesPage extends StatelessWidget {
  const CategoriesPage({super.key});

  // Sample static categories (you can later fetch from Firestore or Spoonacular)
  final List<Map<String, dynamic>> categories = const [
    {'name': 'Vegetables', 'icon': Icons.eco, 'color': Color(0xFFE8F5E9)},
    {'name': 'Fruits', 'icon': Icons.apple, 'color': Color(0xFFFFEBEE)},
    {'name': 'Dairy', 'icon': Icons.local_drink, 'color': Color(0xFFE3F2FD)},
    {'name': 'Bakery', 'icon': Icons.bakery_dining, 'color': Color(0xFFFFF3E0)},
    {'name': 'Grains', 'icon': Icons.rice_bowl, 'color': Color(0xFFF3E5F5)},
    {'name': 'Snacks', 'icon': Icons.fastfood, 'color': Color(0xFFFFFDE7)},
    {'name': 'Meat', 'icon': Icons.set_meal, 'color': Color(0xFFFFEBEE)},
    {'name': 'Spices', 'icon': Icons.local_fire_department, 'color': Color(0xFFFFF8E1)},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: GridView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2, // two per row
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 1.05,
        ),
        itemCount: categories.length,
        itemBuilder: (context, index) {
          final cat = categories[index];
          return _CategoryCard(
            name: cat['name'],
            icon: cat['icon'],
            color: cat['color'],
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Selected ${cat['name']}'),
                  duration: const Duration(milliseconds: 800),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  final String name;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _CategoryCard({
    required this.name,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.green.shade800, size: 40),
            const SizedBox(height: 12),
            Text(
              name,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
