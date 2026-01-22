import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:passenger_ride_app/models/ride_request.dart';

class RideRequestScreen extends StatefulWidget {
  const RideRequestScreen({Key? key}) : super(key: key);

  @override
  _RideRequestScreenState createState() => _RideRequestScreenState();
}

class _RideRequestScreenState extends State<RideRequestScreen> {
  final MapController _mapController = MapController();
  LatLng? _currentLocation;
  LatLng? _selectedDestination;
  final TextEditingController _destinationController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchCurrentLocation();
  }

  Future<void> _fetchCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showSnackBar("Location services are disabled.");
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _showSnackBar("Location permissions are denied.");
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        _showSnackBar(
            "Location permissions are permanently denied. Enable them in settings.");
        return;
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      setState(() {
        _currentLocation = LatLng(position.latitude, position.longitude);
      });

      _mapController.move(_currentLocation!, 15.0);
    } catch (e) {
      _showSnackBar("Error fetching location: $e");
    }
  }

  void _requestRide() {
    if (_currentLocation == null || _selectedDestination == null) {
      _showSnackBar("Set both pickup and destination locations.");
      return;
    }

    final rideRequest = RideRequest(
      pickupLocation: _currentLocation!,
      destinationLocation: _selectedDestination!,
    );

    _showSnackBar(
        "Ride requested from ${rideRequest.pickupLocation} to ${rideRequest.destinationLocation}");
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final markers = <Marker>[
      if (_currentLocation != null)
        Marker(
          point: _currentLocation!,
          width: 40,
          height: 40,
          child: const Icon(Icons.location_on, color: Colors.blue),
        ),
      if (_selectedDestination != null)
        Marker(
          point: _selectedDestination!,
          width: 40,
          height: 40,
          child: const Icon(Icons.flag, color: Colors.red),
        ),
    ];

    final polylines = <Polyline>[
      if (_currentLocation != null && _selectedDestination != null)
        Polyline(
          points: [_currentLocation!, _selectedDestination!],
          strokeWidth: 4,
          color: Colors.blue,
        ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text("Ride Request"),
        backgroundColor: Colors.blue,
      ),
      body: Column(
        children: [
          Expanded(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter:
                    _currentLocation ?? const LatLng(20.5937, 78.9629),
                initialZoom: 5.0,
                onTap: (tapPos, latLng) {
                  setState(() {
                    _selectedDestination = latLng;
                    _destinationController.text =
                        'Lat: ${latLng.latitude.toStringAsFixed(4)}, Lon: ${latLng.longitude.toStringAsFixed(4)}';
                  });
                  _showSnackBar("Destination set by tap.");
                },
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.passenger_ride_app',
                ),
                PolylineLayer(polylines: polylines),
                MarkerLayer(markers: markers),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                TextField(
                  controller: _destinationController,
                  decoration: const InputDecoration(
                    labelText: "Enter Destination",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                ElevatedButton(
                  onPressed: _requestRide,
                  child: const Text("Request Ride"),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
