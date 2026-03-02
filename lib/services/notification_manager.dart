import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'notification_service.dart';
 // your existing notification code

class NotificationManager {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ----------------------------------------------------------
  // 🔹 Funny Notification Messages
  // ----------------------------------------------------------
  final List<String> _messages = [
    "Your {ingredient} has been waiting for you… maybe it’s time to turn it into something tasty?",
    "Your {ingredient} is sitting in the fridge like a forgotten roommate 😅 want to cook with it?",
    "Your {ingredient} has been chilling for a while… shall we make something yummy with it?",
    "Chef! Your {ingredient} has been patiently waiting for its big moment. Ready to make a recipe?",
    "Your {ingredient} is giving ‘use me’ vibes 👀 shall we cook?",
    "Your {ingredient} feels abandoned… let’s rescue it with a recipe!",
    "Your {ingredient} is waiting for its glow-up 😎 want to cook something?",
  ];

  // ----------------------------------------------------------
  // 🔹 Pick Random Message
  // ----------------------------------------------------------
  String _randomMessage(String ingredient) {
    final rand = Random().nextInt(_messages.length);
    return _messages[rand].replaceAll("{ingredient}", ingredient);
  }

  // ----------------------------------------------------------
  // 🔹 MAIN FUNCTION: Check items & send reminder
  // ----------------------------------------------------------
  Future<void> checkExpiringItems() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final snap = await _firestore
        .collection("users")
        .doc(user.uid)
        .collection("inventory")
        .get();

    final now = DateTime.now();

    for (final doc in snap.docs) {
      final data = doc.data();
      final String ingredient = data["name"];
      final DateTime expiryDate = (data["expiryDate"] as Timestamp).toDate();

      final int daysLeft = expiryDate.difference(now).inDays;

      // 🔥 Send reminders if 2 days left OR 1 day OR same day (but not expired)
      if (daysLeft <= 2 && expiryDate.isAfter(now)) {
        final text = _randomMessage(ingredient);

        await NotificationService.showExpiryNotification(
          ingredient: ingredient,
          message: text,
        );
      }
    }
  }

  // ----------------------------------------------------------
  // 🔹 Run every 12 hours → 2 notifications / day
  // ----------------------------------------------------------
  void startPeriodicChecks() {
    // run immediately when app opens
    checkExpiringItems();

    // then repeat every 12 hours
    Timer.periodic(
      const Duration(hours: 12),
          (_) => checkExpiringItems(),
    );
  }
}
