import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class HelpSupportPage extends StatelessWidget {
  const HelpSupportPage({super.key});

  Future<void> _sendSupportEmail(BuildContext context) async {
    final Uri emailUri = Uri(
      scheme: 'mailto',
      path: 'mewadakrupal17@gmail.com',
      query: Uri.encodeQueryComponent(
        'subject=SustAIn - Help & Support&body=Hi, I need help with...',
      ),
    );

    if (!await launchUrl(emailUri)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open email app')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final green = Colors.green.shade700;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Help & Support"),
        backgroundColor: green,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // 🧩 Contact Options
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  const Text(
                    "Need help? We're here for you!",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),

                  _SupportButton(
                    icon: Icons.mail_outline,
                    label: "Email Support",
                    onTap: () => _sendSupportEmail(context),
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            ),

            const SizedBox(height: 25),

            const Text(
              "Frequently Asked Questions",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),

            // 🎯 FAQ items
            _FAQTile(
              question: "How do I add items to my inventory?",
              answer:
              "You can scan receipts, add manually, or use our AI-suggested items for faster entry.",
            ),
            _FAQTile(
              question: "How is shelf-life estimated?",
              answer:
              "We use USDA FoodKeeper data + AI predictions based on your product category.",
            ),
            _FAQTile(
              question: "Why am I not seeing recipes?",
              answer:
              "Your preferences or inventory might be empty. Add items to get personalized recipes.",
            ),
            _FAQTile(
              question: "How do I contact support?",
              answer:
              "Use the Email Support button above or visit our website contact form.",
            ),
          ],
        ),
      ),
    );
  }
}

class _SupportButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SupportButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });


  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 6,
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.green, size: 26),
            const SizedBox(width: 12),
            Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FAQTile extends StatelessWidget {
  final String question;
  final String answer;

  const _FAQTile({required this.question, required this.answer});


  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      title: Text(
        question,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            answer,
            style: const TextStyle(fontSize: 14, color: Colors.black87),
          ),
        ),
      ],
    );
  }
}
