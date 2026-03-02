import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

User? user = FirebaseAuth.instance.currentUser;

class SurveyForm extends StatefulWidget {
  const SurveyForm({super.key});

  @override
  State<SurveyForm> createState() => _SurveyForm();
}

class _SurveyForm extends State<SurveyForm> {
  final _adultController = TextEditingController();
  final _kidsController = TextEditingController();
  final _spendingController = TextEditingController();

  String? _shoppingFrequency;

  // 🔹 Official Spoonacular diet list
  final List<String> dietaryOptions = [
    'Gluten Free',
    'Ketogenic',
    'Vegetarian',
    'Lacto-Vegetarian',
    'Ovo-Vegetarian',
    'Vegan',
    'Pescetarian',
    'Paleo',
    'Primal',
    'Whole30',
    'None',
  ];

  // 🔹 Spoonacular intolerances
  final List<String> intoleranceOptions = [
    'Dairy',
    'Egg',
    'Gluten',
    'Peanut',
    'Seafood',
    'Sesame',
    'Shellfish',
    'Soy',
    'Sulfite',
    'Tree Nut',
    'Wheat',
    'None',
  ];

  final List<String> cuisineOptions = [
    'Italian',
    'Indian',
    'Chinese',
    'Mexican',
    'Fast Food',
    'Japanese',
    'None',
  ];

  List<String> selectedDietary = [];
  List<String> selectedIntolerances = [];
  List<String> selectedCuisines = [];

  bool _isLoading = true;
  bool _isEditMode = false;

  String? _adultError;
  String? _kidsError;
  String? _dietError;
  String? _cuisineError;
  String? _intoleranceError;
  String? _spendingError;
  String? _frequencyError;

  @override
  void initState() {
    super.initState();
    _loadSurveyData();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: Colors.green)),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Personalization", style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.green,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [

                    _buildLabel("Household Members"),
                    Row(
                      children: [
                        Expanded(child: _buildTextField(_adultController, "Adults")),
                        const SizedBox(width: 16),
                        Expanded(child: _buildTextField(_kidsController, "Kids")),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // ======================
                    // 🍽 SPOONACULAR DIETS
                    // ======================
                    _buildLabel("Dietary Restrictions"),
                    Wrap(
                      spacing: 8,
                      children: dietaryOptions.map((option) {
                        final selected = selectedDietary.contains(option);
                        return FilterChip(
                          label: Text(option),
                          selected: selected,
                          selectedColor: Colors.green,
                          checkmarkColor: Colors.white,
                          onSelected: (value) {
                            setState(() {
                              value
                                  ? selectedDietary.add(option)
                                  : selectedDietary.remove(option);
                            });
                          },
                        );
                      }).toList(),
                    ),
                    if (_dietError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 5),
                        child: Text(_dietError!, style: const TextStyle(color: Colors.red)),
                      ),
                    const SizedBox(height: 20),

                    // ======================
                    // ❗ INTOLERANCES
                    // ======================
                    _buildLabel("Food Intolerances"),
                    Wrap(
                      spacing: 8,
                      children: intoleranceOptions.map((option) {
                        final selected = selectedIntolerances.contains(option);
                        return FilterChip(
                          label: Text(option),
                          selected: selected,
                          selectedColor: Colors.green,
                          checkmarkColor: Colors.white,
                          onSelected: (value) {
                            setState(() {
                              value
                                  ? selectedIntolerances.add(option)
                                  : selectedIntolerances.remove(option);
                            });
                          },
                        );
                      }).toList(),
                    ),
                    if (_intoleranceError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 5),
                        child: Text(_intoleranceError!, style: const TextStyle(color: Colors.red)),
                      ),
                    const SizedBox(height: 20),

                    _buildLabel("Preferred Cuisines"),
                    Wrap(
                      spacing: 8,
                      children: cuisineOptions.map((option) {
                        final selected = selectedCuisines.contains(option);
                        return FilterChip(
                          label: Text(option),
                          selected: selected,
                          selectedColor: Colors.green,
                          checkmarkColor: Colors.white,
                          onSelected: (value) {
                            setState(() {
                              value
                                  ? selectedCuisines.add(option)
                                  : selectedCuisines.remove(option);
                            });
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 20),

                    _buildLabel("Weekly grocery spending (\$)"),
                    _buildTextField(_spendingController, "e.g. 150"),
                    const SizedBox(height: 20),

                    _buildLabel("Shopping Frequency"),
                    DropdownButtonFormField<String>(
                      value: _shoppingFrequency,
                      decoration: _inputDecoration("Select frequency"),
                      items: [
                        'Every day',
                        '2-3 times a week',
                        'Once a week',
                        'Bi-weekly',
                        'Monthly',
                      ].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                      onChanged: (value) {
                        setState(() => _shoppingFrequency = value);
                      },
                    ),
                  ],
                ),
              ),
            ),

            // Submit Button
            Container(
              padding: const EdgeInsets.all(16),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  minimumSize: const Size(double.infinity, 50),
                ),
                onPressed: _handleSubmit,
                child: Text(_isEditMode ? "Update" : "Submit",
                    style: const TextStyle(color: Colors.white, fontSize: 18)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Validate + save
  void _handleSubmit() async {
    if (_adultController.text.isEmpty ||
        _kidsController.text.isEmpty ||
        selectedDietary.isEmpty ||
        selectedCuisines.isEmpty ||
        _spendingController.text.isEmpty ||
        _shoppingFrequency == null) {

      setState(() {
        _dietError = selectedDietary.isEmpty ? "Please select at least one diet." : null;
      });
      return;
    }

    await submitSurveyToFirestore();
    Navigator.pop(context);
  }

  Future<void> submitSurveyToFirestore() async {
    if (user == null) return;

    final data = {
      "adults": _adultController.text.trim(),
      "kids": _kidsController.text.trim(),
      "dietaryRestrictions": selectedDietary,
      "intolerances": selectedIntolerances,
      "preferredCuisines": selectedCuisines,
      "weeklySpending": _spendingController.text.trim(),
      "shoppingFrequency": _shoppingFrequency,
    };

    await FirebaseFirestore.instance.collection("users").doc(user!.uid).set({
      "profile": {"survey": data}
    }, SetOptions(merge: true));

    print("🔥 Survey Updated: $data");
  }

  Future<void> _loadSurveyData() async {
    final doc = await FirebaseFirestore.instance
        .collection("users")
        .doc(user!.uid)
        .get();

    final survey = doc.data()?["profile"]?["survey"];
    if (survey != null) {
      selectedDietary = List<String>.from(survey["dietaryRestrictions"] ?? []);
      selectedIntolerances = List<String>.from(survey["intolerances"] ?? []);
      selectedCuisines = List<String>.from(survey["preferredCuisines"] ?? []);
      _shoppingFrequency = survey["shoppingFrequency"];
      _adultController.text = survey["adults"] ?? "";
      _kidsController.text = survey["kids"] ?? "";
      _spendingController.text = survey["weeklySpending"] ?? "";
      _isEditMode = true;
    }

    setState(() => _isLoading = false);
  }

  // UI Helpers
  Text _buildLabel(String text) =>
      Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold));

  Widget _buildTextField(TextEditingController c, String hint) =>
      TextField(controller: c, decoration: _inputDecoration(hint));

  InputDecoration _inputDecoration(String hint) =>
      InputDecoration(border: OutlineInputBorder(), hintText: hint);
}
