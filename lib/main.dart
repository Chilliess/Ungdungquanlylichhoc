import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:untitled/splash/splashscreen.dart';
import 'package:intl/date_symbol_data_local.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Khởi tạo dữ liệu ngôn ngữ cho intl (quan trọng để dùng 'vi_VN')
  await initializeDateFormatting('vi_VN', null);
  await Supabase.initialize(
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
      debugShowCheckedModeBanner: false,
      title: 'App Lịch Học',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: Splashscreen(),
    );
  }
}
