import 'package:flutter/material.dart';
import '../services/api_service.dart';

class RequestRidePage extends StatelessWidget {
  const RequestRidePage({super.key});

  Future<void> _requestRide(
      BuildContext context, Map<String, dynamic> passengerData) async {
    try {
      final result = await ApiService.requestRide(passengerData);

      // Show success snack message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("✅ Ride request sent!")),
      );

      print("Response: $result");
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("❌ Failed: $e")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)!.settings.arguments as Map;
    final Map<String, dynamic> passengerData = args['passengerData'];

    return Scaffold(
      appBar: AppBar(title: const Text("Passenger Ride Request")),
      body: Center(
        child: ElevatedButton(
          onPressed: () => _requestRide(context, passengerData),
          child: const Text("Request Ride"),
        ),
      ),
    );
  }
}
