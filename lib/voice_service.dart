import 'dart:async';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart';

class VoiceService {
  final SpeechToText _speech = SpeechToText();
  bool isListening = false;
  Timer? _restartTimer;

  // Exact distress phrase matchers
  final RegExp _distressPattern = RegExp(
    r'\b(help me|bachao|bachao mujhe|save me|help)\b',
    caseSensitive: false,
  );

  Future<bool> startListening({required Function(String phrase) onDistressDetected}) async {
    var micPermission = await Permission.microphone.request();
    if (!micPermission.isGranted) return false;

    try {
      bool available = await _speech.initialize(
        onError: (err) => _scheduleRestart(onDistressDetected),
        onStatus: (status) {
          if ((status == 'done' || status == 'notListening') && isListening) {
            _scheduleRestart(onDistressDetected);
          }
        },
      );

      if (available) {
        isListening = true;
        _listenLoop(onDistressDetected);
        return true;
      }
    } catch (_) {}

    isListening = false;
    return false;
  }

  void _listenLoop(Function(String phrase) onDistressDetected) {
    if (!isListening || _speech.isListening) return;

    _speech.listen(
      onResult: (result) {
        String words = result.recognizedWords.toLowerCase().trim();

        Match? match = _distressPattern.firstMatch(words);
        if (match != null) {
          String matchedPhrase = match.group(0) ?? 'help';
          stopListening();
          onDistressDetected('Voice Keyword: "$matchedPhrase"');
        }
      },
      listenFor: const Duration(seconds: 15),
      pauseFor: const Duration(seconds: 2),
      partialResults: true,
      cancelOnError: false,
    );
  }

  void _scheduleRestart(Function(String phrase) onDistressDetected) {
    if (!isListening) return;
    _restartTimer?.cancel();
    _restartTimer = Timer(const Duration(seconds: 2), () {
      if (isListening && !_speech.isListening) {
        _listenLoop(onDistressDetected);
      }
    });
  }

  void stopListening() {
    isListening = false;
    _restartTimer?.cancel();
    _speech.stop();
    
  }
}