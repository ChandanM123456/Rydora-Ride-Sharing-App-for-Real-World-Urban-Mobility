import 'package:flutter/material.dart';
import '../services/ride_api_service.dart';

class RiderMatchesPage extends StatefulWidget {
  final int riderId;
  const RiderMatchesPage({super.key, required this.riderId});

  @override
  State<RiderMatchesPage> createState() => _RiderMatchesPageState();
}

class _RiderMatchesPageState extends State<RiderMatchesPage> {
  List<dynamic> _matches = [];
  List<dynamic> _requests = [];

  @override
  void initState() {
    super.initState();
    _fetchMatches();
    _fetchRequests();
  }

  Future<void> _fetchMatches() async {
    final data = await RideApiService.getPassengerMatches(widget.riderId);
    setState(() => _matches = data);
    // _fetchRequests(); // Optional: refresh after matching
  }

  Future<void> _fetchRequests() async {
    final data = await RideApiService.getRiderRequests(widget.riderId);
    setState(() => _requests = data);
  }

  Future<void> _handleRequest(int requestId, String action) async {
    final success = await RideApiService.respondToRequest(requestId, action);
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Request $action!')));
      _fetchRequests();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to process')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Rider Matches')),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('New Matches', style: TextStyle(fontWeight: FontWeight.bold)),
            ..._matches.map((m) => Card(
              child: ListTile(
                leading: const Icon(Icons.person),
                title: Text('Passenger: ${m['passenger_name']}'),
                subtitle: Text('Score: ${(m['score'] * 100).toStringAsFixed(0)}%\nPickup: ${m['pickup']}\nDest: ${m['destination']}'),
              ),
            )),
            const Divider(),
            const Text('Pending Ride Requests', style: TextStyle(fontWeight: FontWeight.bold)),
            Expanded(
              child: ListView.builder(
                itemCount: _requests.length,
                itemBuilder: (context, i) {
                  final req = _requests[i];
                  return Card(
                    child: ListTile(
                      title: Text('Passenger: ${req['passenger_name']}'),
                      subtitle: Text('Status: ${req['status']}'),
                      trailing: req['status'] == 'pending'
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.check, color: Colors.green),
                                onPressed: () => _handleRequest(req['request_id'], 'accepted'),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close, color: Colors.red),
                                onPressed: () => _handleRequest(req['request_id'], 'rejected'),
                              ),
                            ],
                          )
                        : null,
                    ),
                  );
                },
              ),
            ),
            ElevatedButton(
              onPressed: () {
                _fetchMatches();
                _fetchRequests();
              },
              child: const Text('Refresh'),
            ),
          ],
        ),
      ),
    );
  }
}
