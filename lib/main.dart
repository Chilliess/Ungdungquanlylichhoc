import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:untitled/splash/splashscreen.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'services/app_preferences.dart';
import 'widgets/assistant_overlay.dart';
import 'widgets/account_gate.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Khởi tạo dữ liệu ngôn ngữ cho intl (quan trọng để dùng 'vi_VN')
  await initializeDateFormatting('vi_VN', null);
  await Supabase.initialize(
      url: 'https://fjwdaccejrodpcicyxrc.supabase.co',
      anonKey: 'sb_publishable_99PN2b4I_XNZ8bf7yctZGw_M1Rl9mqs');

  await appPreferences.load();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  Widget _accountServices(Widget child) {
    // Splash/login can also render before backend initialization (previews and
    // startup tests). A real initialized session always passes through the gate.
    try {
      Supabase.instance.client;
    } catch (_) {
      return child;
    }
    return AccountGate(child: AssistantOverlay(child: child));
  }

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appPreferences,
      builder: (context, child) {
        return MaterialApp(
          title: 'Quản lý lịch học',
          debugShowCheckedModeBanner: false,
          theme: studyTheme(Brightness.light),
          darkTheme: studyTheme(Brightness.dark),
          themeMode: appPreferences.theme,
          builder: (context, child) {
            final media = MediaQuery.of(context);
            return MediaQuery(
              data: media.copyWith(
                disableAnimations:
                    media.disableAnimations || appPreferences.reduceMotion,
                textScaler: TextScaler.linear(
                    media.textScaler.scale(1) * appPreferences.textScale),
              ),
              child: _accountServices(child ?? const SizedBox.shrink()),
            );
          },
          home: const Splashscreen(),
        );
      },
    );
  }
}
