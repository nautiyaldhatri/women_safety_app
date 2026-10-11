import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'login_screen.dart';
import 'home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Optional but recommended: make status bar & nav bar transparent/dark
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF12121A),
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  await Supabase.initialize(
    url: 'https://msgzotmxqqurofawnjcd.supabase.co',
    anonKey: 'sb_publishable_q2Giprn7HQfEk0VnI5UjGg_KPQ06x6K', // keep your real key
  );

  runApp(const SafeSheApp());
}

class SafeSheApp extends StatelessWidget {
  const SafeSheApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SafeShe AI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF12121A),
        useMaterial3: true,
      ),
      // =========================================================
      // GLOBAL FIX FOR SYSTEM NAVIGATION BAR OVERLAP
      // =========================================================
      builder: (context, child) {
        return Container(
          color: const Color(0xFF12121A), // your dark background
          child: SafeArea(
            top: false,          // keep status bar edge-to-edge if you want
            bottom: true,        // ← this is the important part
            left: false,
            right: false,
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
      home: const AuthGate(),
    );
  }
}

/// Simple gate so we stay on Login or go to Home after auth
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final session = Supabase.instance.client.auth.currentSession;
    if (session != null) {
      return const HomeScreen();
    }
    return const LoginScreen();
  }
}