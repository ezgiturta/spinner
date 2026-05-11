import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tracks free-tier usage of AI features and resolves Pro entitlement.
///
/// Free quotas (intentionally generous on first try, tight after):
/// - condition grader: 1 use
/// - album story: 3 uses
/// - mood picker: 3 uses
class AiAccess {
  AiAccess._();

  static const _kCondition = 'ai_uses_condition';
  static const _kStory = 'ai_uses_story';
  static const _kMood = 'ai_uses_mood';

  static const freeConditionUses = 1;
  static const freeStoryUses = 3;
  static const freeMoodUses = 3;

  /// True if the user has any active RevenueCat entitlement. Best-effort —
  /// returns false if RevenueCat is not configured or call fails.
  static Future<bool> isPro() async {
    try {
      final info = await Purchases.getCustomerInfo();
      return info.entitlements.active.isNotEmpty;
    } catch (_) {
      return false;
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
