import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:local_auth/local_auth.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sensors_plus/sensors_plus.dart';

import 'contacts_screen.dart';
import 'ride_safety_screen.dart';
import 'voice_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  String status = "Press button, say 'Help me', or SHAKE phone in emergency";
  Timer? countdownTimer;
  int secondsLeft = 30;
  bool isCountingDown = false;
  bool isSending = false;
  bool isVoiceActive = false;

  final LocalAuthentication _auth = LocalAuthentication();
  final VoiceService _voiceService = VoiceService();

  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  DateTime _lastShakeTime = DateTime.now();
  late AnimationController _pulseController;

  static const _smsChannel = MethodChannel('com.example.women_safety_app/sms');

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _initShakeGesture();
    _initVoiceAssistant();
  }

  /// 1. Initialize Accelerometer Shake Gesture
  void _initShakeGesture() {
    _accelerometerSubscription = accelerometerEventStream().listen((AccelerometerEvent event) {
      double gForce = sqrt(event.x * event.x + event.y * event.y + event.z * event.z);

      if (gForce > 15.0) {
        final now = DateTime.now();
        if (now.difference(_lastShakeTime).inSeconds > 3) {
          _lastShakeTime = now;
          if (!isCountingDown && !isSending) {
            _startCountdown(); // SHAKE TRIGGERED SOS!
          }
        }
      }
    });
  }

  /// 2. Initialize Voice Assistant ("Help me" / "Bachao")
  Future<void> _initVoiceAssistant() async {
    bool started = await _voiceService.startListening(
      onDistressDetected: () {
        if (!isCountingDown && !isSending) {
          _startCountdown(); // VOICE TRIGGERED SOS!
        }
      },
    );

    if (mounted) {
      setState(() {
        isVoiceActive = started;
      });
    }
  }

  @override
  void dispose() {
    _accelerometerSubscription?.cancel();
    _voiceService.stopListening();
    countdownTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  void _startCountdown() {
    setState(() {
      isCountingDown = true;
      secondsLeft = 30;
      status = "ALERT TRIGGERED! Sending SOS in $secondsLeft seconds...";
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
          status = "ALERT TRIGGERED! Sending SOS in $secondsLeft seconds...";
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
        localizedReason: 'Scan Fingerprint/PIN to cancel SOS alert',
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
      status = "Alert cancelled. You are safe.";
    });
    _initVoiceAssistant();
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
          setState(() => status = "🚨 Cloud SOS Alert sent successfully!");
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

  Future<void> _sendOfflineSMS(Position position) async {
    setState(() => status = "Offline: Requesting SMS permission...");

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
  Widget build(BuildContext context) {
    bool isEmergency = isCountingDown || status.contains("ALERT") || status.contains("Broadcasted");

    return Scaffold(
      backgroundColor: const Color(0xFF12121A),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        title: const Row(
          children: [
            Icon(Icons.shield_outlined, color: Colors.redAccent, size: 28),
            SizedBox(width: 8),
            Text(
              'SAFESHE AI',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: const Icon(Icons.contacts, color: Colors.white),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ContactsScreen()),
                );
              },
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            // STATUS BADGE CARD
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: isEmergency
                    ? Colors.redAccent.withValues(alpha: 0.15)
                    : Colors.greenAccent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isEmergency ? Colors.redAccent : Colors.greenAccent,
                  width: 1.5,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    isEmergency ? Icons.warning_amber_rounded : Icons.check_circle_outline,
                    color: isEmergency ? Colors.redAccent : Colors.greenAccent,
                    size: 28,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      status,
                      style: TextStyle(
                        color: isEmergency ? Colors.redAccent : Colors.greenAccent,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // VOICE ASSISTANT CARD (UI VISUAL INDICATOR)
            GestureDetector(
              onTap: _initVoiceAssistant,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E2C),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isVoiceActive ? Colors.greenAccent.withValues(alpha: 0.5) : Colors.white10,
                  ),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: isVoiceActive
                          ? Colors.greenAccent.withValues(alpha: 0.15)
                          : Colors.redAccent.withValues(alpha: 0.15),
                      child: Icon(
                        isVoiceActive ? Icons.mic : Icons.mic_off,
                        color: isVoiceActive ? Colors.greenAccent : Colors.redAccent,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                "Voice Assistant",
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isVoiceActive ? Colors.greenAccent : Colors.redAccent,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  isVoiceActive ? "ACTIVE" : "TAP TO ENABLE",
                                  style: const TextStyle(
                                    color: Colors.black,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            "Listening for: 'Help me', 'Bachao', 'Save me'",
                            style: TextStyle(color: Colors.white54, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 30),

            // PULSING SOS BUTTON
            Center(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  AnimatedBuilder(
                    animation: _pulseController,
                    builder: (context, child) {
                      return Container(
                        width: 210 + (_pulseController.value * 25),
                        height: 210 + (_pulseController.value * 25),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isEmergency
                              ? Colors.redAccent.withValues(alpha: 0.2 - (_pulseController.value * 0.15))
                              : Colors.red.withValues(alpha: 0.15 - (_pulseController.value * 0.1)),
                        ),
                      );
                    },
                  ),
                  AnimatedBuilder(
                    animation: _pulseController,
                    builder: (context, child) {
                      return Container(
                        width: 185 + (_pulseController.value * 12),
                        height: 185 + (_pulseController.value * 12),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.redAccent.withValues(alpha: 0.25),
                        ),
                      );
                    },
                  ),
                  GestureDetector(
                    onTap: isSending ? null : (isCountingDown ? null : _startCountdown),
                    child: Container(
                      width: 165,
                      height: 165,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: isEmergency
                              ? [const Color(0xFFFF2A2A), const Color(0xFFB30000)]
                              : [const Color(0xFFFF4D4D), const Color(0xFFD90429)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.redAccent.withValues(alpha: 0.6),
                            blurRadius: 28,
                            spreadRadius: 4,
                          ),
                        ],
                      ),
                      child: Center(
                        child: isSending
                            ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 3)
                            : isCountingDown
                            ? Text(
                          "$secondsLeft",
                          style: const TextStyle(
                            fontSize: 60,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        )
                            : const Column(
                          mainAxisAlignment: MainAlignment.center,
                          children: [
                            Text(
                              "SOS",
                              style: TextStyle(
                                fontSize: 40,
                                color: Colors.white,
                                fontWeight: FontWeight.black,
                                letterSpacing: 2,
                              ),
                            ),
                            Text(
                              "PRESS / SAY HELP",
                              style: TextStyle(
                                fontSize: 9,
                                color: Colors.white70,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 1,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // BIOMETRIC CANCEL BUTTON
            if (isCountingDown)
              ElevatedButton.icon(
                icon: const Icon(Icons.fingerprint, color: Colors.white, size: 26),
                label: const Text(
                  "CANCEL ALERT (BIOMETRIC)",
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 0.8),
                ),
                onPressed: _cancelCountdown,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2A2A38),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                    side: const BorderSide(color: Colors.redAccent, width: 1),
                  ),
                  elevation: 8,
                ),
              ),

            const SizedBox(height: 30),

            // QUICK SAFETY SERVICES GRID
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(left: 4, bottom: 12),
                  child: Text(
                    "SAFETY SERVICES",
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const RideSafetyScreen()),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E1E2C),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white10),
                          ),
                          child: const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CircleAvatar(
                                radius: 20,
                                backgroundColor: Color(0xFF2D2A4A),
                                child: Icon(Icons.local_taxi, color: Colors.indigoAccent),
                              ),
                              SizedBox(height: 12),
                              Text(
                                "Ride Safety",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                "Track Taxi / Cab",
                                style: TextStyle(color: Colors.white38, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const ContactsScreen()),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E1E2C),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white10),
                          ),
                          child: const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CircleAvatar(
                                radius: 20,
                                backgroundColor: Color(0xFF4A2A2D),
                                child: Icon(Icons.people_alt, color: Colors.redAccent),
                              ),
                              SizedBox(height: 12),
                              Text(
                                "Guardians",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                "Emergency Contacts",
                                style: TextStyle(color: Colors.white38, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}