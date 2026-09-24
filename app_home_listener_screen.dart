import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'voice_detection_service.dart';
import 'sos_countdown_screen.dart';

/// Main listening screen: fetches the user's chosen wake name and language,
/// starts VoiceDetectionService, and navigates to the SOS countdown screen
/// whenever a trigger is confirmed. This is what main.dart's home: should
/// point to once you're done testing.
class AppHomeListenerScreen extends StatefulWidget {
  const AppHomeListenerScreen({super.key});

  @override
  State<AppHomeListenerScreen> createState() => _AppHomeListenerScreenState();
}

class _AppHomeListenerScreenState extends State<AppHomeListenerScreen> {
  final _supabase = Supabase.instance.client;

  VoiceDetectionService? _voiceService;
  String _statusText = 'Loading your profile...';
  String? _wakeWordName;

  @override
  void initState() {
    super.initState();
    _loadProfileAndStartListening();
  }

  Future<void> _loadProfileAndStartListening() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        setState(() => _statusText = 'Not logged in');
        return;
      }

      final profile = await _supabase
          .from('profiles')
          .select('wake_word_name, preferred_language')
          .eq('id', userId)
          .single();

      final wakeWordName = profile['wake_word_name'] as String? ?? 'Kavach';
      final language = profile['preferred_language'] as String? ?? 'en';

      setState(() {
        _wakeWordName = wakeWordName;
        _statusText = 'Starting voice detection...';
      });

      _voiceService = VoiceDetectionService(
        languageCode: language,
        onSosTriggered: _handleSosTriggered,
      );
      await _voiceService!.start();

      setState(() => _statusText = 'Listening');
    } catch (e) {
      debugPrint('Failed to start voice detection: $e');
      setState(() => _statusText = 'Error starting detection: $e');
    }
  }

  void _handleSosTriggered(String detectedPhrase, bool viaWakeName) {
    _navigateToCountdown(
      detectedPhrase: detectedPhrase,
      triggerSource: 'voice',
    );
  }

  void _handleManualTrigger() {
    _navigateToCountdown(
      detectedPhrase: 'manual button press',
      triggerSource: 'manual_button',
    );
  }

  void _navigateToCountdown({
    required String detectedPhrase,
    required String triggerSource,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => SosCountdownScreen(
          detectedPhrase: detectedPhrase,
          triggerSource: triggerSource,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _voiceService?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Women Safety App')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _statusText == 'Listening' ? Icons.mic : Icons.mic_off,
              size: 64,
              color: _statusText == 'Listening' ? Colors.green : Colors.grey,
            ),
            const SizedBox(height: 16),
            Text(_statusText, style: const TextStyle(fontSize: 16)),
            if (_wakeWordName != null) ...[
              const SizedBox(height: 8),
              Text(
                'Say "$_wakeWordName" to activate',
                style: const TextStyle(fontSize: 14, color: Colors.grey),
              ),
            ],
            const SizedBox(height: 40),
            // Manual SOS button as a fallback - always works regardless
            // of voice detection status.
            ElevatedButton.icon(
              onPressed: _handleManualTrigger,
              icon: const Icon(Icons.warning),
              label: const Text('Manual SOS'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
