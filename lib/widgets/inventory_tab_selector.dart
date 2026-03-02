import 'package:flutter/material.dart';

class InventoryTabSelector extends StatelessWidget {
  final int selectedIndex;
  final Function(int) onTabSelected;

  const InventoryTabSelector({
    super.key,
    required this.selectedIndex,
    required this.onTabSelected,
  });

  @override
  Widget build(BuildContext context) {
    final tabs = ["Recipes", "List"]; // removed Categories

    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      children: List.generate(tabs.length, (index) {
        final isSelected = index == selectedIndex;
        return GestureDetector(
          onTap: () => onTabSelected(index),
          child: Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tabs[index],
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    color: isSelected ? Colors.black : Colors.grey,
                    decoration: isSelected
                        ? TextDecoration.underline
                        : TextDecoration.none,
                    decorationThickness: 0,
                  ),
                ),
                if (isSelected)
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    height: 3,
                    width: 30,
                    decoration: BoxDecoration(
                      color: const Color(0xFF23C483),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
              ],
            ),
          ),
        );
      }),
    );
  }
}

