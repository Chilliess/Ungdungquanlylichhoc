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
  final supabase = Supabase.instance.client;

  nextScreen() async {
    await Future.delayed(Duration(seconds: 3));

    if (supabase.auth.currentSession == null){
      Navigator.pushReplacement(context,
          MaterialPageRoute(builder: (context) => Loginscreen())
      );
    } else {
      Navigator.pushReplacement(context,
          MaterialPageRoute(builder: (context) => MyHomePage())
      );
    }
  }

  @override
  void initState() {
    nextScreen();
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: FlutterLogo(
          size: 100,
        ),
      ),
    );
  }
}