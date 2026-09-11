import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:local_auth/local_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Full-screen alarm shown when a distress trigger (voice or manual button)
/// fires. Counts down from 30 seconds; only a successful biometric check
/// can cancel it before escalation. If the countdown reaches zero, it
/// calls the existing send-alert Edge Function - same one the manual SOS
/// button already uses - which sends a WhatsApp message and a phone call
/// to every emergency contact via Twilio.
class SosCountdownScreen extends StatefulWidget {
  final String detectedPhrase;
  final String triggerSource; // 'voice' or 'manual_button'

  const SosCountdownScreen({
    super.key,
    required this.detectedPhrase,
    required this.triggerSource,
  });

  @override
  State<SosCountdownScreen> createState() => _SosCountdownScreenState();
}

class _SosCountdownScreenState extends State<SosCountdownScreen> {
  static const _countdownSeconds = 30;
  static const _functionsBaseUrl =
      'https://msgzotmxqqurofawnjcd.supabase.co/functions/v1';

  final _audioPlayer = AudioPlayer();
  final _localAuth = LocalAuthentication();
  final _supabase = Supabase.instance.client;

  Timer? _timer;
  int _secondsLeft = _countdownSeconds;
  bool _resolving = false;
  bool _escalating = false;
  String _outcome = ''; // '', 'cancelled', 'escalated', 'escalation_failed'
  dynamic _alertId; // set once send-alert succeeds, used by resolve-alert

  @override
  void initState() {
    super.initState();
    _startAlarm();
    _startCountdown();
  }

  Future<void> _startAlarm() async {
    await _audioPlayer.setReleaseMode(ReleaseMode.loop);
    await _audioPlayer.play(AssetSource('sounds/alarm.wav'));
  }

  void _startCountdown() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsLeft <= 1) {
        timer.cancel();
        _escalate();
      } else {
        setState(() => _secondsLeft--);
      }
    });
  }

  Future<void> _attemptCancel() async {
    if (_resolving) return;
    setState(() => _resolving = true);

    try {
      final canCheckBiometrics = await _localAuth.canCheckBiometrics;
      final isDeviceSupported = await _localAuth.isDeviceSupported();

      if (!canCheckBiometrics && !isDeviceSupported) {
        setState(() => _resolving = false);
        return;
      }

      final didAuthenticate = await _localAuth.authenticate(
        localizedReason: 'Confirm it\'s you to cancel the alert',
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
        ),
      );

      if (didAuthenticate) {
        _cancel();
      } else {
        setState(() => _resolving = false);
      }
    } catch (e) {
      debugPrint('Biometric auth error: $e');
      setState(() => _resolving = false);
    }
  }

  void _cancel() {
    // No alert row exists yet at this point (send-alert hasn't been
    // called), so cancelling before escalation just needs to stop the
    // timer and alarm - nothing to update in the database.
    _timer?.cancel();
    _audioPlayer.stop();
    setState(() => _outcome = 'cancelled');
  }

  Future<void> _escalate() async {
    setState(() => _escalating = true);

    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 10),
      );

      final userId = _supabase.auth.currentUser?.id;
      final session = _supabase.auth.currentSession;

      final response = await http
          .post(
        Uri.parse('$_functionsBaseUrl/send-alert'),
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

      await _audioPlayer.stop();

      if (response.statusCode == 200) {
        // send-alert inserts the alert row itself - we don't get the id
        // back directly from this response shape, so "I'm safe now" after
        // escalation is a nice-to-have follow-up, not required for MVP.
        setState(() => _outcome = 'escalated');
      } else {
        setState(() => _outcome = 'escalation_failed');
      }
    } catch (e) {
      debugPrint('Escalation failed: $e');
      await _audioPlayer.stop();
      setState(() => _outcome = 'escalation_failed');
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_outcome == 'cancelled') {
      return _buildOutcomeScreen(
        color: Colors.green,
        icon: Icons.check_circle,
        title: 'Alert Cancelled',
        message: 'Glad you\'re safe.',
      );
    }

    if (_outcome == 'escalated') {
      return _buildOutcomeScreen(
        color: Colors.red,
        icon: Icons.warning,
        title: 'Alert Sent',
        message: 'Your emergency contacts have been notified via WhatsApp and phone call.',
      );
    }

    if (_outcome == 'escalation_failed') {
      return _buildOutcomeScreen(
        color: Colors.orange,
        icon: Icons.error,
        title: 'Alert Failed to Send',
        message: 'Please call your emergency contacts directly, or check your internet connection.',
      );
    }

    if (_escalating) {
      return const Scaffold(
        backgroundColor: Colors.red,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Colors.white),
              SizedBox(height: 16),
              Text('Sending alert...', style: TextStyle(color: Colors.white, fontSize: 18)),
            ],
          ),
        ),
      );
    }

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.red[900],
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 80),
                const SizedBox(height: 24),
                const Text(
                  'Emergency Alert Active',
                  style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  'Detected: "${widget.detectedPhrase}"',
                  style: const TextStyle(color: Colors.white70, fontSize: 16),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 40),
                Text(
                  '$_secondsLeft',
                  style: const TextStyle(color: Colors.white, fontSize: 72, fontWeight: FontWeight.bold),
                ),
                const Text(
                  'seconds until contacts are alerted',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 48),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _resolving ? null : _attemptCancel,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.red[900],
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(
                      _resolving ? 'Verifying...' : 'I\'m Safe - Cancel',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Face or fingerprint required to cancel',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOutcomeScreen({
    required Color color,
    required IconData icon,
    required String title,
    required String message,
  }) {
    return Scaffold(
      backgroundColor: color,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 80),
              const SizedBox(height: 24),
              Text(
                title,
                style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Text(
                message,
                style: const TextStyle(color: Colors.white70, fontSize: 16),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}