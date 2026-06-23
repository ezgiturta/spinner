import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Resolves Pro entitlement for premium features.
///
/// Spinner is a (skippable) hard paywall: there are NO free uses — scanning,
/// AI grading, album stories, and mood picks all require an active
/// subscription. The free-quota counters are kept at 0 so every `canUse*`
/// check collapses to `isPro`.
class AiAccess {
  AiAccess._();

  static const _kCondition = 'ai_uses_condition';
  static const _kStory = 'ai_uses_story';
  static const _kMood = 'ai_uses_mood';

  // QA only: when set via the hidden testing panel, every entitlement check
  // reports the user as NOT Pro, so the paywall/gates reappear even after a
  // (sandbox) purchase. Invisible to normal users.
  static const _kQaForceFree = 'qa_force_free';

  static Future<bool> qaForceFree() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kQaForceFree) ?? false;
  }

  static Future<void> setQaForceFree(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kQaForceFree, value);
  }

  static const freeConditionUses = 0;
  static const freeStoryUses = 0;
  static const freeMoodUses = 0;

  /// True if the user has any active RevenueCat entitlement. Best-effort —
  /// returns false if RevenueCat is not configured or call fails.
  ///
  /// Caches the last successful result so a transient RevenueCat/network hiccup
  /// doesn't momentarily report a paying user as non-Pro (which would wrongly
  /// pop the paywall mid-session).
  static bool? _lastKnownPro;

  static Future<bool> isPro() async {
    // QA override: force the locked/free experience for testing.
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_kQaForceFree) ?? false) return false;
    try {
      final info = await Purchases.getCustomerInfo();
      final pro = info.entitlements.active.isNotEmpty;
      _lastKnownPro = pro;
      return pro;
    } catch (_) {
      return _lastKnownPro ?? false;
    }
  }

  static Future<int> _used(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(key) ?? 0;
  }

  static Future<void> _bump(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(key, (prefs.getInt(key) ?? 0) + 1);
  }

  // ── Condition ──

  static Future<bool> canUseCondition() async {
    if (await isPro()) return true;
    return (await _used(_kCondition)) < freeConditionUses;
  }

  static Future<int> conditionUsesLeft() async {
    if (await isPro()) return -1; // unlimited
    final used = await _used(_kCondition);
    return (freeConditionUses - used).clamp(0, freeConditionUses);
  }

  static Future<void> recordConditionUse() => _bump(_kCondition);

  // ── Story ──

  static Future<bool> canUseStory() async {
    if (await isPro()) return true;
    return (await _used(_kStory)) < freeStoryUses;
  }

  static Future<int> storyUsesLeft() async {
    if (await isPro()) return -1;
    final used = await _used(_kStory);
    return (freeStoryUses - used).clamp(0, freeStoryUses);
  }

  static Future<void> recordStoryUse() => _bump(_kStory);

  // ── Mood ──

  static Future<bool> canUseMood() async {
    if (await isPro()) return true;
    return (await _used(_kMood)) < freeMoodUses;
  }

  static Future<int> moodUsesLeft() async {
    if (await isPro()) return -1;
    final used = await _used(_kMood);
    return (freeMoodUses - used).clamp(0, freeMoodUses);
  }

  static Future<void> recordMoodUse() => _bump(_kMood);
}
