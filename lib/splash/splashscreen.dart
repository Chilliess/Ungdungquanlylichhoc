import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:untitled/auth/loginscreen.dart';
import 'package:untitled/homescreen.dart';

class Splashscreen extends StatefulWidget {
  const Splashscreen({super.key});

  @override
  State<Splashscreen> createState() => _SplashscreenState();
}

class _SplashscreenState extends State<Splashscreen> {
  /// Client Supabase.
  ///
  /// Truy cập theo kiểu lazy và bọc trong try/catch vì `Supabase.instance` sẽ
  /// ném AssertionError nếu `Supabase.initialize()` chưa được gọi (ví dụ khi
  /// chạy widget test). Khi đó app chuyển thẳng tới màn Login thay vì crash.
  SupabaseClient? get _supabaseClient {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  void nextScreen() {
    if (!mounted) return;

    final client = _supabaseClient;
    final hasSession = client?.auth.currentSession != null;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) =>
            hasSession ? const HomeScreen() : const Loginscreen(),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => nextScreen());
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: FlutterLogo(
          size: 100,
        ),
      ),
    );
  }
}
