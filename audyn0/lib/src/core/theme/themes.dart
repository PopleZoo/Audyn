import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:audyn/src/data/services/hive_box.dart';

class Themes {
  static final List<ThemeColor> _themes = [
    AudyndefaultBlueTheme(),
    AudyndefaultIndigoTheme(),
  ];

  static final List<String> _themeNames = [
    'AudyndefaultBlue',
    'AudyndefaultIndigo',
    'Custom',
  ];

  static List<ThemeColor> get themes => _themes;
  static List<String> get themeNames => _themeNames;

  static ThemeColor getThemeFromKey(String key) {
    switch (key) {
      case 'AudyndefaultBlue':
        return _themes[0];
      case 'AudyndefaultIndigo':
        return _themes[1];
      case 'Custom':
        return CustomTheme(
          themeName: 'Custom',
          primaryColor: const Color(0xFF101010),
          secondaryColor: const Color(0xFF00BFFF),
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFF00BFFF),
            secondary: Color(0xFF40C4FF),
            background: Color(0xFF101010),
            surface: Color(0xFF181818),
            onPrimary: Colors.white,
            onSecondary: Colors.white,
            onBackground: Colors.white70,
            onSurface: Colors.white70,
            error: Colors.redAccent,
            onError: Colors.white,
          ),
        );
      default:
        return _themes[0];
    }
  }

  static Future<void> setTheme(String themeName) async {
    final box = Hive.box(HiveBox.boxName);
    await box.put(HiveBox.themeKey, themeName);
  }

  static String getThemeName() {
    final box = Hive.box(HiveBox.boxName);
    return box.get(HiveBox.themeKey, defaultValue: 'AudyndefaultBlue') as String;
  }

  static ThemeColor getTheme() {
    final name = getThemeName();
    return getThemeFromKey(name);
  }
}

abstract class ThemeColor {
  final String themeName;
  final Color primaryColor; // App background
  final Color secondaryColor; // Accent
  final ColorScheme colorScheme;

  const ThemeColor({
    required this.themeName,
    required this.primaryColor,
    required this.secondaryColor,
    required this.colorScheme,
  });
}

class AudyndefaultBlueTheme extends ThemeColor {
  AudyndefaultBlueTheme()
      : super(
    themeName: 'AudyndefaultBlue',
    primaryColor: const Color(0xFF121212),
    secondaryColor: const Color(0xFF1DB9FF),
    colorScheme: const ColorScheme.dark(
      primary: Color(0xFF1DB9FF),       // Buttons / Highlights
      secondary: Color(0xFF59CBFF),     // Additional Accents
      background: Color(0xFF121212),    // Scaffold background
      surface: Color(0xFF1A1A1A),       // Cards, Panels
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onBackground: Colors.white70,
      onSurface: Colors.white70,
      error: Colors.redAccent,
      onError: Colors.white,
    ),
  );
}

class AudyndefaultIndigoTheme extends ThemeColor {
  AudyndefaultIndigoTheme()
      : super(
    themeName: 'AudyndefaultIndigo',
    primaryColor: const Color(0xFF0F1324),
    secondaryColor: const Color(0xFF5C6BC0),
    colorScheme: const ColorScheme.dark(
      primary: Color(0xFF5C6BC0),
      secondary: Color(0xFF9FA8DA),
      background: Color(0xFF0F1324),
      surface: Color(0xFF1A1E33),
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onBackground: Colors.white70,
      onSurface: Colors.white70,
      error: Colors.redAccent,
      onError: Colors.white,
    ),
  );
}

class CustomTheme extends ThemeColor {
  const CustomTheme({
    required String themeName,
    required Color primaryColor,
    required Color secondaryColor,
    required ColorScheme colorScheme,
  }) : super(
    themeName: themeName,
    primaryColor: primaryColor,
    secondaryColor: secondaryColor,
    colorScheme: colorScheme,
  );
}
