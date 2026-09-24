import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_experience_profile.dart';

class AppExperienceService {
  AppExperienceService._();

  static const _profileKey = 'yallah.experience.profile.v1';
  static final ValueNotifier<AppExperienceProfile> current =
      ValueNotifier<AppExperienceProfile>(AppExperienceProfile.defaults);
  static bool _loaded = false;

  static Future<AppExperienceProfile> load({bool force = false}) async {
    if (_loaded && !force) return current.value;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_profileKey);
    AppExperienceProfile profile = AppExperienceProfile.defaults;
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          profile = AppExperienceProfile.fromJson(
            Map<String, Object?>.from(decoded),
          );
        }
      } catch (_) {
        profile = AppExperienceProfile.defaults;
      }
    }
    _loaded = true;
    current.value = profile;
    return profile;
  }

  static Future<void> save(AppExperienceProfile profile) async {
    if (profile.activities.isEmpty) {
      throw ArgumentError('At least one business activity is required.');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_profileKey, jsonEncode(profile.toJson()));
    _loaded = true;
    current.value = profile;
  }

  static Future<void> resetForTesting() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_profileKey);
    _loaded = false;
    current.value = AppExperienceProfile.defaults;
  }
}
