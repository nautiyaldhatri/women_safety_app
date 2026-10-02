import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:record/record.dart';
import 'package:vosk_flutter/vosk_flutter.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'dart:io';
import 'package:path_provider/path_provider.dart';

typedef SosTriggerCallback = void Function(String detectedPhrase, bool viaWakeName);

/// Voice detection service - manually captures microphone audio and feeds
/// the SAME audio into two parallel paths:
///   1. Vosk recognizer -> text -> wake name / distress phrase matching
///   2. YAMNet -> embeddings -> distress classifier -> tone confidence score
/// A trigger fires on either a confirmed text match, OR a high-confidence
/// tone match (as an extra layer alongside the existing text-based logic).
class VoiceDetectionService {
  final _vosk = VoskFlutterPlugin.instance();
  final _modelLoader = ModelLoader();

  Recognizer? _recognizer;
  Interpreter? _yamnetInterpreter;
  Interpreter? _classifierInterpreter;
  final AudioRecorder _audioRecorder = AudioRecorder();

  StreamSubscription<Uint8List>? _micSubscription;
  Timer? _activeWindowTimer;
  bool _activeWindowOpen = false;

  // Rolling buffer for the tone-classifier path. YAMNet expects ~1 second
  // of 16kHz mono float audio per inference.
  final List<int> _toneBufferBytes = [];
  static const int _sampleRate = 16000;
  static const int _bytesPerSample = 2; // 16-bit PCM
  static const int _toneWindowBytes = _sampleRate * _bytesPerSample; // ~1 second

  static const _activeWindowDuration = Duration(seconds: 10);
  static const double _toneConfidenceThreshold = 0.85; // stricter than text-only

  static const Map<String, List<String>> _distressPhrasesByLang = {
    'en': ['help me', 'help'],
    'hi': ['bachao mujhe', 'bachao'],
  };

  static const List<String> _wakeNames = [
    'kavach', 'sakhi', 'durga', 'shakti', 'diya', 'amba',
  ];

  final SosTriggerCallback onSosTriggered;
  final String languageCode;

  VoiceDetectionService({
    required this.onSosTriggered,
    required this.languageCode,
  });

  List<String> get _distressPhrases =>
      _distressPhrasesByLang[languageCode] ?? _distressPhrasesByLang['en']!;

  String get _voskModelAssetPath => languageCode == 'hi'
      ? 'assets/models/vosk-model-small-hi-0.22.zip'
      : 'assets/models/vosk-model-small-en-us-0.15.zip';

  Future<void> start() async {
    // --- Set up Vosk (text path) ---
    final modelPath = await _modelLoader.loadFromAssets(_voskModelAssetPath);
    final model = await _vosk.createModel(modelPath);
    _recognizer = await _vosk.createRecognizer(model: model, sampleRate: _sampleRate);

    // --- Set up YAMNet + classifier (tone path) ---
    await _loadToneModels();
    print('✅ YAMNet + classifier models loaded successfully');

    // --- Start manual mic capture, feeding both paths ---
    if (!await _audioRecorder.hasPermission()) {
      throw Exception('Microphone permission not granted');
    }

    final stream = await _audioRecorder.startStream(const RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: _sampleRate,
      numChannels: 1,
    ));

    _micSubscription = stream.listen(_onAudioChunk);
  }

  /// Copies bundled .tflite assets to a real file path (interpreters need
  /// an actual file, not an asset bundle reference) and loads them.
  Future<void> _loadToneModels() async {
    final yamnetPath = await _copyAssetToFile('assets/models/yamnet.tflite', 'yamnet.tflite');
    final classifierPath = await _copyAssetToFile(
        'assets/models/distress_classifier.tflite', 'distress_classifier.tflite');

    _yamnetInterpreter = Interpreter.fromFile(File(yamnetPath));
    _classifierInterpreter = Interpreter.fromFile(File(classifierPath));
  }

  Future<String> _copyAssetToFile(String assetPath, String filename) async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$filename');
    if (!await file.exists()) {
      final bytes = await rootBundle.load(assetPath);
      await file.writeAsBytes(bytes.buffer.asUint8List());
    }
    return file.path;
  }

  void _onAudioChunk(Uint8List chunk) {
    // --- Feed Vosk (text path) ---
    _recognizer?.acceptWaveformBytes(chunk).then((resultReady) async {
      if (resultReady) {
        final result = await _recognizer!.getResult();
        _handleTextResult(result);
      }
    });

    // --- Feed the tone-classifier rolling buffer ---
    _toneBufferBytes.addAll(chunk);
    if (_toneBufferBytes.length >= _toneWindowBytes) {
      final windowBytes = Uint8List.fromList(_toneBufferBytes.sublist(0, _toneWindowBytes));
      _toneBufferBytes.removeRange(0, _toneWindowBytes);
      _runToneClassifier(windowBytes);
    }
  }

  void _handleTextResult(String resultJson) {
    final decoded = jsonDecode(resultJson);
    final text = (decoded['text'] as String?)?.toLowerCase().trim() ?? '';
    if (text.isEmpty) return;

    if (_activeWindowOpen) {
      for (final phrase in _distressPhrases) {
        if (text.contains(phrase)) {
          _closeActiveWindow();
          onSosTriggered(phrase, true);
          return;
        }
      }
      return;
    }

    for (final name in _wakeNames) {
      if (text.contains(name)) {
        _openActiveWindow();
        return;
      }
    }

    for (final phrase in _distressPhrases) {
      if (text == phrase) {
        onSosTriggered(phrase, false);
        return;
      }
    }
  }

  void _runToneClassifier(Uint8List pcmBytes) {
    if (_yamnetInterpreter == null || _classifierInterpreter == null) return;

    try {
      // Convert 16-bit PCM bytes to normalized float32 [-1.0, 1.0]
      final byteData = ByteData.sublistView(pcmBytes);
      final sampleCount = pcmBytes.length ~/ 2;
      final waveform = Float32List(sampleCount);
      for (var i = 0; i < sampleCount; i++) {
        final sample = byteData.getInt16(i * 2, Endian.little);
        waveform[i] = sample / 32768.0;
      }

      // Run YAMNet: input is the waveform, output includes embeddings.
      // NOTE: YAMNet's output tensor shapes can be dynamic (frame count
      // depends on input length) - this may need adjustment once tested
      // on a real device. Check output tensor shape via
      // _yamnetInterpreter!.getOutputTensors() while debugging if this
      // doesn't run cleanly on first try.
      final embeddingOutput = List.generate(1, (_) => List.filled(1024, 0.0));
      _yamnetInterpreter!.run(waveform, embeddingOutput);

      // Run our classifier on the embedding
      final input = [embeddingOutput[0]];
      final output = List.generate(1, (_) => List.filled(1, 0.0));
      _classifierInterpreter!.run(input, output);

      final distressScore = output[0][0];
      print('🎤 Tone score: ${distressScore.toStringAsFixed(3)}');
      if (distressScore >= _toneConfidenceThreshold) {
        onSosTriggered('distress tone detected', false);
      }
    } catch (e) {
      // Tone classification is an enhancement layer - if it fails, text
      // detection still works independently. Log and continue.
      print('Tone classifier error: $e');
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

  Future<void> dispose() async {
    _activeWindowTimer?.cancel();
    await _micSubscription?.cancel();
    await _audioRecorder.stop();
    _audioRecorder.dispose();
    _yamnetInterpreter?.close();
    _classifierInterpreter?.close();
  }
}