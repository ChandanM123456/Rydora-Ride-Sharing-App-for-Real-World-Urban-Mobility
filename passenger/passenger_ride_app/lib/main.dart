import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:geocoding/geocoding.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';

// Import your Firebase configuration
import 'firebase_options.dart';

// --- Enhanced Authentication Service ---
class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Future<User?> signUp(String email, String password, String phone) async {
    try {
      UserCredential result = await _auth.createUserWithEmailAndPassword(
          email: email, password: password);
      
      // Store phone number in user profile
      await result.user?.updateDisplayName(phone);
      
      return result.user;
    } catch (e) {
      print('Error signing up: ${e.toString()}');
      return null;
    }
  }

  Future<User?> signIn(String email, String password) async {
    try {
      UserCredential result = await _auth.signInWithEmailAndPassword(
          email: email, password: password);
      return result.user;
    } catch (e) {
      print('Error signing in: ${e.toString()}');
      return null;
    }
  }

  Future<void> signOut() async {
    try {
      return await _auth.signOut();
    } catch (e) {
      print('Error signing out: ${e.toString()}');
      rethrow;
    }
  }

  User? getCurrentUser() {
    return _auth.currentUser;
  }

  Stream<User?> get user {
    return _auth.authStateChanges();
  }
}

// --- Enhanced Data Models ---
class RideRequest {
  final String? id;
  final String passengerId;
  final String passengerName;
  final String passengerPhone;
  final LatLng pickupLocation;
  final LatLng destination;
  final String status;
  final String? riderId;
  final String? riderName;
  final String? riderPhone;
  final LatLng? riderLocation;
  final String? routeToPickupEncoded;
  final String? routeToDestinationEncoded;
  final Timestamp timestamp;
  final String pickupAddress;
  final String destinationAddress;
  final double fareAmount;
  final String paymentMethod;
  final String rideType;
  final double passengerRating;
  final String estimatedDistance;
  final String estimatedDuration;
  final String specialRequests;
  final String vehiclePreference;
  final int luggageCount;
  final int passengerCount;
  final String otp;
  final bool otpVerified;
  final String? sosReason;
  final bool sosActive;
  final Timestamp? sosTimestamp;
  final String? vehicleNumber;
  final String? vehicleModel;
  final String? vehicleColor;
  final double? riderRating;
  final int? totalRides;
  final bool? passengerRated; // NEW: Track if passenger has rated this ride
  final bool? riderRated; // NEW: Track if rider has rated this ride

  RideRequest({
    this.id,
    required this.passengerId,
    required this.passengerName,
    required this.passengerPhone,
    required this.pickupLocation,
    required this.destination,
    this.status = 'pending',
    this.riderId,
    this.riderName,
    this.riderPhone,
    this.riderLocation,
    this.routeToPickupEncoded,
    this.routeToDestinationEncoded,
    required this.timestamp,
    required this.pickupAddress,
    required this.destinationAddress,
    this.fareAmount = 0.0,
    this.paymentMethod = 'Cash',
    this.rideType = 'Standard',
    this.passengerRating = 5.0,
    this.estimatedDistance = 'N/A',
    this.estimatedDuration = 'N/A',
    this.specialRequests = 'None',
    this.vehiclePreference = 'Any',
    this.luggageCount = 0,
    this.passengerCount = 1,
    required this.otp,
    this.otpVerified = false,
    this.sosReason,
    this.sosActive = false,
    this.sosTimestamp,
    this.vehicleNumber,
    this.vehicleModel,
    this.vehicleColor,
    this.riderRating,
    this.totalRides,
    this.passengerRated = false, // NEW: Default to false
    this.riderRated = false, // NEW: Default to false
  });

  factory RideRequest.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    GeoPoint pickupGeoPoint = data['pickupLocation'] as GeoPoint;
    GeoPoint destGeoPoint = data['destinationLocation'] as GeoPoint;

    return RideRequest(
      id: doc.id,
      passengerId: data['passengerId'] ?? 'unknown',
      passengerName: data['passengerName'] ?? 'Unknown Passenger',
      passengerPhone: data['passengerPhone'] ?? 'Not provided',
      pickupLocation: LatLng(pickupGeoPoint.latitude, pickupGeoPoint.longitude),
      destination: LatLng(destGeoPoint.latitude, destGeoPoint.longitude),
      status: data['status'] ?? 'pending',
      riderId: data['riderUid'],
      riderName: data['riderName'],
      riderPhone: data['riderPhone'],
      riderLocation: data['riderLocation'] != null
          ? LatLng(
              (data['riderLocation'] as GeoPoint).latitude,
              (data['riderLocation'] as GeoPoint).longitude,
            )
          : null,
      routeToPickupEncoded: data['route_to_pickup_encoded'],
      routeToDestinationEncoded: data['route_to_destination_encoded'],
      timestamp: data['requestTimestamp'] ?? Timestamp.now(),
      pickupAddress: data['pickupAddress'] ?? '',
      destinationAddress: data['destinationAddress'] ?? '',
      fareAmount: (data['fareAmount'] ?? 0.0).toDouble(),
      paymentMethod: data['paymentMethod'] ?? 'Cash',
      rideType: data['rideType'] ?? 'Standard',
      passengerRating: (data['passengerRating'] ?? 5.0).toDouble(),
      estimatedDistance: data['estimatedDistance'] ?? 'N/A',
      estimatedDuration: data['estimatedDuration'] ?? 'N/A',
      specialRequests: data['specialRequests'] ?? 'None',
      vehiclePreference: data['vehiclePreference'] ?? 'Any',
      luggageCount: data['luggageCount'] ?? 0,
      passengerCount: data['passengerCount'] ?? 1,
      otp: data['otp'] ?? '0000',
      otpVerified: data['otpVerified'] ?? false,
      sosReason: data['sosReason'],
      sosActive: data['sosActive'] ?? false,
      sosTimestamp: data['sosTimestamp'],
      vehicleNumber: data['vehicleNumber'],
      vehicleModel: data['vehicleModel'],
      vehicleColor: data['vehicleColor'],
      riderRating: (data['riderRating'] ?? 5.0).toDouble(),
      totalRides: data['totalRides'] ?? 0,
      passengerRated: data['passengerRated'] ?? false, // NEW
      riderRated: data['riderRated'] ?? false, // NEW
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'passengerId': passengerId,
      'passengerName': passengerName,
      'passengerPhone': passengerPhone,
      'pickupLocation': GeoPoint(pickupLocation.latitude, pickupLocation.longitude),
      'destinationLocation': GeoPoint(destination.latitude, destination.longitude),
      'status': status,
      'riderUid': riderId,
      'riderName': riderName,
      'riderPhone': riderPhone,
      'riderLocation': riderLocation != null
          ? GeoPoint(riderLocation!.latitude, riderLocation!.longitude)
          : null,
      'route_to_pickup_encoded': routeToPickupEncoded,
      'route_to_destination_encoded': routeToDestinationEncoded,
      'requestTimestamp': timestamp,
      'pickupAddress': pickupAddress,
      'destinationAddress': destinationAddress,
      'fareAmount': fareAmount,
      'paymentMethod': paymentMethod,
      'rideType': rideType,
      'passengerRating': passengerRating,
      'estimatedDistance': estimatedDistance,
      'estimatedDuration': estimatedDuration,
      'specialRequests': specialRequests,
      'vehiclePreference': vehiclePreference,
      'luggageCount': luggageCount,
      'passengerCount': passengerCount,
      'otp': otp,
      'otpVerified': otpVerified,
      'sosReason': sosReason,
      'sosActive': sosActive,
      'sosTimestamp': sosTimestamp,
      'vehicleNumber': vehicleNumber,
      'vehicleModel': vehicleModel,
      'vehicleColor': vehicleColor,
      'riderRating': riderRating,
      'totalRides': totalRides,
      'passengerRated': passengerRated, // NEW
      'riderRated': riderRated, // NEW
    };
  }
}

class UserPreferences {
  final String userId;
  final String? phoneNumber;
  final String? gender;
  final int? minDriverAge;
  final int? maxDriverAge;
  final String? preferredVehicleType;
  final bool? hasAccessibilityNeeds;
  final String? preferredPaymentMethod;
  final String? emergencyContact1;
  final String? emergencyContact2;
  final String? profileImageUrl;
  final String? homeAddress;
  final String? workAddress;
  final bool? allowNotifications;
  final bool? allowSMSAlerts;
  final String? preferredLanguage;

  UserPreferences({
    required this.userId,
    this.phoneNumber,
    this.gender,
    this.minDriverAge,
    this.maxDriverAge,
    this.preferredVehicleType,
    this.hasAccessibilityNeeds,
    this.preferredPaymentMethod,
    this.emergencyContact1,
    this.emergencyContact2,
    this.profileImageUrl,
    this.homeAddress,
    this.workAddress,
    this.allowNotifications,
    this.allowSMSAlerts,
    this.preferredLanguage,
  });

  factory UserPreferences.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return UserPreferences(
      userId: doc.id,
      phoneNumber: data['phoneNumber'],
      gender: data['gender'],
      minDriverAge: data['min_driver_age'],
      maxDriverAge: data['max_driver_age'],
      preferredVehicleType: data['preferred_vehicle_type'],
      hasAccessibilityNeeds: data['has_accessibility_needs'],
      preferredPaymentMethod: data['preferred_payment_method'],
      emergencyContact1: data['emergency_contact_1'],
      emergencyContact2: data['emergency_contact_2'],
      profileImageUrl: data['profileImageUrl'],
      homeAddress: data['homeAddress'],
      workAddress: data['workAddress'],
      allowNotifications: data['allowNotifications'] ?? true,
      allowSMSAlerts: data['allowSMSAlerts'] ?? true,
      preferredLanguage: data['preferredLanguage'] ?? 'English',
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      if (phoneNumber != null) 'phoneNumber': phoneNumber,
      if (gender != null) 'gender': gender,
      if (minDriverAge != null) 'min_driver_age': minDriverAge,
      if (maxDriverAge != null) 'max_driver_age': maxDriverAge,
      if (preferredVehicleType != null) 'preferred_vehicle_type': preferredVehicleType,
      if (hasAccessibilityNeeds != null) 'has_accessibility_needs': hasAccessibilityNeeds,
      if (preferredPaymentMethod != null) 'preferred_payment_method': preferredPaymentMethod,
      if (emergencyContact1 != null) 'emergency_contact_1': emergencyContact1,
      if (emergencyContact2 != null) 'emergency_contact_2': emergencyContact2,
      if (profileImageUrl != null) 'profileImageUrl': profileImageUrl,
      if (homeAddress != null) 'homeAddress': homeAddress,
      if (workAddress != null) 'workAddress': workAddress,
      'allowNotifications': allowNotifications ?? true,
      'allowSMSAlerts': allowSMSAlerts ?? true,
      'preferredLanguage': preferredLanguage ?? 'English',
    };
  }
}

// --- Enhanced Firestore Service ---
class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // NEW: Submit passenger rating for rider
  Future<void> submitPassengerRating({
    required String rideRequestId,
    required String riderId,
    required String passengerId,
    required String passengerName,
    required String riderName,
    required int rating,
    required String? comment,
    required double fareAmount,
    required String pickupAddress,
    required String destinationAddress,
  }) async {
    try {
      // Store rating in ratings collection
      await _db.collection('rider_ratings').add({
        'rideRequestId': rideRequestId,
        'riderId': riderId,
        'passengerId': passengerId,
        'passengerName': passengerName,
        'riderName': riderName,
        'rating': rating,
        'comment': comment ?? '',
        'fareAmount': fareAmount,
        'pickupAddress': pickupAddress,
        'destinationAddress': destinationAddress,
        'createdAt': Timestamp.now(),
        'type': 'passenger_to_rider',
      });

      // Update the ride request to mark it as rated by passenger
      await _db.collection('public_ride_requests').doc(rideRequestId).update({
        'passengerRated': true,
        'lastUpdated': Timestamp.now(),
      });

      // Update rider's rating statistics
      await _updateRiderRatingStats(riderId, rating);

      print('✅ Passenger rating submitted successfully for rider: $riderId');
    } catch (e) {
      print('❌ Error submitting passenger rating: $e');
      rethrow;
    }
  }

  // NEW: Update rider's rating statistics
  Future<void> _updateRiderRatingStats(String riderId, int newRating) async {
    try {
      final riderDoc = await _db.collection('riders').doc(riderId).get();
      if (riderDoc.exists) {
        final data = riderDoc.data()!;
        final int currentTotalRatings = data['totalRatings'] ?? 0;
        final int currentRatingSum = data['ratingSum'] ?? 0;
        final int currentTotalRides = data['totalRides'] ?? 0;

        final int newTotalRatings = currentTotalRatings + 1;
        final int newRatingSum = currentRatingSum + newRating;
        final double newAverageRating = newRatingSum / newTotalRatings.toDouble();

        await _db.collection('riders').doc(riderId).update({
          'totalRatings': newTotalRatings,
          'ratingSum': newRatingSum,
          'averageRating': double.parse(newAverageRating.toStringAsFixed(2)),
          'lastRatingUpdate': Timestamp.now(),
        });

        print('✅ Rider rating stats updated: $newAverageRating average from $newTotalRatings ratings');
      }
    } catch (e) {
      print('❌ Error updating rider rating stats: $e');
    }
  }

  // NEW: Get rider ratings history
  Stream<QuerySnapshot> getRiderRatings(String riderId) {
    return _db.collection('rider_ratings')
        .where('riderId', isEqualTo: riderId)
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  // NEW: Get passenger ratings history
  Stream<QuerySnapshot> getPassengerRatings(String passengerId) {
    return _db.collection('passenger_ratings')
        .where('passengerId', isEqualTo: passengerId)
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  Future<UserPreferences?> getUserPreferences(String userId) async {
    try {
      DocumentSnapshot doc = await _db.collection('passengers').doc(userId).get();
      if (doc.exists) {
        return UserPreferences.fromFirestore(doc);
      }
    } catch (e) {
      print('Error getting user preferences: $e');
    }
    return null;
  }

  Future<void> saveUserPreferences(String userId, UserPreferences preferences) async {
    try {
      await _db.collection('passengers').doc(userId).set(preferences.toFirestore(), SetOptions(merge: true));
    } catch (e) {
      print('Error saving preferences: $e');
      rethrow;
    }
  }

  Future<String?> addRideRequest(RideRequest rideRequest) async {
    try {
      DocumentReference docRef = await _db.collection('public_ride_requests').add(rideRequest.toFirestore());
      await _createDriverProposals(rideRequest, docRef.id);
      return docRef.id;
    } catch (e) {
      print('Error adding ride request: $e');
      return null;
    }
  }

  Future<void> _createDriverProposals(RideRequest rideRequest, String requestId) async {
    try {
      final ridersSnapshot = await _db.collection('riders')
          .where('status', isEqualTo: 'available')
          .where('is_online', isEqualTo: true)
          .get();

      for (final riderDoc in ridersSnapshot.docs) {
        final riderData = riderDoc.data();
        final riderLocation = riderData['currentLocation'] as GeoPoint?;
        
        if (riderLocation != null) {
          final double distance = Geolocator.distanceBetween(
            riderLocation.latitude, riderLocation.longitude,
            rideRequest.pickupLocation.latitude, rideRequest.pickupLocation.longitude,
          );

          // Use advanced matching  Dijkstra algorithm within 10km
          if (distance <= 10000) {
            final double matchScore = _calculateMatchScore(
              distance, 
              riderData['rating'] ?? 5.0,
              rideRequest.vehiclePreference,
              riderData['vehicle_type'],
              riderData['total_rides'] ?? 0,
            );

            // Only send proposal if match score is good enough
            if (matchScore >= 0.6) {
              await _db.collection('driver_proposals').add({
                'original_request_id': requestId,
                'riderUid': riderDoc.id,
                'riderName': riderData['name'],
                'riderPhone': riderData['phone'],
                'riderRating': riderData['rating'] ?? 5.0,
                'vehicleNumber': riderData['vehicle_number'],
                'vehicleModel': riderData['vehicle_model'],
                'vehicleColor': riderData['vehicle_color'],
                'vehicleType': riderData['vehicle_type'],
                'totalRides': riderData['total_rides'] ?? 0,
                'passengerId': rideRequest.passengerId,
                'passengerName': rideRequest.passengerName,
                'passengerPhone': rideRequest.passengerPhone,
                'pickupLocation': GeoPoint(rideRequest.pickupLocation.latitude, rideRequest.pickupLocation.longitude),
                'destinationLocation': GeoPoint(rideRequest.destination.latitude, rideRequest.destination.longitude),
                'pickupAddress': rideRequest.pickupAddress,
                'destinationAddress': rideRequest.destinationAddress,
                'fareAmount': _calculateFare(distance, rideRequest.rideType),
                'paymentMethod': rideRequest.paymentMethod,
                'rideType': rideRequest.rideType,
                'passengerRating': rideRequest.passengerRating,
                'estimatedDistance': '${(distance / 1000).toStringAsFixed(1)} km',
                'estimatedDuration': '${(distance / 10000 * 60).toStringAsFixed(0)} min',
                'specialRequests': rideRequest.specialRequests,
                'vehiclePreference': rideRequest.vehiclePreference,
                'luggageCount': rideRequest.luggageCount,
                'passengerCount': rideRequest.passengerCount,
                'status': 'pending',
                'requestTimestamp': Timestamp.now(),
                'distanceToPickup': distance,
                'match_score': matchScore,
                'priority_level': _calculatePriorityLevel(matchScore),
              });
            }
          }
        }
      }
    } catch (e) {
      print('Error creating driver proposals: $e');
    }
  }

  double _calculateMatchScore(double distance, double rating, String passengerPreference, String? riderVehicleType, int totalRides) {
    final double distanceScore = 1.0 - (distance / 10000); // Normalize to 0-1
    final double ratingScore = rating / 5.0; // Normalize to 0-1
    final double experienceScore = min(totalRides / 100.0, 1.0); // Cap at 1.0
    final double preferenceScore = (passengerPreference == 'Any' || riderVehicleType == passengerPreference) ? 1.0 : 0.5;
    
    return (distanceScore * 0.4) + (ratingScore * 0.3) + (experienceScore * 0.2) + (preferenceScore * 0.1);
  }

  int _calculatePriorityLevel(double matchScore) {
    if (matchScore >= 0.8) return 1;
    if (matchScore >= 0.6) return 2;
    return 3;
  }

  double _calculateFare(double distance, String rideType) {
    double baseFare = 30.0;
    double ratePerKm = 8.0;
    
    // Different pricing for different ride types
    switch (rideType) {
      case 'Premium':
        baseFare = 50.0;
        ratePerKm = 12.0;
        break;
      case 'SUV':
        baseFare = 70.0;
        ratePerKm = 15.0;
        break;
      case 'Electric':
        baseFare = 35.0;
        ratePerKm = 7.0;
        break;
    }
    
    return baseFare + (distance / 1000) * ratePerKm;
  }

  Future<void> updateRideRequestStatus(String rideRequestId, String status) async {
    try {
      await _db.collection('public_ride_requests').doc(rideRequestId).update({'status': status});
    } catch (e) {
      print('Error updating ride status: $e');
    }
  }

  Future<void> updateRideRequest(String rideRequestId, Map<String, dynamic> updates) async {
    try {
      await _db.collection('public_ride_requests').doc(rideRequestId).update(updates);
    } catch (e) {
      print('Error updating ride request: $e');
    }
  }

  Stream<DocumentSnapshot> getRideRequestStream(String rideRequestId) {
    return _db.collection('public_ride_requests').doc(rideRequestId).snapshots();
  }

  Stream<QuerySnapshot> getAcceptedRideStream(String passengerId) {
    return _db.collection('public_ride_requests')
        .where('passengerId', isEqualTo: passengerId)
        .where('status', whereIn: ['accepted', 'arrived_at_pickup', 'picked_up', 'on_way', 'completed'])
        .orderBy('requestTimestamp', descending: true)
        .snapshots();
  }

  Future<List<RideRequest>> getRideHistory(String passengerId) async {
    try {
      final snapshot = await _db.collection('public_ride_requests')
          .where('passengerId', isEqualTo: passengerId)
          .where('status', whereIn: ['completed', 'cancelled'])
          .orderBy('requestTimestamp', descending: true)
          .limit(20)
          .get();
      
      return snapshot.docs.map((doc) => RideRequest.fromFirestore(doc)).toList();
    } catch (e) {
      print('Error getting ride history: $e');
      return [];
    }
  }

  String generateOTP() {
    Random random = Random();
    return (1000 + random.nextInt(9000)).toString();
  }

  Future<void> updateRiderLocation(String riderId, LatLng location) async {
    try {
      await _db.collection('riders').doc(riderId).update({
        'currentLocation': GeoPoint(location.latitude, location.longitude),
        'lastUpdated': Timestamp.now(),
      });
    } catch (e) {
      print('Error updating rider location: $e');
    }
  }

  Future<Map<String, dynamic>?> getRiderDetails(String riderId) async {
    try {
      final doc = await _db.collection('riders').doc(riderId).get();
      return doc.data();
    } catch (e) {
      print('Error getting rider details: $e');
      return null;
    }
  }
}

// --- Enhanced Location Service ---
class LocationService {
  static Future<bool> _checkPermissions() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission == LocationPermission.whileInUse || permission == LocationPermission.always;
  }

  static Future<Position?> getCurrentLocation() async {
    try {
      bool hasPermission = await _checkPermissions();
      if (!hasPermission) {
        return null;
      }

      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return null;
      }

      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
    } catch (e) {
      print('Error getting location: $e');
      return null;
    }
  }

  static Future<String> getAddressFromLatLng(LatLng latLng) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(
        latLng.latitude,
        latLng.longitude,
      );
      if (placemarks.isNotEmpty) {
        Placemark place = placemarks.first;
        return '${place.street}, ${place.locality}, ${place.administrativeArea} ${place.postalCode}';
      }
      return '${latLng.latitude.toStringAsFixed(4)}, ${latLng.longitude.toStringAsFixed(4)}';
    } catch (e) {
      return '${latLng.latitude.toStringAsFixed(4)}, ${latLng.longitude.toStringAsFixed(4)}';
    }
  }

  static Future<LatLng?> getLatLngFromAddress(String address) async {
    try {
      List<Location> locations = await locationFromAddress(address);
      if (locations.isNotEmpty) {
        return LatLng(locations.first.latitude, locations.first.longitude);
      }
    } catch (e) {
      print('Error geocoding address: $e');
    }
    return null;
  }

  static double calculateDistance(LatLng start, LatLng end) {
    return Geolocator.distanceBetween(
      start.latitude, start.longitude,
      end.latitude, end.longitude,
    );
  }

  static Future<bool> canReachIn5Minutes(LatLng passengerLocation, LatLng pickupLocation) async {
    double distance = calculateDistance(passengerLocation, pickupLocation);
    double timeInMinutes = distance / 83.33;
    return timeInMinutes <= 5;
  }

  static Future<List<Placemark>> getPlaceDetails(LatLng latLng) async {
    try {
      return await placemarkFromCoordinates(latLng.latitude, latLng.longitude);
    } catch (e) {
      print('Error getting place details: $e');
      return [];
    }
  }

  static Future<bool> isLocationServiceEnabled() async {
    return await Geolocator.isLocationServiceEnabled();
  }

  static Future<void> openLocationSettings() async {
    await Geolocator.openLocationSettings();
  }
}

// --- Enhanced Route Service ---
class RouteService {
  final String apiKey;

  RouteService(this.apiKey);

  Future<Map<String, dynamic>?> getRouteWithDetails(LatLng start, LatLng end) async {
    try {
      final url = Uri.parse(
        'https://graphhopper.com/api/1/route?'
        'point=${start.latitude},${start.longitude}&'
        'point=${end.latitude},${end.longitude}&'
        'vehicle=car&'
        'key=$apiKey&'
        'type=json&'
        'instructions=true&'
        'calc_points=true&'
        'elevation=false&'
        'points_encoded=false',
      );

      final response = await http.get(url);
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final paths = data['paths'] as List;
        if (paths.isNotEmpty) {
          final path = paths.first;
          final points = path['points']?['coordinates'] as List?;
          final distance = path['distance'] as double?;
          final time = path['time'] as int?;
          final instructions = path['instructions'] as List?;
          
          List<LatLng> routePoints = [];
          if (points != null) {
            for (var point in points) {
              routePoints.add(LatLng(point[1] as double, point[0] as double));
            }
          }
          
          return {
            'routePoints': routePoints,
            'distance': distance,
            'duration': time,
            'instructions': instructions,
          };
        }
      } else {
        print('GraphHopper API error: ${response.statusCode}');
      }
    } catch (e) {
      print('Error getting route: $e');
    }
    return null;
  }

  Future<List<LatLng>?> getRoute(LatLng start, LatLng end) async {
    final result = await getRouteWithDetails(start, end);
    return result?['routePoints'] as List<LatLng>?;
  }

  String encodePolylineManual(List<LatLng> points) {
    final pointsList = points.map((point) => {
      'lat': point.latitude,
      'lng': point.longitude
    }).toList();
    
    return json.encode(pointsList);
  }

  List<LatLng> decodePolylineManual(String encoded) {
    try {
      final pointsList = json.decode(encoded) as List;
      return pointsList.map((point) => 
        LatLng(point['lat'], point['lng'])
      ).toList();
    } catch (e) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>?> getAlternativeRoutes(LatLng start, LatLng end) async {
    try {
      final url = Uri.parse(
        'https://graphhopper.com/api/1/route?'
        'point=${start.latitude},${start.longitude}&'
        'point=${end.latitude},${end.longitude}&'
        'vehicle=car&'
        'key=$apiKey&'
        'type=json&'
        'instructions=false&'
        'calc_points=true&'
        'alternative_route.max_paths=3',
      );

      final response = await http.get(url);
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final paths = data['paths'] as List;
        
        List<Map<String, dynamic>> routes = [];
        for (var path in paths) {
          final points = path['points'];
          final distance = path['distance'] as double?;
          final time = path['time'] as int?;
          
          final polylinePoints = PolylinePoints();
          final pointList = polylinePoints.decodePolyline(points);
          final routePoints = pointList.map((point) => LatLng(point.latitude, point.longitude)).toList();
          
          routes.add({
            'routePoints': routePoints,
            'distance': distance,
            'duration': time,
          });
        }
        
        return routes;
      }
    } catch (e) {
      print('Error getting alternative routes: $e');
    }
    return null;
  }
}

// --- Enhanced SOS Service ---
class SOSService {
  static Future<void> sendSOSAlert({
    required String rideId,
    required String passengerName,
    required String passengerPhone,
    required String riderName,
    required String riderPhone,
    required String reason,
    required LatLng currentLocation,
    required String destinationAddress,
    required String pickupAddress,
    required String vehicleNumber,
  }) async {
    try {
      final userPrefs = await FirestoreService().getUserPreferences(FirebaseAuth.instance.currentUser!.uid);
      
      String locationUrl = 'https://maps.google.com/?q=${currentLocation.latitude},${currentLocation.longitude}';
      String message = '''
🚨 EMERGENCY ALERT - RideHail Pro 🚨

Passenger Details:
👤 Name: $passengerName
📞 Phone: $passengerPhone

Rider Details:
🚗 Name: $riderName
📞 Phone: $riderPhone
🔢 Vehicle: $vehicleNumber

Emergency Reason: $reason

📍 Current Location: $pickupAddress
🎯 Destination: $destinationAddress

🗺️ Live Location: $locationUrl

⏰ Timestamp: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now())}

🚨 IMMEDIATE ACTION REQUIRED 🚨
Please check on the passenger immediately and contact authorities if needed.

This is an automated emergency alert from RideHail Pro Safety System.
''';

      // Send to emergency contacts
      if (userPrefs?.emergencyContact1 != null && userPrefs!.allowSMSAlerts == true) {
        await _sendSMS(userPrefs.emergencyContact1!, message);
      }
      if (userPrefs?.emergencyContact2 != null && userPrefs!.allowSMSAlerts == true) {
        await _sendSMS(userPrefs.emergencyContact2!, message);
      }

      // Send to app support
      await _sendToSupport(rideId, message);

      // Make emergency call
      await _launchCall('100');

      // Log SOS event
      await FirebaseFirestore.instance.collection('sos_alerts').add({
        'rideId': rideId,
        'passengerId': FirebaseAuth.instance.currentUser!.uid,
        'passengerName': passengerName,
        'passengerPhone': passengerPhone,
        'riderName': riderName,
        'riderPhone': riderPhone,
        'vehicleNumber': vehicleNumber,
        'reason': reason,
        'location': GeoPoint(currentLocation.latitude, currentLocation.longitude),
        'pickupAddress': pickupAddress,
        'destinationAddress': destinationAddress,
        'timestamp': Timestamp.now(),
        'resolved': false,
        'alertSentTo': [
          if (userPrefs?.emergencyContact1 != null) userPrefs!.emergencyContact1!,
          if (userPrefs?.emergencyContact2 != null) userPrefs!.emergencyContact2!,
        ],
        'priority': 'high',
      });

    } catch (e) {
      print('Error sending SOS alert: $e');
    }
  }

  static Future<void> _sendToSupport(String rideId, String message) async {
    try {
      await FirebaseFirestore.instance.collection('support_alerts').add({
        'type': 'SOS',
        'rideId': rideId,
        'message': message,
        'timestamp': Timestamp.now(),
        'status': 'pending',
      });
    } catch (e) {
      print('Error sending to support: $e');
    }
  }

  static Future<void> _sendSMS(String phoneNumber, String message) async {
    try {
      final Uri smsLaunchUri = Uri(
        scheme: 'sms',
        path: phoneNumber,
        queryParameters: <String, String>{
          'body': message,
        },
      );
      
      if (await canLaunchUrl(smsLaunchUri)) {
        await launchUrl(smsLaunchUri);
      }
    } catch (e) {
      print('Error sending SMS: $e');
    }
  }

  static Future<void> _launchCall(String phoneNumber) async {
    final Uri telLaunchUri = Uri(
      scheme: 'tel',
      path: phoneNumber,
    );
    
    if (await canLaunchUrl(telLaunchUri)) {
      await launchUrl(telLaunchUri);
    }
  }

  static Future<void> shareRideDetails({
    required String passengerName,
    required String riderName,
    required String pickupAddress,
    required String destinationAddress,
    required LatLng currentLocation,
    required String vehicleNumber,
    required String vehicleModel,
    required double fareAmount,
    required String estimatedDuration,
  }) async {
    String locationUrl = 'https://maps.google.com/?q=${currentLocation.latitude},${currentLocation.longitude}';
    String message = '''
🚗 RideHail Pro - Ride Sharing Details

Passenger: $passengerName
Rider: $riderName
Vehicle: $vehicleNumber - $vehicleModel

📍 Pickup: $pickupAddress
🎯 Destination: $destinationAddress
💰 Fare: ₹$fareAmount
⏰ Estimated Time: $estimatedDuration

📍 Current Location: $locationUrl

🕒 Shared at: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now())}

This ride is being tracked in real-time via RideHail Pro for your safety.
''';

    final Uri shareUri = Uri(
      scheme: 'sms',
      queryParameters: {
        'body': message,
      },
    );
    
    if (await canLaunchUrl(shareUri)) {
      await launchUrl(shareUri);
    }
  }

  static Future<void> sendRideCompletionAlert({
    required String passengerName,
    required String riderName,
    required String pickupAddress,
    required String destinationAddress,
    required double fareAmount,
    required double rating,
  }) async {
    String message = '''
✅ Ride Completed - RideHail Pro

Thank you for riding with us!

Passenger: $passengerName
Rider: $riderName

📍 From: $pickupAddress
🎯 To: $destinationAddress
💰 Fare: ₹$fareAmount
⭐ Rating: $rating/5

We hope you had a pleasant journey!

Thank you for choosing RideHail Pro.
''';

    final userPrefs = await FirestoreService().getUserPreferences(FirebaseAuth.instance.currentUser!.uid);
    
    if (userPrefs?.allowSMSAlerts == true) {
      await _sendSMS(userPrefs!.phoneNumber ?? '', message);
    }
  }
}

// --- Enhanced Notification Service ---
class NotificationService {
  static void showRideStatusNotification(BuildContext context, String title, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              message,
              style: const TextStyle(fontSize: 14),
            ),
          ],
        ),
        backgroundColor: Colors.black,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  static void showSuccessNotification(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  static void showErrorNotification(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  static void showInfoNotification(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.info, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.blue,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}

// --- Enhanced Main Application ---
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  
  // Request notification permissions
  await Permission.notification.request();
  await Permission.location.request();
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RideHail Pro',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true, // ✅ optional, recommended for Flutter 3.35+
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            elevation: 2,
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: Colors.grey[100],
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          hintStyle: TextStyle(color: Colors.grey[600]),
        ),
        cardTheme: const CardThemeData(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
        ),
      ),
      home: const SplashScreen(), // ✅ Moved outside ThemeData
    );
  }
}

// --- Enhanced Splash Screen ---
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    
    _controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );
    
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    );
    
    _controller.forward();
    
    Future.delayed(const Duration(seconds: 3), () {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const AuthWrapper()),
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: ScaleTransition(
          scale: _animation,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.directions_car_filled,
                  size: 60,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 30),
              const Text(
                'RideHail Pro',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Safe • Reliable • Fast',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.white70,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 40),
              const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                strokeWidth: 3,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- Auth Wrapper ---
class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: AuthService().user,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.active) {
          User? user = snapshot.data;
          if (user == null) {
            return const LoginScreen();
          }
          return FutureBuilder<UserPreferences?>(
            future: FirestoreService().getUserPreferences(user.uid),
            builder: (context, preferencesSnapshot) {
              if (preferencesSnapshot.connectionState == ConnectionState.done) {
                if (preferencesSnapshot.hasData) {
                  return MainRideScreen(userId: user.uid);
                } else {
                  return PreferencesScreen(userId: user.uid);
                }
              }
              return const Scaffold(
                backgroundColor: Colors.black,
                body: Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              );
            },
          );
        }
        return const Scaffold(
          backgroundColor: Colors.black,
          body: Center(
            child: CircularProgressIndicator(color: Colors.white),
          ),
        );
      },
    );
  }
}

// --- Enhanced Login Screen ---
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final AuthService _auth = AuthService();
  final _formKey = GlobalKey<FormState>();
  String email = '';
  String password = '';
  String phone = '';
  String error = '';
  bool showSignIn = true;
  bool _isLoading = false;
  bool _obscurePassword = true;

  void _showSnackBar(String message) {
    NotificationService.showInfoNotification(context, message);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 40),
              Center(
                child: Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(
                    Icons.directions_car_filled,
                    size: 35,
                    color: Colors.black,
                  ),
                ),
              ),
              const SizedBox(height: 30),
              Center(
                child: Text(
                  showSignIn ? 'Welcome Back!' : 'Create Account',
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: Text(
                  showSignIn 
                      ? 'Sign in to continue your journey'
                      : 'Join us for a better ride experience',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[600],
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 40),
              Form(
                key: _formKey,
                child: Column(
                  children: [
                    TextFormField(
                      decoration: const InputDecoration(
                        labelText: 'Email Address',
                        prefixIcon: Icon(Icons.email_rounded),
                      ),
                      validator: (val) => val!.isEmpty ? 'Enter an email' : null,
                      onChanged: (val) => setState(() => email = val),
                    ),
                    const SizedBox(height: 20),
                    if (!showSignIn)
                      TextFormField(
                        decoration: const InputDecoration(
                          labelText: 'Phone Number',
                          prefixIcon: Icon(Icons.phone_rounded),
                        ),
                        keyboardType: TextInputType.phone,
                        validator: (val) => val!.isEmpty ? 'Enter phone number' : null,
                        onChanged: (val) => setState(() => phone = val),
                      ),
                    if (!showSignIn) const SizedBox(height: 20),
                    TextFormField(
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_rounded),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword ? Icons.visibility_off : Icons.visibility,
                            color: Colors.grey,
                          ),
                          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                        ),
                      ),
                      obscureText: _obscurePassword,
                      validator: (val) => val!.length < 6
                          ? 'Password must be at least 6 characters'
                          : null,
                      onChanged: (val) => setState(() => password = val),
                    ),
                    const SizedBox(height: 30),
                    if (error.isNotEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.red[50],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.red[100]!),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.error, color: Colors.red[400]),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                error,
                                style: TextStyle(color: Colors.red[700]),
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 25),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : () async {
                          if (_formKey.currentState!.validate()) {
                            setState(() => _isLoading = true);
                            User? user;
                            try {
                              if (showSignIn) {
                                user = await _auth.signIn(email, password);
                              } else {
                                user = await _auth.signUp(email, password, phone);
                              }
                            } catch (e) {
                              setState(() {
                                error = 'Could not process credentials: ${e.toString()}';
                              });
                              _showSnackBar(error);
                            } finally {
                              setState(() => _isLoading = false);
                            }

                            if (user == null) {
                              setState(() {
                                error = 'Could not sign in with those credentials.';
                              });
                              _showSnackBar(error);
                            }
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                showSignIn ? 'Sign In' : 'Create Account',
                                style: const TextStyle(fontSize: 16),
                              ),
                      ),
                    ),
                    const SizedBox(height: 25),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          showSignIn
                              ? "Don't have an account?"
                              : "Already have an account?",
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              showSignIn = !showSignIn;
                              error = '';
                            });
                          },
                          child: Text(
                            showSignIn ? 'Sign up' : 'Sign in',
                            style: const TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- Enhanced Preferences Screen ---
class PreferencesScreen extends StatefulWidget {
  final String userId;
  const PreferencesScreen({super.key, required this.userId});

  @override
  State<PreferencesScreen> createState() => _PreferencesScreenState();
}

class _PreferencesScreenState extends State<PreferencesScreen> {
  final _formKey = GlobalKey<FormState>();
  final FirestoreService _firestoreService = FirestoreService();
  String? _selectedGender;
  final TextEditingController _minAgeController = TextEditingController();
  final TextEditingController _maxAgeController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _emergencyContact1Controller = TextEditingController();
  final TextEditingController _emergencyContact2Controller = TextEditingController();
  final TextEditingController _homeAddressController = TextEditingController();
  final TextEditingController _workAddressController = TextEditingController();
  String? _selectedVehicleType;
  bool _hasAccessibilityNeeds = false;
  String? _selectedPaymentMethod;
  bool _isLoading = false;
  bool _allowNotifications = true;
  bool _allowSMSAlerts = true;
  String? _selectedLanguage;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  @override
  void dispose() {
    _minAgeController.dispose();
    _maxAgeController.dispose();
    _phoneController.dispose();
    _emergencyContact1Controller.dispose();
    _emergencyContact2Controller.dispose();
    _homeAddressController.dispose();
    _workAddressController.dispose();
    super.dispose();
  }

  void _showSnackBar(String message) {
    NotificationService.showSuccessNotification(context, message);
  }

  Future<void> _loadPreferences() async {
    setState(() => _isLoading = true);
    try {
      UserPreferences? preferences = await _firestoreService.getUserPreferences(widget.userId);
      if (preferences != null) {
        setState(() {
          _selectedGender = preferences.gender;
          _minAgeController.text = preferences.minDriverAge?.toString() ?? '';
          _maxAgeController.text = preferences.maxDriverAge?.toString() ?? '';
          _phoneController.text = preferences.phoneNumber ?? '';
          _selectedVehicleType = preferences.preferredVehicleType;
          _hasAccessibilityNeeds = preferences.hasAccessibilityNeeds ?? false;
          _selectedPaymentMethod = preferences.preferredPaymentMethod;
          _emergencyContact1Controller.text = preferences.emergencyContact1 ?? '';
          _emergencyContact2Controller.text = preferences.emergencyContact2 ?? '';
          _homeAddressController.text = preferences.homeAddress ?? '';
          _workAddressController.text = preferences.workAddress ?? '';
          _allowNotifications = preferences.allowNotifications ?? true;
          _allowSMSAlerts = preferences.allowSMSAlerts ?? true;
          _selectedLanguage = preferences.preferredLanguage ?? 'English';
        });
      }
    } catch (e) {
      _showSnackBar('Error loading preferences: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _savePreferences() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);
      try {
        UserPreferences preferences = UserPreferences(
          userId: widget.userId,
          phoneNumber: _phoneController.text.isNotEmpty ? _phoneController.text : null,
          gender: _selectedGender,
          minDriverAge: int.tryParse(_minAgeController.text),
          maxDriverAge: int.tryParse(_maxAgeController.text),
          preferredVehicleType: _selectedVehicleType,
          hasAccessibilityNeeds: _hasAccessibilityNeeds,
          preferredPaymentMethod: _selectedPaymentMethod,
          emergencyContact1: _emergencyContact1Controller.text.isNotEmpty ? _emergencyContact1Controller.text : null,
          emergencyContact2: _emergencyContact2Controller.text.isNotEmpty ? _emergencyContact2Controller.text : null,
          homeAddress: _homeAddressController.text.isNotEmpty ? _homeAddressController.text : null,
          workAddress: _workAddressController.text.isNotEmpty ? _workAddressController.text : null,
          allowNotifications: _allowNotifications,
          allowSMSAlerts: _allowSMSAlerts,
          preferredLanguage: _selectedLanguage,
        );

        await _firestoreService.saveUserPreferences(widget.userId, preferences);
        _showSnackBar('Preferences saved successfully! 🎉');
        
        if (mounted) {
          Navigator.of(context).pushReplacement(MaterialPageRoute(
            builder: (context) => MainRideScreen(userId: widget.userId),
          ));
        }
      } catch (e) {
        NotificationService.showErrorNotification(context, 'Error saving preferences: $e');
      } finally {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Your Preferences'),
        centerTitle: true,
        backgroundColor: Colors.black,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Center(
                      child: CircleAvatar(
                        radius: 40,
                        backgroundColor: Colors.black,
                        child: Icon(
                          Icons.person,
                          size: 40,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Center(
                      child: Text(
                        'Customize Your Ride',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: Text(
                        'Set your preferences for a better experience',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                    ),
                    const SizedBox(height: 30),

                    _buildPreferenceSection('📱 Contact Information'),
                    TextFormField(
                      controller: _phoneController,
                      decoration: const InputDecoration(
                        hintText: 'Enter your phone number',
                        prefixIcon: Icon(Icons.phone_rounded),
                      ),
                      keyboardType: TextInputType.phone,
                    ),

                    const SizedBox(height: 20),
                    _buildPreferenceSection('👤 Personal Details'),
                    DropdownButtonFormField<String>(
                      value: _selectedGender,
                      decoration: const InputDecoration(
                        hintText: 'Select your gender',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      items: ['Male', 'Female', 'Other', 'Prefer not to say']
                          .map((value) => DropdownMenuItem(
                                value: value,
                                child: Text(value),
                              ))
                          .toList(),
                      onChanged: (value) => setState(() => _selectedGender = value),
                    ),
                    const SizedBox(height: 20),
                    _buildPreferenceSection('🎂 Driver Preferences'),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _minAgeController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Minimum Age',
                              prefixIcon: Icon(Icons.arrow_upward),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextFormField(
                            controller: _maxAgeController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Maximum Age',
                              prefixIcon: Icon(Icons.arrow_downward),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _buildPreferenceSection('🚗 Vehicle Preferences'),
                    DropdownButtonFormField<String>(
                      value: _selectedVehicleType,
                      decoration: const InputDecoration(
                        hintText: 'Select preferred vehicle type',
                        prefixIcon: Icon(Icons.directions_car),
                      ),
                      items: [
                        'Gear Bike',
                        'Gear Less Bike',
                        'Electric Vehicle',
                        'Non Registered Electric Vehicle',
                        'Any Vehicle'
                      ].map((value) => DropdownMenuItem(
                                value: value,
                                child: Text(value),
                              ))
                          .toList(),
                      onChanged: (value) => setState(() => _selectedVehicleType = value),
                    ),
                    const SizedBox(height: 20),
                    _buildPreferenceSection('♿ Special Requirements'),
                    Card(
                      child: SwitchListTile(
                        title: const Text('I have accessibility needs'),
                        subtitle: const Text('Wheelchair access, extra space, etc.'),
                        value: _hasAccessibilityNeeds,
                        onChanged: (value) => setState(() => _hasAccessibilityNeeds = value),
                      ),
                    ),
                    const SizedBox(height: 20),
                    _buildPreferenceSection('💳 Payment Preferences'),
                    DropdownButtonFormField<String>(
                      value: _selectedPaymentMethod,
                      decoration: const InputDecoration(
                        hintText: 'Select preferred payment method',
                        prefixIcon: Icon(Icons.payment),
                      ),
                      items: ['UPI', 'Cash', 'Mobile Wallet', 'Credit Card', 'Others']
                          .map((value) => DropdownMenuItem(
                                value: value,
                                child: Text(value),
                              ))
                          .toList(),
                      onChanged: (value) => setState(() => _selectedPaymentMethod = value),
                    ),
                    const SizedBox(height: 20),
                    _buildPreferenceSection('🏠 Saved Addresses'),
                    TextFormField(
                      controller: _homeAddressController,
                      decoration: const InputDecoration(
                        labelText: 'Home Address',
                        prefixIcon: Icon(Icons.home_rounded),
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _workAddressController,
                      decoration: const InputDecoration(
                        labelText: 'Work Address',
                        prefixIcon: Icon(Icons.work_rounded),
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 20),
                    _buildPreferenceSection('🆘 Emergency Contacts'),
                    Text(
                      'These contacts will be notified in case of emergency',
                      style: TextStyle(color: Colors.grey[600], fontSize: 14),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _emergencyContact1Controller,
                      decoration: const InputDecoration(
                        labelText: 'Emergency Contact 1',
                        prefixIcon: Icon(Icons.emergency_share),
                      ),
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _emergencyContact2Controller,
                      decoration: const InputDecoration(
                        labelText: 'Emergency Contact 2',
                        prefixIcon: Icon(Icons.emergency_share),
                      ),
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 20),
                    _buildPreferenceSection('🔔 Notification Settings'),
                    Card(
                      child: Column(
                        children: [
                          SwitchListTile(
                            title: const Text('Push Notifications'),
                            subtitle: const Text('Receive ride updates and alerts'),
                            value: _allowNotifications,
                            onChanged: (value) => setState(() => _allowNotifications = value),
                          ),
                          SwitchListTile(
                            title: const Text('SMS Alerts'),
                            subtitle: const Text('Receive emergency alerts via SMS'),
                            value: _allowSMSAlerts,
                            onChanged: (value) => setState(() => _allowSMSAlerts = value),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    _buildPreferenceSection('🌐 Language Preferences'),
                    DropdownButtonFormField<String>(
                      value: _selectedLanguage,
                      decoration: const InputDecoration(
                        hintText: 'Select preferred language',
                        prefixIcon: Icon(Icons.language),
                      ),
                      items: ['English', 'Hindi', 'Spanish', 'French', 'German']
                          .map((value) => DropdownMenuItem(
                                value: value,
                                child: Text(value),
                              ))
                          .toList(),
                      onChanged: (value) => setState(() => _selectedLanguage = value),
                    ),
                    const SizedBox(height: 40),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _savePreferences,
                        style: ElevatedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.save_rounded),
                                  SizedBox(width: 10),
                                  Text(
                                    'Save Preferences & Continue',
                                    style: TextStyle(fontSize: 16),
                                  ),
                                ],
                              ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildPreferenceSection(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: Colors.black,
        ),
      ),
    );
  }
}

// --- Enhanced Main Ride Screen ---
class MainRideScreen extends StatefulWidget {
  final String userId;
  const MainRideScreen({super.key, required this.userId});

  @override
  State<MainRideScreen> createState() => _MainRideScreenState();
}

class _MainRideScreenState extends State<MainRideScreen> {
  LatLng? _currentLocation;
  LatLng? _selectedDestination;
  String _currentAddress = 'Getting your location...';
  String _destinationAddress = '';
  final TextEditingController _destinationController = TextEditingController();
  bool _isLoading = false;
  bool _locationLoaded = false;
  final FirestoreService _firestoreService = FirestoreService();
  final String _graphHopperApiKey = '4f39eb06-7c1e-45c1-b8c2-722244e66fdc';
  StreamSubscription<QuerySnapshot>? _acceptedRideSubscription;
  RideRequest? _activeRide;
  int _selectedIndex = 0;
  List<RideRequest> _rideHistory = [];

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
    _listenForAcceptedRides();
    _loadRideHistory();
  }

  @override
  void dispose() {
    _destinationController.dispose();
    _acceptedRideSubscription?.cancel();
    super.dispose();
  }

  void _showSnackBar(String message) {
    NotificationService.showInfoNotification(context, message);
  }

  void _loadRideHistory() async {
    try {
      final history = await _firestoreService.getRideHistory(widget.userId);
      setState(() {
        _rideHistory = history;
      });
    } catch (e) {
      print('Error loading ride history: $e');
    }
  }

  void _listenForAcceptedRides() {
    _acceptedRideSubscription = _firestoreService.getAcceptedRideStream(widget.userId).listen((snapshot) {
      if (snapshot.docs.isNotEmpty) {
        final doc = snapshot.docs.first;
        final rideRequest = RideRequest.fromFirestore(doc);
        setState(() {
          _activeRide = rideRequest;
        });
        
        if (rideRequest.status == 'accepted') {
          NotificationService.showRideStatusNotification(
            context, 
            'Ride Accepted!', 
            'Your ride has been accepted by ${rideRequest.riderName ?? 'a rider'}!'
          );
        } else if (rideRequest.status == 'arrived_at_pickup') {
          NotificationService.showRideStatusNotification(
            context,
            'Rider Arrived!',
            'Your rider has arrived at the pickup point!'
          );
        } else if (rideRequest.status == 'completed') {
          NotificationService.showSuccessNotification(
            context,
            'Ride completed successfully! Thank you for choosing RideHail Pro.'
          );
        }
      } else {
        setState(() {
          _activeRide = null;
        });
      }
    });
  }

  Future<void> _getCurrentLocation() async {
    setState(() {
      _isLoading = true;
    });
    try {
      Position? position = await LocationService.getCurrentLocation();
      if (position != null) {
        LatLng location = LatLng(position.latitude, position.longitude);
        String address = await LocationService.getAddressFromLatLng(location);
        
        setState(() {
          _currentLocation = location;
          _currentAddress = address;
          _locationLoaded = true;
        });
      } else {
        _showSnackBar('📍 Unable to get current location. Please check location permissions.');
      }
    } catch (e) {
      _showSnackBar('❌ Error getting location: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _searchDestination() async {
    if (_destinationController.text.isEmpty) {
      _showSnackBar('📍 Please enter a destination');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      LatLng? destination = await LocationService.getLatLngFromAddress(_destinationController.text);
      if (destination != null) {
        String address = await LocationService.getAddressFromLatLng(destination);
        setState(() {
          _selectedDestination = destination;
          _destinationAddress = address;
        });
        _showSnackBar('✅ Destination found!');
      } else {
        _showSnackBar('❌ Destination not found. Please try a different address.');
      }
    } catch (e) {
      _showSnackBar('❌ Error searching destination: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _requestRide() async {
    if (_currentLocation == null) {
      _showSnackBar('📍 Please wait for location to load');
      return;
    }
    if (_selectedDestination == null) {
      _showSnackBar('📍 Please select a destination first');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      User? currentUser = AuthService().getCurrentUser();
      UserPreferences? userPrefs = await _firestoreService.getUserPreferences(widget.userId);
      
      String? rideId = await _firestoreService.addRideRequest(
        RideRequest(
          passengerId: widget.userId,
          passengerName: currentUser?.email?.split('@').first ?? 'Passenger',
          passengerPhone: userPrefs?.phoneNumber ?? 'Not provided',
          pickupLocation: _currentLocation!,
          destination: _selectedDestination!,
          timestamp: Timestamp.now(),
          status: 'pending',
          pickupAddress: _currentAddress,
          destinationAddress: _destinationAddress,
          otp: _firestoreService.generateOTP(),
        ),
      );

      if (rideId != null) {
        _showSnackBar('🚗 Ride requested successfully! Looking for riders...');
        
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => RideStatusScreen(
              rideRequestId: rideId,
              pickupLocation: _currentLocation!,
              destination: _selectedDestination!,
              passengerId: widget.userId,
              graphHopperApiKey: _graphHopperApiKey,
              pickupAddress: _currentAddress,
              destinationAddress: _destinationAddress,
            ),
          ),
        );
      } else {
        _showSnackBar('❌ Failed to request ride. Please try again.');
      }
    } catch (e) {
      _showSnackBar('❌ Error requesting ride: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _viewActiveRide() {
    if (_activeRide != null) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => RideStatusScreen(
            rideRequestId: _activeRide!.id!,
            pickupLocation: _activeRide!.pickupLocation,
            destination: _activeRide!.destination,
            passengerId: widget.userId,
            graphHopperApiKey: _graphHopperApiKey,
            pickupAddress: _activeRide!.pickupAddress,
            destinationAddress: _activeRide!.destinationAddress,
          ),
        ),
      );
    }
  }

  Widget _buildHomeTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildWelcomeCard(),
          const SizedBox(height: 20),
          
          if (_activeRide != null) ...[
            _buildActiveRideCard(),
            const SizedBox(height: 16),
          ],
          
          _buildLocationCard(),
          const SizedBox(height: 16),
          
          _buildDestinationInput(),
          const SizedBox(height: 20),
          
          _buildActionButtons(),
        ],
      ),
    );
  }

  Widget _buildHistoryTab() {
    return _rideHistory.isEmpty
        ? const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.history, size: 80, color: Colors.grey),
                SizedBox(height: 16),
                Text(
                  'No ride history yet',
                  style: TextStyle(fontSize: 18, color: Colors.grey),
                ),
                SizedBox(height: 8),
                Text(
                  'Your completed rides will appear here',
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
          )
        : ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _rideHistory.length,
            itemBuilder: (context, index) {
              final ride = _rideHistory[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: ride.status == 'completed' ? Colors.green : Colors.red,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      ride.status == 'completed' ? Icons.check : Icons.cancel,
                      color: Colors.white,
                    ),
                  ),
                  title: Text(
                    '${ride.pickupAddress.split(',').first} → ${ride.destinationAddress.split(',').first}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Rider: ${ride.riderName ?? 'N/A'}'),
                      Text('Fare: ₹${ride.fareAmount.toStringAsFixed(2)}'),
                      Text(
                        DateFormat('MMM dd, yyyy - HH:mm').format(ride.timestamp.toDate()),
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                  trailing: Chip(
                    label: Text(
                      ride.status == 'completed' ? 'Completed' : 'Cancelled',
                      style: const TextStyle(fontSize: 12, color: Colors.white),
                    ),
                    backgroundColor: ride.status == 'completed' ? Colors.green : Colors.red,
                  ),
                ),
              );
            },
          );
  }

  Widget _buildProfileTab() {
    return FutureBuilder<UserPreferences?>(
      future: _firestoreService.getUserPreferences(widget.userId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        
        final preferences = snapshot.data;
        final user = AuthService().getCurrentUser();
        
        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      const CircleAvatar(
                        radius: 40,
                        backgroundColor: Colors.black,
                        child: Icon(
                          Icons.person,
                          size: 40,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        user?.email?.split('@').first ?? 'User',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        user?.email ?? 'No email',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildProfileStat('Rides', _rideHistory.length.toString()),
                          _buildProfileStat('Rating', '4.8'),
                          _buildProfileStat('Member', '2024'),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.phone),
                      title: const Text('Phone Number'),
                      subtitle: Text(preferences?.phoneNumber ?? 'Not set'),
                      trailing: const Icon(Icons.edit),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => PreferencesScreen(userId: widget.userId),
                          ),
                        );
                      },
                    ),
                    const Divider(),
                    ListTile(
                      leading: const Icon(Icons.payment),
                      title: const Text('Payment Method'),
                      subtitle: Text(preferences?.preferredPaymentMethod ?? 'Not set'),
                      trailing: const Icon(Icons.arrow_forward_ios),
                    ),
                    const Divider(),
                    ListTile(
                      leading: const Icon(Icons.notifications),
                      title: const Text('Notifications'),
                      subtitle: const Text('Manage your alerts'),
                      trailing: const Icon(Icons.arrow_forward_ios),
                    ),
                    const Divider(),
                    ListTile(
                      leading: const Icon(Icons.help),
                      title: const Text('Help & Support'),
                      trailing: const Icon(Icons.arrow_forward_ios),
                    ),
                    const Divider(),
                    ListTile(
                      leading: const Icon(Icons.logout),
                      title: const Text('Logout'),
                      textColor: Colors.red,
                      iconColor: Colors.red,
                      onTap: () async {
                        await AuthService().signOut();
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildProfileStat(String title, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          title,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  Widget _buildWelcomeCard() {
    User? currentUser = AuthService().getCurrentUser();
    String userName = currentUser?.email?.split('@').first ?? 'Passenger';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Colors.black, Colors.grey],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.waving_hand, color: Colors.white, size: 24),
              SizedBox(width: 10),
              Text(
                'Hello!',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Ready to ride, $userName? Where would you like to go today?',
            style: const TextStyle(
              fontSize: 16,
              color: Colors.white,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveRideCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: Colors.green[50],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: Colors.green,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.directions_car_rounded,
                color: Colors.white,
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Active Ride with ${_activeRide!.riderName ?? 'Rider'}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Status: ${_activeRide!.status.replaceAll('_', ' ').toUpperCase()}',
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.green,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Pickup: ${_activeRide!.pickupAddress.split(',').first}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.green, size: 20),
              onPressed: _viewActiveRide,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.my_location_rounded,
                color: Colors.black,
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Current Location',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _currentAddress,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            IconButton(
              icon: Icon(
                Icons.refresh_rounded,
                color: _isLoading ? Colors.grey : Colors.black,
                size: 24,
              ),
              onPressed: _isLoading ? null : _getCurrentLocation,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDestinationInput() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.place_rounded, color: Colors.black),
                SizedBox(width: 8),
                Text(
                  'Where to?',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _destinationController,
              decoration: InputDecoration(
                hintText: 'Enter destination address...',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.arrow_forward_rounded),
                  onPressed: _searchDestination,
                ),
                filled: true,
                fillColor: Colors.grey[50],
              ),
              onFieldSubmitted: (_) => _searchDestination(),
            ),
            if (_destinationAddress.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green[100]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle_rounded, color: Colors.green[600], size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Destination Set',
                            style: TextStyle(
                              color: Colors.green[800],
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _destinationAddress,
                            style: TextStyle(
                              color: Colors.green[700],
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton(
            onPressed: (_isLoading || _selectedDestination == null) 
                ? null 
                : _requestRide,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _isLoading
                ? const CircularProgressIndicator(color: Colors.white)
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.directions_car_rounded, size: 24),
                      SizedBox(width: 12),
                      Text(
                        'Request Ride',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('RideHail Pro'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        actions: [
          if (_activeRide != null)
            IconButton(
              icon: Badge(
                backgroundColor: Colors.green,
                child: const Icon(Icons.directions_car_rounded),
              ),
              onPressed: _viewActiveRide,
              tooltip: 'View Active Ride',
            ),
          IconButton(
            icon: const Icon(Icons.settings_rounded),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => PreferencesScreen(userId: widget.userId),
                ),
              );
            },
          ),
        ],
      ),
      body: _selectedIndex == 0
          ? _buildHomeTab()
          : _selectedIndex == 1
              ? _buildHistoryTab()
              : _buildProfileTab(),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history),
            label: 'History',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

// --- Enhanced Ride Status Screen ---
class RideStatusScreen extends StatefulWidget {
  final String rideRequestId;
  final LatLng pickupLocation;
  final LatLng destination;
  final String passengerId;
  final String graphHopperApiKey;
  final String pickupAddress;
  final String destinationAddress;

  const RideStatusScreen({
    super.key,
    required this.rideRequestId,
    required this.pickupLocation,
    required this.destination,
    required this.passengerId,
    required this.graphHopperApiKey,
    required this.pickupAddress,
    required this.destinationAddress,
  });

  @override
  State<RideStatusScreen> createState() => _RideStatusScreenState();
}

class _RideStatusScreenState extends State<RideStatusScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirestoreService _firestoreService = FirestoreService();
  RideRequest? _rideRequest;
  List<LatLng> _routePoints = [];
  List<LatLng> _destinationRoutePoints = [];
  bool _isLoading = true;
  StreamSubscription<DocumentSnapshot>? _rideSubscription;
  Timer? _locationUpdateTimer;
  Timer? _routeUpdateTimer;
  bool _showSOSButton = false;
  
  // NEW: Rating system variables
  bool _shouldShowRatingDialog = false;
  int _selectedRating = 0;
  TextEditingController _ratingCommentController = TextEditingController();
  bool _isSubmittingRating = false;

  @override
  void initState() {
    super.initState();
    _listenToRideRequest();
  }

  @override
  void dispose() {
    _rideSubscription?.cancel();
    _locationUpdateTimer?.cancel();
    _routeUpdateTimer?.cancel();
    _ratingCommentController.dispose();
    super.dispose();
  }

  void _listenToRideRequest() {
    _rideSubscription = _firestoreService.getRideRequestStream(widget.rideRequestId).listen((snapshot) async {
      if (snapshot.exists) {
        final request = RideRequest.fromFirestore(snapshot);
        setState(() {
          _rideRequest = request;
          _isLoading = false;
          
          // Show SOS button only after pickup
          _showSOSButton = request.status == 'picked_up' || request.status == 'on_way';
        });

        if (request.status == 'accepted' && request.riderLocation != null && _routePoints.isEmpty) {
          _getRouteToPickup();
        }

        if (request.status == 'picked_up' && _destinationRoutePoints.isEmpty) {
          _getRouteToDestination();
        }

        // Send completion notification and show rating dialog
        if (request.status == 'completed' && !request.passengerRated!) {
          _sendCompletionNotification();
          // Show rating dialog after a short delay
          Future.delayed(const Duration(seconds: 2), () {
            _showRatingDialog();
          });
        }
      }
    });
  }

  void _sendCompletionNotification() {
    if (_rideRequest != null) {
      SOSService.sendRideCompletionAlert(
        passengerName: _rideRequest!.passengerName,
        riderName: _rideRequest!.riderName ?? 'Unknown',
        pickupAddress: widget.pickupAddress,
        destinationAddress: widget.destinationAddress,
        fareAmount: _rideRequest!.fareAmount,
        rating: _rideRequest!.passengerRating,
      );
    }
  }

  // NEW: Show rating dialog for passenger to rate rider
  Future<void> _showRatingDialog() async {
  if (_rideRequest == null || _rideRequest!.riderId == null) return;

  setState(() {
    _shouldShowRatingDialog = true; // Changed from _showRatingDialog
    _selectedRating = 0;
    _ratingCommentController.clear();
  });

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text(
                'Rate Your Rider',
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.deepPurple),
                textAlign: TextAlign.center,
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _rideRequest!.riderName ?? 'Rider',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'How was your experience with this rider?',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16),
                    ),
                    const SizedBox(height: 20),
                    
                    // Star Rating
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(5, (index) {
                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              _selectedRating = index + 1;
                            });
                          },
                          child: Icon(
                            index < _selectedRating ? Icons.star : Icons.star_border,
                            color: Colors.amber,
                            size: 40,
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _selectedRating == 0 ? 'Tap to rate' : '${_selectedRating} ${_selectedRating == 1 ? 'star' : 'stars'}',
                      style: TextStyle(
                        fontSize: 16,
                        color: _selectedRating == 0 ? Colors.grey : Colors.amber[700],
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 20),
                    
                    // Comment Section
                    TextField(
                      controller: _ratingCommentController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        labelText: 'Additional comments (optional)',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        hintText: 'Share your experience with this rider...',
                      ),
                    ),
                    const SizedBox(height: 10),
                    
                    // Rating Labels
                    if (_selectedRating > 0)
                      Text(
                        _getRatingLabel(_selectedRating),
                        style: TextStyle(
                          color: _getRatingColor(_selectedRating),
                          fontWeight: FontWeight.w500,
                          fontSize: 14,
                        ),
                        textAlign: TextAlign.center,
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: _isSubmittingRating ? null : () {
                    Navigator.of(context).pop();
                    _handleRatingSubmission(false);
                  },
                  child: const Text('Skip'),
                ),
                ElevatedButton(
                  onPressed: _isSubmittingRating || _selectedRating == 0 ? null : () {
                    Navigator.of(context).pop();
                    _handleRatingSubmission(true);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    foregroundColor: Colors.white,
                  ),
                  child: _isSubmittingRating 
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)))
                      : const Text('Submit Rating'),
                ),
              ],
            );
          },
        );
      },
    );

    setState(() {
      _shouldShowRatingDialog = false;
    });
  }

  // NEW: Gets rating label based on selected rating
  String _getRatingLabel(int rating) {
    switch (rating) {
      case 1: return 'Poor - Significant issues';
      case 2: return 'Fair - Some concerns';
      case 3: return 'Good - Satisfactory experience';
      case 4: return 'Very Good - Great rider';
      case 5: return 'Excellent - Outstanding experience';
      default: return '';
    }
  }

  // NEW: Gets color based on rating
  Color _getRatingColor(int rating) {
    switch (rating) {
      case 1: return Colors.red;
      case 2: return Colors.orange;
      case 3: return Colors.yellow[700]!;
      case 4: return Colors.lightGreen;
      case 5: return Colors.green;
      default: return Colors.grey;
    }
  }

  // NEW: Handles rating submission
  Future<void> _handleRatingSubmission(bool submitted) async {
    if (!submitted || _rideRequest == null || _rideRequest!.riderId == null) {
      // Rating was skipped or invalid data
      return;
    }

    setState(() {
      _isSubmittingRating = true;
    });

    try {
      await _firestoreService.submitPassengerRating(
        rideRequestId: widget.rideRequestId,
        riderId: _rideRequest!.riderId!,
        passengerId: widget.passengerId,
        passengerName: _rideRequest!.passengerName,
        riderName: _rideRequest!.riderName ?? 'Unknown Rider',
        rating: _selectedRating,
        comment: _ratingCommentController.text.trim(),
        fareAmount: _rideRequest!.fareAmount,
        pickupAddress: widget.pickupAddress,
        destinationAddress: widget.destinationAddress,
      );

      NotificationService.showSuccessNotification(context, '⭐ Thank you for your rating!');

    } catch (e) {
      NotificationService.showErrorNotification(context, '❌ Failed to submit rating: ${e.toString()}');
      print('❌ Error submitting rating: $e');
    } finally {
      setState(() {
        _isSubmittingRating = false;
      });
    }
  }

  Future<void> _getRouteToPickup() async {
    if (_rideRequest == null || _rideRequest!.riderLocation == null) return;
    
    try {
      final routeService = RouteService(widget.graphHopperApiKey);
      final points = await routeService.getRoute(
        _rideRequest!.riderLocation!,
        widget.pickupLocation,
      );
      
      if (points != null) {
        setState(() {
          _routePoints = points;
        });
      }
    } catch (e) {
      print('Error getting route to pickup: $e');
    }
  }

  Future<void> _getRouteToDestination() async {
    if (_rideRequest == null) return;
    
    try {
      final routeService = RouteService(widget.graphHopperApiKey);
      final points = await routeService.getRoute(
        widget.pickupLocation,
        widget.destination,
      );
      
      if (points != null) {
        setState(() {
          _destinationRoutePoints = points;
        });
      }
    } catch (e) {
      print('Error getting route to destination: $e');
    }
  }

  Future<void> _cancelRide() async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.cancel_rounded, color: Colors.red),
            SizedBox(width: 8),
            Text('Cancel Ride'),
          ],
        ),
        content: const Text('Are you sure you want to cancel this ride? A cancellation fee may apply.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await _firestoreService.updateRideRequestStatus(widget.rideRequestId, 'cancelled');
              if (mounted) {
                Navigator.of(context).pop();
              }
            },
            child: const Text('Yes, Cancel'),
          ),
        ],
      ),
    );
  }

  void _showSOSDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red),
            SizedBox(width: 8),
            Text('Emergency SOS'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Select reason for emergency:'),
            const SizedBox(height: 16),
            _buildSOSOption('🚨 Unsafe situation or threat'),
            _buildSOSOption('😰 Feeling uncomfortable or harassed'),
            _buildSOSOption('⚡ Rash or dangerous driving'),
            _buildSOSOption('🧭 Wrong route or suspicious location'),
            _buildSOSOption('🤢 Medical emergency'),
            _buildSOSOption('❓ Other emergency situation'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Widget _buildSOSOption(String reason) {
    return ListTile(
      leading: const Icon(Icons.warning_rounded, color: Colors.red),
      title: Text(reason),
      onTap: () {
        Navigator.of(context).pop();
        _triggerSOS(reason);
      },
    );
  }

  Future<void> _triggerSOS(String reason) async {
    if (_rideRequest == null) return;

    await SOSService.sendSOSAlert(
      rideId: widget.rideRequestId,
      passengerName: _rideRequest!.passengerName,
      passengerPhone: _rideRequest!.passengerPhone,
      riderName: _rideRequest!.riderName ?? 'Unknown',
      riderPhone: _rideRequest!.riderPhone ?? 'Unknown',
      reason: reason,
      currentLocation: _rideRequest!.riderLocation ?? widget.pickupLocation,
      destinationAddress: widget.destinationAddress,
      pickupAddress: widget.pickupAddress,
      vehicleNumber: _rideRequest!.vehicleNumber ?? 'Unknown',
    );

    await _firestoreService.updateRideRequest(widget.rideRequestId, {
      'sosActive': true,
      'sosReason': reason,
      'sosTimestamp': Timestamp.now(),
    });

    NotificationService.showErrorNotification(
      context,
      'Emergency alert sent! Help is on the way. 🚨'
    );
  }

  Future<void> _shareRideDetails() async {
    if (_rideRequest == null) return;

    await SOSService.shareRideDetails(
      passengerName: _rideRequest!.passengerName,
      riderName: _rideRequest!.riderName ?? 'Unknown',
      pickupAddress: widget.pickupAddress,
      destinationAddress: widget.destinationAddress,
      currentLocation: _rideRequest!.riderLocation ?? widget.pickupLocation,
      vehicleNumber: _rideRequest!.vehicleNumber ?? 'Unknown',
      vehicleModel: _rideRequest!.vehicleModel ?? 'Unknown',
      fareAmount: _rideRequest!.fareAmount,
      estimatedDuration: _rideRequest!.estimatedDuration,
    );

    NotificationService.showSuccessNotification(context, 'Ride details shared! 📤');
  }

  String _getStatusMessage(String status) {
    switch (status) {
      case 'pending':
        return '🔍 Searching for available riders...';
      case 'accepted':
        return '🚗 Rider is on the way to pickup location!';
      case 'arrived_at_pickup':
        return '📍 Rider has arrived at pickup point!';
      case 'picked_up':
        return '🎉 You\'re on your way to destination';
      case 'on_way':
        return '🛣️ Ride in progress to destination';
      case 'completed':
        return '✅ Ride completed successfully!';
      case 'cancelled':
        return '❌ Ride has been cancelled';
      default:
        return '❓ Unknown status';
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'pending':
        return Colors.orange;
      case 'accepted':
        return Colors.green;
      case 'arrived_at_pickup':
        return Colors.blue;
      case 'picked_up':
      case 'on_way':
        return Colors.purple;
      case 'completed':
        return Colors.grey;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  Widget _buildRiderInfo() {
    if (_rideRequest?.riderName == null) return Container();
    
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Your Rider',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              CircleAvatar(
                backgroundColor: Colors.black,
                radius: 30,
                child: Text(
                  _rideRequest!.riderName!.substring(0, 1).toUpperCase(),
                  style: const TextStyle(color: Colors.white, fontSize: 18),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _rideRequest!.riderName!,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '📱 ${_rideRequest!.riderPhone ?? 'N/A'}',
                      style: const TextStyle(fontSize: 14),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.star, color: Colors.amber, size: 16),
                        const SizedBox(width: 4),
                        Text(
                          (_rideRequest!.riderRating ?? 5.0).toStringAsFixed(1),
                          style: const TextStyle(fontSize: 14),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '• ${_rideRequest!.totalRides ?? 0} rides',
                          style: const TextStyle(fontSize: 14, color: Colors.grey),
                        ),
                      ],
                    ),
                    if (_rideRequest!.vehicleNumber != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        '🚗 ${_rideRequest!.vehicleNumber!} • ${_rideRequest!.vehicleModel ?? ''}',
                        style: const TextStyle(fontSize: 14, color: Colors.grey),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (_rideRequest!.riderLocation != null && _rideRequest!.status == 'accepted') ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.directions_car_rounded, color: Colors.green),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'En route to pickup',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                        Text(
                          'ETA: ${(_routePoints.isNotEmpty ? (_routePoints.length / 100).round() : 5)} min',
                          style: const TextStyle(
                            color: Colors.green,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildOTPDisplay() {
    if (_rideRequest?.status != 'arrived_at_pickup' || _rideRequest?.otpVerified == true) {
      return Container();
    }

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blue),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.security_rounded, color: Colors.blue),
              SizedBox(width: 8),
              Text(
                'OTP Verification',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text('Share this OTP with your rider to start the ride:'),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: Colors.blue),
            ),
            child: Center(
              child: Text(
                _rideRequest!.otp,
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                  letterSpacing: 8,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'The rider will verify this OTP in their app to start the ride.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildMap() {
    final currentPoints = _rideRequest?.status == 'picked_up' || _rideRequest?.status == 'on_way'
        ? _destinationRoutePoints
        : _routePoints;
    
    LatLng mapCenter = widget.pickupLocation;
    double zoom = 15.0;

    if (_rideRequest?.riderLocation != null) {
      if (_rideRequest?.status == 'accepted' || _rideRequest?.status == 'arrived_at_pickup') {
        mapCenter = _rideRequest!.riderLocation!;
        zoom = 14.0;
      } else if (_rideRequest?.status == 'picked_up' || _rideRequest?.status == 'on_way') {
        mapCenter = widget.pickupLocation;
        zoom = 13.0;
      }
    }

    return SizedBox(
      height: 300,
      child: FlutterMap(
        options: MapOptions(
          initialCenter: mapCenter,
          initialZoom: zoom,
          interactionOptions: const InteractionOptions(
            flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
          ),
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
            subdomains: const ['a', 'b', 'c'],
          ),
          if (currentPoints.isNotEmpty)
            PolylineLayer(
              polylines: [
                Polyline(
                  points: currentPoints,
                  color: _getRouteColor(),
                  strokeWidth: 4.0,
                ),
              ],
            ),
          MarkerLayer(
            markers: _buildMapMarkers(),
          ),
        ],
      ),
    );
  }

  Color _getRouteColor() {
    switch (_rideRequest?.status) {
      case 'accepted':
      case 'arrived_at_pickup':
        return Colors.blue;
      case 'picked_up':
      case 'on_way':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  List<Marker> _buildMapMarkers() {
    final markers = <Marker>[];

    // Pickup point marker
    markers.add(
      Marker(
        width: 40.0,
        height: 40.0,
        point: widget.pickupLocation,
        child: const Icon(
          Icons.location_pin,
          color: Colors.red,
          size: 40,
        ),
      ),
    );

    // Destination marker
    markers.add(
      Marker(
        width: 40.0,
        height: 40.0,
        point: widget.destination,
        child: const Icon(
          Icons.flag_rounded,
          color: Colors.green,
          size: 40,
        ),
      ),
    );

    // Rider marker (if available)
    if (_rideRequest?.riderLocation != null && 
        (_rideRequest?.status == 'accepted' || _rideRequest?.status == 'arrived_at_pickup' || _rideRequest?.status == 'picked_up')) {
      markers.add(
        Marker(
          width: 40.0,
          height: 40.0,
          point: _rideRequest!.riderLocation!,
          child: const Icon(
            Icons.directions_car_rounded,
            color: Colors.blue,
            size: 40,
          ),
        ),
      );
    }

    return markers;
  }

  Widget _buildActionButtons() {
    if (_rideRequest?.status == 'completed' || _rideRequest?.status == 'cancelled') {
      return Container();
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: Colors.grey[300]!),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_rideRequest?.status == 'pending') 
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _cancelRide,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 2,
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.cancel_rounded),
                    SizedBox(width: 12),
                    Text(
                      'Cancel Ride',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),

          if (_rideRequest?.status == 'accepted' || _rideRequest?.status == 'arrived_at_pickup') 
            Row(
              children: [
                if (_showSOSButton) ...[
                  Expanded(
                    child: SizedBox(
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _showSOSDialog,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 2,
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.warning_rounded),
                            SizedBox(width: 8),
                            Text(
                              'SOS',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: SizedBox(
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _shareRideDetails,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 2,
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.share_rounded),
                          SizedBox(width: 8),
                          Text(
                            'Share Ride',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),

          if (_rideRequest?.status == 'picked_up' || _rideRequest?.status == 'on_way') 
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _showSOSDialog,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 2,
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.warning_rounded),
                          SizedBox(width: 8),
                          Text(
                            'SOS Emergency',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _shareRideDetails,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 2,
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.share_rounded),
                          SizedBox(width: 8),
                          Text(
                            'Share Ride',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildRideDetails() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        border: Border(
          top: BorderSide(color: Colors.grey[300]!),
        ),
      ),
      child: Column(
        children: [
          _buildCompactInfoRow(Icons.location_on, 'Pickup', widget.pickupAddress),
          const SizedBox(height: 12),
          _buildCompactInfoRow(Icons.flag, 'Destination', widget.destinationAddress),
          if (_rideRequest!.fareAmount > 0) ...[
            const SizedBox(height: 12),
            _buildCompactInfoRow(Icons.currency_rupee, 'Fare', '₹${_rideRequest!.fareAmount.toStringAsFixed(2)}'),
          ],
          if (_rideRequest!.estimatedDistance != 'N/A') ...[
            const SizedBox(height: 12),
            _buildCompactInfoRow(Icons.space_dashboard, 'Distance', _rideRequest!.estimatedDistance),
          ],
          if (_rideRequest!.estimatedDuration != 'N/A') ...[
            const SizedBox(height: 12),
            _buildCompactInfoRow(Icons.access_time, 'Estimated Time', _rideRequest!.estimatedDuration),
          ],
        ],
      ),
    );
  }

  Widget _buildCompactInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.grey),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: const TextStyle(
            fontSize: 14,
            color: Colors.grey,
            fontWeight: FontWeight.w500,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ride Status'),
        centerTitle: true,
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          if (_rideRequest?.status == 'pending')
            IconButton(
              icon: const Icon(Icons.cancel_rounded, color: Colors.red),
              onPressed: _cancelRide,
              tooltip: 'Cancel Ride',
            ),
        ],
      ),
      body: _isLoading || _rideRequest == null
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text(
                    'Loading ride details...',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                // Status Header - Fixed height
                Container(
                  height: 80,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: _getStatusColor(_rideRequest!.status).withOpacity(0.1),
                    border: Border(
                      bottom: BorderSide(
                        color: _getStatusColor(_rideRequest!.status).withOpacity(0.2),
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: _getStatusColor(_rideRequest!.status),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _getStatusMessage(_rideRequest!.status),
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: _getStatusColor(_rideRequest!.status),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Map - Fixed height for mobile
                SizedBox(
                  height: 250,
                  child: _buildMap(),
                ),
                
                // Scrollable content area
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        // Rider Info
                        if (_rideRequest!.riderName != null) _buildRiderInfo(),
                        
                        // OTP Display
                        _buildOTPDisplay(),
                        
                        // Add some space before buttons
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ),
                
                // Action Buttons - Always visible at bottom
                _buildActionButtons(),
                
                // Ride Details - Compact design
                Container(
                  constraints: const BoxConstraints(minHeight: 120),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    border: Border(
                      top: BorderSide(color: Colors.grey[300]!),
                    ),
                  ),
                  child: _buildRideDetails(),
                ),
              ],
            ),
    );
  }
}