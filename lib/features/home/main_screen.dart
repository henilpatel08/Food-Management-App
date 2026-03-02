// import 'package:flutter/material.dart';
// import 'package:sust_ai_n/features/home/receipe/receipe_base_page.dart';
// import '../../widgets/bottom_nav_bar.dart';
// import 'User_inventory/user_inventory_page.dart';
//
// class MainScreen extends StatefulWidget {
//   const MainScreen({super.key});
//
//   @override
//   State<MainScreen> createState() => _MainScreenState();
// }
//
// class _MainScreenState extends State<MainScreen> {
//   int _currentIndex = 0;
//
//   // List of tabs in bottom navigation
//   final List<Widget> _pages = const [
//     HomePage(),           // 🏠
//     ReceipeBasePage(),    // 🍽
//     UserInventoryPage(),  // 🧾
//     // ProfilePage(),        // 👤
//   ];
//
//   void _onTabTapped(int index) {
//     setState(() => _currentIndex = index);
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       backgroundColor: Colors.white,
//       body: _pages[_currentIndex],
//       bottomNavigationBar: BottomNavBar(
//         currentIndex: _currentIndex,
//         onTap: _onTabTapped,
//       ),
//     );
//   }
// }
