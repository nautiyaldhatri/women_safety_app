import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Ride safety screen: user enters driver/vehicle details, picks up to 2
/// contacts, starts a ride. Shows a persistent notification asking whether
/// to send the details, which stays visible (as an ongoing "ride in
/// progress" notification) until the user ends the ride.
class RideSafetyScreen extends StatefulWidget {
  const RideSafetyScreen({super.key});

  @override
  State<RideSafetyScreen> createState() => _RideSafetyScreenState();
}

class _RideSafetyScreenState extends State<RideSafetyScreen> {
  final _supabase = Supabase.instance.client;
  final _notifications = FlutterLocalNotificationsPlugin();

  final _driverNameController = TextEditingController();
  final _driverPhoneController = TextEditingController();
  final _vehicleNumberController = TextEditingController();
  final _vehicleModelController = TextEditingController();

  List<Map<String, dynamic>> _contacts = [];
  final Set<String> _selectedContactIds = {};
  bool _loadingContacts = true;
  bool _rideActive = false;
  String? _activeRideId;

  static const int _maxRideContacts = 2;
  static const int _notificationId = 1001;

  @override
  void initState() {
    super.initState();
    _initNotifications();
    _fetchContacts();
  }

  Future<void> _initNotifications() async {
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const settings = InitializationSettings(android: androidSettings);
    await _notifications.initialize(
      settings,
      onDidReceiveNotificationResponse: _handleNotificationAction,
    );
  }

  void _handleNotificationAction(NotificationResponse response) {
    switch (response.actionId) {
      case 'send_details':
        _sendRideDetails();
        break;
      case 'dont_send':
        _dismissWithoutSending();
        break;
      case 'end_ride':
        _endRide();
        break;
    }
  }

  Future<void> _fetchContacts() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      final response = await _supabase
          .from('emergency_contacts')
          .select()
          .eq('user_id', userId);

      setState(() {
        _contacts = List<Map<String, dynamic>>.from(response);
        _loadingContacts = false;
      });
    } catch (e) {
      debugPrint('Failed to fetch contacts: $e');
      setState(() => _loadingContacts = false);
    }
  }

  void _toggleContact(String id) {
    setState(() {
      if (_selectedContactIds.contains(id)) {
        _selectedContactIds.remove(id);
      } else {
        if (_selectedContactIds.length >= _maxRideContacts) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'You can select up to $_maxRideContacts contacts only',
              ),
            ),
          );
          return;
        }
        _selectedContactIds.add(id);
      }
    });
  }

  Future<void> _startRide() async {
    if (_driverNameController.text.trim().isEmpty ||
        _driverPhoneController.text.trim().isEmpty ||
        _vehicleNumberController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill in driver and vehicle details'),
        ),
      );
      return;
    }

    if (_selectedContactIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one contact')),
      );
      return;
    }

    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      final response = await _supabase
          .from('ride_safety_shares')
          .insert({
            'user_id': userId,
            'driver_name': _driverNameController.text.trim(),
            'driver_phone': _driverPhoneController.text.trim(),
            'vehicle_number': _vehicleNumberController.text.trim(),
            'user_consented': false,
          })
          .select('id')
          .single();

      setState(() {
        _activeRideId = response['id'] as String;
        _rideActive = true;
      });

      await _showSendPrompt();
    } catch (e) {
      debugPrint('Failed to start ride: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to start ride: $e')));
      }
    }
  }

  Future<void> _showSendPrompt() async {
    const androidDetails = AndroidNotificationDetails(
      'ride_safety_channel',
      'Ride Safety',
      channelDescription: 'Ride safety alerts and status',
      importance: Importance.high,
      priority: Priority.high,
      ongoing: true, // can't be swiped away
      autoCancel: false,
      actions: [
        AndroidNotificationAction('send_details', 'Send Details'),
        AndroidNotificationAction('dont_send', 'Don\'t Send'),
      ],
    );
    const details = NotificationDetails(android: androidDetails);

    await _notifications.show(
      _notificationId,
      'Share ride details?',
      'Send driver and vehicle info to your selected contacts?',
      details,
    );
  }

  Future<void> _showRideInProgressNotification() async {
    const androidDetails = AndroidNotificationDetails(
      'ride_safety_channel',
      'Ride Safety',
      channelDescription: 'Ride safety alerts and status',
      importance: Importance.high,
      priority: Priority.high,
      ongoing: true,
      autoCancel: false,
      actions: [AndroidNotificationAction('end_ride', 'End Ride')],
    );
    const details = NotificationDetails(android: androidDetails);

    await _notifications.show(
      _notificationId,
      'Ride in progress',
      'Tap End Ride when you\'ve reached safely',
      details,
    );
  }

  Future<void> _sendRideDetails() async {
    if (_activeRideId == null) return;

    try {
      final selectedContacts = _contacts
          .where((c) => _selectedContactIds.contains(c['id']))
          .map((c) => {'name': c['contact_name'], 'phone': c['contact_phone']})
          .toList();

      await _supabase
          .from('ride_safety_shares')
          .update({
            'user_consented': true,
            'consented_at': DateTime.now().toIso8601String(),
            'shared_with': selectedContacts,
          })
          .eq('id', _activeRideId!);


      await _showRideInProgressNotification();
    } catch (e) {
      debugPrint('Failed to send ride details: $e');
    }
  }

  Future<void> _dismissWithoutSending() async {
    await _showRideInProgressNotification();
  }

  Future<void> _endRide() async {
    if (_activeRideId != null) {
      await _supabase
          .from('ride_safety_shares')
          .update({'trip_ended_at': DateTime.now().toIso8601String()})
          .eq('id', _activeRideId!);
    }

    await _notifications.cancel(_notificationId);

    setState(() {
      _rideActive = false;
      _activeRideId = null;
      _selectedContactIds.clear();
      _driverNameController.clear();
      _driverPhoneController.clear();
      _vehicleNumberController.clear();
      _vehicleModelController.clear();
    });
  }

  @override
  void dispose() {
    _driverNameController.dispose();
    _driverPhoneController.dispose();
    _vehicleNumberController.dispose();
    _vehicleModelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_rideActive) {
      return Scaffold(
        appBar: AppBar(title: const Text('Ride in Progress')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.directions_car, size: 64, color: Colors.green),
              const SizedBox(height: 16),
              const Text('Ride is active', style: TextStyle(fontSize: 18)),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _endRide,
                icon: const Icon(Icons.stop_circle),
                label: const Text('End Ride'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 14,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Ride Safety')),
      body: _loadingContacts
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _driverNameController,
                    decoration: const InputDecoration(
                      labelText: 'Driver Name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _driverPhoneController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Driver Phone',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _vehicleNumberController,
                    decoration: const InputDecoration(
                      labelText: 'Vehicle Number',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _vehicleModelController,
                    decoration: const InputDecoration(
                      labelText: 'Vehicle Model (optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Select up to $_maxRideContacts contacts to share with',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  if (_contacts.isEmpty)
                    const Text(
                      'No emergency contacts saved yet. Add some in Contacts first.',
                    )
                  else
                    ..._contacts.map((contact) {
                      final id = contact['id'] as String;
                      return CheckboxListTile(
                        title: Text(contact['contact_name'] ?? ''),
                        subtitle: Text(contact['contact_phone'] ?? ''),
                        value: _selectedContactIds.contains(id),
                        onChanged: (_) => _toggleContact(id),
                      );
                    }),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: _startRide,
                    icon: const Icon(Icons.play_circle),
                    label: const Text('Start Ride'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
