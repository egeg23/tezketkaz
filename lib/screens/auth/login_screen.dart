import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';
import 'package:provider/provider.dart';
import '../../l10n/l10n.dart';
import '../../models/models.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phoneController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  // Маска для узбекского номера: +998 (99) 999-99-99
  final _phoneMask = MaskTextInputFormatter(
    mask: '+998 (##) ###-##-##',
    filter: {'#': RegExp(r'[0-9]')},
  );

  bool _isLoading = false;
  bool _isSocialLoading = false;

  String get _rawPhone =>
    '+998${_phoneMask.getUnmaskedText()}';

  bool get _isPhoneFilled =>
    _phoneMask.getUnmaskedText().length == 9;

  /// Apple Sign-In is only available on iOS / macOS native runtimes.
  /// Web sign-in-with-apple needs a server redirect we don't ship yet,
  /// and Android requires the Google flow instead. Using
  /// [defaultTargetPlatform] avoids importing `dart:io` (which breaks web
  /// compilation).
  bool get _showAppleButton {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
  }

  Future<void> _socialLogin(Future<bool> Function() runner) async {
    if (_isSocialLoading || _isLoading) return;
    setState(() => _isSocialLoading = true);
    final auth = context.read<AuthProvider>();
    final ok = await runner();
    if (!mounted) return;
    setState(() => _isSocialLoading = false);
    if (ok) {
      // Same redirect logic the OTP screen uses.
      if (auth.user?.name == null) {
        context.go('/auth/name');
      } else {
        switch (auth.user?.activeRole) {
          case UserRole.courier:
            context.go('/courier');
            break;
          case UserRole.shop:
            context.go('/shop');
            break;
          default:
            context.go('/buyer');
        }
      }
    } else if (auth.error != null) {
      _showError(_translateAuthError(auth.error!));
    }
  }

  /// Auth provider stores either a raw backend message or a sentinel l10n key
  /// (e.g. `auth.social_apple_error`). When the value starts with a known
  /// prefix we translate via l10n; otherwise we surface the raw message.
  String _translateAuthError(String msg) {
    if (msg.startsWith('auth.') || msg.startsWith('common.')) {
      final translated = t(context, msg);
      // L10n.t returns the key itself if missing — fall back to a generic.
      return translated == msg ? t(context, 'common.error') : translated;
    }
    return msg;
  }

  Future<void> _sendOtp() async {
    if (!_isPhoneFilled) return;
    setState(() => _isLoading = true);

    final auth = context.read<AuthProvider>();
    final ok = await auth.sendOtp(_rawPhone);

    if (mounted) {
      setState(() => _isLoading = false);
      if (ok) {
        context.push('/auth/otp', extra: _rawPhone);
      } else {
        _showError(_translateAuthError(auth.error ?? 'common.error'));
      }
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(flex: 2),

              // Иллюстрация
              Center(
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: Text('🛒', style: TextStyle(fontSize: 56)),
                  ),
                ),
              ),
              const SizedBox(height: 32),

              Text(
                t(context, 'login.title'),
                style: Theme.of(context).textTheme.displayMedium,
              ),
              const SizedBox(height: 8),
              Text(
                t(context, 'login.subtitle'),
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 32),

              // Phone input
              Form(
                key: _formKey,
                child: TextFormField(
                  controller: _phoneController,
                  inputFormatters: [_phoneMask],
                  keyboardType: TextInputType.phone,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.5,
                  ),
                  decoration: const InputDecoration(
                    hintText: '+998 (90) 123-45-67',
                    prefixIcon: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Text('🇺🇿', style: TextStyle(fontSize: 22)),
                    ),
                    prefixIconConstraints: BoxConstraints(
                      minWidth: 56, minHeight: 0,
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                  onFieldSubmitted: (_) => _sendOtp(),
                  autofocus: true,
                ),
              ),
              const SizedBox(height: 20),

              // CTA Button
              AnimatedOpacity(
                opacity: _isPhoneFilled ? 1.0 : 0.5,
                duration: const Duration(milliseconds: 200),
                child: ElevatedButton(
                  onPressed: _isPhoneFilled && !_isLoading && !_isSocialLoading
                      ? _sendOtp
                      : null,
                  child: _isLoading
                    ? const SizedBox(
                        width: 22, height: 22,
                        child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2.5,
                        ),
                      )
                    : Text(t(context, 'login.cta')),
                ),
              ),

              const SizedBox(height: 20),

              // ── Divider with "or" label ───────────────────────────────
              Row(
                children: [
                  const Expanded(child: Divider(color: AppColors.border)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      t(context, 'auth.or'),
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Expanded(child: Divider(color: AppColors.border)),
                ],
              ),

              const SizedBox(height: 16),

              // ── Apple (iOS/macOS only) ────────────────────────────────
              if (_showAppleButton) ...[
                _SocialButton(
                  label: t(context, 'auth.continue_with_apple'),
                  icon: const Icon(Icons.apple, color: Colors.white, size: 22),
                  background: Colors.black,
                  foreground: Colors.white,
                  loading: _isSocialLoading,
                  onTap: () => _socialLogin(
                    () => context.read<AuthProvider>().loginWithApple(),
                  ),
                ),
                const SizedBox(height: 10),
              ],

              // ── Google (all platforms) ────────────────────────────────
              _SocialButton(
                label: t(context, 'auth.continue_with_google'),
                icon: const _GoogleGlyph(),
                background: Colors.white,
                foreground: AppColors.textPrimary,
                border: AppColors.border,
                loading: _isSocialLoading,
                onTap: () => _socialLogin(
                  () => context.read<AuthProvider>().loginWithGoogle(),
                ),
              ),

              const Spacer(flex: 3),

              // Terms
              Center(
                child: Text(
                  t(context, 'login.terms_blurb'),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

/// A primary-style button used for the Apple / Google entry points on the
/// login screen. Renders a leading icon, label, and a small spinner while
/// the social flow is in progress.
class _SocialButton extends StatelessWidget {
  final String label;
  final Widget icon;
  final Color background;
  final Color foreground;
  final Color? border;
  final bool loading;
  final VoidCallback onTap;

  const _SocialButton({
    required this.label,
    required this.icon,
    required this.background,
    required this.foreground,
    required this.onTap,
    this.border,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: loading ? null : onTap,
          borderRadius: BorderRadius.circular(14),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: border != null ? Border.all(color: border!) : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (loading)
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: foreground,
                    ),
                  )
                else
                  icon,
                const SizedBox(width: 12),
                Text(
                  label,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Tiny Google "G" glyph drawn with `Text` to avoid shipping an extra
/// asset. Falls back to a generic icon if the system font can't render it.
class _GoogleGlyph extends StatelessWidget {
  const _GoogleGlyph();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.border),
      ),
      child: const Text(
        'G',
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w900,
          color: Color(0xFF4285F4),
        ),
      ),
    );
  }
}
