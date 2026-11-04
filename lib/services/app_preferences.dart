import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

final appPreferences = AppPreferences();

class AppPreferences extends ChangeNotifier {
  ThemeMode theme = ThemeMode.system;
  double textScale = 1;
  bool reduceMotion = false;
  bool showAssistant = true;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    final saved = p.getString('appearance_theme');
    theme = saved == null
        ? (p.containsKey('is_dark_mode')
            ? (p.getBool('is_dark_mode')! ? ThemeMode.dark : ThemeMode.light)
            : ThemeMode.system)
        : ThemeMode.values
            .firstWhere((v) => v.name == saved, orElse: () => ThemeMode.system);
    textScale = (p.getDouble('appearance_scale') ?? 1).clamp(1, 1.3);
    reduceMotion = p.getBool('appearance_reduce_motion') ?? false;
    showAssistant = p.getBool('assistant_visible') ?? true;
    notifyListeners();
  }

  Future<void> update(
      {ThemeMode? themeMode,
      double? scale,
      bool? reduced,
      bool? assistant}) async {
    theme = themeMode ?? theme;
    textScale = (scale ?? textScale).clamp(1, 1.3);
    reduceMotion = reduced ?? reduceMotion;
    showAssistant = assistant ?? showAssistant;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setString('appearance_theme', theme.name);
    await p.setDouble('appearance_scale', textScale);
    await p.setBool('appearance_reduce_motion', reduceMotion);
    await p.setBool('assistant_visible', showAssistant);
  }
}
