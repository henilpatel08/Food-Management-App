import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sust_ai_n/features/account/pages/account_page.dart';
import 'package:sust_ai_n/features/home/User_inventory/user_inventory_page.dart';
import 'package:sust_ai_n/services/notification_manager.dart';
import 'package:sust_ai_n/services/notification_service.dart';
import 'features/chatbot/chat_page.dart';
import 'firebase_options.dart';

// Import all feature screens
import 'features/Login/user_login.dart';
import 'features/home/inventory/inventory_tab.dart';
import 'features/home/receipe/receipe_base_page.dart';
import 'features/home/receipe/recipes_page.dart';
import 'features/home/receipe/categories_page.dart';
import 'features/home/receipe/grocery_list_page.dart';
import 'features/ocr_scan/presentation/pages/scan_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await NotificationService.init();
  await requestNotificationPermission();

  await dotenv.load(fileName: "assets/keys.env");
  runApp(const MyApp());
}

Future<void> requestNotificationPermission() async {
  final status = await Permission.notification.request();

  if (status.isDenied) {
    // User denied — you may show a dialog
    print("❌ Notification permission denied");
  } else if (status.isGranted) {
    print("✅ Notification permission granted");
  }
}

final RouteObserver<ModalRoute<void>> routeObserver =
RouteObserver<ModalRoute<void>>();

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SustAIn',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.white,
      ),

      navigatorObservers: [routeObserver],

      // ✅ Only InventoryTab handles BottomNav now
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          } else if (snapshot.hasData && snapshot.data != null) {
            // ✅ User logged in → go directly to InventoryTab
            return const InventoryTab(); // your BottomNav lives here
          } else {
            // 🚪 Not logged in → show login
            return const UserLogin();
          }
        },
      ),

      // ✅ Named routes (unchanged)
      routes: {
        '/login': (context) => const UserLogin(),
        '/inventory': (context) => const InventoryTab(),
        '/scan': (context) => const ScanPage(),
        '/userinventory': (context) => const UserInventoryPage(),
        '/recipes': (context) => const ReceipeBasePage(),
        '/recipesPage': (context) => const RecipesPage(inventoryItems: []),
        '/categories': (context) => const CategoriesPage(),
        '/groceryList': (context) => const GroceryListPage(),
        '/peely' :(context)=> const ChatPage(),
        '/profile' : (context) => const AccountPage(),
      },
    );
  }
}
