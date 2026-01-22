// rider_app/lib/home_page.dart

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:rider_app/rider_details_page.dart';
// import 'package:rider_app/pages/rider_home.dart'; // REMOVED: No longer navigating here directly
import 'package:rider_app/pages/current_location_page.dart'; // ADDED: Import for the new starting point
import 'package:flutter_map/flutter_map.dart'; // For displaying maps
import 'package:latlong2/latlong.dart'; // For LatLng coordinates
import 'package:geolocator/geolocator.dart'; // For fetching current location

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  LatLng? _currentLocation;
  bool _isLoadingLocation = true;

  @override
  void initState() {
    super.initState();
    _fetchCurrentLocationForMap(); // Fetch location when the page initializes
  }

  // Fetches the current location for display on the map
  Future<void> _fetchCurrentLocationForMap() async {
    setState(() {
      _isLoadingLocation = true; // Indicate that location is being loaded
    });
    try {
      // Request location permissions from the user
      LocationPermission permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        // If permissions are denied, show a message and stop loading
        if (mounted) {
          _showMessage("Location permissions are denied. Map will not show your current location.", Colors.orange);
        }
        setState(() {
          _isLoadingLocation = false;
        });
        return;
      }
      // Get the current position with high accuracy
      Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      setState(() {
        _currentLocation = LatLng(pos.latitude, pos.longitude); // Set the current location
        _isLoadingLocation = false; // Loading complete
      });
    } catch (e) {
      // Handle any errors during location fetching
      if (mounted) {
        _showMessage("Could not get current location for map: ${e.toString()}", Colors.red);
      }
      print('Map location error: $e'); // Log the error for debugging
      setState(() {
        _isLoadingLocation = false; // Loading complete (with error)
      });
    }
  }

  // Handles user logout
  Future<void> _signOut(BuildContext context) async {
    try {
      await FirebaseAuth.instance.signOut(); // Sign out from Firebase
      // The `main.dart`'s `StreamBuilder` will automatically detect the logout
      // and navigate the user back to the `WelcomePage`.
    } catch (e) {
      // Show an error message if logout fails
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error signing out: ${e.toString()}'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10.0),
            ),
            margin: const EdgeInsets.all(10),
          ),
        );
      }
    }
  }

  // Helper function to display snackbar messages
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
    final user = FirebaseAuth.instance.currentUser; // Get the current authenticated user

    if (user != null) {
      print('HomePage: User logged in: ${user.email}, UID: ${user.uid}');
    } else {
      print('HomePage: No user logged in. (This should be handled by main.dart routing)');
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Rider Dashboard'),
        centerTitle: true,
        backgroundColor: Colors.blueAccent,
        foregroundColor: Colors.white,
        leading: Builder(
          builder: (BuildContext context) {
            return IconButton(
              icon: const Icon(Icons.menu), // Hamburger menu icon
              onPressed: () {
                Scaffold.of(context).openDrawer(); // Open the navigation drawer
              },
              tooltip: MaterialLocalizations.of(context).openAppDrawerTooltip,
            );
          },
        ),
        actions: [
          // This logout button is kept for quick access, but also added to drawer
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => _signOut(context),
            tooltip: 'Logout',
          ),
        ],
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: <Widget>[
            DrawerHeader(
              decoration: BoxDecoration(
                color: Colors.blueAccent.shade700,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // StreamBuilder to dynamically display user's profile picture from Firestore
                  StreamBuilder<DocumentSnapshot>(
                    stream: FirebaseFirestore.instance.collection('riders').doc(user?.uid).snapshots(),
                    builder: (context, snapshot) {
                      String? profileImageUrl;
                      if (snapshot.hasData && snapshot.data!.exists) {
                        profileImageUrl = (snapshot.data!.data() as Map<String, dynamic>)['profileImageUrl'];
                      }
                      return CircleAvatar(
                        radius: 30,
                        backgroundColor: Colors.white,
                        backgroundImage: profileImageUrl != null && profileImageUrl.isNotEmpty
                            ? NetworkImage(profileImageUrl) // Display image from URL
                            : null, // No image, show child icon
                        child: (profileImageUrl == null || profileImageUrl.isEmpty)
                            ? Icon(Icons.person, size: 40, color: Colors.blueAccent.shade700) // Default icon
                            : null,
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    user?.email ?? 'Rider App User',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    user?.uid ?? '',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.person_outline, color: Colors.blueGrey),
              title: const Text('My Rider Profile', style: TextStyle(fontSize: 16)),
              onTap: () {
                Navigator.pop(context); // Close drawer
                // Navigate to the RiderDetailsPage to view/edit profile and upload photo
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const RiderDetailsPage()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.map, color: Colors.blueGrey),
              title: const Text('Start New Ride', style: TextStyle(fontSize: 16)),
              onTap: () {
                Navigator.pop(context); // Close the drawer
                // CHANGED: Navigate to CurrentLocationPage to start the flow
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const CurrentLocationPage()),
                );
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.settings, color: Colors.blueGrey),
              title: const Text('Settings', style: TextStyle(fontSize: 16)),
              onTap: () {
                Navigator.pop(context);
                _showMessage('Settings page not implemented yet.', Colors.blueGrey);
              },
            ),
            ListTile(
              leading: const Icon(Icons.info_outline, color: Colors.blueGrey),
              title: const Text('About', style: TextStyle(fontSize: 16)),
              onTap: () {
                Navigator.pop(context);
                _showMessage('About page not implemented yet.', Colors.blueGrey);
              },
            ),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.redAccent), // Logout icon
              title: const Text('Logout', style: TextStyle(fontSize: 16, color: Colors.redAccent)),
              onTap: () {
                Navigator.pop(context); // Close drawer
                _signOut(context); // Call the logout function
              },
            ),
          ],
        ),
      ),
      body: user == null
          ? const Center(child: Text('Please log in to view your dashboard.'))
          : SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // Welcome Message
            Center(
              child: Column(
                children: [
                  Icon(Icons.directions_bike, size: 100, color: Colors.blueAccent.shade700),
                  const SizedBox(height: 16),
                  Text(
                    'Welcome, ${user.email?.split('@')[0] ?? 'Rider'}!',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.blueGrey[800],
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Ready for your next ride?',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.grey[600],
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),

            // Map Section displaying current location
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15.0)),
              margin: const EdgeInsets.only(bottom: 24.0),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Your Current Location',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.blueGrey[700],
                      ),
                    ),
                    const Divider(height: 20, thickness: 1),
                    Container(
                      height: 200, // Fixed height for the map
                      width: double.infinity,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10.0),
                        border: Border.all(color: Colors.blueAccent.shade100, width: 2),
                      ),
                      child: _isLoadingLocation
                          ? const Center(child: CircularProgressIndicator()) // Show loading indicator
                          : _currentLocation == null
                          ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.error_outline, size: 60, color: Colors.redAccent),
                            const SizedBox(height: 10),
                            Text(
                              'Location not available.',
                              style: TextStyle(color: Colors.redAccent),
                            ),
                          ],
                        ),
                      )
                          : FlutterMap(
                        options: MapOptions(
                          initialCenter: _currentLocation!,
                          initialZoom: 14.0,
                          minZoom: 5.0,
                          maxZoom: 18.0,
                          // Use `interactionOptions` to control map interactions
                          interactionOptions: InteractionOptions(
                            flags: InteractiveFlag.all & ~InteractiveFlag.rotate, // Allow pan/zoom, but not rotate
                          ),
                        ),
                        children: [
                          TileLayer(
                            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'com.example.rider_app', // Important for OpenStreetMap policy
                          ),
                          MarkerLayer(
                            markers: [
                              Marker(
                                point: _currentLocation!,
                                width: 50,
                                height: 50,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.blue.withOpacity(0.8),
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white, width: 2),
                                  ),
                                  child: const Icon(Icons.my_location, color: Colors.white, size: 30),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Action Button to Start a New Ride (Bigger and more prominent)
            ElevatedButton.icon(
              onPressed: () {
                // CHANGED: Navigate to CurrentLocationPage to start the delivery flow
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const CurrentLocationPage()),
                );
              },
              icon: const Icon(Icons.directions_bike_sharp, size: 30), // Larger icon
              label: const Text('Start New Ride', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)), // Larger text
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20), // Bigger padding
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30.0),
                ),
                backgroundColor: Colors.green.shade600,
                foregroundColor: Colors.white,
                elevation: 8, // More prominent shadow
                minimumSize: const Size.fromHeight(70), // Ensure a minimum height
              ),
            ),
            const SizedBox(height: 16),
            // The "View/Edit Profile" OutlinedButton has been removed from here as requested.
            // It is now accessible via the drawer's "My Rider Profile" option.
          ],
        ),
      ),
    );
  }
}
