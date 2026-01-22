import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // For Firestore operations
import 'package:passenger_ride_app/models/user_preferences.dart'; // Import UserPreferences model

// Widget for passengers to set their preferences
class PreferencesScreen extends StatefulWidget {
  final String userId; // User ID passed from the authentication flow
  const PreferencesScreen({super.key, required this.userId});

  @override
  State<PreferencesScreen> createState() => _PreferencesScreenState();
}

class _PreferencesScreenState extends State<PreferencesScreen> {
  final _formKey = GlobalKey<FormState>(); // Key for form validation
  String? _selectedGender; // Holds selected gender preference
  final TextEditingController _minAgeController = TextEditingController(); // For min driver age input
  final TextEditingController _maxAgeController = TextEditingController(); // For max driver age input
  String? _selectedVehicleType; // Holds selected vehicle type preference
  bool _isLoading = false; // To show a loading indicator during saving/loading

  @override
  void initState() {
    super.initState();
    _loadPreferences(); // Load any existing preferences when the screen initializes
  }

  @override
  void dispose() {
    _minAgeController.dispose();
    _maxAgeController.dispose();
    super.dispose();
  }

  // Helper function to show a SnackBar message
  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  // Load existing user preferences from Firestore
  Future<void> _loadPreferences() async {
    setState(() {
      _isLoading = true;
    });
    try {
      // Get the document for the current user's preferences
      DocumentSnapshot doc = await FirebaseFirestore.instance
          .collection('passenger_profiles') // Collection for passenger preferences
          .doc(widget.userId) // Document ID is the user's UID
          .get();

      if (doc.exists) {
        // If document exists, populate the form fields with existing data
        UserPreferences preferences = UserPreferences.fromFirestore(doc);
        setState(() {
          _selectedGender = preferences.gender;
          _minAgeController.text = preferences.minDriverAge?.toString() ?? '';
          _maxAgeController.text = preferences.maxDriverAge?.toString() ?? '';
          _selectedVehicleType = preferences.preferredVehicleType;
        });
      }
    } catch (e) {
      _showSnackBar('Error loading preferences: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Save user preferences to Firestore
  Future<void> _savePreferences() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });
      try {
        // Create a UserPreferences object from current form values
        UserPreferences preferences = UserPreferences(
          userId: widget.userId,
          gender: _selectedGender,
          minDriverAge: int.tryParse(_minAgeController.text), // Convert string to int
          maxDriverAge: int.tryParse(_maxAgeController.text),
          preferredVehicleType: _selectedVehicleType,
        );

        // Save (or merge) the preferences to Firestore
        await FirebaseFirestore.instance
            .collection('passenger_profiles')
            .doc(widget.userId)
            .set(preferences.toFirestore(), SetOptions(merge: true)); // Use merge: true to update specific fields without overwriting the entire document

        _showSnackBar('Preferences saved successfully!');
        Navigator.of(context).pop(); // Go back to the previous screen (RideRequestScreen)
      } catch (e) {
        _showSnackBar('Error saving preferences: $e');
      } finally {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Your Preferences'),
      ),
      body: _isLoading // Show loading indicator if saving/loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey, // Associate form with GlobalKey
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Gender (Optional):', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    DropdownButton<String>(
                      isExpanded: true,
                      value: _selectedGender,
                      hint: const Text('Select Gender'),
                      items: <String>['Male', 'Female', 'Other']
                          .map<DropdownMenuItem<String>>((String value) {
                        return DropdownMenuItem<String>(
                          value: value,
                          child: Text(value),
                        );
                      }).toList(),
                      onChanged: (String? newValue) {
                        setState(() {
                          _selectedGender = newValue;
                        });
                      },
                    ),
                    const SizedBox(height: 20),
                    const Text('Preferred Driver Age Range (Optional):',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _minAgeController,
                            keyboardType: TextInputType.number, // Only allow numbers
                            decoration: const InputDecoration(
                              labelText: 'Min Age',
                              border: OutlineInputBorder(),
                            ),
                            validator: (val) {
                              if (val != null && val.isNotEmpty && int.tryParse(val) == null) {
                                return 'Enter a valid number';
                              }
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextFormField(
                            controller: _maxAgeController,
                            keyboardType: TextInputType.number, // Only allow numbers
                            decoration: const InputDecoration(
                              labelText: 'Max Age',
                              border: OutlineInputBorder(),
                            ),
                            validator: (val) {
                              if (val != null && val.isNotEmpty && int.tryParse(val) == null) {
                                return 'Enter a valid number';
                              }
                              return null;
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const Text('Preferred Vehicle Type (Optional):', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    DropdownButton<String>(
                      isExpanded: true,
                      value: _selectedVehicleType,
                      hint: const Text('Select Vehicle Type'),
                      items: <String>['Sedan', 'SUV', 'Hatchback', 'Electric']
                          .map<DropdownMenuItem<String>>((String value) {
                        return DropdownMenuItem<String>(
                          value: value,
                          child: Text(value),
                        );
                      }).toList(),
                      onChanged: (String? newValue) {
                        setState(() {
                          _selectedVehicleType = newValue;
                        });
                      },
                    ),
                    const SizedBox(height: 30),
                    // Save Preferences button
                    Center(
                      child: ElevatedButton(
                        onPressed: _savePreferences,
                        child: const Text('Save Preferences', style: TextStyle(fontSize: 18)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
