import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'ai_access.dart';

/// Central Pro gate.
///
/// Spinner uses a *skippable* hard paywall: the user can dismiss the paywall
/// (the X) and browse the app, but every premium action — scanning, adding to
/// the collection, importing from Discogs, AI features — re-triggers the
/// paywall on each tap until they subscribe.
class SubscriptionGate {
  SubscriptionGate._();

  /// Returns true if the user has an active entitlement. Otherwise it opens
  /// the paywall and returns false — callers must bail out when false.
  static Future<bool> requirePro(BuildContext context) async {
    if (await AiAccess.isPro()) return true;
    if (!context.mounted) return false;
    // Open the paywall and WAIT for it. PaywallScreen pops `true` on a
    // successful purchase/restore, so the caller can continue (e.g. reveal the
    // scan result) without the user having to start over.
    final purchased = await context.push<bool>('/paywall');
    if (purchased == true) return true;
    return AiAccess.isPro();
  }
}
