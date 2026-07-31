import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Root user-interface state exposed to the widget tree through Provider.
class AppState extends ChangeNotifier {
  static const _lightModeKey = 'finmo_light_mode';
  static const _periodKey = 'finmo_default_period';

  bool _isLightMode = true;
  String _period = 'monthly';

  bool get isLightMode => _isLightMode;
  String get period => _period;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _isLightMode = prefs.getBool(_lightModeKey) ?? true;
    _period = prefs.getString(_periodKey) ?? 'monthly';
    notifyListeners();
  }

  Future<void> setLightMode(bool enabled) async {
    if (_isLightMode == enabled) return;
    _isLightMode = enabled;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_lightModeKey, enabled);
  }

  Future<void> setPeriod(String period) async {
    if (period != 'weekly' && period != 'monthly') return;
    if (_period == period) return;
    _period = period;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_periodKey, period);
  }
}
