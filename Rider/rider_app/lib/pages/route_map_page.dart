// rider_app/lib/pages/route_map_page.dart

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'face_verification.dart';

class RouteMapPage extends StatefulWidget {
  final LatLng startLocation;
  final LatLng endLocation;
  final String? riderName;

  const RouteMapPage({
    super.key,
    required this.startLocation,
    required this.endLocation,
    this.riderName,
  });

  @override
  State<RouteMapPage> createState() => _RouteMapPageState();
}

class _RouteMapPageState extends State<RouteMapPage> {
  final MapController _mapController = MapController();
  final ScrollController _instructionsScrollController = ScrollController();
  List<LatLng> _routePoints = [];
  List<Map<String, dynamic>> _osrmSteps = [];
  String _eta = 'Calculating...';
  String _distance = 'Calculating...';
  bool _isLoadingRoute = true;
  bool _rideConfirmed = false;
  bool _showDetailsPanel = false;

  LatLng? _vehicleLocation;
  LatLng? _pickupLocation;
  LatLng? _passengerDestination;

  int _currentRoutePointIndex = 0;
  int _currentInstructionIndex = 0;
  Timer? _progressTimer;
  StreamSubscription<QuerySnapshot>? _requestSubscription;
  StreamSubscription<DocumentSnapshot>? _acceptedRideSubscription;
  String _currentInstruction = 'Loading route...';

  double _totalRouteDurationSeconds = 0.0;
  double _totalRouteDistanceMeters = 0.0;

  List<Map<String, dynamic>> _pendingPassengerRequests = [];
  Map<String, dynamic>? _acceptedPassengerRequest;

  bool _hasArrivedAtPickupPoint = false;
  bool _hasArrivedAtDestination = false;
  bool _isVerifyingPassenger = false;
  bool _showCallButton = false;
  bool _isNearPickupPoint = false;
  bool _isNearDestination = false;
  bool _passengerPickedUp = false;

  // Rating system variables
  bool _isRatingDialogVisible = false;
  int _selectedRating = 0;
  TextEditingController _ratingCommentController = TextEditingController();
  bool _isSubmittingRating = false;

  // Real-time tracking
  StreamSubscription<Position>? _positionStream;
  Position? _currentPosition;

  // NEW: Ride completion state
  bool _showRideCompletionScreen = false;
  bool _isContinuingToDestination = false;

  static const double _ON_ROUTE_THRESHOLD_METERS = 300.0;
  static const double _PICKUP_REACHED_THRESHOLD_METERS = 50.0;
  static const double _PICKUP_APPROACHING_THRESHOLD_METERS = 200.0;
  static const double _DESTINATION_REACHED_THRESHOLD_METERS = 50.0;

  // Request handling
  bool _isListeningForRequests = false;
  Timer? _requestCheckTimer;
  int _requestCheckCount = 0;
  final int _maxRequestChecks = 10;

  @override
  void initState() {
    super.initState();
    _initializeFirebaseAndAuth();
    _fetchRoute(widget.startLocation, widget.endLocation, updateMapFit: true);
    _startRealTimeLocationTracking();
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _requestSubscription?.cancel();
    _acceptedRideSubscription?.cancel();
    _positionStream?.cancel();
    _requestCheckTimer?.cancel();
    _instructionsScrollController.dispose();
    _ratingCommentController.dispose();
    super.dispose();
  }

  /// Initializes Firebase and signs in anonymously if no user is authenticated.
  Future<void> _initializeFirebaseAndAuth() async {
    try {
      if (FirebaseAuth.instance.currentUser == null) {
        await FirebaseAuth.instance.signInAnonymously();
        print('🚗 Signed in anonymously: ${FirebaseAuth.instance.currentUser?.uid}');
        if (mounted) {
          _showMessage('Successfully signed in! Ready to go online.', Colors.green);
        }
        await _createRiderProfile();
      } else {
        await _createRiderProfile();
      }
    } catch (e) {
      if (mounted) {
        _showMessage('Failed to sign in to Firebase: ${e.toString()}', Colors.red);
      }
      print('Firebase Auth Error: $e');
    }
  }

  /// Creates or updates rider profile in Firestore
  Future<void> _createRiderProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      await FirebaseFirestore.instance.collection('riders').doc(user.uid).set({
        'status': 'offline',
        'currentLocation': GeoPoint(widget.startLocation.latitude, widget.startLocation.longitude),
        'riderName': widget.riderName ?? 'Anonymous Rider',
        'lastActive': FieldValue.serverTimestamp(),
        'vehicleType': 'gear less bike',
        'createdAt': FieldValue.serverTimestamp(),
        'isOnline': false,
        'currentRouteStart': GeoPoint(widget.startLocation.latitude, widget.startLocation.longitude),
        'currentRouteEnd': GeoPoint(widget.endLocation.latitude, widget.endLocation.longitude),
        // Add rating fields to rider profile
        'totalRides': 0,
        'averageRating': 0.0,
        'totalRatings': 0,
        'ratingSum': 0,
      }, SetOptions(merge: true));

      print('✅ Rider profile created/updated successfully');
    } catch (e) {
      print('❌ Error creating rider profile: $e');
    }
  }

  /// Starts real-time location tracking
  void _startRealTimeLocationTracking() {
    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).listen((Position position) {
      _currentPosition = position;
      if (mounted) {
        setState(() {
          _vehicleLocation = LatLng(position.latitude, position.longitude);
        });
      }

      // Always check proximity when we have an accepted ride
      if (_acceptedPassengerRequest != null) {
        _updateRiderLocation(position);
        _checkProximityToPoints(position);
      } else if (_rideConfirmed) {
        _updateRiderLocation(position);
      }
    });
  }

  /// Updates rider location in Firestore
  Future<void> _updateRiderLocation(Position position) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      await FirebaseFirestore.instance.collection('riders').doc(user.uid).update({
        'currentLocation': GeoPoint(position.latitude, position.longitude),
        'lastActive': FieldValue.serverTimestamp(),
      });

      // Update accepted ride with rider location
      if (_acceptedPassengerRequest != null && _acceptedPassengerRequest!['request_id'] != null) {
        await FirebaseFirestore.instance.collection('driver_proposals').doc(_acceptedPassengerRequest!['request_id']).update({
          'riderLocation': GeoPoint(position.latitude, position.longitude),
          'lastLocationUpdate': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      print('❌ Error updating rider location: $e');
    }
  }

  /// FIXED: Checks proximity to pickup point and destination
  void _checkProximityToPoints(Position position) {
    if (_pickupLocation != null && !_hasArrivedAtPickupPoint && !_passengerPickedUp) {
      final double distanceToPickup = Geolocator.distanceBetween(
        position.latitude, position.longitude,
        _pickupLocation!.latitude, _pickupLocation!.longitude,
      );

      print('📍 Distance to pickup: ${distanceToPickup.toStringAsFixed(2)} meters');

      if (mounted) {
        setState(() {
          _isNearPickupPoint = distanceToPickup <= _PICKUP_APPROACHING_THRESHOLD_METERS;

          if (distanceToPickup <= _PICKUP_REACHED_THRESHOLD_METERS && !_hasArrivedAtPickupPoint) {
            _hasArrivedAtPickupPoint = true;
            _showCallButton = true;
            _currentInstruction = 'You have reached the pickup point!';
            _showMessage('🎉 You have reached the pickup point! Please confirm arrival.', Colors.green);
            _notifyPassengerOfArrival();
          }
        });
      }
    }

    if (_passengerDestination != null && _passengerPickedUp && !_hasArrivedAtDestination) {
      final double distanceToDestination = Geolocator.distanceBetween(
        position.latitude, position.longitude,
        _passengerDestination!.latitude, _passengerDestination!.longitude,
      );

      print('🏁 Distance to destination: ${distanceToDestination.toStringAsFixed(2)} meters');

      if (mounted) {
        setState(() {
          _isNearDestination = distanceToDestination <= _PICKUP_APPROACHING_THRESHOLD_METERS;

          if (distanceToDestination <= _DESTINATION_REACHED_THRESHOLD_METERS && !_hasArrivedAtDestination) {
            _hasArrivedAtDestination = true;
            _currentInstruction = 'You have reached the destination!';

            // NEW: Show full-screen completion message
            _showRideCompletionMessage();
          }
        });
      }
    }
  }

  /// NEW: Shows full-screen ride completion message
  void _showRideCompletionMessage() {
    if (mounted) {
      setState(() {
        _showRideCompletionScreen = true;
      });
    }
    _showMessage('🎉 You have reached the passenger\'s destination!', Colors.green);
  }

  /// NEW: Handles continuing to rider's destination
  Future<void> _continueToRiderDestination() async {
    if (mounted) {
      setState(() {
        _isContinuingToDestination = true;
        _showRideCompletionScreen = false;
      });
    }

    try {
      // Complete the current ride in Firestore
      await _completeRide();

      // Fetch route from current location to rider's original destination
      if (_vehicleLocation != null) {
        await _fetchRoute(_vehicleLocation!, widget.endLocation, updateMapFit: true);
        if (mounted) {
          setState(() {
            _currentInstruction = '🚗 Continuing to your destination...';
          });
        }
        _startRouteSimulation();
      }
    } catch (e) {
      _showMessage('❌ Error continuing to destination: ${e.toString()}', Colors.red);
      print('❌ Error continuing to destination: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isContinuingToDestination = false;
        });
      }
    }
  }

  /// Fetches route from OSRM and updates state.
  Future<void> _fetchRoute(LatLng start, LatLng end, {bool updateMapFit = false}) async {
    _progressTimer?.cancel();
    if (mounted) {
      setState(() {
        _isLoadingRoute = true;
        _routePoints = [];
        _osrmSteps = [];
        _eta = 'Calculating...';
        _distance = 'Calculating...';
        _currentInstruction = 'Fetching route...';
        _vehicleLocation = start;
        _currentRoutePointIndex = 0;
        _currentInstructionIndex = 0;
        _totalRouteDurationSeconds = 0.0;
        _totalRouteDistanceMeters = 0.0;
      });
    }

    final url =
        'http://router.project-osrm.org/route/v1/driving/'
        '${start.longitude},${start.latitude};'
        '${end.longitude},${end.latitude}'
        '?overview=full&geometries=geojson&steps=true';

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['routes'] != null && data['routes'].isNotEmpty) {
          final route = data['routes'][0];
          final geometry = route['geometry']['coordinates'];
          _osrmSteps = (route['legs'] as List<dynamic>)
              .expand<dynamic>((leg) => leg['steps'] as List<dynamic>)
              .map((step) => step as Map<String, dynamic>)
              .toList();

          List<LatLng> points = geometry.map<LatLng>((c) => LatLng(c[1], c[0])).toList();

          if (mounted) {
            setState(() {
              _routePoints = points;
              _totalRouteDurationSeconds = route['duration']?.toDouble() ?? 0.0;
              _totalRouteDistanceMeters = route['distance']?.toDouble() ?? 0.0;

              _eta = "${(_totalRouteDurationSeconds / 60).ceil()} mins";
              _distance = "${(_totalRouteDistanceMeters / 1000).toStringAsFixed(2)} km";

              _isLoadingRoute = false;

              if (_routePoints.isNotEmpty) {
                _vehicleLocation = _routePoints.first;
                _currentInstruction = _osrmSteps.isNotEmpty
                    ? (_osrmSteps[0]['maneuver']?['instruction'] ?? 'Start journey')
                    : 'Start journey';
              } else {
                _showMessage('No valid route points received from OSRM.', Colors.orange);
              }

              if (updateMapFit && _routePoints.isNotEmpty) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _mapController.fitCamera(
                    CameraFit.bounds(
                      bounds: LatLngBounds.fromPoints(points),
                      padding: const EdgeInsets.all(50.0),
                    ),
                  );
                });
              }
            });
          }
        } else {
          if (mounted) {
            _showMessage('No route found for these locations. Please adjust coordinates.', Colors.orange);
            setState(() {
              _currentInstruction = 'No route found.';
              _isLoadingRoute = false;
              _routePoints = [];
              _osrmSteps = [];
            });
          }
        }
      } else {
        if (mounted) {
          _showMessage('Failed to fetch route: HTTP ${response.statusCode}. Please check network/OSRM server.', Colors.red);
          setState(() {
            _currentInstruction = '❌ Failed to get route: ${response.statusCode}';
            _isLoadingRoute = false;
            _routePoints = [];
            _osrmSteps = [];
          });
        }
      }
    } catch (e) {
      if (mounted) {
        _showMessage('Network error fetching route: ${e.toString()}. Is OSRM server running?', Colors.red);
        setState(() {
          _currentInstruction = '❌ Network error: ${e.toString()}';
          _isLoadingRoute = false;
          _routePoints = [];
          _osrmSteps = [];
        });
      }
    }
  }

  /// Starts route simulation using real GPS data
  void _startRouteSimulation() {
    _progressTimer?.cancel();

    if (_routePoints.isEmpty || _vehicleLocation == null) {
      print("Cannot start simulation, route points are empty or vehicle location is null.");
      return;
    }

    const Duration simulationInterval = Duration(seconds: 5);

    _progressTimer = Timer.periodic(simulationInterval, (timer) {
      if (!mounted || !_rideConfirmed) {
        timer.cancel();
        return;
      }

      // Update instructions based on real position
      if (_currentPosition != null) {
        _updateInstructionsBasedOnRealPosition(LatLng(_currentPosition!.latitude, _currentPosition!.longitude));
      }
    });
  }

  /// Updates instructions based on real GPS position
  void _updateInstructionsBasedOnRealPosition(LatLng position) {
    if (_routePoints.isEmpty) return;

    // Find the closest point on the route
    double minDistance = double.infinity;
    int closestPointIndex = _currentRoutePointIndex;

    for (int i = max(0, _currentRoutePointIndex - 5); i < min(_routePoints.length, _currentRoutePointIndex + 10); i++) {
      double distance = Geolocator.distanceBetween(
        position.latitude, position.longitude,
        _routePoints[i].latitude, _routePoints[i].longitude,
      );

      if (distance < minDistance) {
        minDistance = distance;
        closestPointIndex = i;
      }
    }

    if (mounted) {
      setState(() {
        _currentRoutePointIndex = closestPointIndex;
        _updateCurrentInstruction();

        if (_vehicleLocation != null) {
          _mapController.move(_vehicleLocation!, _mapController.camera.zoom);
        }
      });
    }
  }

  /// Updates current instruction based on route progress
  void _updateCurrentInstruction() {
    int newInstructionIndex = _currentInstructionIndex;

    for (int i = _currentInstructionIndex; i < _osrmSteps.length; i++) {
      final step = _osrmSteps[i];
      final stepIntersections = step['intersections'];
      if (stepIntersections != null && stepIntersections.isNotEmpty) {
        int instructionStartPointIndex = stepIntersections[0]['location_idx'] ?? 0;

        if (_currentRoutePointIndex + 1 >= instructionStartPointIndex) {
          newInstructionIndex = i;
        } else {
          break;
        }
      }
    }

    if (newInstructionIndex != _currentInstructionIndex) {
      setState(() {
        _currentInstructionIndex = newInstructionIndex;
        _currentInstruction = _osrmSteps[_currentInstructionIndex]['maneuver']?['instruction'] ?? 'Continue';
        _scrollInstructionsListToCurrent(_currentInstructionIndex);
      });
    }
  }

  /// Projects a point onto a line segment.
  LatLng _projectPointToLineSegment(LatLng p, LatLng a, LatLng b) {
    final double ax = a.longitude;
    final double ay = a.latitude;
    final double bx = b.longitude;
    final double by = b.latitude;
    final double px = p.longitude;
    final double py = p.latitude;

    final double dx = bx - ax;
    final double dy = by - ay;

    if (dx == 0 && dy == 0) {
      return a;
    }

    final double t = ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy);

    if (t < 0) {
      return a;
    } else if (t > 1) {
      return b;
    } else {
      return LatLng(ay + t * dy, ax + t * dx);
    }
  }

  /// Determines the optimal pickup point for a passenger on the *rider's current route*.
  Future<Map<String, dynamic>> _calculateOptimalPickupPoint(LatLng passengerLocation) async {
    LatLng optimalPickupPoint = passengerLocation;
    bool isOnRoute = false;
    double minDistance = double.infinity;

    for (int i = 0; i < _routePoints.length - 1; i++) {
      LatLng segmentStart = _routePoints[i];
      LatLng segmentEnd = _routePoints[i + 1];

      LatLng projectedPoint = _projectPointToLineSegment(passengerLocation, segmentStart, segmentEnd);

      double geodesicDistanceToProjected = Geolocator.distanceBetween(
        passengerLocation.latitude, passengerLocation.longitude,
        projectedPoint.latitude, projectedPoint.longitude,
      );

      if (geodesicDistanceToProjected < minDistance) {
        minDistance = geodesicDistanceToProjected;
        if (minDistance <= _ON_ROUTE_THRESHOLD_METERS) {
          optimalPickupPoint = projectedPoint;
          isOnRoute = true;
        }
      }
    }

    if (!isOnRoute) {
      optimalPickupPoint = passengerLocation;
    }

    return {'pickupPoint': optimalPickupPoint, 'isOnRoute': isOnRoute};
  }

  void _scrollInstructionsListToCurrent(int index) {
    if (_instructionsScrollController.hasClients && index < _osrmSteps.length) {
      double offset = index * 50.0;
      double centerOffset = offset - (_instructionsScrollController.position.viewportDimension / 2) + 25.0;
      if (centerOffset < 0) centerOffset = 0;
      if (centerOffset > _instructionsScrollController.position.maxScrollExtent) {
        centerOffset = _instructionsScrollController.position.maxScrollExtent;
      }

      _instructionsScrollController.animateTo(
        centerOffset,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeIn,
      );
    }
  }

  /// IMPROVED: Sets up a real-time Firestore listener for pending ride requests
  void _startRequestPolling() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showMessage('Rider not authenticated. Cannot listen for requests.', Colors.red);
      return;
    }

    print('🔍 Starting request polling for rider: ${user.uid}');
    print('📊 Current rider UID: ${user.uid}');

    // Cancel any existing subscriptions
    _requestSubscription?.cancel();
    _requestCheckTimer?.cancel();

    // Set up real-time listener for driver_proposals where riderUid matches current user
    _requestSubscription = FirebaseFirestore.instance
        .collection('driver_proposals')
        .where('riderUid', isEqualTo: user.uid)
        .where('status', isEqualTo: 'pending_acceptance')
        .snapshots()
        .listen((QuerySnapshot querySnapshot) {
      print('📨 Real-time update: Received ${querySnapshot.docs.length} driver proposals');

      _processIncomingRequests(querySnapshot);
    }, onError: (error) {
      print('❌ Error in real-time listener: $error');
      _showMessage('Error listening to requests: ${error.toString()}', Colors.red);
    });

    // Also set up a periodic check as backup
    _requestCheckTimer = Timer.periodic(Duration(seconds: 5), (timer) {
      if (!_isListeningForRequests || _acceptedPassengerRequest != null) {
        timer.cancel();
        return;
      }
      _manualCheckForRequests();
    });

    setState(() {
      _isListeningForRequests = true;
    });
  }

  /// Manual check for requests as backup
  Future<void> _manualCheckForRequests() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final querySnapshot = await FirebaseFirestore.instance
          .collection('driver_proposals')
          .where('riderUid', isEqualTo: user.uid)
          .where('status', isEqualTo: 'pending_acceptance')
          .get();

      print('🔍 Manual check: Found ${querySnapshot.docs.length} pending requests');
      _processIncomingRequests(querySnapshot);
    } catch (e) {
      print('❌ Error in manual check: $e');
    }
  }

  /// FIXED: Process incoming requests from Firestore - Use passenger fields
  void _processIncomingRequests(QuerySnapshot querySnapshot) {
    if (!mounted) return;

    setState(() {
      _pendingPassengerRequests.clear();

      if (querySnapshot.docs.isNotEmpty) {
        for (final requestDoc in querySnapshot.docs) {
          final requestData = requestDoc.data() as Map<String, dynamic>;
          final requestId = requestDoc.id;

          print('🔄 Processing proposal: $requestId');
          print('📋 Request data: ${requestData.toString()}');

          // Extract passenger data from Firestore document - FIXED: Use passenger fields
          final pickupGeoPoint = requestData['pickupLocation'] as GeoPoint;
          final destinationGeoPoint = requestData['destinationLocation'] as GeoPoint;

          final passengerPickup = LatLng(pickupGeoPoint.latitude, pickupGeoPoint.longitude);
          final passengerDestination = LatLng(destinationGeoPoint.latitude, destinationGeoPoint.longitude);

          // Build enhanced request details object - FIXED: Use passengerName and passengerPhone
          Map<String, dynamic> requestDetails = {
            'passenger_name': requestData['passengerName'] ?? 'Passenger', // FIXED: passengerName not riderName
            'passenger_phone': requestData['passengerPhone'] ?? 'N/A',     // FIXED: passengerPhone not riderPhone
            'pickup_location': passengerPickup,
            'destination_location': passengerDestination,
            'pickup_address': requestData['pickupAddress'] ?? 'Pickup Location',
            'destination_address': requestData['destinationAddress'] ?? 'Destination Location',
            'request_id': requestId,
            'otp': requestData['otp'] ?? '0000', // Add OTP for verification
            'fare_amount': requestData['fareAmount'] ?? 0.0,
            'estimated_distance': requestData['estimatedDistance'] ?? '0 km',
            'estimated_duration': requestData['estimatedDuration'] ?? '0 min',
          };

          // Check if this request is already in the list
          bool isDuplicate = _pendingPassengerRequests.any((req) => req['request_id'] == requestId);
          if (!isDuplicate) {
            _pendingPassengerRequests.add(requestDetails);
            print('✅ Added request to pending list: $requestId');
            print('👤 Passenger details: ${requestDetails['passenger_name']} - ${requestDetails['passenger_phone']}');
          }
        }

        if (_pendingPassengerRequests.isNotEmpty) {
          _showMessage('🎉 New ride request received!', Colors.lightGreen);
        }
      } else {
        print('📭 No pending requests found');
        _pendingPassengerRequests.clear();
      }
    });
  }

  /// FIXED: Listens for accepted ride status updates and handles automatic verification
  void _listenForAcceptedRide(String proposalId) {
    _acceptedRideSubscription?.cancel();

    _acceptedRideSubscription = FirebaseFirestore.instance
        .collection('driver_proposals')
        .doc(proposalId)
        .snapshots()
        .listen((documentSnapshot) async {
      if (documentSnapshot.exists) {
        final data = documentSnapshot.data();
        final status = data?['status'];

        print('🔄 Ride status update: $status');

        switch (status) {
          case 'accepted':
            _showMessage('✅ Ride accepted successfully!', Colors.green);
            break;
          case 'arrived_at_pickup':
            _showMessage('📍 You have arrived at pickup point! Starting verification...', Colors.blue);
            // Automatically start verification when status is arrived_at_pickup
            if (!_isVerifyingPassenger && !_passengerPickedUp) {
              await _startVerificationProcess();
            }
            break;
          case 'picked_up':
            _showMessage('👥 Passenger picked up! Heading to destination.', Colors.green);
            if (mounted) {
              setState(() {
                _passengerPickedUp = true;
                _isVerifyingPassenger = false;
              });
            }
            // Start navigation to destination
            if (_pickupLocation != null && _passengerDestination != null) {
              await _fetchRoute(_pickupLocation!, _passengerDestination!, updateMapFit: true);
              if (mounted) {
                setState(() {
                  _currentInstruction = '🚗 Heading to passenger destination...';
                });
              }
              _startRouteSimulation();
            }
            break;
          case 'completed':
            _showMessage('🎉 Ride completed successfully!', Colors.green);
            _resetToInitialState();
            break;
          case 'cancelled':
            _showMessage('❌ Ride was cancelled.', Colors.orange);
            _resetToInitialState();
            break;
        }
      }
    }, onError: (error) {
      print('❌ Error listening to accepted ride: $error');
    });
  }

  /// IMPROVED: Handles rider's response to a passenger request (accept/reject)
  Future<void> _handleRequestResponse(String requestId, String action) async {
    final user = FirebaseAuth.instance.currentUser;

    print('🔄 Handling request response: $action for request: $requestId');

    if (action == 'rejected') {
      _showMessage('❌ Ride rejected.', Colors.red);
      try {
        // Update Firestore document status to 'rejected'
        await FirebaseFirestore.instance.collection('driver_proposals').doc(requestId).update({
          'status': 'rejected',
          'rejectedTimestamp': FieldValue.serverTimestamp(),
          'rejectedBy': user?.uid,
        });
        print('✅ Request rejected in Firestore: $requestId');
      } catch (e) {
        print('❌ Error rejecting request in Firestore: ${e.toString()}');
        _showMessage('Failed to update request status in Firestore.', Colors.red);
      }
      if (mounted) {
        setState(() {
          _pendingPassengerRequests.removeWhere((req) => req['request_id'] == requestId);
        });
      }
      return;
    }

    _showMessage('🔄 Request accepted! Processing...', Colors.blue);

    try {
      // Find the accepted request
      final acceptedRequest = _pendingPassengerRequests.firstWhere((req) => req['request_id'] == requestId);

      if (mounted) {
        setState(() {
          _acceptedPassengerRequest = acceptedRequest;
          _pickupLocation = acceptedRequest['pickup_location'] as LatLng;
          _passengerDestination = acceptedRequest['destination_location'] as LatLng;
          _pendingPassengerRequests.clear();
          _requestSubscription?.cancel(); // Stop listening for new requests
          _requestCheckTimer?.cancel();
          _isListeningForRequests = false;
        });
      }

      // Update Firestore document status to 'accepted'
      await FirebaseFirestore.instance.collection('driver_proposals').doc(requestId).update({
        'status': 'accepted',
        'acceptedTimestamp': FieldValue.serverTimestamp(),
        'driverId': user?.uid,
        'driverName': widget.riderName ?? 'Anonymous Rider',
        'riderLocation': _vehicleLocation != null
            ? GeoPoint(_vehicleLocation!.latitude, _vehicleLocation!.longitude)
            : GeoPoint(widget.startLocation.latitude, widget.startLocation.longitude),
      });

      print('✅ Request accepted in Firestore: $requestId');

      // Start listening for ride status updates
      _listenForAcceptedRide(requestId);

      // Calculate optimal pickup point and start navigation
      final passengerLocation = _pickupLocation!;
      final pickupInfo = await _calculateOptimalPickupPoint(passengerLocation);
      LatLng optimalPickupPoint = pickupInfo['pickupPoint'] as LatLng;
      final bool isOnRoute = pickupInfo['isOnRoute'] as bool;

      _showMessage(isOnRoute
          ? '🎯 Passenger is on your route. Optimized pickup selected!'
          : '📍 Passenger is off-route. Routing to their exact location.',
          Colors.blue);

      await _updateRiderStatus('on_trip');

      // Fetch route to pickup point
      await _fetchRoute(_vehicleLocation ?? widget.startLocation, optimalPickupPoint, updateMapFit: true);
      if (mounted) {
        setState(() {
          _pickupLocation = optimalPickupPoint;
          _currentInstruction = '🚗 Heading to passenger pickup...';
        });
      }
      _startRouteSimulation();

    } catch (e) {
      _showMessage('❌ Error responding to request: ${e.toString()}', Colors.red);
      print('❌ Error handling request response: $e');
    }
  }

  /// Updates rider status in Firestore
  Future<void> _updateRiderStatus(String status) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      await FirebaseFirestore.instance.collection('riders').doc(user.uid).update({
        'status': status,
        'isOnline': status == 'available',
        'lastActive': FieldValue.serverTimestamp(),
      });
      print('✅ Rider status updated to: $status');
    } catch (e) {
      print('❌ Error updating rider status: $e');
    }
  }

  /// Notifies passenger of arrival at pickup point
  Future<void> _notifyPassengerOfArrival() async {
    if (_acceptedPassengerRequest == null || _acceptedPassengerRequest!['request_id'] == null) {
      return;
    }

    try {
      await FirebaseFirestore.instance.collection('driver_proposals').doc(_acceptedPassengerRequest!['request_id']).update({
        'status': 'arrived_at_pickup',
        'arrivalTimestamp': FieldValue.serverTimestamp(),
      });

      print('✅ Passenger notified of arrival at pickup point');
    } catch (e) {
      print('❌ Error notifying passenger of arrival: $e');
    }
  }

  /// NEW: Starts the verification process automatically when arrived_at_pickup status is detected
  Future<void> _startVerificationProcess() async {
    if (_acceptedPassengerRequest == null) {
      return;
    }

    if (mounted) {
      setState(() {
        _isVerifyingPassenger = true;
      });
    }

    try {
      // Show verification dialog
      await _showVerificationDialog();
    } catch (e) {
      _showMessage('❌ Failed to verify passenger: ${e.toString()}', Colors.red);
      print('❌ Error in verification: $e');
      if (mounted) {
        setState(() {
          _isVerifyingPassenger = false;
        });
      }
    }
  }

  /// Handles the "Reached Pickup Point" button press.
  Future<void> _onReachedPickupPoint() async {
    if (_acceptedPassengerRequest == null) {
      _showMessage('No active passenger request to confirm arrival for.', Colors.red);
      return;
    }

    if (mounted) {
      setState(() {
        _isVerifyingPassenger = true;
      });
    }

    try {
      // Update status to arrived at pickup
      await FirebaseFirestore.instance.collection('driver_proposals').doc(_acceptedPassengerRequest!['request_id']).update({
        'status': 'arrived_at_pickupa',
        'arrivalTimestamp': FieldValue.serverTimestamp(),
      });

      // Show verification dialog
      await _showVerificationDialog();

    } catch (e) {
      _showMessage('❌ Failed to verify passenger: ${e.toString()}', Colors.red);
      print('❌ Error in verification: $e');
      if (mounted) {
        setState(() {
          _isVerifyingPassenger = false;
        });
      }
    }
  }

  /// Shows verification dialog with face verification and OTP
  Future<void> _showVerificationDialog() async {
    bool faceVerified = false;
    bool otpVerified = false;

    // Step 1: Face Verification
    faceVerified = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => FaceVerificationPage()),
    );

    if (!faceVerified) {
      _showMessage('Face verification failed! Ride cannot proceed.', Colors.red);
      if (mounted) {
        setState(() {
          _isVerifyingPassenger = false;
        });
      }
      return;
    }

    // Step 2: OTP Verification - Use actual OTP from Firestore
    otpVerified = await _showOtpVerificationDialog();

    if (otpVerified) {
      // Update status to picked up
      await FirebaseFirestore.instance.collection('driver_proposals').doc(_acceptedPassengerRequest!['request_id']).update({
        'status': 'picked_up',
        'pickupTimestamp': FieldValue.serverTimestamp(),
        'otpVerified': true,
      });

      if (mounted) {
        setState(() {
          _passengerPickedUp = true;
          _isVerifyingPassenger = false;
          _showCallButton = false;
        });
      }

      _showMessage('✅ Passenger verified and picked up! Heading to destination.', Colors.green);

      // Fetch route to destination
      if (_pickupLocation != null && _passengerDestination != null) {
        await _fetchRoute(_pickupLocation!, _passengerDestination!, updateMapFit: true);
        if (mounted) {
          setState(() {
            _currentInstruction = '🚗 Heading to passenger destination...';
          });
        }
        _startRouteSimulation();
      }
    } else {
      _showMessage('OTP verification failed!', Colors.red);
      if (mounted) {
        setState(() {
          _isVerifyingPassenger = false;
        });
      }
    }
  }

  /// IMPROVED: Shows OTP verification dialog using actual OTP from Firestore
  Future<bool> _showOtpVerificationDialog() async {
    TextEditingController otpController = TextEditingController();
    // Get actual OTP from the accepted passenger request
    String actualOtp = _acceptedPassengerRequest?['otp'] ?? '0000';

    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Enter OTP', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF4A4A4A))),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                const Text('Ask the passenger for the 4-digit OTP.', style: TextStyle(fontSize: 16)),
                const SizedBox(height: 20),
                TextField(
                  controller: otpController,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 5),
                  decoration: InputDecoration(
                    labelText: 'Enter OTP',
                    hintText: '----',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.0)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12.0), borderSide: const BorderSide(color: Colors.deepPurple, width: 2)),
                    counterText: '',
                    contentPadding: const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
                  ),
                ),
                const SizedBox(height: 10),
                Text('Ask passenger for OTP: $actualOtp',
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                    textAlign: TextAlign.center),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              style: TextButton.styleFrom(foregroundColor: Colors.redAccent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (otpController.text == actualOtp) {
                  Navigator.of(dialogContext).pop(true);
                } else {
                  _showMessage('❌ Invalid OTP. Please try again.', Colors.red);
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12)),
              child: const Text('Verify OTP'),
            ),
          ],
        );
      },
    ) ?? false;
  }

  /// Calls the passenger
  Future<void> _callPassenger() async {
    if (_acceptedPassengerRequest == null || _acceptedPassengerRequest!['passenger_phone'] == 'N/A') {
      _showMessage('📞 Passenger phone number not available.', Colors.red);
      return;
    }

    final phoneNumber = _acceptedPassengerRequest!['passenger_phone'];
    final url = 'tel:$phoneNumber';

    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url));
    } else {
      _showMessage('❌ Could not launch phone app.', Colors.red);
    }
  }

  /// NEW: Shows rating dialog after ride completion
  Future<void> _showRatingDialog() async {
    if (_acceptedPassengerRequest == null) return;

    setState(() {
      _isRatingDialogVisible = true;
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
                'Rate Your Passenger',
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.deepPurple),
                textAlign: TextAlign.center,
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _acceptedPassengerRequest!['passenger_name'] ?? 'Passenger',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'How was your experience with this passenger?',
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
                        hintText: 'Share your experience with this passenger...',
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
      _isRatingDialogVisible = false;
    });
  }

  /// NEW: Gets rating label based on selected rating
  String _getRatingLabel(int rating) {
    switch (rating) {
      case 1: return 'Poor - Significant issues';
      case 2: return 'Fair - Some concerns';
      case 3: return 'Good - Satisfactory experience';
      case 4: return 'Very Good - Great passenger';
      case 5: return 'Excellent - Outstanding experience';
      default: return '';
    }
  }

  /// NEW: Gets color based on rating
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

  /// NEW: Handles rating submission
  Future<void> _handleRatingSubmission(bool submitted) async {
    if (!submitted) {
      // Rating was skipped, just complete the ride
      await _completeRide();
      return;
    }

    setState(() {
      _isSubmittingRating = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // Store rating in Firestore
      final ratingData = {
        'riderId': user.uid,
        'riderName': widget.riderName ?? 'Anonymous Rider',
        'passengerName': _acceptedPassengerRequest!['passenger_name'],
        'passengerPhone': _acceptedPassengerRequest!['passenger_phone'],
        'rating': _selectedRating,
        'comment': _ratingCommentController.text.trim(),
        'rideRequestId': _acceptedPassengerRequest!['request_id'],
        'createdAt': FieldValue.serverTimestamp(),
        'pickupLocation': _pickupLocation != null
            ? GeoPoint(_pickupLocation!.latitude, _pickupLocation!.longitude)
            : null,
        'destinationLocation': _passengerDestination != null
            ? GeoPoint(_passengerDestination!.latitude, _passengerDestination!.longitude)
            : null,
      };

      // Save rating to ratings collection
      await FirebaseFirestore.instance.collection('passenger_ratings').add(ratingData);

      // Update rider's rating statistics
      await _updateRiderRatingStats(_selectedRating);

      _showMessage('⭐ Thank you for your rating!', Colors.green);

      // Complete the ride
      await _completeRide();

    } catch (e) {
      _showMessage('❌ Failed to submit rating: ${e.toString()}', Colors.red);
      print('❌ Error submitting rating: $e');
    } finally {
      setState(() {
        _isSubmittingRating = false;
      });
    }
  }

  /// NEW: Updates rider's rating statistics
  Future<void> _updateRiderRatingStats(int newRating) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final riderDoc = await FirebaseFirestore.instance.collection('riders').doc(user.uid).get();
      if (riderDoc.exists) {
        final data = riderDoc.data()!;
        final int currentTotalRatings = data['totalRatings'] ?? 0;
        final int currentRatingSum = data['ratingSum'] ?? 0;
        final int currentTotalRides = data['totalRides'] ?? 0;

        final int newTotalRatings = currentTotalRatings + 1;
        final int newRatingSum = currentRatingSum + newRating;
        final double newAverageRating = newRatingSum / newTotalRatings.toDouble();
        final int newTotalRides = currentTotalRides + 1;

        await FirebaseFirestore.instance.collection('riders').doc(user.uid).update({
          'totalRatings': newTotalRatings,
          'ratingSum': newRatingSum,
          'averageRating': double.parse(newAverageRating.toStringAsFixed(2)),
          'totalRides': newTotalRides,
          'lastRatingUpdate': FieldValue.serverTimestamp(),
        });

        print('✅ Rider rating stats updated: $newAverageRating average from $newTotalRatings ratings');
      }
    } catch (e) {
      print('❌ Error updating rider rating stats: $e');
    }
  }

  /// Completes the ride when destination is reached
  Future<void> _completeRide() async {
    if (_acceptedPassengerRequest == null) {
      _showMessage('No active ride to complete.', Colors.red);
      return;
    }

    try {
      await FirebaseFirestore.instance.collection('driver_proposals').doc(_acceptedPassengerRequest!['request_id']).update({
        'status': 'completed',
        'completionTimestamp': FieldValue.serverTimestamp(),
        'rideEndLocation': _vehicleLocation != null
            ? GeoPoint(_vehicleLocation!.latitude, _vehicleLocation!.longitude)
            : GeoPoint(widget.endLocation.latitude, widget.endLocation.longitude),
        'actualDistance': _totalRouteDistanceMeters,
        'actualDuration': _totalRouteDurationSeconds,
      });

      _showMessage('🎉 Ride completed successfully!', Colors.green);

      // Store ride completion in separate collection for history
      await _storeRideCompletion();

      // Don't reset to initial state here - let the rider continue to destination

    } catch (e) {
      _showMessage('❌ Failed to complete ride: ${e.toString()}', Colors.red);
      print('❌ Error completing ride: $e');
    }
  }

  /// Stores ride completion details in Firestore
  Future<void> _storeRideCompletion() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _acceptedPassengerRequest == null) return;

    try {
      await FirebaseFirestore.instance.collection('completed_rides').add({
        'riderId': user.uid,
        'riderName': widget.riderName ?? 'Anonymous Rider',
        'passengerName': _acceptedPassengerRequest!['passenger_name'],
        'passengerPhone': _acceptedPassengerRequest!['passenger_phone'],
        'pickupLocation': GeoPoint(_pickupLocation!.latitude, _pickupLocation!.longitude),
        'destinationLocation': GeoPoint(_passengerDestination!.latitude, _passengerDestination!.longitude),
        'startTime': FieldValue.serverTimestamp(),
        'endTime': FieldValue.serverTimestamp(),
        'status': 'completed',
        'distance': _totalRouteDistanceMeters,
        'duration': _totalRouteDurationSeconds,
        'fareAmount': _acceptedPassengerRequest!['fare_amount'] ?? 0.0,
        'paymentMethod': 'Cash', // You can get this from the proposal if available
      });

      print('✅ Ride completion stored in history');
    } catch (e) {
      print('❌ Error storing ride completion: $e');
    }
  }

  /// Cancels the ride due to issues
  Future<void> _cancelRideDueToIssues(String reason) async {
    if (_acceptedPassengerRequest == null) {
      _showMessage('No active ride to cancel.', Colors.red);
      return;
    }

    try {
      await FirebaseFirestore.instance.collection('driver_proposals').doc(_acceptedPassengerRequest!['request_id']).update({
        'status': 'cancelled_by_rider',
        'cancellationTimestamp': FieldValue.serverTimestamp(),
        'cancellationReason': reason,
        'cancelledBy': 'rider',
      });

      // Store cancellation in history
      await _storeRideCancellation(reason);

      _showMessage('❌ Ride cancelled due to: $reason', Colors.orange);
      _resetToInitialState();

    } catch (e) {
      _showMessage('❌ Failed to cancel ride: ${e.toString()}', Colors.red);
      print('❌ Error cancelling ride: $e');
    }
  }

  /// Stores ride cancellation details in Firestore
  Future<void> _storeRideCancellation(String reason) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _acceptedPassengerRequest == null) return;

    try {
      await FirebaseFirestore.instance.collection('cancelled_rides').add({
        'riderId': user.uid,
        'riderName': widget.riderName ?? 'Anonymous Rider',
        'passengerName': _acceptedPassengerRequest!['passenger_name'],
        'pickupLocation': _pickupLocation != null
            ? GeoPoint(_pickupLocation!.latitude, _pickupLocation!.longitude)
            : null,
        'destinationLocation': _passengerDestination != null
            ? GeoPoint(_passengerDestination!.latitude, _passengerDestination!.longitude)
            : null,
        'cancellationReason': reason,
        'cancellationTime': FieldValue.serverTimestamp(),
        'cancelledBy': 'rider',
        'vehicleLocationAtCancellation': _vehicleLocation != null
            ? GeoPoint(_vehicleLocation!.latitude, _vehicleLocation!.longitude)
            : null,
      });

      print('✅ Ride cancellation stored in history');
    } catch (e) {
      print('❌ Error storing ride cancellation: $e');
    }
  }

  /// Shows cancellation reason dialog
  Future<void> _showCancellationDialog() async {
    String? selectedReason;
    final List<String> reasons = [
      'Vehicle breakdown/repair needed',
      'Family emergency',
      'Health issues',
      'Route not accessible',
      'Passenger not available',
      'Weather conditions',
      'Other personal reasons'
    ];

    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Cancel Ride', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Please select the reason for cancellation:'),
                const SizedBox(height: 20),
                DropdownButtonFormField<String>(
                  value: selectedReason,
                  items: reasons.map((String reason) {
                    return DropdownMenuItem<String>(
                      value: reason,
                      child: Text(reason),
                    );
                  }).toList(),
                  onChanged: (String? newValue) {
                    selectedReason = newValue;
                  },
                  decoration: InputDecoration(
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.0)),
                    labelText: 'Cancellation Reason',
                  ),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
              child: const Text('Back'),
            ),
            ElevatedButton(
              onPressed: () {
                if (selectedReason != null) {
                  Navigator.of(dialogContext).pop();
                  _cancelRideDueToIssues(selectedReason!);
                } else {
                  _showMessage('Please select a cancellation reason.', Colors.red);
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Confirm Cancellation'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _confirmRide() async {
    if (_routePoints.isEmpty) {
      _showMessage('Cannot confirm ride: No route available.', Colors.red);
      return;
    }

    if (mounted) {
      setState(() {
        _isLoadingRoute = true;
      });
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showMessage('Please log in to confirm the ride.', Colors.redAccent);
      if (mounted) {
        setState(() { _isLoadingRoute = false; });
      }
      return;
    }

    try {
      await _updateRiderStatus('available');

      if (mounted) {
        setState(() {
          _rideConfirmed = true;
          _isLoadingRoute = false;
          _showMessage('🎉 Ride confirmed! Heading to your destination. We are now looking for passengers.', Colors.green);
          _startRouteSimulation();
          _startRequestPolling();
        });
      }
    } catch (e) {
      _showMessage('❌ Failed to confirm ride: ${e.toString()}', Colors.red);
      print('❌ Firestore Error confirming ride: $e');
      if (mounted) {
        setState(() {
          _isLoadingRoute = false;
        });
      }
    }
  }

  /// Resets to initial state
  void _resetToInitialState() {
    _progressTimer?.cancel();
    _acceptedRideSubscription?.cancel();

    if (mounted) {
      setState(() {
        _acceptedPassengerRequest = null;
        _pickupLocation = null;
        _passengerDestination = null;
        _hasArrivedAtPickupPoint = false;
        _hasArrivedAtDestination = false;
        _isVerifyingPassenger = false;
        _showCallButton = false;
        _isNearPickupPoint = false;
        _isNearDestination = false;
        _passengerPickedUp = false;
        _rideConfirmed = true;
        _showRideCompletionScreen = false;
        _isContinuingToDestination = false;
      });
    }

    _startRequestPolling();
    _fetchRoute(widget.startLocation, widget.endLocation, updateMapFit: true);
    _startRouteSimulation();
  }

  // Helper method to show SnackBar messages
  void _showMessage(String msg, Color color) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.info, color: Colors.white),
              SizedBox(width: 8),
              Expanded(child: Text(msg)),
            ],
          ),
          backgroundColor: color,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
          margin: const EdgeInsets.all(10),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  /// NEW: Builds the full-screen ride completion overlay
  Widget _buildRideCompletionOverlay() {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.9),
        child: Center(
          child: Container(
            margin: const EdgeInsets.all(20),
            padding: const EdgeInsets.all(30),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 20,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Success Icon
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_circle,
                    color: Colors.green,
                    size: 50,
                  ),
                ),
                const SizedBox(height: 20),

                // Title
                const Text(
                  'Reached Passenger\'s Destination!',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),

                // Subtitle
                Text(
                  'Ride Completed Successfully!',
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.grey[700],
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),

                // Passenger Details
                if (_acceptedPassengerRequest != null)
                  Container(
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        Text(
                          'Passenger: ${_acceptedPassengerRequest!['passenger_name']}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          'Destination: ${_acceptedPassengerRequest!['destination_address'] ?? 'Passenger Destination'}',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 30),

                // Continue Button
                _buildActionButton(
                  onPressed: () {
                    // Show rating dialog first, then continue to destination
                    _showRatingDialog();
                  },
                  icon: Icons.star,
                  label: 'Rate Passenger & Continue',
                  color: Colors.orange,
                ),
                const SizedBox(height: 15),

                // Continue without rating
                TextButton(
                  onPressed: _continueToRiderDestination,
                  child: const Text(
                    'Continue to My Destination Without Rating',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.blue,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _rideConfirmed
              ? (_acceptedPassengerRequest != null
              ? '🚗 Active Ride: ${_acceptedPassengerRequest!['passenger_name']}'
              : '🟢 Rider Online - Looking for Passengers')
              : '📍 Confirm Your Journey',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF6200EA), Color(0xFF8800FF)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        centerTitle: true,
        elevation: 0,
        actions: [
          // Add search button in app bar
          IconButton(
            icon: Icon(Icons.search, color: Colors.white),
            onPressed: _handleManualSearch,
            tooltip: 'Search & Refresh Route',
          ),
          if (_showCallButton && _acceptedPassengerRequest != null)
            IconButton(
              icon: const Icon(Icons.phone, color: Colors.white),
              onPressed: _callPassenger,
              tooltip: 'Call Passenger',
            ),
          if (_isNearPickupPoint && !_hasArrivedAtPickupPoint)
            IconButton(
              icon: const Icon(Icons.location_pin, color: Colors.orange),
              onPressed: () {
                _showMessage('📍 Approaching pickup point...', Colors.orange);
              },
              tooltip: 'Near Pickup Point',
            ),
          if (_isNearDestination && !_hasArrivedAtDestination)
            IconButton(
              icon: const Icon(Icons.flag, color: Colors.green),
              onPressed: () {
                _showMessage('🏁 Approaching destination...', Colors.green);
              },
              tooltip: 'Near Destination',
            ),
          IconButton(
            icon: Icon(_showDetailsPanel ? Icons.list_alt : Icons.list, color: Colors.white),
            onPressed: () {
              setState(() {
                _showDetailsPanel = !_showDetailsPanel;
              });
            },
            tooltip: 'Toggle Route Instructions',
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _vehicleLocation ?? widget.startLocation,
              initialZoom: 13.0,
              onTap: (_, __) {
                if (_pendingPassengerRequests.isNotEmpty && _acceptedPassengerRequest == null) {
                  return;
                }
                if (mounted) {
                  setState(() {
                    _showDetailsPanel = !_showDetailsPanel;
                  });
                }
              },
            ),
            children: [
              TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.example.rider_app'),
              PolylineLayer(
                polylines: [
                  if (_routePoints.isNotEmpty)
                    Polyline(
                      points: _routePoints,
                      color: const Color(0xFF6200EA),
                      strokeWidth: 6.0,
                      borderColor: const Color(0xFFBB86FC),
                      borderStrokeWidth: 1.5,
                    ),
                ],
              ),
              MarkerLayer(
                markers: [
                  Marker(point: widget.startLocation, width: 50, height: 50, child: _buildLocationMarker(Icons.start, Colors.green, 'Start')),
                  Marker(point: widget.endLocation, width: 50, height: 50, child: _buildLocationMarker(Icons.flag, Colors.red, 'End')),
                  if (_pickupLocation != null) Marker(point: _pickupLocation!, width: 50, height: 50, child: _buildLocationMarker(Icons.person_pin_circle, Colors.orange, 'Pickup')),
                  if (_passengerDestination != null) Marker(point: _passengerDestination!, width: 50, height: 50, child: _buildLocationMarker(Icons.location_on, Colors.blue, 'Destination')),
                  if (_vehicleLocation != null) Marker(point: _vehicleLocation!, width: 50, height: 50, rotate: true, child: _buildVehicleMarker()),
                ],
              ),
            ],
          ),

          if (_isLoadingRoute)
            Positioned.fill(
              child: Container(
                color: Colors.black.withOpacity(0.6),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Colors.white)),
                      const SizedBox(height: 15),
                      Text(_currentInstruction, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w500), textAlign: TextAlign.center),
                    ],
                  ),
                ),
              ),
            ),

          // NEW: Show ride completion overlay when destination is reached
          if (_showRideCompletionScreen)
            _buildRideCompletionOverlay(),

          Positioned(
            top: 10,
            left: 10,
            right: _showDetailsPanel ? MediaQuery.of(context).size.width * 0.3 + 10 : 10,
            child: AnimatedOpacity(
              opacity: _showDetailsPanel ? 0 : 1,
              duration: const Duration(milliseconds: 300),
              child: IgnorePointer(
                ignoring: _showDetailsPanel,
                child: Card(
                  elevation: 8,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  color: Colors.white.withOpacity(0.95),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              _acceptedPassengerRequest != null ? Icons.person : Icons.directions_car,
                              color: _acceptedPassengerRequest != null ? Colors.orange : Colors.blueGrey,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${_acceptedPassengerRequest != null ? 'Driving to Pickup' : 'Your Journey'}',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _acceptedPassengerRequest != null ? Colors.orange[800] : Colors.blueGrey),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text('Next: $_currentInstruction', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF4A4A4A)), maxLines: 2, overflow: TextOverflow.ellipsis),
                        const Divider(height: 20, thickness: 1),
                        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [_buildInfoChip(Icons.access_time, _eta), _buildInfoChip(Icons.social_distance, _distance)]),
                        if (_isNearPickupPoint && !_hasArrivedAtPickupPoint) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.orange.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.orange),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.location_pin, color: Colors.orange, size: 16),
                                const SizedBox(width: 4),
                                Text('Approaching pickup point', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        ],
                        if (_isNearDestination && !_hasArrivedAtDestination) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.green),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.flag, color: Colors.green, size: 16),
                                const SizedBox(width: 4),
                                Text('Approaching destination', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // FIXED: Enhanced Ride Request Cards - Scrollable and Properly Positioned
          if (_pendingPassengerRequests.isNotEmpty && _acceptedPassengerRequest == null)
            Positioned.fill(
              child: Container(
                color: Colors.black54,
                child: Column(
                  children: [
                    // Add some space at the top
                    SizedBox(height: MediaQuery.of(context).padding.top + 20),

                    // Header with close button
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 20),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.notifications_active, color: Colors.orange),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'New Ride Request',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.grey),
                            onPressed: () {
                              setState(() {
                                _pendingPassengerRequests.clear();
                              });
                            },
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Scrollable content
                    Expanded(
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.only(bottom: 20),
                        child: Column(
                          children: [
                            ..._pendingPassengerRequests.map((request) =>
                                Container(
                                  margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                                  child: _buildEnhancedRideRequestCard(request),
                                )
                            ).toList(),

                            // Add some extra space at the bottom for better scrolling
                            const SizedBox(height: 40),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Container(
                padding: const EdgeInsets.all(16.0),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.95),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 20, spreadRadius: 5)],
                ),
                child: Column(
                  children: [
                    // Search/Refresh Route Button - Always visible when not in active ride
                    if (!_rideConfirmed && !_isLoadingRoute)
                      Column(
                        children: [
                          _buildActionButton(
                            onPressed: _handleManualSearch,
                            icon: Icons.search,
                            label: 'Search & Refresh Route',
                            color: Colors.blue,
                          ),
                          SizedBox(height: 10),
                          _buildActionButton(
                              onPressed: _confirmRide,
                              icon: Icons.play_arrow_rounded,
                              label: 'Go Online & Start Journey',
                              color: const Color(0xFF6200EA)
                          ),
                        ],
                      )

                    // FIXED: Show "Reached Pickup Point" button when near pickup and not yet verified
                    else if (_acceptedPassengerRequest != null &&
                        _hasArrivedAtPickupPoint &&
                        !_isVerifyingPassenger &&
                        !_passengerPickedUp)
                      Column(
                        children: [
                          _buildActionButton(
                              onPressed: _onReachedPickupPoint,
                              icon: Icons.person_add_alt_1_rounded,
                              label: 'Reached Pickup Point - Start Verification',
                              color: Colors.orange
                          ),
                          SizedBox(height: 10),
                          if (_showCallButton)
                            _buildActionButton(
                                onPressed: _callPassenger,
                                icon: Icons.phone,
                                label: 'Call Passenger',
                                color: Colors.green
                            ),
                        ],
                      )

                    // Show progress when on the way to pickup
                    else if (_acceptedPassengerRequest != null &&
                          !_hasArrivedAtPickupPoint &&
                          !_passengerPickedUp)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8.0),
                          child: Column(
                            children: [
                              Text(
                                  'On the way to pick up ${_acceptedPassengerRequest!['passenger_name']}...',
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF6200EA)),
                                  textAlign: TextAlign.center
                              ),
                              SizedBox(height: 10),
                              LinearProgressIndicator(
                                  value: _routePoints.isEmpty ? 0 : (_currentRoutePointIndex / _routePoints.length),
                                  backgroundColor: const Color(0xFFE0E0E0),
                                  valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFBB86FC))
                              ),
                              SizedBox(height: 10),
                              _buildActionButton(
                                  onPressed: _showCancellationDialog,
                                  icon: Icons.cancel,
                                  label: 'Cancel Trip Due to Issues',
                                  color: Colors.red
                              ),
                            ],
                          ),
                        )

                      // Show verification in progress
                      else if (_acceptedPassengerRequest != null && _isVerifyingPassenger)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8.0),
                            child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF6200EA))),
                                  SizedBox(width: 15),
                                  Text('Verifying Passenger...', style: TextStyle(fontSize: 16, color: Color(0xFF6200EA), fontWeight: FontWeight.w600))
                                ]
                            ),
                          )

                        // Show destination reached and completion options - UPDATED: Now includes completion message
                        else if (_acceptedPassengerRequest != null && _hasArrivedAtDestination)
                            Column(
                              children: [
                                // Completion Success Message
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  margin: const EdgeInsets.only(bottom: 10),
                                  decoration: BoxDecoration(
                                    color: Colors.green.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Colors.green),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.check_circle, color: Colors.green, size: 20),
                                      SizedBox(width: 8),
                                      Text(
                                        'Ride Completed Successfully!',
                                        style: TextStyle(
                                          color: Colors.green,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                _buildActionButton(
                                    onPressed: () {
                                      // Show rating dialog instead of directly completing ride
                                      _showRatingDialog();
                                    },
                                    icon: Icons.star,
                                    label: 'Rate Passenger & Complete',
                                    color: Colors.green
                                ),
                                SizedBox(height: 10),
                                _buildActionButton(
                                    onPressed: _showCancellationDialog,
                                    icon: Icons.cancel,
                                    label: 'Cancel Trip Due to Issues',
                                    color: Colors.red
                                ),
                              ],
                            )

                          // Show online status when no active ride
                          else
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8.0),
                              child: Column(
                                children: [
                                  Text(
                                      _isLoadingRoute ? 'Calculating route for your journey...' : '🟢 Online and looking for passengers...',
                                      style: const TextStyle(fontSize: 16, color: Colors.grey, fontWeight: FontWeight.w500),
                                      textAlign: TextAlign.center
                                  ),
                                  if (_isLoadingRoute)
                                    const Padding(
                                        padding: EdgeInsets.only(top: 10.0),
                                        child: LinearProgressIndicator(
                                            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFBB86FC)),
                                            backgroundColor: Color(0xFFE0E0E0)
                                        )
                                    ),
                                  // Add search button when online
                                  if (!_isLoadingRoute && _rideConfirmed)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 10.0),
                                      child: _buildActionButton(
                                        onPressed: _handleManualSearch,
                                        icon: Icons.refresh,
                                        label: 'Refresh Route',
                                        color: Colors.blue,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                    SizedBox(height: 10),
                    if (_rideConfirmed)
                      _buildActionButton(
                        onPressed: () {
                          _progressTimer?.cancel();
                          _acceptedRideSubscription?.cancel();
                          _requestSubscription?.cancel();
                          _requestCheckTimer?.cancel();
                          if (mounted) {
                            setState(() {
                              _rideConfirmed = false;
                              _isLoadingRoute = true;
                              _acceptedPassengerRequest = null;
                              _pickupLocation = null;
                              _passengerDestination = null;
                              _hasArrivedAtPickupPoint = false;
                              _hasArrivedAtDestination = false;
                              _isVerifyingPassenger = false;
                              _showCallButton = false;
                              _isNearPickupPoint = false;
                              _isNearDestination = false;
                              _passengerPickedUp = false;
                              _isListeningForRequests = false;
                              _showRideCompletionScreen = false;
                              _isContinuingToDestination = false;
                            });
                          }
                          _showMessage('🛑 Ride ended manually.', Colors.orange);
                          _updateRiderStatus('offline');
                          _fetchRoute(widget.startLocation, widget.endLocation, updateMapFit: true);
                        },
                        icon: Icons.stop_circle_rounded,
                        label: 'End Current Ride',
                        color: Colors.redAccent,
                      ),
                  ],
                ),
              ),
            ),
          ),

          AnimatedPositioned(
            duration: const Duration(milliseconds: 300),
            right: _showDetailsPanel ? 0 : -(MediaQuery.of(context).size.width * 0.4),
            top: 0,
            bottom: 0,
            width: MediaQuery.of(context).size.width * 0.4,
            child: ClipRRect(
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(25), bottomLeft: Radius.circular(25)),
              child: Container(
                color: Colors.white.withOpacity(0.95),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16.0),
                      decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFFBB86FC), Color(0xFF6200EA)], begin: Alignment.topLeft, end: Alignment.bottomRight)),
                      child: Row(children: [Icon(Icons.directions, color: Colors.white, size: 28), const SizedBox(width: 10), Text('Route Details', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold, color: Colors.white))]),
                    ),
                    Expanded(
                      child: _osrmSteps.isEmpty
                          ? const Center(child: Text('No detailed instructions available.', style: TextStyle(color: Colors.grey)))
                          : ListView.builder(
                        controller: _instructionsScrollController,
                        padding: const EdgeInsets.all(12.0),
                        itemCount: _osrmSteps.length,
                        itemBuilder: (context, index) {
                          final step = _osrmSteps[index];
                          final instruction = step['maneuver']?['instruction'] ?? 'Unknown instruction';
                          final duration = step['duration'] ?? 0.0;
                          final distance = step['distance'] ?? 0.0;

                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.symmetric(vertical: 6.0),
                            decoration: BoxDecoration(
                              color: _currentInstructionIndex == index ? Colors.blue.withOpacity(0.1) : Colors.white,
                              borderRadius: BorderRadius.circular(15),
                              border: Border.all(color: _currentInstructionIndex == index ? Colors.blueAccent : Colors.grey.withOpacity(0.3), width: _currentInstructionIndex == index ? 2 : 1),
                              boxShadow: _currentInstructionIndex == index ? [BoxShadow(color: Colors.blueAccent.withOpacity(0.2), blurRadius: 8, spreadRadius: 2)] : [BoxShadow(color: Colors.grey.withOpacity(0.05), blurRadius: 4, spreadRadius: 1)],
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(14.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(instruction, style: TextStyle(fontWeight: _currentInstructionIndex == index ? FontWeight.bold : FontWeight.normal, color: _currentInstructionIndex == index ? Color(0xFF6200EA) : Colors.black87, fontSize: 15)),
                                  const SizedBox(height: 6),
                                  Text('${(distance / 1000).toStringAsFixed(2)} km, ${(duration / 60).ceil()} mins', style: const TextStyle(fontSize: 13, color: Colors.grey)),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationMarker(IconData icon, Color color, String tooltip) {
    return Tooltip(
      message: tooltip,
      child: Container(
        decoration: BoxDecoration(color: color.withOpacity(0.2), shape: BoxShape.circle, border: Border.all(color: color, width: 2)),
        child: Icon(icon, color: color, size: 30),
      ),
    );
  }

  Widget _buildVehicleMarker() {
    return Container(
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.9), shape: BoxShape.circle, border: Border.all(color: Colors.deepPurple, width: 2), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 5, spreadRadius: 2)]),
      child: const Icon(Icons.two_wheeler_rounded, color: Colors.deepPurple, size: 30),
    );
  }

  Widget _buildInfoChip(IconData icon, String text) {
    return Row(children: [Icon(icon, color: Colors.grey[600], size: 20), const SizedBox(width: 5), Text(text, style: const TextStyle(fontSize: 15, color: Color(0xFF4A4A4A)))]);
  }

  Widget _buildActionButton({required VoidCallback onPressed, required IconData icon, required String label, required Color color}) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 28),
      label: Text(label, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      style: ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30.0)), elevation: 8, minimumSize: const Size(double.infinity, 50)),
    );
  }

  /// FIXED: Builds a professional ride request card with improved UI and scrolling
  Widget _buildEnhancedRideRequestCard(Map<String, dynamic> request) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: Card(
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        color: Colors.white,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.7,
          ),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header with passenger info and avatar
                  Row(
                    children: [
                      Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF6200EA), Color(0xFFBB86FC)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.purple.withOpacity(0.3),
                              blurRadius: 8,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: const Icon(Icons.person, color: Colors.white, size: 35),
                      ),
                      const SizedBox(width: 15),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Ride Request',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[600],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              request['passenger_name'] ?? 'Passenger',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.deepPurple,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Mobile: ${request['passenger_phone'] ?? 'N/A'}',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[600],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // Route information - More compact
                  _buildCompactRouteInfo(
                    Icons.location_on,
                    Colors.red,
                    'Pickup',
                    request['pickup_address'] ?? 'Pickup Location',
                  ),
                  const SizedBox(height: 12),
                  _buildCompactRouteInfo(
                    Icons.flag,
                    Colors.green,
                    'Destination',
                    request['destination_address'] ?? 'Destination Location',
                  ),

                  const SizedBox(height: 16),

                  // Additional ride info - Single row
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildCompactRideDetail(Icons.money, '₹${request['fare_amount'] ?? '0'}'),
                        _buildCompactRideDetail(Icons.social_distance, request['estimated_distance'] ?? '0 km'),
                        _buildCompactRideDetail(Icons.access_time, request['estimated_duration'] ?? '0 min'),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Contact information - More compact
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.green.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.phone, color: Colors.green[700], size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Mobile: ${request['passenger_phone'] ?? 'N/A'}',
                            style: TextStyle(
                              color: Colors.green[700],
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Accept/Reject buttons with improved design
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(15),
                            gradient: const LinearGradient(
                              colors: [Color(0xFF6200EA), Color(0xFFBB86FC)],
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.purple.withOpacity(0.3),
                                blurRadius: 8,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: ElevatedButton(
                            onPressed: () => _handleRequestResponse(request['request_id'], 'accepted'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              foregroundColor: Colors.white,
                              shadowColor: Colors.transparent,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.check_circle, size: 22),
                                SizedBox(width: 8),
                                Text(
                                  'Accept Ride',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => _handleRequestResponse(request['request_id'], 'rejected'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.grey[100],
                            foregroundColor: Colors.red,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                              side: BorderSide(color: Colors.grey[300]!),
                            ),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.cancel, size: 22),
                              SizedBox(width: 8),
                              Text(
                                'Decline',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Add helper methods for compact layout
  Widget _buildCompactRouteInfo(IconData icon, Color color, String title, String subtitle) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCompactRideDetail(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.blueGrey[50],
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.blueGrey[100]!),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.blueGrey[600]),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              color: Colors.blueGrey[700],
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  /// NEW: Method to handle manual search functionality
  void _handleManualSearch() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Search Destination'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Current route: ${_routePoints.length} points'),
            SizedBox(height: 10),
            Text('ETA: $_eta | Distance: $_distance'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _fetchRoute(widget.startLocation, widget.endLocation, updateMapFit: true);
            },
            child: Text('Refresh Route'),
          ),
        ],
      ),
    );
  }
}