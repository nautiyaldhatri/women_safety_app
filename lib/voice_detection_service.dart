import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:vosk_flutter/vosk_flutter.dart';
import 'package:permission_handler/permission_handler.dart';

typedef SosTriggerCallback = void Function(String reason);

class VoiceDetectionService {
  final _vosk = VoskFlutterPlugin.instance();
  final _modelLoader = ModelLoader();

  Model? _voskModel;
  Recognizer? _recognizer;
  SpeechService? _speechService;
  StreamSubscription? _voskResultSub;
  StreamSubscription? _voskPartialSub;

  Interpreter? _yamnetInterpreter;
  Interpreter? _classifierInterpreter;
  final AudioRecorder _audioRecorder = AudioRecorder();
  StreamSubscription<Uint8List>? _micSubscription;
  final List<int> _toneBufferBytes = [];

  static const int _sampleRate = 16000;
  static const int _bytesPerSample = 2;
  static const int _toneWindowBytes = _sampleRate * _bytesPerSample;

  static const double _toneConfidenceThreshold = 0.97;
  int _consecutiveHighScores = 0;
  static const int _requiredConsecutiveFrames = 3;

  final SosTriggerCallback onSosTriggered;
  final String languageCode; // 'en' or 'hi'

  VoiceDetectionService({
    required this.onSosTriggered,
    this.languageCode = 'en',
  });

  static const Map<String, List<String>> _distressPhrases = {
    'en': [
      'help',
      'help me',
      'save me',
      'emergency',
      'somebody help me',
      'someone is following me',
      'please help me',
      'i am in danger',
    ],
    'hi': [
      'bachao',
      'bachao mujhe',
      'madad',
      'mujhe bachao',
      'koi mera peecha kar raha hai',
      'meri madad karo',
      'police ko bulao',
    ],
  };

  Future<void> start() async {
    try {
      var micPermission = await Permission.microphone.request();
      if (!micPermission.isGranted) {
        print('❌ Microphone permission denied');
        return;
      }

      // 1. Initialize Vosk Speech Engine using assets from your folder structure
      final modelAssetPath = languageCode == 'hi'
          ? 'assets/models/vosk-model-small-hi-0.22.zip'
          : 'assets/models/vosk-model-small-en-us-0.15.zip';

      final modelPath = await _modelLoader.loadFromAssets(modelAssetPath);
      _voskModel = await _vosk.createModel(modelPath);
      _recognizer = await _vosk.createRecognizer(
        model: _voskModel!,
        sampleRate: _sampleRate,
      );

      _speechService = await _vosk.initSpeechService(_recognizer!);

      _voskResultSub = _speechService!.onResult().listen((json) => _handleSpeech(json, false));
      _voskPartialSub = _speechService!.onPartial().listen((json) => _handleSpeech(json, true));
      await _speechService!.start();
      print('🗣️ Vosk Speech Recognition Started ($languageCode)');

      // 2. Initialize TFLite Acoustic Models
      await _loadToneModels();

      // 3. Start Live Audio Stream for TFLite Scream Detection
      if (await _audioRecorder.hasPermission()) {
        final stream = await _audioRecorder.startStream(const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: _sampleRate,
          numChannels: 1,
        ));

        _micSubscription = stream.listen(_onAudioChunk);
        print('🎤 Acoustic Scream Stream Started');
      }
    } catch (e) {
      print('❌ VoiceDetectionService Start Error: $e');
    }
  }

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

  void _handleSpeech(String jsonString, bool isPartial) {
    try {
      final decoded = jsonDecode(jsonString);
      final textKey = isPartial ? 'partial' : 'text';
      final text = (decoded[textKey] as String?)?.toLowerCase().trim() ?? '';
      if (text.isEmpty) return;

      print('📝 Vosk Heard (${isPartial ? "Partial" : "Final"}): "$text"');

      // Combine BOTH English and Hindi phrases into one unified scan list
      final allPhrases = [
        ...(_distressPhrases['en'] ?? []),
        ...(_distressPhrases['hi'] ?? []),
      ];

      for (final phrase in allPhrases) {
        // 1. Direct match or substring match (e.g., "bachao mujhe" inside a sentence)
        // 2. Component word matching for distance: if phrase has multiple words,
        //    trigger if key strong words (length > 3) match.
        final words = phrase.split(' ');
        bool isMatched = text.contains(phrase) ||
            (words.length > 1 && words.any((w) => w.length > 3 && text.contains(w))) ||
            (words.length == 1 && text.contains(phrase));

        if (isMatched) {
          print('🚨 DUAL-LANGUAGE EMERGENCY TRIGGERED: "$phrase" found in "$text"');
          onSosTriggered('Emergency Keyword: "$phrase"');
          return;
        }
      }
    } catch (e) {
      print('⚠️ Speech parsing error: $e');
    }
  }

  void _onAudioChunk(Uint8List chunk) {
    _toneBufferBytes.addAll(chunk);

    if (_toneBufferBytes.length >= _toneWindowBytes) {
      final windowBytes = Uint8List.fromList(_toneBufferBytes.sublist(0, _toneWindowBytes));
      _toneBufferBytes.removeRange(0, _toneWindowBytes);
      _runToneClassifier(windowBytes);
    }
  }

  void _runToneClassifier(Uint8List pcmBytes) {
    if (_yamnetInterpreter == null || _classifierInterpreter == null) return;

    try {
      final byteData = ByteData.sublistView(pcmBytes);
      final sampleCount = pcmBytes.length ~/ 2;
      final waveform = Float32List(sampleCount);

      for (var i = 0; i < sampleCount; i++) {
        final sample = byteData.getInt16(i * 2, Endian.little);
        waveform[i] = sample / 32768.0;
      }

      var yamnetOutputTensors = _yamnetInterpreter!.getOutputTensors();
      var yamnetOutputs = <int, Object>{};

      for (int i = 0; i < yamnetOutputTensors.length; i++) {
        var shape = yamnetOutputTensors[i].shape;
        if (shape.length == 2) {
          yamnetOutputs[i] = List.generate(shape[0], (_) => List.filled(shape[1], 0.0));
        } else if (shape.length == 3) {
          yamnetOutputs[i] = List.generate(
              shape[0], (_) => List.generate(shape[1], (_) => List.filled(shape[2], 0.0)));
        }
      }

      _yamnetInterpreter!.runForMultipleInputs([waveform], yamnetOutputs);

      List<double> embeddingVector;
      if (yamnetOutputs.containsKey(1) && (yamnetOutputs[1] as List).isNotEmpty) {
        embeddingVector = List<double>.from((yamnetOutputs[1] as List)[0]);
      } else {
        int idx = (yamnetOutputs[0] as List).length > 1 ? 1 : 0;
        embeddingVector = List<double>.from((yamnetOutputs[0] as List)[idx]);
      }

      if (embeddingVector.length > 1024) {
        embeddingVector = embeddingVector.sublist(0, 1024);
      } else if (embeddingVector.length < 1024) {
        embeddingVector = List<double>.from(embeddingVector)..addAll(List.filled(1024 - embeddingVector.length, 0.0));
      }

      final classifierInput = [embeddingVector];
      final classifierOutput = List.generate(1, (_) => List.filled(1, 0.0));

      _classifierInterpreter!.run(classifierInput, classifierOutput);

      final double distressScore = classifierOutput[0][0];

      if (distressScore >= _toneConfidenceThreshold) {
        _consecutiveHighScores++;
        if (_consecutiveHighScores >= _requiredConsecutiveFrames) {
          _consecutiveHighScores = 0;
          print('🚨 HIGH DISTRESS SOUND CONFIRMED BY ML MODEL! (Score: $distressScore)');
          onSosTriggered('Acoustic Scream (${(distressScore * 100).toStringAsFixed(0)}%)');
        }
      } else {
        if (_consecutiveHighScores > 0) {
          _consecutiveHighScores--;
        }
      }
    } catch (e) {
      print('⚠️ ML Inference Error: $e');
    }
  }

  Future<void> dispose() async {
    await _micSubscription?.cancel();
    await _audioRecorder.stop();
    _audioRecorder.dispose();
    await _voskResultSub?.cancel();
    await _voskPartialSub?.cancel();
    await _speechService?.stop();
    await _speechService?.dispose();
    await _recognizer?.dispose();
          _voskModel?.dispose();
    _yamnetInterpreter?.close();
    _classifierInterpreter?.close();
  }
}