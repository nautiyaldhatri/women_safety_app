import 'dart:async';
import 'dart:convert';
import 'package:vosk_flutter/vosk_flutter.dart';

/// Callback fired when a real distress trigger is confirmed.
/// [detectedPhrase] is the exact text that triggered it.
/// [viaWakeName] is true if it came through the wake-name -> active-window
/// path, false if it was a direct distress-phrase match (no wake name said).
typedef SosTriggerCallback = void Function(String detectedPhrase, bool viaWakeName);

/// Handles continuous voice detection: listens for the user's chosen wake
/// name, opens a short active-listening window, and checks for distress
/// phrases either within that window or as a direct (stricter) match.
class VoiceDetectionService {
  final _vosk = VoskFlutterPlugin.instance();
  final _modelLoader = ModelLoader();

  Model? _model;
  Recognizer? _recognizer;
  SpeechService? _speechService;
  StreamSubscription? _resultSubscription;
  Timer? _activeWindowTimer;

  bool _activeWindowOpen = false;

  static const _sampleRate = 16000;
  static const _activeWindowDuration = Duration(seconds: 10);

  // Distress phrases, one list per supported language.
  static const Map<String, List<String>> _distressPhrasesByLang = {
    'en': ['help me', 'help'],
    'hi': ['bachao mujhe', 'bachao'],
  };

  // Wake names - same list regardless of language, since these are proper
  // nouns the user picked from the preset list.
  static const List<String> _wakeNames = [
    'kavach',
    'sakhi',
    'durga',
    'shakti',
    'diya',
    'amba',
  ];

  final SosTriggerCallback onSosTriggered;
  final String languageCode; // 'en' or 'hi'

  VoiceDetectionService({
    required this.onSosTriggered,
    required this.languageCode,
  });

  List<String> get _distressPhrases =>
      _distressPhrasesByLang[languageCode] ?? _distressPhrasesByLang['en']!;

  String get _modelAssetPath => languageCode == 'hi'
      ? 'assets/models/vosk-model-small-hi-0.22.zip'
      : 'assets/models/vosk-model-small-en-us-0.15.zip';

  /// Loads the model and starts continuous background listening.
  /// Call this once, e.g. from your app's startup / home screen initState.
  Future<void> start() async {
    final modelPath = await _modelLoader.loadFromAssets(_modelAssetPath);
    final model = await _vosk.createModel(modelPath);
    final recognizer = await _vosk.createRecognizer(
      model: model,
      sampleRate: _sampleRate,
    );
    final speechService = await _vosk.initSpeechService(recognizer);

    _resultSubscription = speechService.onResult().listen(_handleResult);

    _model = model;
    _recognizer = recognizer;
    _speechService = speechService;

    await speechService.start();
  }

  void _handleResult(String resultJson) {
    final decoded = jsonDecode(resultJson);
    final text = (decoded['text'] as String?)?.toLowerCase().trim() ?? '';
    if (text.isEmpty) return;

    if (_activeWindowOpen) {
      // We're in the post-wake-name window: check for a distress phrase
      // with a looser threshold (any distress phrase anywhere in the text).
      for (final phrase in _distressPhrases) {
        if (text.contains(phrase)) {
          _closeActiveWindow();
          onSosTriggered(phrase, true);
          return;
        }
      }
      // Didn't match this time, keep the window open until it expires.
      return;
    }

    // Not in an active window: check for the wake name first.
    for (final name in _wakeNames) {
      if (text.contains(name)) {
        _openActiveWindow();
        return;
      }
    }

    // No wake name heard: fall back to a direct, stricter distress-phrase
    // check. "Stricter" here means the phrase must be the ENTIRE
    // recognized utterance, not just contained somewhere in a longer
    // sentence - reduces accidental triggers from casual conversation.
    for (final phrase in _distressPhrases) {
      if (text == phrase) {
        onSosTriggered(phrase, false);
        return;
      }
    }
  }

  void _openActiveWindow() {
    _activeWindowOpen = true;
    _activeWindowTimer?.cancel();
    _activeWindowTimer = Timer(_activeWindowDuration, _closeActiveWindow);
  }

  void _closeActiveWindow() {
    _activeWindowOpen = false;
    _activeWindowTimer?.cancel();
    _activeWindowTimer = null;
  }

  /// Call this when the app is closing or voice detection should stop.
  Future<void> dispose() async {
    _activeWindowTimer?.cancel();
    await _resultSubscription?.cancel();
    await _speechService?.dispose();
  }
}