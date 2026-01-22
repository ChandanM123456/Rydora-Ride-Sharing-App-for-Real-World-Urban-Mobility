// rider_app/lib/pages/current_location_page.dart

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:rider_app/pages/destination_entry_page.dart'; // Ensure this internal import is correct if it exists.

class CurrentLocationPage extends StatefulWidget {
  const CurrentLocationPage({super.key});

  @override
  State<CurrentLocationPage> createState() => _CurrentLocationPageState();
}

class _CurrentLocationPageState extends State<CurrentLocationPage> {
  @override
  void initState() {
    super.initState();
    _getAndNavigate();
  }

  Future<void> _getAndNavigate() async {
    try {
      await Geolocator.requestPermission();
      Position pos = await Geolocator.getCurrentPosition();
      LatLng current = LatLng(pos.latitude, pos.longitude);

      // Debug print
      print("📍 Current location: ${current.latitude}, ${current.longitude}");

      // Pass location as argument and navigate to destination entry
      await Future.delayed(const Duration(seconds: 1)); // Small delay for UX
      Navigator.pushReplacementNamed(
        context,
        '/rider/destination', // This route is defined in main.dart
        arguments: {
          'pickup': current,
        },
      );
    } catch (e) {
      print('❗ Location error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to get current location: ${e.toString()}")),
      );
      // Optional: Navigate back or show a retry option if location fails
      Navigator.pop(context); // Go back to the previous screen (HomePage)
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Getting Location...")),
      body: const Center(child: CircularProgressIndicator()),
    );
  }
}
