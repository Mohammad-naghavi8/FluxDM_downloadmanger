import 'dart:convert';

import 'package:download_manager/features/settings/models/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettingsService {
  static const String _key = 'app_configuration_v1';

  Future<AppSettings> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw != null && raw.isNotEmpty) {
        return AppSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      }
    } catch (_) {}
    return const AppSettings();
  }

  Future<void> save(AppSettings settings) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(settings.toJson()));
    } catch (_) {}
  }
}
