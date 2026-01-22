// rider_app/lib/services/api_service.dart

import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  // Set your actual backend base URL
  static const String baseUrl = 'http://10.12.191.10:5000'; // Make sure this IP is reachable from your device/emulator

  // Generic POST request handler (useful if endpoints are similar)
  static Future<Map<String, dynamic>> _sendPostRequest(String endpoint, Map<String, dynamic> data) async {
    final url = Uri.parse('$baseUrl$endpoint');
    print("Sending POST to: $url with data: $data");
    final res = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(data),
    );
    if (res.statusCode >= 200 && res.statusCode < 300) { // Check for 2xx success codes
      return jsonDecode(res.body);
    } else {
      throw Exception("Failed to send data to $endpoint: Status ${res.statusCode}, Body: ${res.body}");
    }
  }

  // Existing: Send passenger data (if still needed, ensure it hits correct backend endpoint)
  static Future<Map<String, dynamic>> sendPassengerData(Map<String, dynamic> data) async {
    // This endpoint might be for a passenger setting their destination, or requesting a ride.
    // It's currently mapped to /passenger/set_destination as per your old file.
    // If it's used by passenger, keep it. If this is where ride requests go, rename it.
    return _sendPostRequest('/passenger/set_destination', data); // Or appropriate path
  }

  // NEW/MODIFIED: For rider to request/confirm a ride after selecting destination
  static Future<Map<String, dynamic>> requestRide(Map<String, dynamic> data) async {
    // This should ideally be an endpoint like /rider/request_ride or /rides/create
    return _sendPostRequest('/rider/request_ride', data); // Assuming a new endpoint for riders to request
  }

// Other API methods could go here (e.g., getRiderMatches, respondToRequest, etc.)
// These would ideally be in ride_api_service.dart or match_service.dart if those are your dedicated files.
}
    