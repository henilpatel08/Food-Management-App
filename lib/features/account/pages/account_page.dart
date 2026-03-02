import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sust_ai_n/features/account/pages/edit_profile.dart';
import '../../../waste_dashboard/presentation/pages/waste_dashboard.dart';
import '../../../waste_dashboard/presentation/widgets/waste_impact_summary_card.dart';
import 'AboutAppPage.dart';
import 'HelpSupportPage.dart';
import 'change_password.dart';
import '../../../widgets/bottom_nav_bar.dart';
import '../../Login/survey_form.dart';

class AccountPage extends StatefulWidget {
  const AccountPage({super.key});

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  User? user = FirebaseAuth.instance.currentUser;
  bool _isLoading = true;
  String? profileName;
  String? profilePhotoBase64;
  bool notificationsEnabled = true;

  final Color appGreen = Colors.green.shade600;

  @override
  void initState() {
    super.initState();
    _refreshUser();
  }

  Future<void> _refreshUser() async {
    setState(() => _isLoading = true);

    await FirebaseAuth.instance.currentUser?.reload();
    user = FirebaseAuth.instance.currentUser;

    if (user != null) {
      try {
        final docSnapshot = await FirebaseFirestore.instance
            .collection("users")
            .doc(user!.uid)
            .get();

        if (docSnapshot.exists) {
          final data = docSnapshot.data();
          profileName = data?["profile"]?["info"]?["name"];
          profilePhotoBase64 = data?["profile"]?["info"]?["photoUrl"];

          final settings = data?["profile"]?["settings"];
          if (settings != null && settings["notificationsEnabled"] != null) {
            notificationsEnabled = settings["notificationsEnabled"];
          }
        }
      } catch (e) {
        print("Error loading profile: $e");
      }
    }

    setState(() => _isLoading = false);
  }

  Future<void> _updateNotificationSetting(bool value) async {
    if (user == null) return;

    await FirebaseFirestore.instance.collection("users").doc(user!.uid).set({
      "profile": {
        "settings": {"notificationsEnabled": value},
      },
    }, SetOptions(merge: true));
  }

  int _currentIndex = 3;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final green = appGreen;

    ImageProvider? profileImage;
    if (profilePhotoBase64 != null &&
        profilePhotoBase64!.isNotEmpty &&
        profilePhotoBase64 != "null") {
      try {
        profileImage = MemoryImage(base64Decode(profilePhotoBase64!));
      } catch (e) {
        print("Error decoding profile image: $e");
      }
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8F7),
      appBar: AppBar(
        backgroundColor: green,
        automaticallyImplyLeading: false,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          "My Account",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      vertical: 24,
                      horizontal: 20,
                    ),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [green, green.withOpacity(0.75)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(24),
                        bottomRight: Radius.circular(24),
                      ),
                    ),
                    child: Column(
                      children: [
                        Stack(
                          alignment: Alignment.bottomRight,
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 3,
                                ),
                              ),
                              child: CircleAvatar(
                                radius: 45,
                                backgroundColor: Colors.white,
                                backgroundImage: profileImage,
                                child: profileImage == null
                                    ? const Icon(
                                        Icons.person,
                                        size: 50,
                                        color: Colors.grey,
                                      )
                                    : null,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          profileName ?? user?.displayName ?? "Guest User",
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          user?.email ?? "No email available",
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        _QuickActionButton(
                          icon: Icons.edit_note_rounded,
                          label: "Edit Profile",
                          green: green,
                          onTap: () async {
                            final updated = await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const EditProfilePage(),
                              ),
                            );

                            if (updated == true) {
                              _refreshUser();
                            }
                          },
                        ),
                        const SizedBox(width: 12),
                        _QuickActionButton(
                          icon: Icons.list_alt_rounded,
                          label: "Change Preference",
                          green: green,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const SurveyForm(),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: WasteImpactSummaryCard(
                      onOpenDetails: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const WasteDashboardPage(),
                          ),
                        );
                      },
                    ),
                  ),

                  const SizedBox(height: 20),

                  _SettingsCard(
                    title: "Settings",
                    items: [
                      SwitchListTile(
                        secondary: Icon(
                          Icons.notifications_active,
                          color: green,
                        ),
                        title: const Text(
                          "Notifications",
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                        value: notificationsEnabled,
                        onChanged: (value) {
                          setState(() => notificationsEnabled = value);
                          _updateNotificationSetting(value);
                        },
                      ),
                      _SettingsItem(
                        icon: Icons.lock_outline,
                        label: "Privacy",
                        green: green,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const ChangePasswordPage(),
                            ),
                          );
                        },
                      ),
                      _SettingsItem(
                        icon: Icons.help_outline,
                        label: "Help & Support",
                        green: green,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const HelpSupportPage(),
                            ),
                          );
                        },
                      ),
                      _SettingsItem(
                        icon: Icons.info_outline,
                        label: "About App",
                        green: green,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const AboutAppPage(),
                            ),
                          );
                        },
                      ),
                    ],
                  ),

                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        await FirebaseAuth.instance.signOut();
                        if (context.mounted) {
                          Navigator.pushReplacementNamed(context, '/login');
                        }
                      },
                      icon: const Icon(Icons.logout_rounded),
                      label: const Text("Log Out"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

      bottomNavigationBar: BottomNavBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() => _currentIndex = index);
          if (index == 0) Navigator.pushNamed(context, '/inventory');
          if (index == 1) Navigator.pushNamed(context, '/recipes');
          if (index == 2) Navigator.pushNamed(context, '/userinventory');
        },
      ),
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color green;
  final VoidCallback onTap;

  const _QuickActionButton({
    required this.icon,
    required this.label,
    required this.green,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            children: [
              Icon(icon, color: green, size: 24),
              const SizedBox(height: 6),
              Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final String title;
  final List<Widget> items;

  const _SettingsCard({required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            ...items,
          ],
        ),
      ),
    );
  }
}

class _SettingsItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color green;
  final VoidCallback? onTap;

  const _SettingsItem({
    required this.icon,
    required this.label,
    required this.green,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: green),
      title: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
      trailing: const Icon(Icons.chevron_right_rounded, color: Colors.grey),
      onTap: onTap,
    );
  }
}
