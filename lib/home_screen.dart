import 'dart:async';
import 'contacts_screen.dart';
import 'vosk_test_screen.dart';
import 'ride_safety_screen.dart';
import 'app_home_listener_screen.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';
import 'package:flutter/services.dart';

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
  static const _gpsChannel = MethodChannel('com.example.women_safety_app/gps');

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

  void _cancelCountdown() {
    countdownTimer?.cancel();
    setState(() {
      isCountingDown = false;
      status = "Alert cancelled. Press the button in an emergency";
    });
  }

  Future<void> _sendSOS() async {
    setState(() => status = "Getting location...");

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(
          () => status =
              "❌ Location is turned OFF on this device. Enable it in system settings.",
        );
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        setState(
          () => status = "❌ Location permission denied. Enable it in Settings.",
        );
        return;
      }

      final locData = await _gpsChannel.invokeMethod('getGpsLocation');
      final lat = locData['lat'] as double;
      final lng = locData['lng'] as double;

      setState(() => status = "Sending alert...");

      final userId = Supabase.instance.client.auth.currentUser?.id;
      final session = Supabase.instance.client.auth.currentSession;

      final response = await http
          .post(
            Uri.parse(
              'https://msgzotmxqqurofawnjcd.supabase.co/functions/v1/send-alert',
            ),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${session?.accessToken}',
              'apikey': 'sb_publishable_q2Giprn7HQfEk0VnI5UjGg_KPQ06x6K',
            },
            body: jsonEncode({
              'latitude': lat,
              'longitude': lng,
              'user_id': userId,
            }),
          )
          .timeout(const Duration(seconds: 15));

      setState(() {
        status = response.statusCode == 200
            ? "✅ Alert sent successfully!"
            : "❌ Failed: ${response.body}";
      });
    } catch (e) {
      setState(() => status = "❌ Something went wrong: $e");
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
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                status,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18),
              ),
              const SizedBox(height: 30),
              if (!isCountingDown)
                ElevatedButton(
                  onPressed: _startCountdown,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 40,
                      vertical: 20,
                    ),
                  ),
                  child: const Text(
                    "SOS",
                    style: TextStyle(fontSize: 24, color: Colors.white),
                  ),
                ),
              if (isCountingDown)
                Column(
                  children: [
                    Text(
                      "$secondsLeft",
                      style: const TextStyle(
                        fontSize: 60,
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: _cancelCountdown,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 30,
                          vertical: 15,
                        ),
                      ),
                      child: const Text(
                        "Cancel",
                        style: TextStyle(fontSize: 18, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 40),
              TextButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const VoskTestScreen()),
                  );
                },
                child: const Text("Test Voice (temp)"),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const RideSafetyScreen()),
                  );
                },
                child: const Text("Ride Safety (temp)"),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const AppHomeListenerScreen(),
                    ),
                  );
                },
                child: const Text("Voice Listener (temp)"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
