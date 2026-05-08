import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

/// Phase 9.3 — thin wrapper around the native Apple / Google sign-in SDKs.
///
/// Both flows return the provider's id-token (a signed JWT). The caller
/// then forwards it to our backend at
/// `POST /api/auth/oauth/{apple|google}` which verifies the signature with
/// the provider's JWKS, finds-or-creates the user, and returns the same
/// `{accessToken, refreshToken, user}` shape as `/api/auth/verify-otp`.
class SocialAuthService {
  static final SocialAuthService instance = SocialAuthService._();
  SocialAuthService._();

  /// Triggers the native Apple flow. Returns the `identityToken` JWT or
  /// `null` if the user cancelled.
  ///
  /// Throws [SignInWithAppleException] subclasses on platform / config
  /// errors so the caller can show a friendly message.
  Future<String?> appleSignIn() async {
    if (kIsWeb) {
      // Apple Sign-In on web requires a server-redirect flow. We skip it
      // here and rely on phone-OTP / Google for web buyers.
      return null;
    }
    final cred = await SignInWithApple.getAppleIDCredential(
      scopes: const [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
    );
    return cred.identityToken;
  }

  /// Triggers the native Google account picker. Returns Google's
  /// `id_token` (a signed JWT) or `null` if the user dismissed the picker.
  Future<String?> googleSignIn() async {
    final google = GoogleSignIn(scopes: const ['email', 'profile']);
    final account = await google.signIn();
    if (account == null) return null;
    final auth = await account.authentication;
    return auth.idToken;
  }

  /// Best-effort sign-out from Google so the next tap re-prompts the
  /// account picker. No-op on Apple — Apple has no SDK-level sign-out.
  Future<void> signOut() async {
    try {
      await GoogleSignIn().signOut();
    } catch (_) {/* swallow */}
  }
}
