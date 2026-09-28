import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:untitled/auth/loginscreen.dart';
import 'homescreen.dart';

void main() {
  Supabase.initialize(
      url: 'https://fjwdaccejrodpcicyxrc.supabase.co',
      anonKey: 'sb_publishable_99PN2b4I_XNZ8bf7yctZGw_M1Rl9mqs'
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: Loginscreen(),
    );
  }
}
