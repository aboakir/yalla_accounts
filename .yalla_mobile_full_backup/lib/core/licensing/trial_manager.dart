// -----------------------------------------------------------------------------
// 📁 lib/core/licensing/trial_manager.dart
// Trial Manager — 300 HOURS REAL TIME (from first run)
// -----------------------------------------------------------------------------

import 'package:shared_preferences/shared_preferences.dart';

class TrialManager {
  static const int trialHoursLimit = 300;

  static const String _kTrialStartTs = 'trial_start_ts';
  static const String _kLastSeenTs = 'trial_last_seen_ts';
  static const String _kTrialExpired = 'trial_expired';

  /// Initialize trial timestamps on first run
  static Future<void> ensureInitialized() async {
    final prefs = await SharedPreferences.getInstance();

    if (prefs.getBool(_kTrialExpired) == true) {
      return;
    }

    final now = DateTime.now().millisecondsSinceEpoch;

    if (!prefs.containsKey(_kTrialStartTs)) {
      // First ever run
      await prefs.setInt(_kTrialStartTs, now);
      await prefs.setInt(_kLastSeenTs, now);
      return;
    }

    final lastSeen = prefs.getInt(_kLastSeenTs) ?? now;

    // Detect time rollback
    if (now < lastSeen) {
      await _expireTrial(prefs);
      return;
    }

    await prefs.setInt(_kLastSeenTs, now);

    final usedHours = _calculateUsedHours(prefs);
    if (usedHours >= trialHoursLimit) {
      await _expireTrial(prefs);
    }
  }

  /// Returns true if trial is expired
  static Future<bool> isExpired() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kTrialExpired) == true;
  }

  /// Returns used hours since first run
  static Future<int> getUsedHours() async {
    final prefs = await SharedPreferences.getInstance();
    return _calculateUsedHours(prefs);
  }

  /// Returns remaining hours (can be 0)
  static Future<int> getRemainingHours() async {
    final used = await getUsedHours();
    final remaining = trialHoursLimit - used;
    return remaining < 0 ? 0 : remaining;
  }

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  static int _calculateUsedHours(SharedPreferences prefs) {
    final startTs = prefs.getInt(_kTrialStartTs);
    if (startTs == null) return trialHoursLimit;

    final now = DateTime.now().millisecondsSinceEpoch;
    final diffMs = now - startTs;

    final diffHours = diffMs ~/ (1000 * 60 * 60);
    return diffHours;
  }

  static Future<void> _expireTrial(SharedPreferences prefs) async {
    await prefs.setBool(_kTrialExpired, true);
  }
}
