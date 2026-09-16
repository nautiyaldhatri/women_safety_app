import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'login_screen.dart';
import 'vosk_test_screen.dart';
import 'app_home_listener_screen.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

late Interpreter interpreter;

Future loadModel() async {
  interpreter = await Interpreter.fromAsset('assets/models/model.tflite');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://msgzotmxqqurofawnjcd.supabase.co',
    anonKey: 'sb_publishable_q2Giprn7HQfEk0VnI5UjGg_KPQ06x6K',
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: LoginScreen(),
    );
  }
}
