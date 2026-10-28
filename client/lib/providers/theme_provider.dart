import 'package:flutter/material.dart';
import '../services/storage_service.dart';

class ThemeProvider extends ChangeNotifier {
  ThemeMode _themeMode = StorageService.getThemeMode();

  ThemeMode get themeMode => _themeMode;

  bool get isDarkMode => _themeMode == ThemeMode.dark;
  bool get isLightMode => _themeMode == ThemeMode.light;
  bool get isSystemMode => _themeMode == ThemeMode.system;

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    await StorageService.setThemeMode(mode);
    notifyListeners();
  }

  Future<void> toggleTheme(BuildContext context) async {
    if (_themeMode == ThemeMode.system) {
      final isPlatformDark = MediaQuery.platformBrightnessOf(context) == Brightness.dark;
      await setThemeMode(isPlatformDark ? ThemeMode.light : ThemeMode.dark);
    } else if (_themeMode == ThemeMode.dark) {
      await setThemeMode(ThemeMode.light);
    } else {
      await setThemeMode(ThemeMode.dark);
    }
  }
}
