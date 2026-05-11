import 'package:flutter/foundation.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Phase 12 — gentle, one-shot prompt for the platform native review sheet.
///
/// We wait until the buyer has confirmed delivery on at least 5 orders before
/// asking — that way we don't pester users who are still evaluating the app.
/// Once the sheet has been requested we never ask again (App Store has its
/// own quota anyway, but we want to be polite about it).
class ReviewPromptService {
  static const _kCountKey = 'review.orderCount';
  static const _kPromptedKey = 'review.prompted';
  static const _threshold = 5;

  /// Test seam: lets unit tests inject a fake `InAppReview` implementation
  /// without going through the platform channel.
  @visibleForTesting
  static InAppReview? overrideReview;

  /// Call after a successful buyer confirmation. Increments the counter and
  /// shows the native review sheet exactly once when the threshold is hit.
  /// Best-effort — silently swallows any platform-channel failures so a
  /// review-prompt hiccup never breaks the order-complete UX.
  static Future<void> recordOrderCompleted() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_kPromptedKey) ?? false) return;
      final count = (prefs.getInt(_kCountKey) ?? 0) + 1;
      await prefs.setInt(_kCountKey, count);
      if (count < _threshold) return;
      final ir = overrideReview ?? InAppReview.instance;
      if (await ir.isAvailable()) {
        await ir.requestReview();
        await prefs.setBool(_kPromptedKey, true);
      }
    } catch (_) {
      // Silent — best-effort UX nudge.
    }
  }

  /// Test-only helper. Wipes the persisted counters so a fresh threshold can
  /// be exercised end-to-end.
  @visibleForTesting
  static Future<void> resetForTesting() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kCountKey);
    await prefs.remove(_kPromptedKey);
  }
}
