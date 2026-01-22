import 'package:cloud_firestore/cloud_firestore.dart';

// Data model for optional user preferences
class UserPreferences {
  final String userId; // User ID (document ID in Firestore)
  final String? gender; // Preferred gender of driver (e.g., 'Male', 'Female', 'Other')
  final int? minDriverAge; // Minimum preferred driver age
  final int? maxDriverAge; // Maximum preferred driver age
  final String? preferredVehicleType; // Preferred vehicle type (e.g., 'Sedan', 'SUV', 'Electric')

  UserPreferences({
    required this.userId,
    this.gender,
    this.minDriverAge,
    this.maxDriverAge,
    this.preferredVehicleType,
  });

  // Factory constructor to create a UserPreferences object from a Firestore DocumentSnapshot
  factory UserPreferences.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return UserPreferences(
      userId: doc.id, // The document ID is the userId
      gender: data['gender'],
      minDriverAge: data['min_driver_age'],
      maxDriverAge: data['max_driver_age'],
      preferredVehicleType: data['preferred_vehicle_type'],
    );
  }

  // Convert the UserPreferences object to a Map for storing in Firestore
  Map<String, dynamic> toFirestore() {
    return {
      // Only include non-null values for optional fields
      if (gender != null) 'gender': gender,
      if (minDriverAge != null) 'min_driver_age': minDriverAge,
      if (maxDriverAge != null) 'max_driver_age': maxDriverAge,
      if (preferredVehicleType != null) 'preferred_vehicle_type': preferredVehicleType,
    };
  }
}
