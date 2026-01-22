// rider_app/lib/pages/destination_entry_page.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'package:rider_app/pages/route_map_page.dart'; // <--- CHANGED: Import RouteMapPage
import 'package:rider_app/services/api_service.dart'; // Assuming this path is correct

class DestinationEntryPage extends StatefulWidget {
  const DestinationEntryPage({super.key});

  @override
  State<DestinationEntryPage> createState() => _DestinationEntryPageState();
}

class _DestinationEntryPageState extends State<DestinationEntryPage> {
  final _nameController = TextEditingController();
  final _controller = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  LatLng? _pickup; // This will hold the current location from CurrentLocationPage

  // Preferences are likely for matching riders/passengers, may not be needed here
  Map<String, String> _preferences = {
    "gender": "any",
    "smoking": "no",
    "pets": "yes"
  };

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)!.settings.arguments as Map?;
    if (args != null && args.containsKey('pickup')) {
      _pickup = args['pickup'];
      print("✅ DestinationEntryPage: Received pickup location: $_pickup");
    } else {
      print("❌ DestinationEntryPage: No pickup location received.");
      // Handle case where pickup is not received, maybe pop back
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error: Pickup location not received. Please try again.')),
        );
        Navigator.pop(context); // Go back to the previous screen (CurrentLocationPage)
      });
    }
  }

  Future<void> _search(String query) async {
    if (query.isEmpty) {
      setState(() {
        _results = [];
      });
      return;
    }
    final url = Uri.parse('https://nominatim.openstreetmap.org/search?q=$query&format=json&limit=5');
    try {
      final response = await http.get(url, headers: {'User-Agent': 'ridershare-app/1.0'});
      if (response.statusCode == 200) {
        final List data = json.decode(response.body);
        setState(() {
          _results = List<Map<String, dynamic>>.from(data);
        });
        print("🔍 Search results: $_results");
      } else {
        print("❗ Search failed with status: ${response.statusCode}");
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Search failed. Status: ${response.statusCode}")),
        );
      }
    } catch (e) {
      print("❗ Search request failed: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Search failed. Please check internet connection.")),
      );
    }
  }

  Future<void> _selectPlace(Map<String, dynamic> place) async {
    final LatLng destination = LatLng(
      double.parse(place['lat']),
      double.parse(place['lon']),
    );
    print("📍 Selected destination: $destination");

    if (_pickup == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pickup location missing')),
      );
      return;
    }

    if (_nameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your name')),
      );
      return;
    }

    // --- Navigate to RouteMapPage and pass data ---
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => RouteMapPage( // <--- Navigating to RouteMapPage
          startLocation: _pickup!,
          endLocation: destination,
          riderName: _nameController.text, // Pass rider name for display if needed
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Set Destination")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: "Your Name"),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _controller,
              decoration: InputDecoration(
                labelText: "Search your Destination",
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: () => _search(_controller.text),
                ),
              ),
              onSubmitted: _search,
            ),
            const SizedBox(height: 10),
            Expanded(
              child: ListView.builder(
                itemCount: _results.length,
                itemBuilder: (context, index) {
                  final place = _results[index];
                  return ListTile(
                    title: Text(place['display_name']),
                    subtitle: Text('Lat: ${place['lat']}, Lon: ${place['lon']}'),
                    onTap: () => _selectPlace(place),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
