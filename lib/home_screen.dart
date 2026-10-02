import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:local_auth/local_auth.dart';
import 'package:permission_handler/permission_handler.dart';

import 'contacts_screen.dart';
import 'ride_safety_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String status = "Press the button in an emergency";
  Timer? countdownTimer;
  int secondsLeft = 30;
  bool isCountingDown = false;
  bool isSending = false;

  final LocalAuthentication _auth = LocalAuthentication();
  static const _smsChannel = MethodChannel('com.example.women_safety_app/sms');

  void _startCountdown() {
    setState(() {
      isCountingDown = true;
      secondsLeft = 30;
      status = "Sending alert in $secondsLeft seconds...";
    });

    countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (secondsLeft <= 1) {
        timer.cancel();
        setState(() {
          isCountingDown = false;
        });
        _sendSOS();
      } else {
        setState(() {
          secondsLeft--;
          status = "Sending alert in $secondsLeft seconds...";
        });
      }
    });
  }

  Future<void> _cancelCountdown() async {
    try {
      bool canAuthenticate = await _auth.canCheckBiometrics || await _auth.isDeviceSupported();

      if (!canAuthenticate) {
        _forceCancelCountdown();
        return;
      }

      bool authenticated = await _auth.authenticate(
        localizedReason: 'Authenticate with Fingerprint/PIN to cancel SOS alert',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
        ),
      );

      if (authenticated) {
        _forceCancelCountdown();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('❌ Verification failed! SOS countdown continuing...'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      _forceCancelCountdown();
    }
  }

  void _forceCancelCountdown() {
    countdownTimer?.cancel();
    setState(() {
      isCountingDown = false;
      status = "Alert cancelled. Press the button in an emergency";
    });
  }

  Future<Position?> _getFastLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() => status = "❌ Location is turned OFF. Enable GPS in settings.");
      return null;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      setState(() => status = "❌ Location permission denied in settings.");
      return null;
    }

    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 10),
        ),
      );
    } catch (e) {
      return await Geolocator.getLastKnownPosition();
    }
  }

  Future<void> _sendSOS() async {
    setState(() {
      isSending = true;
      status = "Getting location...";
    });

    try {
      Position? position = await _getFastLocation();

      if (position == null) {
        setState(() {
          isSending = false;
          status = "❌ Could not get GPS location.";
        });
        return;
      }

      final connectivityResult = await Connectivity().checkConnectivity();
      final bool isOnline = !connectivityResult.contains(ConnectivityResult.none);

      if (isOnline) {
        setState(() => status = "Sending Cloud SOS alert...");

        final userId = Supabase.instance.client.auth.currentUser?.id;
        final session = Supabase.instance.client.auth.currentSession;

        final response = await http
            .post(
          Uri.parse('https://msgzotmxqqurofawnjcd.supabase.co/functions/v1/send-alert'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${session?.accessToken}',
            'apikey': 'sb_publishable_q2Giprn7HQfEk0VnI5UjGg_KPQ06x6K',
          },
          body: jsonEncode({
            'latitude': position.latitude,
            'longitude': position.longitude,
            'user_id': userId,
          }),
        )
            .timeout(const Duration(seconds: 15));

        if (response.statusCode == 200) {
          setState(() => status = "🚨 SOS Alert sent successfully!");
        } else {
          await _sendOfflineSMS(position);
        }
      } else {
        await _sendOfflineSMS(position);
      }
    } catch (e) {
      setState(() => status = "❌ Error: $e");
    } finally {
      setState(() => isSending = false);
    }
  }

  /// Sends Direct SMS silently in background to each contact individually
  Future<void> _sendOfflineSMS(Position position) async {
    setState(() => status = "Offline: Requesting SMS permission...");

    // Request SMS permission from Android OS
    var smsPermission = await Permission.sms.request();
    if (!smsPermission.isGranted) {
      setState(() => status = "❌ SMS Permission denied by user.");
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final cachedJson = prefs.getStringList('cached_emergency_contacts') ?? [];

    if (cachedJson.isEmpty) {
      setState(() => status = "❌ No emergency contacts cached! Add contacts first.");
      return;
    }

    final contacts = cachedJson
        .map((c) => jsonDecode(c) as Map<String, dynamic>)
        .toList();

    final String mapsLink = 'https://maps.google.com/?q=${position.latitude},${position.longitude}';
    final String message = 'EMERGENCY SOS! I need help immediately. My Location: $mapsLink';

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
          print("Failed to send SMS to $phone: $e");
        }
      }
    }

    if (sentCount > 0) {
      setState(() => status = "🚨 Direct SMS sent to $sentCount emergency contacts!");
    } else {
      setState(() => status = "❌ Failed to send direct SMS.");
    }
  }

  @override
  void dispose() {
    countdownTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Women Safety App'),
        backgroundColor: Colors.redAccent,
        actions: [
          IconButton(
            icon: const Icon(Icons.contacts),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ContactsScreen()),
              );
            },
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                status,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 40),

              if (!isCountingDown)
                GestureDetector(
                  onTap: isSending ? null : _startCountdown,
                  child: Container(
                    width: 180,
                    height: 180,
                    decoration: BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.red.withValues(alpha: 0.4),
                          spreadRadius: 8,
                          blurRadius: 16,
                        ),
                      ],
                    ),
                    child: Center(
                      child: isSending
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text(
                        "SOS",
                        style: TextStyle(
                          fontSize: 44,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),

              if (isCountingDown)
                Column(
                  children: [
                    Text(
                      "$secondsLeft",
                      style: const TextStyle(
                        fontSize: 72,
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.fingerprint, color: Colors.white),
                      label: const Text(
                        "CANCEL ALERT",
                        style: TextStyle(fontSize: 18, color: Colors.white),
                      ),
                      onPressed: _cancelCountdown,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey[850],
                        padding: const EdgeInsets.symmetric(
                          horizontal: 32,
                          vertical: 16,
                        ),
                      ),
                    ),
                  ],
                ),

              const SizedBox(height: 50),

              TextButton.icon(
                icon: const Icon(Icons.directions_car, color: Colors.redAccent),
                label: const Text(
                  "Ride Safety Mode",
                  style: TextStyle(color: Colors.redAccent, fontSize: 16),
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const RideSafetyScreen()),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}