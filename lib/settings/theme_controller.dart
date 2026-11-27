import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The user's choice of Light, Dark or System appearance. It is saved on the
/// device and applied by `SafeSpendApp`.
class ThemeController extends ChangeNotifier {
  static const String _key = 'themeMode';

  ThemeMode _mode = ThemeMode.dark;

  ThemeMode get mode => _mode;

  /// Reads the saved choice. Dark is the default.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _mode = _parse(prefs.getString(_key));
    } catch (_) {
      _mode = ThemeMode.dark;
    }
  }

  Future<void> setMode(ThemeMode mode) async {
    if (mode == _mode) return;
    _mode = mode;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, mode.name);
    } catch (_) {
      // The choice still applies for this session.
    }
  }

  static ThemeMode _parse(String? value) {
    for (final mode in ThemeMode.values) {
      if (mode.name == value) return mode;
    }
    return ThemeMode.dark;
  }
}

/// The one controller the whole app shares.
final ThemeController themeController = ThemeController();
