#!/usr/bin/env python3
"""
Greedy Ride Matcher - Python
Matches pending passengers (public_ride_requests) -> riders (riders)
Writes proposals to rider DB collection driver_proposals.

Notes:
- Requires firebase_admin with access to service account JSON files.
- Uses a real-time Firestore listener on passenger DB (pending requests).
- Added automatic passenger status progression based on driver/proposal actions:
    pending -> accepted -> arrived_at_pickup -> picked_up -> on_way -> completed
"""
import os
import time
import traceback
from math import radians, sin, cos, sqrt, atan2

import firebase_admin
from firebase_admin import credentials, firestore
from firebase_admin.firestore import GeoPoint

# ----------------- CONFIG -----------------
PASSENGER_DB_CREDENTIALS = os.environ.get(
    "PASSENGER_DB_CREDENTIALS",
    "passenger-ride-app-firebase-adminsdk-fbsvc-1061e4a556.json",
)
RIDER_DB_CREDENTIALS = os.environ.get(
    "RIDER_DB_CREDENTIALS",
    "rider-ba88e-firebase-adminsdk-fbsvc-57d40ed3f7.json",
)

PASSENGER_REQUESTS_COL = "public_ride_requests"
RIDERS_COL = "riders"
DRIVER_PROPOSALS_COL = "driver_proposals"

MAX_MATCH_DISTANCE_KM = float(os.environ.get("MAX_MATCH_DISTANCE_KM", 5.0))
MAX_DESTINATION_DEVIATION_KM = float(os.environ.get("MAX_DESTINATION_DEVIATION_KM", 5.0))

ELIGIBLE_DRIVER_STATUSES = (
    "on_route_to_original_destination",
    "available",
    "idle",
    "on_route_to_pickup",
    "en_route",
)

# How close driver must be to count as "arrived" (km)
ARRIVED_DISTANCE_THRESHOLD_KM = float(os.environ.get("ARRIVED_DISTANCE_THRESHOLD_KM", 0.05))  # 50 meters

# ----------------- Utilities -----------------

def log(msg: str):
    print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] {msg}")

def init_firestore_app(cred_path: str, name: str):
    """Initialize Firestore client for a Firebase app."""
    if not os.path.exists(cred_path):
        log(f"ERROR: credential file not found: {cred_path}")
        return None
    try:
        cred = credentials.Certificate(cred_path)
        try:
            app = firebase_admin.get_app(name)
            log(f"Re-using Firebase app '{name}'.")
        except ValueError:
            app = firebase_admin.initialize_app(cred, name=name)
            log(f"Initialized Firebase app '{name}'.")
        return firestore.client(app=app)
    except Exception as e:
        log(f"Error initializing Firebase app '{name}': {e}")
        traceback.print_exc()
        return None

def haversine_km(lat1, lon1, lat2, lon2):
    """Haversine distance between two points in kilometers."""
    lat1_rad, lon1_rad, lat2_rad, lon2_rad = map(radians, map(float, [lat1, lon1, lat2, lon2]))
    dlat = lat2_rad - lat1_rad
    dlon = lon2_rad - lon1_rad
    a = sin(dlat / 2) ** 2 + cos(lat1_rad) * cos(lat2_rad) * sin(dlon / 2) ** 2
    return 2 * 6371.0 * atan2(sqrt(a), sqrt(1 - a))

def to_geopoint(loc):
    """Normalize input to a Firestore GeoPoint."""
    if loc is None:
        return None
    if isinstance(loc, GeoPoint):
        return loc
    if isinstance(loc, dict):
        lat = next((loc.get(k) for k in ("latitude", "lat", "Latitude") if loc.get(k) is not None), None)
        lon = next((loc.get(k) for k in ("longitude", "lng", "lon", "Longitude") if loc.get(k) is not None), None)
        for cand in ("coords", "location", "geo", "position"):
            if cand in loc and isinstance(loc[cand], dict):
                nested = loc[cand]
                lat = nested.get("latitude") or nested.get("lat") or lat
                lon = nested.get("longitude") or nested.get("lng") or nested.get("lon") or lon
                if lat is not None and lon is not None:
                    break
        if lat is not None and lon is not None:
            try:
                return GeoPoint(float(lat), float(lon))
            except Exception:
                return None
    if hasattr(loc, "latitude") and hasattr(loc, "longitude"):
        try:
            return GeoPoint(float(loc.latitude), float(loc.longitude))
        except Exception:
            return None
    return None

def calculate_incremental_detour_km(driver_start, driver_end, pickup, dropoff):
    """Incremental detour in km if driver picks up this passenger."""
    base = haversine_km(driver_start.latitude, driver_start.longitude, driver_end.latitude, driver_end.longitude)
    new_total = (
        haversine_km(driver_start.latitude, driver_start.longitude, pickup.latitude, pickup.longitude)
        + haversine_km(pickup.latitude, pickup.longitude, dropoff.latitude, dropoff.longitude)
        + haversine_km(dropoff.latitude, dropoff.longitude, driver_end.latitude, driver_end.longitude)
    )
    return new_total - base, base, new_total

# ----------------- Matching Logic -----------------

def create_proposal_payload(passenger_doc, passenger_data, driver_doc_id, driver_data, final_pickup):
    """Prepare proposal payload with all necessary info for rider."""
    passenger_uid = passenger_data.get("passengerId") or passenger_data.get("passengerUid") or passenger_data.get("riderUid")
    pickup_loc = to_geopoint(passenger_data.get("pickupLocation") or passenger_data.get("pickup_location") or passenger_data.get("pickup"))
    dest_loc = to_geopoint(passenger_data.get("destinationLocation") or passenger_data.get("destination") or passenger_data.get("destination_location"))

    driver_loc = to_geopoint(driver_data.get("currentRouteStart") or driver_data.get("nextTargetLocation") or driver_data.get("current_location") or driver_data.get("currentLocation"))

    payload = {
        "request_id": passenger_doc.id,
        "status": "pending_acceptance",
        "createdAt": firestore.SERVER_TIMESTAMP,
        # --- Passenger Info ---
        "passengerUid": passenger_uid,
        "passengerName": passenger_data.get("passengerName") or passenger_data.get("name") or "Unknown Passenger",
        "passengerPhone": passenger_data.get("passengerPhone") or passenger_data.get("phone") or "Not Provided",
        "pickupLocation": final_pickup,
        "destinationLocation": dest_loc,
        "pickup_address": passenger_data.get("pickupAddress") or passenger_data.get("pickup_address"),
        "destination_address": passenger_data.get("destinationAddress") or passenger_data.get("destination_address"),
        "fareAmount": passenger_data.get("fareAmount") or 0.0,
        "paymentMethod": passenger_data.get("paymentMethod") or "Cash",
        "rideType": passenger_data.get("rideType") or "Standard",
        "passengerRating": passenger_data.get("passengerRating") or 5.0,
        "estimatedDistance": passenger_data.get("estimatedDistance") or "N/A",
        "estimatedDuration": passenger_data.get("estimatedDuration") or "N/A",
        "specialRequests": passenger_data.get("specialRequests") or "None",
        "vehiclePreference": passenger_data.get("vehiclePreference") or "Any",
        "luggageCount": passenger_data.get("luggageCount") or 0,
        "passengerCount": passenger_data.get("passengerCount") or 1,
        "otp": passenger_data.get("otp") or "0000",
        "otpVerified": passenger_data.get("otpVerified") or False,
        "sosActive": passenger_data.get("sosActive") or False,
        "sosReason": passenger_data.get("sosReason"),
        "sosTimestamp": passenger_data.get("sosTimestamp"),
        # --- Driver Info ---
        "riderUid": driver_data.get("uid") or driver_doc_id,
        "driverId": driver_data.get("uid") or driver_doc_id,
        "driverName": driver_data.get("name") or driver_data.get("driverName") or "Unknown Driver",
        "driverPhone": driver_data.get("phone") or "Not Provided",
        "driverVehicle": driver_data.get("vehicleType") or "Unknown Vehicle",
        "riderLocation": driver_loc,
        "lastLocationUpdate": firestore.SERVER_TIMESTAMP,
        # --- Route Info ---
        "routeToPickupEncoded": passenger_data.get("routeToPickupEncoded"),
        "routeToDestinationEncoded": passenger_data.get("routeToDestinationEncoded"),
        # --- Timestamps ---
        "acceptedTimestamp": None,
        "arrivalTimestamp": None,
        "pickupTimestamp": None,
        "completionTimestamp": None,
        "cancellationTimestamp": None,
        "distanceToPickup": None,
    }

    # compute distanceToPickup safely
    try:
        if pickup_loc and driver_loc:
            payload["distanceToPickup"] = haversine_km(
                pickup_loc.latitude, pickup_loc.longitude,
                driver_loc.latitude, driver_loc.longitude
            )
    except Exception:
        payload["distanceToPickup"] = None

    return payload

def try_reserve_driver_and_create_proposal(rider_db, passenger_db, passenger_doc, driver_doc_id, driver_data, proposal_payload):
    """Reserve driver and write proposal atomically, then update passenger doc."""
    rider_ref = rider_db.collection(RIDERS_COL).document(driver_doc_id)
    proposal_ref = rider_db.collection(DRIVER_PROPOSALS_COL).document()

    @firestore.transactional
    def txn_reserve(transaction):
        snapshot = rider_ref.get(transaction=transaction)
        if not snapshot.exists:
            raise RuntimeError("Driver doc disappeared during reservation.")
        if snapshot.get("status") not in ELIGIBLE_DRIVER_STATUSES:
            raise RuntimeError(f"Driver {driver_doc_id} status not eligible.")
        transaction.update(rider_ref, {"status": "reserved_for_proposal", "reserved_for_request": passenger_doc.id})
        transaction.set(proposal_ref, proposal_payload)

    try:
        transaction = rider_db.transaction()
        txn_reserve(transaction)
    except Exception as e:
        log(f"Failed to reserve driver {driver_doc_id}: {e}")
        traceback.print_exc()
        return False, None

    try:
        # Update passenger with full driver info for Flutter to read directly
        passenger_db.collection(PASSENGER_REQUESTS_COL).document(passenger_doc.id).update({
            "status": "proposed",
            "riderUid": driver_data.get("uid") or driver_doc_id,
            "riderName": driver_data.get("name") or "Unknown Driver",
            "riderPhone": driver_data.get("phone") or "Not Provided",
            "riderLocation": driver_data.get("current_location") or driver_data.get("currentLocation"),
            "matchedDriverName": driver_data.get("name") or "Unknown Driver",
            "matchedDriverPhone": driver_data.get("phone") or "Not Provided",
            "matchedDriverVehicle": driver_data.get("vehicleType") or "Unknown Vehicle",
            "proposed_at": firestore.SERVER_TIMESTAMP,
            "proposal_id": proposal_ref.id,
        })
        log(f"Passenger {passenger_doc.id} updated to 'proposed' with driver {driver_doc_id}.")
        return True, proposal_ref.id
    except Exception as e:
        log(f"Failed to update passenger {passenger_doc.id}: {e}")
        traceback.print_exc()
        try:
            rider_db.collection(RIDERS_COL).document(driver_doc_id).update(
                {"status": driver_data.get("status", "available"), "reserved_for_request": firestore.DELETE_FIELD}
            )
        except Exception:
            log(f"Warning: failed to revert reservation for driver {driver_doc_id}.")
        return False, None

def match_one_request(passenger_db, rider_db, passenger_doc):
    """Match a single passenger request to the best available driver."""
    try:
        passenger_data = passenger_doc.to_dict() or {}
        if not passenger_data or passenger_data.get("status", "").lower() != "pending_acceptance":
            return

        pickup = to_geopoint(passenger_data.get("pickupLocation") or passenger_data.get("pickup_location") or passenger_data.get("pickup"))
        dest = to_geopoint(passenger_data.get("destinationLocation") or passenger_data.get("destination") or passenger_data.get("destination_location"))
        vehicle_pref = passenger_data.get("vehiclePreference") or "Any"

        if not (pickup and dest):
            log(f"Passenger {passenger_doc.id}: pickup/destination invalid - skipping.")
            return

        log(f"Matching passenger {passenger_doc.id} at ({pickup.latitude:.6f},{pickup.longitude:.6f})")

        riders_q = rider_db.collection(RIDERS_COL).where("status", "in", list(ELIGIBLE_DRIVER_STATUSES))
        riders = list(riders_q.stream())
        if not riders:
            log("No eligible drivers available.")
            return

        best = None
        best_cost = float("inf")
        best_pickup_dist = float("inf")

        for rdoc in riders:
            try:
                rdata = rdoc.to_dict() or {}
                driver_start = to_geopoint(rdata.get("currentRouteStart") or rdata.get("nextTargetLocation") or rdata.get("current_location") or rdata.get("currentLocation"))
                driver_end = to_geopoint(rdata.get("currentRouteEnd") or rdata.get("destination") or rdata.get("currentDestination"))

                if not (driver_start and driver_end):
                    continue

                driver_vehicle = (rdata.get("vehicleType") or "").lower()
                if vehicle_pref != "Any" and vehicle_pref.lower() not in driver_vehicle:
                    continue

                pickup_dist = haversine_km(driver_start.latitude, driver_start.longitude, pickup.latitude, pickup.longitude)
                if pickup_dist > MAX_MATCH_DISTANCE_KM:
                    continue

                dest_dev = haversine_km(driver_end.latitude, driver_end.longitude, dest.latitude, dest.longitude)
                if dest_dev > MAX_DESTINATION_DEVIATION_KM:
                    continue

                inc_detour, _, _ = calculate_incremental_detour_km(driver_start, driver_end, pickup, dest)
                if inc_detour < best_cost or (abs(inc_detour - best_cost) < 1e-6 and pickup_dist < best_pickup_dist):
                    best_cost = inc_detour
                    best = (rdoc.id, rdata, driver_start, driver_end, pickup_dist, inc_detour)
                    best_pickup_dist = pickup_dist
            except Exception:
                log("Warning: error evaluating driver; skipping.")
                traceback.print_exc()

        if not best:
            log(f"No suitable driver for passenger {passenger_doc.id}.")
            return

        driver_doc_id, driver_data, driver_start, driver_end, pickup_dist, inc_detour = best
        log(f"Selected driver {driver_doc_id}: pickup_dist={pickup_dist:.3f} km, incremental_detour={inc_detour:.3f} km")

        final_pickup = GeoPoint((driver_start.latitude + pickup.latitude) / 2, (driver_start.longitude + pickup.longitude) / 2) if pickup_dist < 2.0 else pickup

        proposal_payload = create_proposal_payload(passenger_doc, passenger_data, driver_doc_id, driver_data, final_pickup)
        success, proposal_id = try_reserve_driver_and_create_proposal(rider_db, passenger_db, passenger_doc, driver_doc_id, driver_data, proposal_payload)

        if success:
            log(f"Proposal created (id={proposal_id}) for passenger {passenger_doc.id} -> driver {driver_doc_id}")
        else:
            log(f"Failed to finalize proposal for passenger {passenger_doc.id}")

    except Exception as e:
        log(f"Error matching passenger {passenger_doc.id}: {e}")
        traceback.print_exc()

# ----------------- Status mapping helpers -----------------

def _safe_get(data, *keys, default=None):
    for k in keys:
        if data is None:
            break
        if isinstance(data, dict) and k in data:
            return data.get(k)
    return default

def map_proposal_status_to_passenger(proposal_status):
    """Map a driver_proposal.status to a passenger request status."""
    ps = (proposal_status or "").lower()
    if ps in ("accepted", "driver_accepted"):
        return "accepted"
    if ps in ("driver_arrived", "arrived", "arrived_at_pickup"):
        return "arrived_at_pickup"
    if ps in ("otp_verified",) :
        # OTP alone might not mean picked; wait for face verification or picked_up explicit.
        return "otp_verified"
    if ps in ("face_verified",):
        return "face_verified"
    if ps in ("picked_up", "pickedup"):
        return "picked_up"
    if ps in ("on_way", "on_the_way", "en_route"):
        return "on_way"
    if ps in ("completed", "finished"):
        return "completed"
    if ps in ("rejected", "cancelled", "declined"):
        return "rejected"
    return None

# ----------------- Driver Proposal Listener (progress updates) -----------------

def listen_for_driver_proposal_progress(rider_db, passenger_db):
    """Listen for updates on driver proposals and propagate to passenger request statuses."""
    # watch for proposals changing to statuses we care about
    interesting_statuses = [
        "accepted", "driver_arrived", "otp_verified", "face_verified",
        "picked_up", "on_way", "completed", "rejected", "arrived", "pickedup", "driver_accepted", "finished"
    ]

    def on_proposals_snapshot(col_snapshot, changes, read_time):
        for change in changes:
            try:
                doc = change.document
                data = doc.to_dict() or {}
                # only handle modifications (status transitions)
                if change.type.name not in ("ADDED", "MODIFIED"):
                    continue

                proposal_status = (data.get("status") or "").lower()
                mapped = map_proposal_status_to_passenger(proposal_status)
                request_id = data.get("request_id") or data.get("requestId") or data.get("request")
                rider_uid = data.get("riderUid") or data.get("driverId") or data.get("riderId") or (data.get("riderUid") if isinstance(data, dict) else None)

                if not request_id:
                    # nothing to update
                    continue

                # Ensure passenger doc exists before attempting updates
                pdoc_ref = passenger_db.collection(PASSENGER_REQUESTS_COL).document(request_id)
                try:
                    pdoc_snapshot = pdoc_ref.get()
                except Exception as e:
                    log(f"Warning: failed to fetch passenger doc {request_id} (proposal {doc.id}): {e}")
                    continue

                if not pdoc_snapshot.exists:
                    log(f"Warning: passenger document {request_id} not found; skipping proposal update {doc.id}.")
                    # Optional: delete orphan proposal to keep rider DB clean
                    # try:
                    #     rider_db.collection(DRIVER_PROPOSALS_COL).document(doc.id).delete()
                    #     log(f"Deleted orphan proposal {doc.id} (missing passenger {request_id}).")
                    # except Exception:
                    #     log(f"Warning: failed to delete orphan proposal {doc.id}")
                    continue

                # If mapping not recognized, skip
                if mapped is None:
                    continue

                # Special handling for some intermediate states:
                if mapped == "otp_verified":
                    # mark otpVerified on passenger; do not change status to picked_up yet
                    try:
                        current = pdoc_snapshot.to_dict() or {}
                        if not current.get("otpVerified", False):
                            pdoc_ref.update({
                                "otpVerified": True,
                                "otp_verified_at": firestore.SERVER_TIMESTAMP,
                            })
                            log(f"Passenger {request_id}: OTP verified (proposal {doc.id}).")
                        else:
                            # already set; skip
                            pass
                    except Exception as e:
                        log(f"Failed to set otpVerified for {request_id}: {e}")
                        traceback.print_exc()
                    continue

                if mapped == "face_verified":
                    # mark faceVerified
                    try:
                        current = pdoc_snapshot.to_dict() or {}
                        if not current.get("faceVerified", False):
                            pdoc_ref.update({
                                "faceVerified": True,
                                "face_verified_at": firestore.SERVER_TIMESTAMP,
                            })
                            log(f"Passenger {request_id}: Face verified (proposal {doc.id}).")
                        else:
                            pass
                    except Exception as e:
                        log(f"Failed to set faceVerified for {request_id}: {e}")
                        traceback.print_exc()
                    continue

                if mapped == "rejected":
                    # Proposal rejected by driver - revert passenger to 'pending' or 'no_driver' (app logic)
                    try:
                        # Re-fetch to ensure current state
                        current = pdoc_ref.get().to_dict() or {}
                        # Only revert if passenger currently in proposed/related state
                        if current.get("status") in ("proposed", "pending_accepted", "accepted"):
                            pdoc_ref.update({
                                "status": "pending",
                                "proposed_driver": firestore.DELETE_FIELD,
                                "riderUid": firestore.DELETE_FIELD,
                                "matchedDriverName": firestore.DELETE_FIELD,
                                "matchedDriverPhone": firestore.DELETE_FIELD,
                                "matchedDriverVehicle": firestore.DELETE_FIELD,
                                "proposed_at": firestore.DELETE_FIELD,
                                "proposal_id": firestore.DELETE_FIELD,
                            })
                        # free rider reservation if rider uid present
                        if rider_uid:
                            try:
                                rider_db.collection(RIDERS_COL).document(rider_uid).update({
                                    "status": "available",
                                    "reserved_for_request": firestore.DELETE_FIELD
                                })
                            except Exception:
                                log(f"Warning: failed to clear reservation for rider {rider_uid}")
                        log(f"Passenger {request_id}: proposal rejected; reverted to pending if applicable.")
                    except Exception as e:
                        log(f"Failed to revert passenger {request_id} after proposal rejection: {e}")
                        traceback.print_exc()
                    continue

                # For arrival, picked_up, on_way, completed -> set passenger status accordingly and add timestamps
                update_payload = {}
                ts_field = None

                if mapped == "accepted":
                    update_payload["status"] = "accepted"
                    update_payload["accepted_at"] = firestore.SERVER_TIMESTAMP
                    ts_field = "accepted_at"
                elif mapped == "arrived_at_pickup":
                    update_payload["status"] = "arrived_at_pickup"
                    update_payload["arrived_at"] = firestore.SERVER_TIMESTAMP
                    ts_field = "arrived_at"
                elif mapped == "picked_up":
                    update_payload["status"] = "picked_up"
                    update_payload["pickupTimestamp"] = firestore.SERVER_TIMESTAMP
                    update_payload["picked_up_at"] = firestore.SERVER_TIMESTAMP
                    ts_field = "picked_up_at"
                elif mapped == "on_way":
                    update_payload["status"] = "on_way"
                    update_payload["on_way_at"] = firestore.SERVER_TIMESTAMP
                    ts_field = "on_way_at"
                elif mapped == "completed":
                    update_payload["status"] = "completed"
                    update_payload["completed_at"] = firestore.SERVER_TIMESTAMP
                    ts_field = "completed_at"

                # Add driver summary fields so passenger UI can display live info
                driver_name = data.get("driverName") or data.get("driver_name") or data.get("driver") or data.get("driverFullName")
                driver_phone = data.get("driverPhone") or data.get("driver_phone") or data.get("driver_contact")
                rider_location = data.get("riderLocation") or data.get("driverLocation") or data.get("rider_location")

                if driver_name:
                    update_payload["matchedDriverName"] = driver_name
                if driver_phone:
                    update_payload["matchedDriverPhone"] = driver_phone
                if rider_uid:
                    update_payload["riderUid"] = rider_uid
                    update_payload["riderId"] = rider_uid

                if rider_location:
                    update_payload["riderLocation"] = rider_location
                    update_payload["lastLocationUpdate"] = firestore.SERVER_TIMESTAMP

                # apply update but only if it actually changes something
                try:
                    current = pdoc_ref.get().to_dict() or {}
                    # If current status is already the same as intended, skip to avoid spamming
                    if update_payload.get("status") and current.get("status") == update_payload.get("status"):
                        # Maybe still update ephemeral fields like riderLocation — handle those:
                        ephemeral = {k: v for k, v in update_payload.items() if k not in ("status",)}
                        if ephemeral:
                            pdoc_ref.update(ephemeral)
                        log(f"Passenger {request_id} already '{current.get('status')}', applied ephemeral updates if any (proposal {doc.id}).")
                    else:
                        pdoc_ref.update(update_payload)
                        log(f"Passenger {request_id} updated to '{update_payload.get('status')}' (proposal {doc.id}).")
                except Exception as e:
                    log(f"Failed to update passenger {request_id} for proposal {doc.id}: {e}")
                    traceback.print_exc()

                # Also update driver/rider doc statuses to keep them in sync
                try:
                    if rider_uid and mapped in ("accepted", "arrived_at_pickup", "picked_up", "on_way", "completed"):
                        # derive driver status mapping
                        driver_status_map = {
                            "accepted": "on_route_to_pickup",
                            "arrived_at_pickup": "on_site_pickup",
                            "picked_up": "en_route",
                            "on_way": "en_route",
                            "completed": "idle",
                        }
                        new_driver_status = driver_status_map.get(mapped)
                        if new_driver_status:
                            rider_db.collection(RIDERS_COL).document(rider_uid).update({
                                "status": new_driver_status,
                                "current_ride_request": request_id if mapped != "completed" else firestore.DELETE_FIELD,
                            })
                except Exception:
                    log(f"Warning: failed to sync rider doc for rider {rider_uid}")

            except Exception as e:
                log(f"Error processing proposal snapshot change: {e}")
                traceback.print_exc()

    try:
        query = rider_db.collection(DRIVER_PROPOSALS_COL).where("status", "in", interesting_statuses)
        query.on_snapshot(on_proposals_snapshot)
        log("Driver proposal progress listener attached.")
    except Exception as e:
        log(f"Failed to attach driver proposal progress listener: {e}")
        traceback.print_exc()

# ----------------- Rider Location Updates -----------------

def listen_for_rider_location_updates(rider_db, passenger_db):
    """Listen for rider location updates and update passenger request in real-time.
    Also optionally detect 'arrived' if driver gets close to pickupLocation (best-effort).
    """
    def on_rider_location_snapshot(col_snapshot, changes, read_time):
        for change in changes:
            try:
                if change.type.name in ("MODIFIED", "ADDED"):
                    doc = change.document
                    data = doc.to_dict() or {}

                    rider_uid = doc.id
                    current_location = data.get("currentLocation") or data.get("current_location") or data.get("riderLocation")
                    current_ride_request = data.get("current_ride_request") or data.get("currentRideRequest") or data.get("current_ride")

                    if not current_location:
                        continue

                    # update passenger request last known location for UI
                    if current_ride_request:
                        try:
                            # ensure passenger exists
                            pdoc_ref = passenger_db.collection(PASSENGER_REQUESTS_COL).document(current_ride_request)
                            try:
                                pdoc_snapshot = pdoc_ref.get()
                            except Exception as e:
                                log(f"Warning: failed to fetch passenger doc {current_ride_request} while updating location: {e}")
                                continue

                            if not pdoc_snapshot.exists:
                                log(f"Warning: passenger doc {current_ride_request} missing when updating rider location; skipping.")
                            else:
                                pdoc_ref.update({
                                    "riderLocation": current_location,
                                    "lastLocationUpdate": firestore.SERVER_TIMESTAMP,
                                })
                                log(f"Updated rider location for request {current_ride_request}")
                        except Exception as e:
                            log(f"Failed to update passenger ride location for {current_ride_request}: {e}")
                            traceback.print_exc()

                    # BEST-EFFORT: detect arrival if rider has no explicit proposal 'arrived' but driver comes very close to pickup
                    try:
                        # only attempt when driver indicates en route to pickup or similar
                        driver_status = data.get("status", "").lower()
                        if current_ride_request and driver_status in ("on_route_to_pickup", "on_route_to_original_destination", "reserved_for_proposal"):
                            # fetch passenger pickup point
                            pdoc_ref = passenger_db.collection(PASSENGER_REQUESTS_COL).document(current_ride_request)
                            try:
                                pdoc = pdoc_ref.get()
                            except Exception:
                                pdoc = None
                            if pdoc and pdoc.exists:
                                p = pdoc.to_dict() or {}
                                pickup = to_geopoint(p.get("pickupLocation") or p.get("pickup_location") or p.get("pickup"))
                                if pickup:
                                    # compute distance
                                    try:
                                        drv_lat = current_location.get("latitude") or current_location.get("lat") or current_location.get("Latitude")
                                        drv_lon = current_location.get("longitude") or current_location.get("lng") or current_location.get("lon") or current_location.get("Longitude")
                                        if drv_lat is not None and drv_lon is not None:
                                            dist = haversine_km(float(drv_lat), float(drv_lon), pickup.latitude, pickup.longitude)
                                            if dist <= ARRIVED_DISTANCE_THRESHOLD_KM:
                                                # set passenger to arrived_at_pickup if not already
                                                try:
                                                    cur_state = pdoc.to_dict() or {}
                                                    if cur_state.get("status") != "arrived_at_pickup":
                                                        pdoc_ref.update({
                                                            "status": "arrived_at_pickup",
                                                            "arrived_at": firestore.SERVER_TIMESTAMP,
                                                        })
                                                        log(f"Auto-marked passenger {current_ride_request} as 'arrived_at_pickup' (driver {rider_uid} within {dist:.3f} km).")
                                                except Exception:
                                                    pass
                                    except Exception:
                                        # if anything fails, ignore best-effort arrival detection
                                        pass
                    except Exception:
                        pass

            except Exception as e:
                log(f"Error processing rider location update: {e}")
                traceback.print_exc()

    try:
        query = rider_db.collection(RIDERS_COL)
        query.on_snapshot(on_rider_location_snapshot)
        log("Rider location update listener attached.")
    except Exception as e:
        log(f"Failed to attach rider location listener: {e}")
        traceback.print_exc()

# ----------------- Firestore Listener for Pending Requests -----------------

def on_pending_requests_snapshot(col_snapshot, changes, read_time):
    """Firestore listener callback for new or modified pending requests."""
    for change in changes:
        try:
            if change.type.name in ("ADDED", "MODIFIED"):
                doc = change.document
                data = doc.to_dict() or {}
                if data.get("status", "").lower() == "pending":
                    match_one_request(db_passenger, db_rider, doc)
        except Exception:
            log("Error in snapshot handler.")
            traceback.print_exc()

# ----------------- Main -----------------

if __name__ == "__main__":
    db_passenger = init_firestore_app(PASSENGER_DB_CREDENTIALS, "passenger_app")
    db_rider = init_firestore_app(RIDER_DB_CREDENTIALS, "rider_app")

    if not db_passenger or not db_rider:
        log("FATAL: Firestore clients failed to initialize. Exiting.")
        raise SystemExit(1)

    log(f"Matcher: Listening to passenger requests ({PASSENGER_REQUESTS_COL})")

    try:
        # Start all listeners
        query = db_passenger.collection(PASSENGER_REQUESTS_COL).where("status", "==", "pending")
        query.on_snapshot(on_pending_requests_snapshot)

        # Listen for driver proposal progress (accept / arrived / otp / face / picked / on_way / completed / rejected)
        listen_for_driver_proposal_progress(db_rider, db_passenger)

        # Listen for rider location updates (and best-effort arrive detection)
        listen_for_rider_location_updates(db_rider, db_passenger)

        log("All listeners attached. Running... (Ctrl+C to stop)")

        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        log("Shutting down (KeyboardInterrupt).")
    except Exception as e:
        log(f"FATAL error in main loop: {e}")
        traceback.print_exc()
