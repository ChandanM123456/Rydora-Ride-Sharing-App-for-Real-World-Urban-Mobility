import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';

class RideRequest {
  final String userId;
  final LatLng pickupLocation;
  final LatLng destinationLocation;
  final Timestamp timestamp;
  final String status; // 'pending', 'accepted', 'completed', 'cancelled'

  final String? driverId;
  final LatLng? driverLocation;
  final String? routeToPickupEncoded;

  RideRequest({
    required this.userId,
    required this.pickupLocation,
    required this.destinationLocation,
    required this.timestamp,
    required this.status,
    this.driverId,
    this.driverLocation,
    this.routeToPickupEncoded,
  });

  Map<String, dynamic> toFirestore() {
    return {
      'user_id': userId,
      'pickup': {
        'lat': pickupLocation.latitude,
        'lng': pickupLocation.longitude,
      },
      'destination': {
        'lat': destinationLocation.latitude,
        'lng': destinationLocation.longitude,
      },
      'timestamp': timestamp,
      'status': status,
      if (driverId != null) 'driver_id': driverId,
      if (driverLocation != null)
        'driver_location': {
          'lat': driverLocation!.latitude,
          'lng': driverLocation!.longitude,
        },
      if (routeToPickupEncoded != null)
        'route_to_pickup': routeToPickupEncoded,
    };
  }

  static RideRequest fromFirestore(DocumentSnapshot doc) {
    final data = doc.data()! as Map<String, dynamic>;
    final pickup = data['pickup'] as Map<String, dynamic>;
    final dest = data['destination'] as Map<String, dynamic>;
    final driverLoc = data['driver_location'] as Map<String, dynamic>?;

    return RideRequest(
      userId: data['user_id'] as String,
      pickupLocation: LatLng(
        (pickup['lat'] as num).toDouble(),
        (pickup['lng'] as num).toDouble(),
      ),
      destinationLocation: LatLng(
        (dest['lat'] as num).toDouble(),
        (dest['lng'] as num).toDouble(),
      ),
      timestamp: (data['timestamp'] as Timestamp),
      status: data['status'] as String,
      driverId: data['driver_id'] as String?,
      driverLocation: driverLoc == null
          ? null
          : LatLng(
              (driverLoc['lat'] as num).toDouble(),
              (driverLoc['lng'] as num).toDouble(),
            ),
      routeToPickupEncoded: data['route_to_pickup'] as String?,
    );
  }
}
