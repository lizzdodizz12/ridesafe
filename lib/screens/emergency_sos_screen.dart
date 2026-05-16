import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../services/emergency_service.dart';

class EmergencySOSScreen extends StatefulWidget {
  const EmergencySOSScreen({super.key});

  @override
  State<EmergencySOSScreen> createState() => _EmergencySOSScreenState();
}

class _EmergencySOSScreenState extends State<EmergencySOSScreen> {
  bool isActivated = false;
  bool sosActive = false;
  Position? currentLocation;
  int? selectedContactIndex;
  List<EmergencyContact> emergencyContacts = [
    EmergencyContact(
      name: 'Mom',
      phoneNumber: '+639000000000',
      relation: 'Parent',
    ),
    EmergencyContact(
      name: 'Best Friend',
      phoneNumber: '+639111111111',
      relation: 'Friend',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _getLocation();
  }

  Future<void> _getLocation() async {
    final location = await EmergencyService.getCurrentLocation();
    setState(() {
      currentLocation = location;
    });
  }

  Future<void> _sendSOSAlert() async {
    if (isActivated) return;

    setState(() => isActivated = true);
    await _getLocation();

    if (currentLocation == null) {
      _showError('Could not get your location. Please enable GPS.');
      setState(() => isActivated = false);
      return;
    }

    final contactsToNotify = selectedContactIndex != null
        ? [emergencyContacts[selectedContactIndex!]]
        : emergencyContacts;

    try {
      await EmergencyService.sendSOSAlert(
        contactsToNotify,
        currentLocation!.latitude,
        currentLocation!.longitude,
      );

      await EmergencyService.activateSOSAlert(
        currentLocation!.latitude,
        currentLocation!.longitude,
      );

      if (mounted) {
        setState(() => sosActive = true);
      }

      _showSuccess(
        'SOS alert sent to ${contactsToNotify.length == 1 ? contactsToNotify.first.name : 'your emergency contacts'}.'
        '\n\nLocation: ${currentLocation!.latitude.toStringAsFixed(4)}, '
        '${currentLocation!.longitude.toStringAsFixed(4)}',
      );
    } catch (e) {
      _showError('Error sending SOS alert: $e');
    } finally {
      if (mounted) {
        setState(() => isActivated = false);
      }
    }
  }

  Future<void> _callContact(String phoneNumber) async {
    setState(() => isActivated = true);

    try {
      await EmergencyService.callPhoneNumber(phoneNumber);
    } catch (e) {
      _showError('Could not place the call: $e');
    } finally {
      if (mounted) {
        setState(() => isActivated = false);
      }
    }
  }

  Future<void> _cancelSOS() async {
    await EmergencyService.deactivateSOSAlert();
    if (mounted) {
      setState(() => sosActive = false);
    }
    _showSuccess('SOS alert canceled.');
  }

  Future<void> _call911() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Call 911?'),
        content: const Text(
          'Use this option when you need immediate police, fire, or medical assistance.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('CALL 911'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => isActivated = true);

    try {
      await EmergencyService.callEmergency();
    } catch (e) {
      _showError('Could not dial 911: $e');
    } finally {
      if (mounted) {
        setState(() => isActivated = false);
      }
    }
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 5),
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedContact = selectedContactIndex != null
        ? emergencyContacts[selectedContactIndex!]
        : null;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Emergency SOS'),
        backgroundColor: Colors.red,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 30),

            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
              decoration: BoxDecoration(
                color: Colors.grey[900],
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Selected contact',
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    selectedContact != null
                        ? '${selectedContact.name} • ${selectedContact.relation}'
                        : 'No contact selected. SOS alerts will be sent to all contacts.',
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            GestureDetector(
              onTap: isActivated ? null : _sendSOSAlert,
              child: Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isActivated ? Colors.orange : Colors.red,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.red.withOpacity(0.5),
                      blurRadius: 20,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      isActivated
                          ? Icons.hourglass_bottom
                          : Icons.notification_important,
                      size: 80,
                      color: Colors.white,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      isActivated ? 'SENDING...' : 'SEND SOS\nALERT',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 18),

            if (sosActive)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'SOS is active. Nearby community members within 3km can see your location.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.redAccent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),

            if (sosActive)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.cancel),
                  label: const Text('Cancel SOS'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey[800],
                  ),
                  onPressed: _cancelSOS,
                ),
              ),

            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.call),
                    label: const Text('Call 911'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                    ),
                    onPressed: _call911,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 30),

            Card(
              color: Colors.grey[900],
              child: Padding(
                padding: const EdgeInsets.all(15),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Your Current Location',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (currentLocation != null)
                      Text(
                        'Latitude: ${currentLocation!.latitude.toStringAsFixed(4)}\n'
                        'Longitude: ${currentLocation!.longitude.toStringAsFixed(4)}\n'
                        'Accuracy: ${currentLocation!.accuracy.toStringAsFixed(1)}m',
                        style: const TextStyle(color: Colors.grey),
                      )
                    else
                      const Text(
                        'Fetching location...',
                        style: TextStyle(color: Colors.orange),
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 30),

            const Text(
              'Emergency Contacts',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 10),

            Expanded(
              child: ListView.builder(
                itemCount: emergencyContacts.length,
                itemBuilder: (context, index) {
                  final contact = emergencyContacts[index];
                  return Card(
                    color: selectedContactIndex == index
                        ? Colors.red.withOpacity(0.2)
                        : Colors.grey[900],
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      leading: Radio<int>(
                        value: index,
                        groupValue: selectedContactIndex,
                        activeColor: Colors.red,
                        onChanged: (value) {
                          setState(() {
                            selectedContactIndex = value;
                          });
                        },
                      ),
                      title: Text(
                        contact.name,
                        style: const TextStyle(color: Colors.white),
                      ),
                      subtitle: Text(
                        '${contact.relation} • ${contact.phoneNumber}',
                        style: const TextStyle(color: Colors.grey),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(
                              Icons.message,
                              color: Colors.white,
                            ),
                            tooltip: 'Send SMS',
                            onPressed: () async {
                              if (currentLocation == null) {
                                _showError('Getting location, please wait.');
                                return;
                              }
                              await EmergencyService.sendSOSAlert(
                                [contact],
                                currentLocation!.latitude,
                                currentLocation!.longitude,
                              );
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.call, color: Colors.white),
                            tooltip: 'Call contact',
                            onPressed: () => _callContact(contact.phoneNumber),
                          ),
                        ],
                      ),
                      onTap: () {
                        setState(() {
                          selectedContactIndex = index;
                        });
                      },
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 20),

            const Text(
              'Select one contact to prioritize the alert. If none is selected, all emergency contacts will receive the SOS message. 911 remains available as a separate call option.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
