import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';

class EmergencyContact {
  final String name;
  final String phoneNumber;
  final String relation;

  EmergencyContact({
    required this.name,
    required this.phoneNumber,
    required this.relation,
  });
}

class EmergencyService {
  static const String emergencyNumber = '911';
  static const String emergencySMSMessage =
      'RIDESAFE EMERGENCY ALERT: I need help! My location: ';

  // Get current location
  static Future<Position?> getCurrentLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      return position;
    } catch (e) {
      print('Error getting location: $e');
      return null;
    }
  }

  // Generate Google Maps link
  static String generateLocationLink(double latitude, double longitude) {
    return 'https://maps.google.com/?q=$latitude,$longitude';
  }

  // Publish current SOS state so nearby app users can see it
  static Future<void> activateSOSAlert(
    double latitude,
    double longitude,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
      'sosActive': true,
      'sosLocation': {'lat': latitude, 'lng': longitude},
      'sosTimestamp': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Future<void> deactivateSOSAlert() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
      'sosActive': false,
      'sosLocation': FieldValue.delete(),
      'sosTimestamp': FieldValue.delete(),
    }, SetOptions(merge: true));
  }

  // Call emergency services
  static Future<void> callEmergency() async {
    await callPhoneNumber(emergencyNumber);
  }

  // Call a specific phone number
  static Future<void> callPhoneNumber(String phoneNumber) async {
    final Uri phoneUri = Uri(scheme: 'tel', path: phoneNumber);

    try {
      if (await canLaunchUrl(phoneUri)) {
        await launchUrl(phoneUri);
      } else {
        throw 'Could not launch phone call';
      }
    } catch (e) {
      print('Error calling $phoneNumber: $e');
      rethrow;
    }
  }

  // Send SOS SMS with location
  static Future<void> sendSOSAlert(
    List<EmergencyContact> contacts,
    double latitude,
    double longitude,
  ) async {
    final locationLink = generateLocationLink(latitude, longitude);
    final message = '$emergencySMSMessage$locationLink';

    for (var contact in contacts) {
      await _sendSMS(contact.phoneNumber, message);
    }
  }

  // Send individual SMS
  static Future<void> _sendSMS(String phoneNumber, String message) async {
    final Uri smsUri = Uri(
      scheme: 'sms',
      path: phoneNumber,
      queryParameters: {'body': message},
    );

    try {
      if (await canLaunchUrl(smsUri)) {
        await launchUrl(smsUri);
      }
    } catch (e) {
      print('Error sending SMS to $phoneNumber: $e');
    }
  }

  // Share location via WhatsApp/Messenger (optional)
  static Future<void> shareLocationViaWhatsApp(
    String phoneNumber,
    double latitude,
    double longitude,
  ) async {
    final message =
        'RIDESAFE EMERGENCY: https://maps.google.com/?q=$latitude,$longitude';
    final Uri whatsappUri = Uri.parse(
      'https://wa.me/$phoneNumber?text=${Uri.encodeComponent(message)}',
    );

    try {
      if (await canLaunchUrl(whatsappUri)) {
        await launchUrl(whatsappUri);
      }
    } catch (e) {
      print('Error sharing via WhatsApp: $e');
    }
  }
}
