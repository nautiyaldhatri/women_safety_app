import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:vosk_flutter/vosk_flutter.dart';

/// Throwaway test screen: confirms Vosk loads correctly and transcribes
/// live speech. Not part of the final app UI — just a validation step.
class VoskTestScreen extends StatefulWidget {
  const VoskTestScreen({super.key});

  @override
  State<VoskTestScreen> createState() => _VoskTestScreenState();
}

class _VoskTestScreenState extends State<VoskTestScreen> {
  final _vosk = VoskFlutterPlugin.instance();
  final _modelLoader = ModelLoader();

  SpeechService? _speechService;

  String _liveText = '';
  String _status = 'Not started';
  bool _recognitionStarted = false;

  static const _sampleRate = 16000;
  // Change this to the Hindi zip filename to test that model instead.
  static const _modelAssetPath =
      'assets/models/vosk-model-small-en-us-0.15.zip';

  @override
  void initState() {
    super.initState();
    _initVosk();
  }

  Future<void> _initVosk() async {
    // Mic permission must be granted before Vosk can listen.
    final micStatus = await Permission.microphone.request();
    if (!micStatus.isGranted) {
      setState(() => _status = 'Microphone permission denied');
      return;
    }

    try {
      setState(() => _status = 'Loading model... (first run takes longer)');

      final modelPath = await _modelLoader.loadFromAssets(_modelAssetPath);
      final model = await _vosk.createModel(modelPath);
      final recognizer = await _vosk.createRecognizer(
        model: model,
        sampleRate: _sampleRate,
      );

      final speechService = await _vosk.initSpeechService(recognizer);

      speechService.onPartial().listen((partial) {
        // Partial results are JSON like {"partial": "help me"}
        final decoded = jsonDecode(partial);
        final text = decoded['partial'] ?? '';
        if (text.isNotEmpty) {
          setState(() => _liveText = text);
        }
      });

      speechService.onResult().listen((result) {
        // Final results are JSON like {"text": "help me"}
        final decoded = jsonDecode(result);
        final text = decoded['text'] ?? '';
        if (text.isNotEmpty) {
          setState(() => _liveText = text);
        }
      });

      setState(() {
        _speechService = speechService;
        _status = 'Ready';
      });
    } catch (e) {
      setState(() => _status = 'Error: $e');
    }
  }

  Future<void> _toggleListening() async {
    if (_speechService == null) return;

    if (_recognitionStarted) {
      await _speechService!.stop();
    } else {
      await _speechService!.start();
    }
    setState(() => _recognitionStarted = !_recognitionStarted);
  }

  @override
  void dispose() {
    _speechService?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Vosk Test')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Status: $_status', style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _speechService == null ? null : _toggleListening,
              child: Text(
                _recognitionStarted ? 'Stop Listening' : 'Start Listening',
              ),
            ),
            const SizedBox(height: 32),
            const Text('Heard:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              _liveText.isEmpty ? '(nothing yet)' : _liveText,
              style: const TextStyle(fontSize: 22),
            ),
          ],
        ),
      ),
    );
  }
}
