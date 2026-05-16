import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'login_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  bool _isRequesting = false;
  bool trackingStarted = false;
  bool isSharing = true;

  GoogleMapController? mapController;
  StreamSubscription<Position>? positionStream;

  LatLng currentPosition = const LatLng(7.1907, 125.4553);
  Set<Marker> markers = {};

  final TextEditingController emailController = TextEditingController();

  // 🔥 FRIEND LISTENERS
  Map<String, StreamSubscription<DocumentSnapshot>> friendListeners = {};

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
    } catch (e) {
      _showSnackBar('Error adding user');
    }
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

    setState(() {
      trackingStarted = true;
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
            child: Column(
              children: [
                ElevatedButton(
                  onPressed: _handleStartRideTracking,
                  child: Text(
                    trackingStarted ? 'Tracking Active' : 'Start Ride Tracking',
                  ),
                ),

                const SizedBox(height: 10),

                // 🔥 ADD CONTACT
                TextField(
                  controller: emailController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    hintText: 'Enter email to add',
                  ),
                ),

                const SizedBox(height: 10),

                ElevatedButton(
                  onPressed: () {
                    final email = emailController.text.trim();
                    if (email.isNotEmpty) {
                      addTrustedUserByEmail(email);
                      emailController.clear();
                    }
                  },
                  child: const Text('Add Trusted Contact'),
                ),

                const SizedBox(height: 10),

                // 🔥 SHARING SWITCH
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Live Sharing'),
                    Switch(value: isSharing, onChanged: _toggleSharing),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
