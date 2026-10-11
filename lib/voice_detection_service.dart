import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:permission_handler/permission_handler.dart';

typedef SosTriggerCallback = void Function(String reason);

class VoiceDetectionService {
  Interpreter? _yamnetInterpreter;
  Interpreter? _classifierInterpreter;
  final AudioRecorder _audioRecorder = AudioRecorder();

  StreamSubscription<Uint8List>? _micSubscription;
  final List<int> _toneBufferBytes = [];

  static const int _sampleRate = 16000;
  static const int _bytesPerSample = 2; // 16-bit PCM
  static const int _toneWindowBytes = _sampleRate * _bytesPerSample; // ~1 second (32,000 bytes)

  // Strict threshold: 92% confidence + must hold for 2 consecutive frames
  static const double _toneConfidenceThreshold = 0.92;
  int _consecutiveHighScores = 0;

  // Added property for toggling on/off from UI
  bool isEnabled = true;

  final SosTriggerCallback onSosTriggered;

  VoiceDetectionService({required this.onSosTriggered});

  /// Starts loading TFLite models and streaming live audio into YAMNet
  Future<void> start() async {
    try {
      var micPermission = await Permission.microphone.request();
      if (!micPermission.isGranted) {
        print('❌ ML Voice Service: Microphone permission denied');
        return;
      }

      await _loadToneModels();
      print('🧠 ML Models Loaded Successfully: YAMNet + Distress Classifier');

      if (await _audioRecorder.hasPermission()) {
        final stream = await _audioRecorder.startStream(const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: _sampleRate,
          numChannels: 1,
        ));

        print('🎤 ML Audio Stream Started: Listening for distress tones...');
        _micSubscription = stream.listen(_onAudioChunk);
      }
    } catch (e) {
      print('❌ ML Voice Service Start Error: $e');
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

  void _onAudioChunk(Uint8List chunk) {
    if (!isEnabled) return; // Skip processing when paused from UI

    _toneBufferBytes.addAll(chunk);

    if (_toneBufferBytes.length >= _toneWindowBytes) {
      final windowBytes = Uint8List.fromList(_toneBufferBytes.sublist(0, _toneWindowBytes));
      _toneBufferBytes.removeRange(0, _toneWindowBytes);
      _runToneClassifier(windowBytes);
    }
  }

  void _runToneClassifier(Uint8List pcmBytes) {
    if (_yamnetInterpreter == null || _classifierInterpreter == null || !isEnabled) return;

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
      print('📊 ML DISTRESS CONFIDENCE SCORE: ${distressScore.toStringAsFixed(4)} | Threshold: $_toneConfidenceThreshold');

      if (distressScore >= _toneConfidenceThreshold) {
        _consecutiveHighScores++;
        if (_consecutiveHighScores >= 2) {
          _consecutiveHighScores = 0;
          print('🚨 HIGH DISTRESS SOUND CONFIRMED BY ML MODEL! (Score: $distressScore)');
          onSosTriggered('ML Scream Model (${(distressScore * 100).toStringAsFixed(0)}% confidence)');
        }
      } else {
        _consecutiveHighScores = 0;
      }
    } catch (e) {
      print('⚠️ ML Inference Error: $e');
    }
  }

  Future<void> dispose() async {
    await _micSubscription?.cancel();
    await _audioRecorder.stop();
    _audioRecorder.dispose();
    _yamnetInterpreter?.close();
    _classifierInterpreter?.close();
  }
}