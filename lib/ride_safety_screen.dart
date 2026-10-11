import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:permission_handler/permission_handler.dart';

class RideSafetyScreen extends StatefulWidget {
  const RideSafetyScreen({super.key});

  @override
  State<RideSafetyScreen> createState() => _RideSafetyScreenState();
}

class _RideSafetyScreenState extends State<RideSafetyScreen> {
  final _formKey = GlobalKey<FormState>();
  final _driverNameController = TextEditingController();
  final _vehicleNumberController = TextEditingController();
  final _cabServiceController = TextEditingController(text: "Uber / Ola");

  bool _isRideActive = false;
  bool _isLoading = false;
  String _statusMessage = "";

  static const _smsChannel = MethodChannel('com.example.women_safety_app/sms');

  @override
  void dispose() {
    _driverNameController.dispose();
    _vehicleNumberController.dispose();
    _cabServiceController.dispose();
    super.dispose();
  }

  /// Sends initial Ride Tracking details to Guardians via Direct SMS
  Future<void> _startRideSafety() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _statusMessage = "Getting current ride location...";
    });

    try {
      // 1. Get GPS Location
      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
            timeLimit: Duration(seconds: 10),
          ),
        );
      } catch (_) {
        position = await Geolocator.getLastKnownPosition();
      }

      if (position == null) {
        setState(() {
          _isLoading = false;
          _statusMessage = "❌ Could not get GPS location for ride start.";
        });
        return;
      }

      // 2. Read cached contacts
      final prefs = await SharedPreferences.getInstance();
      final cachedJson = prefs.getStringList('cached_emergency_contacts') ?? [];

      if (cachedJson.isEmpty) {
        setState(() {
          _isLoading = false;
          _statusMessage = "❌ No emergency contacts saved! Add contacts first.";
        });
        return;
      }

      final contacts = cachedJson
          .map((c) => jsonDecode(c) as Map<String, dynamic>)
          .toList();

      // 3. Format Ride Safety Broadcast Message
      final String driver = _driverNameController.text.trim();
      final String vehicle = _vehicleNumberController.text.trim().toUpperCase();
      final String service = _cabServiceController.text.trim();
      final String mapsLink = 'https://maps.google.com/?q=${position.latitude},${position.longitude}';

      final String message =
          'SAFE RIDE ALERT: I am in a $service ride.\n'
          'Vehicle No: $vehicle\n'
          'Driver: $driver\n'
          'Track Start Location: $mapsLink';

      // 4. Request SMS permission & send direct SMS
      var smsPermission = await Permission.sms.request();
      if (!smsPermission.isGranted) {
        setState(() {
          _isLoading = false;
          _statusMessage = "❌ SMS permission denied.";
        });
        return;
      }

      int sentCount = 0;
      for (var contact in contacts) {
        String phone = (contact['contact_phone'] ?? contact['phone'])?.toString() ?? '';
        if (phone.isNotEmpty) {
          try {
            await _smsChannel.invokeMethod('sendDirectSms', {
              'phone': phone,
              'message': message,
            });
            sentCount++;
          } catch (e) {
            print("Failed SMS to $phone: $e");
          }
        }
      }

      setState(() {
        _isRideActive = true;
        _isLoading = false;
        _statusMessage = "🚖 Safe Ride Active! Sent info to $sentCount guardians.";
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _statusMessage = "❌ Error: $e";
      });
    }
  }

  void _stopRideSafety() {
    setState(() {
      _isRideActive = false;
      _statusMessage = "Ride ended. Safe Ride Tracking deactivated.";
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF12121A),
      appBar: AppBar(
        title: const Text('Ride Safety Mode'),
        backgroundColor: const Color(0xFF1E1E2C),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // HEADER CARD
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.indigoAccent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.indigoAccent.withOpacity(0.3)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.local_taxi, color: Colors.indigoAccent, size: 32),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        "Share cab & driver details with guardians before starting your ride.",
                        style: TextStyle(color: Colors.white, fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // CAB SERVICE FIELD
              TextFormField(
                controller: _cabServiceController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Cab / Ride Service',
                  labelStyle: const TextStyle(color: Colors.white60),
                  prefixIcon: const Icon(Icons.apps, color: Colors.indigoAccent),
                  filled: true,
                  fillColor: const Color(0xFF1E1E2C),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                validator: (val) => val == null || val.isEmpty ? 'Enter service (e.g. Uber/Ola)' : null,
              ),

              const SizedBox(height: 16),

              // VEHICLE NUMBER FIELD
              TextFormField(
                controller: _vehicleNumberController,
                style: const TextStyle(color: Colors.white),
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  labelText: 'Vehicle Number',
                  hintText: 'e.g. UP70 AB 1234',
                  hintStyle: const TextStyle(color: Colors.white24),
                  labelStyle: const TextStyle(color: Colors.white60),
                  prefixIcon: const Icon(Icons.directions_car, color: Colors.indigoAccent),
                  filled: true,
                  fillColor: const Color(0xFF1E1E2C),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                validator: (val) => val == null || val.isEmpty ? 'Enter vehicle plate number' : null,
              ),

              const SizedBox(height: 16),

              // DRIVER NAME FIELD
              TextFormField(
                controller: _driverNameController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Driver Name',
                  hintText: 'e.g. Ramesh Kumar',
                  hintStyle: const TextStyle(color: Colors.white24),
                  labelStyle: const TextStyle(color: Colors.white60),
                  prefixIcon: const Icon(Icons.person, color: Colors.indigoAccent),
                  filled: true,
                  fillColor: const Color(0xFF1E1E2C),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                validator: (val) => val == null || val.isEmpty ? 'Enter driver name' : null,
              ),

              const SizedBox(height: 28),

              // ACTION BUTTON
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton.icon(
                  icon: Icon(_isRideActive ? Icons.stop_circle : Icons.shield, color: Colors.white),
                  label: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text(
                    _isRideActive ? 'END SAFE RIDE' : 'START SAFE RIDE',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  onPressed: _isLoading
                      ? null
                      : (_isRideActive ? _stopRideSafety : _startRideSafety),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isRideActive ? Colors.redAccent : Colors.indigoAccent,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              if (_statusMessage.isNotEmpty)
                Center(
                  child: Text(
                    _statusMessage,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.greenAccent,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}