// rider_app/lib/pages/rider_home.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:rider_app/services/ride_api_service.dart'; // Assuming this service exists for requests

class RiderHomePage extends StatefulWidget {
  final LatLng? initialPickup;
  final LatLng? initialDestination;

  // Constructor now accepts optional initial coordinates
  const RiderHomePage({super.key, this.initialPickup, this.initialDestination});

  @override
  State<RiderHomePage> createState() => _RiderHomePageState();
}

class _RiderHomePageState extends State<RiderHomePage> {
  LatLng? _current;
  LatLng? _destination;
  List<LatLng> _polylinePoints = [];

  late int _riderId; // Placeholder for rider's ID (should come from authenticated user data)
  LatLng? _vehicleLocation; // Represents the driver's current position
  List<String> _routeInstructions = []; // Turn-by-turn instructions
  String _eta = ''; // Estimated Time of Arrival
  String _distance = ''; // Total distance of the route
  List<dynamic> _pendingRequests = []; // List of incoming ride requests for this rider

  // FIX: Declare _isLoading variable here
  bool _isLoading = false; // State to show loading for API calls

  Timer? _timer; // Timer for polling ride requests

  @override
  void initState() {
    super.initState();
    _riderId = 123; // TEMPORARY: Replace with actual authenticated rider ID (e.g., from Firebase Auth UID)

    // Check if initial coordinates are provided
    if (widget.initialPickup != null && widget.initialDestination != null) {
      _current = widget.initialPickup;
      _destination = widget.initialDestination;
      _polylinePoints = _mockRoute(_current!, _destination!); // Calculate route immediately
      _routeInstructions = ['Mock Instruction 1: Go straight', 'Mock Instruction 2: Turn left'];
      _eta = '15 mins';
      _distance = '5 km';
      _vehicleLocation = _current; // Initialize vehicle location to pickup
      _showMessage("Route loaded from selected destination!", Colors.blue);
    } else {
      // If no initial coordinates, get current location (for general map view)
      _getCurrentLocation();
    }

    _startPollingRequests(); // Start checking for new ride requests
  }

  @override
  void dispose() {
    _timer?.cancel(); // Cancel the timer when the widget is disposed
    super.dispose();
  }

  Future<void> _getCurrentLocation() async {
    try {
      LocationPermission permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        _showMessage("Location permissions denied. Cannot display your current location.", Colors.red);
        return;
      }
      Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      setState(() {
        _current = LatLng(pos.latitude, pos.longitude);
        _vehicleLocation = _current; // Initialize vehicle location to current location
      });
      _showMessage("Current location fetched!", Colors.green);
    } catch (e) {
      print('Error fetching current location: $e');
      _showMessage("Failed to get current location. Please check permissions.", Colors.red);
    }
  }

  void _onTapMap(TapPosition _, LatLng point) {
    // This function will primarily be used if the map is opened without a predefined destination
    // (i.e., when initialPickup/Destination are null).
    setState(() {
      _destination = point;
      if (_current != null) { // Ensure current location is known before mocking route
        _polylinePoints = _mockRoute(_current!, _destination!); // Update polyline for mock route
        _routeInstructions = ['Mock Instruction 1: Go straight', 'Mock Instruction 2: Turn left'];
        _eta = '15 mins';
        _distance = '5 km';
        _showMessage("Destination set by tap. Mock route calculated.", Colors.blue);
      } else {
        _showMessage("Cannot set route, current location unknown.", Colors.orange);
      }
    });
  }

  // A mock route generation for demonstration purposes
  List<LatLng> _mockRoute(LatLng start, LatLng end) {
    List<LatLng> points = [];
    for (int i = 0; i <= 10; i++) {
      double lat = start.latitude + (end.latitude - start.latitude) * i / 10;
      double lng = start.longitude + (end.longitude - start.longitude) * i / 10;
      points.add(LatLng(lat, lng));
    }
    return points;
  }

  // Function to start polling for ride requests
  void _startPollingRequests() {
    _timer = Timer.periodic(const Duration(seconds: 10), (timer) {
      _fetchRequests();
    });
    _fetchRequests(); // Fetch immediately on init
  }

  // Function to fetch pending ride requests for this rider
  Future<void> _fetchRequests() async {
    try {
      // Use the RideApiService to get requests for the current rider ID
      final data = await RideApiService.getRiderRequests(_riderId);
      setState(() {
        _pendingRequests = data;
      });
      print('Fetched requests: $_pendingRequests'); // Debugging print
    } catch (e) {
      print('Error fetching requests: $e');
      // _showMessage("Failed to fetch ride requests.", Colors.red); // Avoid spamming if backend is down
    }
  }

  // Function for rider to respond to a ride request
  Future<void> _respondRideRequest(int requestId, String action) async {
    setState(() { _isLoading = true; }); // Show loading for response
    try {
      final success = await RideApiService.respondToRequest(requestId, action);
      if (success) {
        _showMessage('Request $action successfully!', Colors.green);
        _fetchRequests(); // Refresh requests after response
      } else {
        _showMessage('Failed to $action request.', Colors.red);
      }
    } catch (e) {
      _showMessage('Error responding to request: ${e.toString()}', Colors.red);
      print('Error responding to request: $e');
    } finally {
      setState(() { _isLoading = false; });
    }
  }

  void _showMessage(String message, Color color) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: color,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
          margin: const EdgeInsets.all(10),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // If current location is not yet set and no initial pickup was provided, show loading
    if (_current == null && widget.initialPickup == null) {
      return Scaffold(
        appBar: AppBar(title: const Text("Rider Map")),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Rider Map & Requests")),
      body: Stack(
        children: [
          FlutterMap(
            options: MapOptions(
              initialCenter: _current!, // Use current or initial pickup location
              initialZoom: 14.0,
              onTap: widget.initialDestination == null ? _onTapMap : null, // Only allow tap if no initial destination
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.maproute_app',
              ),
              MarkerLayer(
                markers: [
                  // Rider's current location marker
                  Marker(
                    point: _current!,
                    width: 50,
                    height: 50,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.8),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: const Icon(Icons.two_wheeler, color: Colors.white, size: 30),
                    ),
                  ),
                  // Destination marker if set
                  if (_destination != null)
                    Marker(
                      point: _destination!,
                      width: 50,
                      height: 50,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.8),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: const Icon(Icons.location_on, color: Colors.white, size: 30),
                      ),
                    ),
                ],
              ),
              // Polyline for the route
              if (_polylinePoints.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _polylinePoints,
                      color: Colors.green,
                      strokeWidth: 5.0,
                    ),
                  ],
                ),
            ],
          ),

          // Route Information Overlay
          if (_destination != null && _polylinePoints.isNotEmpty)
            Positioned(
              top: 10,
              left: 10,
              right: 10,
              child: Card(
                elevation: 4,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Current Trip Details:',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const Divider(),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('ETA: $_eta'),
                          Text('Distance: $_distance'),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text('Next Steps: ${_routeInstructions.join(' -> ')}'),
                    ],
                  ),
                ),
              ),
            ),

          // Ride Requests Overlay
          if (_pendingRequests.isNotEmpty)
            Positioned(
              bottom: 10,
              left: 10,
              right: 10,
              child: Card(
                elevation: 6,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Pending Ride Requests:',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.deepPurple),
                      ),
                      const SizedBox(height: 10),
                      // Loop through pending requests and display them
                      ..._pendingRequests.map((request) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  'Passenger: ${request['passenger_name'] ?? 'N/A'}\n'
                                      'Pickup: ${request['pickup_address'] ?? 'N/A'}\n'
                                      'Destination: ${request['destination_address'] ?? 'N/A'}',
                                  style: const TextStyle(fontSize: 14),
                                ),
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Accept Button
                                  IconButton(
                                    icon: const Icon(Icons.check_circle, color: Colors.green, size: 30),
                                    onPressed: _isLoading ? null : () => _respondRideRequest(request['request_id'], 'accepted'),
                                    tooltip: 'Accept Ride',
                                  ),
                                  const SizedBox(width: 8),
                                  // Reject Button
                                  IconButton(
                                    icon: const Icon(Icons.cancel, color: Colors.red, size: 30),
                                    onPressed: _isLoading ? null : () => _respondRideRequest(request['request_id'], 'rejected'),
                                    tooltip: 'Reject Ride',
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
