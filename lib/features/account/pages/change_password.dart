import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ChangePasswordPage extends StatefulWidget {
  const ChangePasswordPage({super.key});

  @override
  State<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<ChangePasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _currentPasswordController = TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();

  bool _isLoading = false;
  bool _obscure1 = true;
  bool _obscure2 = true;
  bool _obscure3 = true;

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _reAuthenticate(String currentPassword) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw FirebaseAuthException(code: 'no-user', message: 'No authenticated user.');

    final email = user.email;
    if (email == null || email.isEmpty) {
      throw FirebaseAuthException(code: 'no-email', message: 'No email associated with account.');
    }

    final credential = EmailAuthProvider.credential(email: email, password: currentPassword);
    await user.reauthenticateWithCredential(credential);
  }

  Future<void> _changePassword() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final current = _currentPasswordController.text.trim();
      final next = _newPasswordController.text.trim();

      await _reAuthenticate(current);

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw FirebaseAuthException(code: 'no-user', message: 'No authenticated user.');
      await user.updatePassword(next);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password updated successfully'), backgroundColor: Colors.green),
      );
      Navigator.pop(context);
    } on FirebaseAuthException catch (e) {
      String errorMessage = 'Error: ${e.message ?? e.code}';
      if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
        errorMessage = 'Current password is incorrect.';
      } else if (e.code == 'requires-recent-login') {
        errorMessage = 'Please login again and try. (Recent sign-in required)';
      } else if (e.code == 'no-email' || e.code == 'no-user') {
        errorMessage = 'Account information missing. Please contact support.';
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMessage), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unexpected error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String? _validateNewPassword(String? value) {
    if (value == null || value.isEmpty) return 'Enter a new password';
    if (value.length < 8) return 'At least 8 characters required';
    if (!RegExp(r'[0-9]').hasMatch(value)) return 'Must contain a number';
    if (!RegExp(r'[!@#\$%^&*(),.?":{}|<>]').hasMatch(value)) return 'Must contain a special character';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final green = Colors.green.shade700;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Change Password'),
        backgroundColor: green,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(18.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              // Current Password
              TextFormField(
                controller: _currentPasswordController,
                obscureText: _obscure1,
                decoration: InputDecoration(
                  labelText: 'Current Password',
                  suffixIcon: IconButton(
                    icon: Icon(_obscure1 ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _obscure1 = !_obscure1),
                  ),
                ),
                validator: (v) => (v == null || v.isEmpty) ? 'Enter current password' : null,
              ),
              const SizedBox(height: 16),

              // New Password
              TextFormField(
                controller: _newPasswordController,
                obscureText: _obscure2,
                decoration: InputDecoration(
                  labelText: 'New Password',
                  suffixIcon: IconButton(
                    icon: Icon(_obscure2 ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _obscure2 = !_obscure2),
                  ),
                ),
                validator: _validateNewPassword,
              ),
              const SizedBox(height: 16),

              // Confirm Password
              TextFormField(
                controller: _confirmPasswordController,
                obscureText: _obscure3,
                decoration: InputDecoration(
                  labelText: 'Confirm New Password',
                  suffixIcon: IconButton(
                    icon: Icon(_obscure3 ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _obscure3 = !_obscure3),
                  ),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Confirm the new password';
                  if (v != _newPasswordController.text) return 'Passwords do not match';
                  return null;
                },
              ),
              const SizedBox(height: 28),

              ElevatedButton(
                onPressed: _isLoading ? null : _changePassword,
                style: ElevatedButton.styleFrom(
                  backgroundColor: green,
                  minimumSize: const Size.fromHeight(48),
                ),
                child: _isLoading
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Update Password',style: TextStyle(color: Colors.white),),
              ),
            ],
          ),
        ),
      ),
    );
  }
}