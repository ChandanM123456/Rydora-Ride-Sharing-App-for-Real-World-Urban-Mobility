import 'dart:convert';
import 'package:http/http.dart' as http;

class RideApiService {
  static const String baseUrl = 'http://10.12.191.10:5000';


  // Fetch ride matches for a rider
  static Future<List<dynamic>> getPassengerMatches(int riderId) async {
    final url = Uri.parse('$baseUrl/match/$riderId');
    final resp = await http.get(url);
    if (resp.statusCode == 200) {
      return jsonDecode(resp.body)['matches'];
    }
    return [];
  }

  // Fetch all ride requests for a rider
  static Future<List<dynamic>> getRiderRequests(int riderId) async {
    final url = Uri.parse('$baseUrl/rider/requests/$riderId');
    final resp = await http.get(url);
    if (resp.statusCode == 200) {
      return jsonDecode(resp.body);
    }
    return [];
  }

  // Rider responds to a ride request (accept/reject)
  static Future<bool> respondToRequest(int requestId, String action) async {
    final url = Uri.parse('$baseUrl/rider/respond_request');
    final resp = await http.post(url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"request_id": requestId, "action": action}));
    return resp.statusCode == 200;
  }
}
