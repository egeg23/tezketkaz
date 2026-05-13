import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';
import 'package:provider/provider.dart';
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
      _showError(auth.error!);
    }
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
        _showError(auth.error ?? 'Ошибка');
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
      // master.html .login (line ~432): radial lime spotlights on ink-deep,
      // big tz-mark + close X header, Playfair hero, glass phone input
      // (country + number), lime CTA, "yoki" divider, social pair.
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Color(0xFF0A0A10), Color(0xFF050507)],
          ),
        ),
        child: Stack(
          children: [
            Positioned.fill(child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0.8, -0.9), radius: 0.85,
                  colors: [const Color(0xFF06C167).withValues(alpha: 0.10), Colors.transparent],
                ),
              ),
            )),
            SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _TzMark(size: 44),
                      _GlassCircleBtn(
                        icon: Icons.close_rounded,
                        onTap: () => Navigator.of(context).maybePop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 60),
                  RichText(
                    text: TextSpan(
                      style: GoogleFonts.playfairDisplay(
                        fontSize: 36, fontWeight: FontWeight.w500,
                        letterSpacing: -0.8, color: Colors.white, height: 1.1,
                      ),
                      children: [
                        const TextSpan(text: 'Добро '),
                        TextSpan(
                          text: 'пожаловать',
                          style: GoogleFonts.playfairDisplay(
                            fontStyle: FontStyle.italic,
                            color: AppColors.primary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: 280,
                    child: Text(
                      'Введите номер телефона и получите SMS-код. Одна минута — и можно заказывать.',
                      style: TextStyle(
                        fontSize: 15, color: AppColors.textSecondary, height: 1.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),

                  Text(
                    'Номер телефона',
                    style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary, letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Glass phone input — country chip + number field
                  Form(
                    key: _formKey,
                    child: Container(
                      height: 60,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceMuted,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.border),
                      ),
                      clipBehavior: Clip.hardEdge,
                      child: Row(
                        children: [
                          Container(
                            height: 60,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.02),
                              border: Border(right: BorderSide(color: AppColors.border)),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 20, height: 14,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(2),
                                    gradient: const LinearGradient(
                                      begin: Alignment.topCenter, end: Alignment.bottomCenter,
                                      colors: [
                                        Color(0xFF1FB6E6), Color(0xFF1FB6E6),
                                        Color(0xFFFFFFFF), Color(0xFFFFFFFF),
                                        Color(0xFF16A75C), Color(0xFF16A75C),
                                      ],
                                      stops: [0.0, 0.33, 0.33, 0.66, 0.66, 1.0],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Text('+998',
                                    style: TextStyle(
                                      fontSize: 16, fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    )),
                              ],
                            ),
                          ),
                          Expanded(
                            child: TextFormField(
                              controller: _phoneController,
                              inputFormatters: [_phoneMask],
                              keyboardType: TextInputType.phone,
                              cursorColor: AppColors.primary,
                              style: const TextStyle(
                                fontSize: 17, fontWeight: FontWeight.w500,
                                color: Colors.white, letterSpacing: 0.5,
                              ),
                              decoration: const InputDecoration(
                                hintText: '90 123 45 67',
                                filled: false,
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                contentPadding: EdgeInsets.symmetric(horizontal: 16),
                              ),
                              onChanged: (_) => setState(() {}),
                              onFieldSubmitted: (_) => _sendOtp(),
                              autofocus: true,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Lime CTA — disabled until 9 digits
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
                                color: AppColors.bg, strokeWidth: 2.5,
                              ),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Text('Продолжить'),
                                const SizedBox(width: 8),
                                Icon(Icons.arrow_forward_rounded,
                                    size: 18, color: AppColors.bg),
                              ],
                            ),
                    ),
                  ),

                  const SizedBox(height: 20),
                  Row(
                    children: [
                      const Expanded(child: Divider(color: AppColors.border)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          'или',
                          style: TextStyle(
                            color: AppColors.textHint,
                            fontSize: 12, fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const Expanded(child: Divider(color: AppColors.border)),
                    ],
                  ),
                  const SizedBox(height: 16),

                  Row(
                    children: [
                      Expanded(child: _SocialBtn(
                        label: 'Telegram',
                        icon: const Icon(Icons.send_rounded,
                            size: 18, color: Color(0xFF229ED9)),
                        loading: _isSocialLoading,
                        onTap: () => _socialLogin(
                          () => context.read<AuthProvider>().loginWithGoogle(),
                        ),
                      )),
                      const SizedBox(width: 10),
                      if (_showAppleButton)
                        Expanded(child: _SocialBtn(
                          label: 'Apple',
                          icon: const Icon(Icons.apple, size: 20, color: Colors.white),
                          loading: _isSocialLoading,
                          onTap: () => _socialLogin(
                            () => context.read<AuthProvider>().loginWithApple(),
                          ),
                        ))
                      else
                        Expanded(child: _SocialBtn(
                          label: 'Google',
                          icon: const _GoogleGlyph(),
                          loading: _isSocialLoading,
                          onTap: () => _socialLogin(
                            () => context.read<AuthProvider>().loginWithGoogle(),
                          ),
                        )),
                    ],
                  ),

                  const SizedBox(height: 28),
                  Center(
                    child: SizedBox(
                      width: 320,
                      child: Text.rich(
                        const TextSpan(children: [
                          TextSpan(text: 'Продолжая, вы соглашаетесь с '),
                          TextSpan(
                            text: 'Условиями использования',
                            style: TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          TextSpan(text: ' и '),
                          TextSpan(
                            text: 'Политикой конфиденциальности',
                            style: TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ]),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11, color: AppColors.textHint, height: 1.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Lime tz-mark with black bolt-disc (master.html .tz-mark, lines 319-322).
class _TzMark extends StatelessWidget {
  final double size;
  const _TzMark({this.size = 44});
  @override
  Widget build(BuildContext context) => Container(
    width: size, height: size,
    decoration: BoxDecoration(
      color: AppColors.primary,
      borderRadius: BorderRadius.circular(size * 0.27),
      boxShadow: [BoxShadow(
        color: AppColors.primary.withValues(alpha: 0.3),
        blurRadius: 20, offset: const Offset(0, 6),
      )],
    ),
    child: Stack(
      children: [
        Center(child: Text('tz',
            style: TextStyle(
              fontWeight: FontWeight.w900, fontSize: size * 0.41,
              color: AppColors.bg, letterSpacing: -1.5, height: 1,
            ))),
        Positioned(
          top: size * 0.09, right: size * 0.09,
          child: Container(
            width: size * 0.23, height: size * 0.23,
            decoration: BoxDecoration(
              color: AppColors.bg, shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(Icons.bolt_rounded,
                color: AppColors.primary, size: size * 0.14),
          ),
        ),
      ],
    ),
  );
}

/// Glass round button (master.html .login-close / .float-chip).
class _GlassCircleBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _GlassCircleBtn({required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surfaceMuted,
    shape: const CircleBorder(),
    child: InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.border),
        ),
        child: Icon(icon, size: 14, color: AppColors.textSecondary),
      ),
    ),
  );
}

class _SocialBtn extends StatelessWidget {
  final String label;
  final Widget icon;
  final bool loading;
  final VoidCallback onTap;
  const _SocialBtn({
    required this.label, required this.icon,
    required this.loading, required this.onTap,
  });
  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surfaceMuted,
    borderRadius: BorderRadius.circular(14),
    child: InkWell(
      onTap: loading ? null : onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            loading
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : icon,
            const SizedBox(width: 10),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14, fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// A primary-style button used for the Apple / Google entry points on the
/// login screen. Renders a leading icon, label, and a small spinner while
/// the social flow is in progress.
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
