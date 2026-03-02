import 'package:flutter/material.dart';
import 'package:sust_ai_n/features/account/pages/account_page.dart';
import '../features/ocr_scan/presentation/pages/scan_page.dart';

class BottomNavBar extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;

  const BottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 12, right: 12, bottom: 6),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 10,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 24.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _NavIcon(
                icon: Icons.home_outlined,
                isActive: currentIndex == 0,
                onTap: () => onTap(0),
              ),
              _NavIcon(
                icon: Icons.restaurant_menu,
                isActive: currentIndex == 1,
                onTap: () => onTap(1),
              ),

              // ✅ The scan button stays independent
              const _ScannerIcon(),

              // ✅ Inventory now correctly mapped to index 2
              _NavIcon(
                icon: Icons.inventory_2_outlined,
                isActive: currentIndex == 2,
                onTap: () => onTap(2),
              ),

              _NavIcon(
                icon: Icons.person_outline,
                isActive: currentIndex == 3,
                 onTap: ()  => onTap(3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavIcon extends StatelessWidget {
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;

  const _NavIcon({
    required this.icon,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(50),
      onTap: onTap,
      child: Icon(
        icon,
        size: 26,
        color: isActive ? const Color(0xFF000000) : Colors.grey,
      ),
    );
  }
}

/// 🔹 Scanner Button – does not change currentIndex
class _ScannerIcon extends StatelessWidget {
  const _ScannerIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(100),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const ScanPage()),
        );
      },
      child: Container(
        width: 56,
        height: 56,
        decoration: const BoxDecoration(
          color: Color(0xFF23C483),
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.center_focus_strong,
          color: Colors.white,
          size: 30,
        ),
      ),
    );
  }
}
