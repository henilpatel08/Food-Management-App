import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../widgets/bottom_nav_bar.dart';
import '../../../services/inventory_service.dart';

class UserInventoryPage extends StatefulWidget {
  const UserInventoryPage({super.key});

  @override
  State<UserInventoryPage> createState() => _UserInventoryPageState();
}

class _UserInventoryPageState extends State<UserInventoryPage> {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  final InventoryService _invService = InventoryService();

  int _currentIndex = 2; // Inventory tab active

  Stream<Map<String, List<Map<String, dynamic>>>> _streamUserInventory() {
    final user = _auth.currentUser;
    if (user == null) return const Stream.empty();

    return _firestore
        .collection('users')
        .doc(user.uid)
        .collection('inventory')
        .snapshots()
        .map((snapshot) {
      final Map<String, List<Map<String, dynamic>>> grouped = {};

      for (var doc in snapshot.docs) {
        final data = doc.data();
        data['id'] = doc.id;

        final rawCategory =
        (data['category'] ?? '').toString().trim().toLowerCase();
        final rawAisle = (data['aisle'] ?? '').toString().trim();

        final category = (rawCategory.isEmpty ||
            rawCategory == 'general' ||
            rawCategory == 'misc' ||
            rawCategory == 'other')
            ? (rawAisle.isNotEmpty ? _capitalize(rawAisle) : 'Uncategorized')
            : _capitalize(rawCategory);

        grouped.putIfAbsent(category, () => []);
        grouped[category]!.add(data);
      }

      return grouped;
    });
  }

  String _capitalize(String value) {
    if (value.isEmpty) return value;
    return value[0].toUpperCase() + value.substring(1);
  }

  // POPUP CONFIRM DELETE → uses removeSingleItemById()
  void _confirmDelete(Map<String, dynamic> item) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Finish Item?"),
          content: Text("Have you finished using '${item['name']}'?"),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("No"),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(context);

                await _invService.removeSingleItemById(item['id']);

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content:
                        Text("✔ ${item['name']} removed successfully")),
                  );
                }
              },
              child: const Text("Yes", style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,

      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'User Inventory',
          style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
      ),

      body: StreamBuilder<Map<String, List<Map<String, dynamic>>>>(
        stream: _streamUserInventory(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('🧺 No items in your inventory'));
          }

          final inventory = snapshot.data!;
          final categories = inventory.keys.toList()..sort(); // SORT A-Z

          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            itemCount: categories.length,
            itemBuilder: (context, index) {
              final category = categories[index];
              final items = inventory[category]!;

              // SORT ITEMS BY EARLIEST EXPIRY FIRST
              items.sort((a, b) {
                final da = (a['expiryDate'] as Timestamp).toDate();
                final db = (b['expiryDate'] as Timestamp).toDate();
                return da.compareTo(db);
              });

              return Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                margin: const EdgeInsets.only(bottom: 16),
                child: ExpansionTile(
                  backgroundColor: Colors.white,
                  collapsedBackgroundColor: Colors.grey.shade100,
                  title: Text(
                    category,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, color: Colors.black),
                  ),
                  children: items.map((item) {
                    return ListTile(
                      leading:
                      const Icon(Icons.inventory_2_outlined, color: Colors.grey),

                      title: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              item['name'] ?? 'Unnamed',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 16),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),

                          Text(
                            "${item['qty']} ${item['unit'] ?? ''}",
                            style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                                color: Colors.black87),
                          ),

                          const SizedBox(width: 12),

                          // ✔ DELETE BUTTON
                          IconButton(
                            icon: const Icon(Icons.check_circle,
                                color: Colors.green, size: 28),
                            onPressed: () => _confirmDelete(item),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              );
            },
          );
        },
      ),

      bottomNavigationBar: BottomNavBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() => _currentIndex = index);
          if (index == 0) {
            Navigator.pushNamed(context, '/inventory');
          } else if (index == 1) {
            Navigator.pushNamed(context, '/recipes');
          } else if (index == 3) {
            Navigator.pushNamed(context, '/profile');
          }
        },
      ),
    );
  }
}
