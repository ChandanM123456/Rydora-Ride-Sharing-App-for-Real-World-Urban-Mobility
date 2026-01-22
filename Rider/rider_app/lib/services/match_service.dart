import 'dart:convert';
import 'package:http/http.dart' as http;

class MatchService {
  static const String baseUrl = 'http://10.0.2.2:5000';

  static Future<void> sendRiderData({
    required String id,
    required String name,
    required List<double> start,
    required List<double> end,
    required List<List<double>> route,
    required Map<String, String> preferences,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/rider/set_route'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        "id": id,
        "name": name,
        "start": start,
        "end": end,
        "route": route,
        "preferences": preferences,
      }),
    );
    print("Rider response: ${res.body}");
  }

  static Future<void> sendPassengerRequest({
    required String id,
    required List<double> pickup,
    required List<double> destination,
    required Map<String, String> preferences,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/passenger/request_ride'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        "id": id,
        "pickup": pickup,
        "destination": destination,
        "preferences": preferences,
      }),
    );
    print("Passenger response: ${res.body}");
  }
}
