import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'login_screen.dart';
import '../services/crash_detection_service.dart';
import '../services/emergency_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final CrashDetectionService _crashDetection = CrashDetectionService();

  bool _isRequesting = false;
  bool trackingStarted = false;
  bool isSharing = true;
  bool crashDetectionActive = false;

  GoogleMapController? mapController;
  StreamSubscription<Position>? positionStream;

  LatLng currentPosition = const LatLng(7.1907, 125.4553);
  Set<Marker> markers = {};

  final TextEditingController emailController = TextEditingController();

  // 🔥 FRIEND LISTENERS
  Map<String, StreamSubscription<DocumentSnapshot>> friendListeners = {};
  StreamSubscription<QuerySnapshot>? sosSubscription;

  // 🔥 TRUSTED CONTACTS
  List<Map<String, String>> trustedContacts = [];

  // � CRASH DETECTION
  Future<void> _onCrashDetected() async {
    if (!mounted) return;

    print('🚨 CRASH DETECTED - Showing confirmation dialog');

    // Show crash alert dialog
    bool confirmed =
        await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            backgroundColor: Colors.grey[900],
            title: const Text(
              '🚨 CRASH DETECTED',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
            content: const Text(
              'A possible crash has been detected. Your location is being shared with nearby community members. Tap "I\'m OK" to cancel SOS.',
              style: TextStyle(color: Colors.white),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text(
                  'I\'m OK',
                  style: TextStyle(color: Colors.green),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text(
                  'Emergency Help',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
        ) ??
        false;

    if (confirmed) {
      // User dismissed - cancel SOS
      print('✅ User dismissed crash alert');
      _crashDetection.dismissCrashAlert();
    } else {
      // Trigger SOS automatically
      print('📍 Triggering automatic SOS due to crash detection');
      final position = await EmergencyService.getCurrentLocation();
      if (position != null && mounted) {
        try {
          // Send SOS to emergency contacts (using default list)
          await EmergencyService.sendSOSAlert(
            [], // Will send to all contacts
            position.latitude,
            position.longitude,
          );

          // Activate community SOS
          await EmergencyService.activateSOSAlert(
            position.latitude,
            position.longitude,
          );

          _showSnackBar(
            'SOS triggered! Emergency contacts notified and location shared with nearby community.',
          );
        } catch (e) {
          print('Error triggering SOS: $e');
          _showSnackBar('Error triggering SOS');
        }
      }
    }
  }

  // �🔥 FETCH TRUSTED CONTACTS
  Future<void> _fetchTrustedContacts() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .get();

      final data = userDoc.data();
      if (data == null || data['trustedUsers'] == null) {
        setState(() => trustedContacts = []);
        return;
      }

      List trustedUserIds = data['trustedUsers'];
      final contacts = <Map<String, String>>[];

      for (String uid in trustedUserIds) {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .get();
        if (doc.exists) {
          contacts.add({'uid': uid, 'email': doc['email'] ?? 'Unknown'});
        }
      }

      setState(() => trustedContacts = contacts);
    } catch (e) {
      _showSnackBar('Error fetching contacts');
    }
  }

  // ---------------- ADD TRUSTED USER ----------------
  Future<void> addTrustedUserByEmail(String email) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    try {
      final query = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: email)
          .get();

      if (query.docs.isEmpty) {
        _showSnackBar('User not found');
        return;
      }

      final targetDoc = query.docs.first;
      final targetUid = targetDoc.id;

      if (targetUid == currentUser.uid) {
        _showSnackBar('You cannot add yourself');
        return;
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .set({
            'trustedUsers': FieldValue.arrayUnion([targetUid]),
          }, SetOptions(merge: true));

      _showSnackBar('Trusted contact added');
      await _fetchTrustedContacts();
    } catch (e) {
      _showSnackBar('Error adding user');
    }
  }

  Future<void> removeTrustedUser(String uid) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .set({
            'trustedUsers': FieldValue.arrayRemove([uid]),
          }, SetOptions(merge: true));

      _showSnackBar('Contact removed');
      await _fetchTrustedContacts();
    } catch (e) {
      _showSnackBar('Error removing contact');
    }
  }

  void _showAddContactDialog() {
    emailController.clear();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text(
          'Add Trusted Contact',
          style: TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: emailController,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Enter email',
            hintStyle: const TextStyle(color: Colors.grey),
            filled: true,
            fillColor: Colors.grey[800],
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final email = emailController.text.trim();
              if (email.isNotEmpty) {
                addTrustedUserByEmail(email);
                Navigator.pop(context);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  // ---------------- STOP TRACKING ----------------
  Future<void> _handleStopRideTracking() async {
    // 🚨 STOP CRASH DETECTION
    _crashDetection.stopMonitoring();

    setState(() {
      trackingStarted = false;
      crashDetectionActive = false;
    });

    _showSnackBar('Ride tracking stopped');
  }

  // ---------------- PERMISSION ----------------
  Future<bool> _ensureLocationPermission() async {
    final status = await Permission.locationWhenInUse.status;

    if (status.isGranted) return true;

    if (status.isDenied || status.isRestricted) {
      final result = await Permission.locationWhenInUse.request();
      return result.isGranted;
    }

    if (status.isPermanentlyDenied) {
      await openAppSettings();
      return false;
    }

    return false;
  }

  // ---------------- START TRACKING ----------------
  Future<void> _handleStartRideTracking() async {
    if (_isRequesting) return;

    setState(() => _isRequesting = true);

    final granted = await _ensureLocationPermission();

    if (!granted) {
      _showSnackBar('Location permission is required.');
      setState(() => _isRequesting = false);
      return;
    }

    _startLocationStream();
    await _listenToTrustedUsers(); // 🔥 start listening to friends
    await _fetchTrustedContacts();
    _listenToCommunitySOS(); // 🔥 start listening to nearby SOS alerts

    // 🚨 START CRASH DETECTION
    await _crashDetection.startMonitoring(onCrashDetected: _onCrashDetected);

    setState(() {
      trackingStarted = true;
      crashDetectionActive = true;
      _isRequesting = false;
    });
  }

  // ---------------- LOCATION STREAM ----------------
  void _startLocationStream() {
    positionStream =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 5,
          ),
        ).listen((Position position) async {
          LatLng newPos = LatLng(position.latitude, position.longitude);

          setState(() {
            currentPosition = newPos;

            // 🔴 Update self marker
            markers.removeWhere((m) => m.markerId.value == "me");

            markers.add(
              Marker(
                markerId: const MarkerId("me"),
                position: newPos,
                infoWindow: const InfoWindow(title: "You"),
              ),
            );
          });

          mapController?.animateCamera(CameraUpdate.newLatLng(newPos));

          // 🔥 FIRESTORE UPDATE
          if (isSharing) {
            final user = FirebaseAuth.instance.currentUser;
            if (user == null) return;

            await FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid)
                .set({
                  'email': user.email,
                  'sharing': true,
                  'location': {
                    'lat': position.latitude,
                    'lng': position.longitude,
                  },
                  'updatedAt': FieldValue.serverTimestamp(),
                }, SetOptions(merge: true));
          }
        });
  }

  // ---------------- LISTEN TO FRIENDS ----------------
  Future<void> _listenToTrustedUsers() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(currentUser.uid)
        .get();

    final data = userDoc.data();
    if (data == null || data['trustedUsers'] == null) return;

    List trustedUsers = data['trustedUsers'];

    for (String uid in trustedUsers) {
      if (friendListeners.containsKey(uid)) continue;

      final sub = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .snapshots()
          .listen((doc) {
            if (!doc.exists) return;

            final friendData = doc.data();
            if (friendData == null) return;

            if (friendData['sharing'] != true) return;

            final location = friendData['location'];
            if (location == null) return;

            final lat = location['lat'];
            final lng = location['lng'];

            setState(() {
              // 🔵 Update friend marker (no duplicates)
              markers.removeWhere((m) => m.markerId.value == uid);

              markers.add(
                Marker(
                  markerId: MarkerId(uid),
                  position: LatLng(lat, lng),
                  infoWindow: InfoWindow(
                    title: friendData['email'] ?? 'Friend',
                  ),
                  icon: BitmapDescriptor.defaultMarkerWithHue(
                    BitmapDescriptor.hueBlue,
                  ),
                ),
              );
            });
          });

      friendListeners[uid] = sub;
    }
  }

  void _listenToCommunitySOS() {
    sosSubscription?.cancel();

    sosSubscription = FirebaseFirestore.instance
        .collection('users')
        .where('sosActive', isEqualTo: true)
        .snapshots()
        .listen((snapshot) {
          final currentUser = FirebaseAuth.instance.currentUser;
          if (currentUser == null) return;

          final activeMarkers = <String>{};
          final newSosMarkers = <Marker>[];

          for (final doc in snapshot.docs) {
            if (doc.id == currentUser.uid) continue;

            final data = doc.data();
            if (data == null) continue;

            final location = data['sosLocation'];
            if (location == null) continue;

            final lat = location['lat'];
            final lng = location['lng'];
            if (lat == null || lng == null) continue;

            final distance = Geolocator.distanceBetween(
              currentPosition.latitude,
              currentPosition.longitude,
              lat.toDouble(),
              lng.toDouble(),
            );

            if (distance <= 3000) {
              final markerId = 'sos-${doc.id}';
              activeMarkers.add(markerId);

              newSosMarkers.add(
                Marker(
                  markerId: MarkerId(markerId),
                  position: LatLng(lat, lng),
                  infoWindow: InfoWindow(
                    title: data['email'] ?? 'SOS Alert',
                    snippet:
                        'Active SOS within ${distance.toStringAsFixed(0)} m',
                  ),
                  icon: BitmapDescriptor.defaultMarkerWithHue(
                    BitmapDescriptor.hueRed,
                  ),
                ),
              );
            }
          }

          setState(() {
            markers.removeWhere(
              (m) =>
                  m.markerId.value.startsWith('sos-') &&
                  !activeMarkers.contains(m.markerId.value),
            );
            markers.removeWhere(
              (m) => activeMarkers.contains(m.markerId.value),
            );
            markers.addAll(newSosMarkers);
          });
        });
  }

  // ---------------- TOGGLE SHARING ----------------
  Future<void> _toggleSharing(bool value) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => isSharing = value);

    await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
      'sharing': value,
    }, SetOptions(merge: true));
  }

  // ---------------- LOGOUT ----------------
  Future<void> _logout() async {
    await _auth.signOut();
    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const LoginScreen()),
      (route) => false,
    );
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    positionStream?.cancel();
    sosSubscription?.cancel();
    _crashDetection.stopMonitoring();

    for (var sub in friendListeners.values) {
      sub.cancel();
    }

    emailController.dispose();
    super.dispose();
  }

  // ---------------- UI ----------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('RideSafe PH Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add),
            tooltip: 'Add trusted contact',
            onPressed: _showAddContactDialog,
          ),
          IconButton(icon: const Icon(Icons.logout), onPressed: _logout),
        ],
      ),

      body: Column(
        children: [
          Expanded(
            child: GoogleMap(
              initialCameraPosition: CameraPosition(
                target: currentPosition,
                zoom: 18,
              ),
              markers: markers,
              myLocationEnabled: true,
              myLocationButtonEnabled: true,
              onMapCreated: (controller) {
                mapController = controller;
              },
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ElevatedButton.icon(
                    onPressed: trackingStarted
                        ? _handleStopRideTracking
                        : _handleStartRideTracking,
                    icon: Icon(trackingStarted ? Icons.stop : Icons.play_arrow),
                    label: Text(
                      trackingStarted ? 'Stop Tracking' : 'Start Ride Tracking',
                    ),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                      backgroundColor: trackingStarted
                          ? Colors.orange
                          : Colors.green,
                    ),
                  ),

                  if (crashDetectionActive)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.2),
                          border: Border.all(color: Colors.red, width: 1.5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.verified_user,
                              color: Colors.red,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Crash Detection Active',
                                style: TextStyle(
                                  color: Colors.red[300],
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  const SizedBox(height: 16),

                  // 🔥 SHARING SWITCH
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Live Sharing',
                        style: TextStyle(fontSize: 14),
                      ),
                      Switch(value: isSharing, onChanged: _toggleSharing),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // 🔥 TRUSTED CONTACTS LIST
                  const Text(
                    'Trusted Contacts',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  if (trustedContacts.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'No trusted contacts yet. Tap the + icon to add one.',
                        style: TextStyle(color: Colors.grey[500], fontSize: 12),
                      ),
                    )
                  else
                    Column(
                      children: trustedContacts
                          .map(
                            (contact) => Card(
                              color: Colors.grey[900],
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                dense: true,
                                leading: const Icon(
                                  Icons.person,
                                  color: Colors.blue,
                                  size: 20,
                                ),
                                title: Text(
                                  contact['email'] ?? 'Unknown',
                                  style: const TextStyle(fontSize: 13),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: IconButton(
                                  icon: const Icon(
                                    Icons.close,
                                    size: 18,
                                    color: Colors.red,
                                  ),
                                  onPressed: () =>
                                      removeTrustedUser(contact['uid'] ?? ''),
                                  tooltip: 'Remove contact',
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
