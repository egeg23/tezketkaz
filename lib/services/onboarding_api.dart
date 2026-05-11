import 'api_client.dart';

/// Phase 11 — onboarding tutorial status.
///
/// The backend stores `User.onboardedAt`. On the first buyer launch the
/// tutorial intercepts `/buyer/*` and routes to `/onboarding`. Completing the
/// last slide PATCHes `onboardedAt = now` so subsequent launches skip it.
class OnboardingApi {
  OnboardingApi._();
  static final OnboardingApi instance = OnboardingApi._();

  final _api = ApiClient.instance;

  /// `GET /api/users/me/onboarding-status` → `{onboarded: bool, completedAt?: ISO}`.
  /// Returns `false` if the endpoint errors so the worst case is a redundant
  /// tutorial — never a hard auth crash.
  Future<bool> isOnboarded() async {
    try {
      final res = await _api.get('/api/users/me/onboarding-status');
      final body = res.data;
      if (body is Map) {
        return body['onboarded'] == true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// `PATCH /api/users/me` body `{onboardedAt: "now"}` — sentinel string the
  /// backend converts to the current server timestamp.
  Future<void> markOnboarded() async {
    await _api.patch('/api/users/me', {'onboardedAt': 'now'});
  }
}
