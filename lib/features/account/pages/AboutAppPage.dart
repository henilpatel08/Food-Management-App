import 'package:flutter/material.dart';

class AboutAppPage extends StatelessWidget {
  const AboutAppPage({super.key});

  @override
  Widget build(BuildContext context) {
    final green = Colors.green.shade700;

    return Scaffold(
      appBar: AppBar(
        title: const Text("About App"),
        backgroundColor: green,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "SustAIn — Reduce Food Waste with AI",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 12),

            const Text(
              "SustAIn helps households track their groceries, reduce waste, "
                  "and automatically find recipes based on what they already have.\n\n"
                  "Features include:\n"
                  "• OCR receipt scanning\n"
                  "• AI shelf-life prediction\n"
                  "• Inventory tracking\n"
                  "• Personalized recipe suggestions\n"
                  "• Food expiry alerts\n",
              style: TextStyle(fontSize: 15),
            ),

            const SizedBox(height: 20),

            // 📌 App Version Box
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "App Version",
                    style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  SizedBox(height: 6),
                  Text(
                    "1.0.0",
                    style: TextStyle(fontSize: 15),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 25),

            const Text(
              "Developed By",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 6),

            const Text(
                  "Henil | Faizan | Krupal\n"
                  "In collaboration with Verdanza Tech",
              style: TextStyle(fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }
}
