import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pin_code_fields/pin_code_fields.dart';
import 'package:provider/provider.dart';
import '../../constants/legal.dart';
import '../../l10n/l10n.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_theme.dart';

class OtpScreen extends StatefulWidget {
  final String phone;
  const OtpScreen({super.key, required this.phone});

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  String _code = '';
  int _resendSeconds = 60;
  Timer? _timer;
  bool _isLoading = false;
  bool _acceptedLegal = false;

  // Recognizers must outlive each build pass so taps register reliably and we
  // can dispose them when the screen is torn down.
  late final TapGestureRecognizer _termsTap;
  late final TapGestureRecognizer _privacyTap;

  @override
  void initState() {
    super.initState();
    _startTimer();
    _termsTap = TapGestureRecognizer()
      ..onTap = () => context.go('/legal?tab=terms');
    _privacyTap = TapGestureRecognizer()
      ..onTap = () => context.go('/legal?tab=privacy');
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() => _resendSeconds = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_resendSeconds == 0) {
        t.cancel();
      } else {
        setState(() => _resendSeconds--);
      }
    });
  }

  Future<void> _verify(String code) async {
    if (code.length != 6) return;
    if (!_acceptedLegal) return;
    setState(() => _isLoading = true);

    final auth = context.read<AuthProvider>();
    final ok = await auth.verifyOtp(
      widget.phone,
      code,
      acceptedLegalVersion: kCurrentLegalVersion,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(auth.error ?? 'Неверный код'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Existing user whose acceptance is on a stale version — prompt before
    // continuing to the home shell. Reject of the modal still lets the user
    // continue (we do not block login yet, only nudge), matching backend
    // behaviour that returns 200 with `legalUpdateRequired: true`.
    if (auth.legalUpdateRequired) {
      await _showLegalUpdateDialog();
    }

    if (!mounted) return;
    if (auth.user?.name == null) {
      context.go('/auth/name');
    } else {
      context.go('/buyer');
    }
  }

  Future<void> _showLegalUpdateDialog() async {
    final auth = context.read<AuthProvider>();
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return AlertDialog(
          title: Text(t(dialogCtx, 'auth.legal_updated_title')),
          content: Text(t(dialogCtx, 'auth.legal_updated_body')),
          actions: [
            TextButton(
              onPressed: () => dialogCtx.go('/legal?tab=terms'),
              child: Text(t(dialogCtx, 'auth.legal_review')),
            ),
            ElevatedButton(
              onPressed: () async {
                final ok = await auth.acceptLegal(
                  version: auth.currentLegalVersion ?? kCurrentLegalVersion,
                );
                if (!dialogCtx.mounted) return;
                Navigator.of(dialogCtx).pop();
                if (!ok) {
                  ScaffoldMessenger.of(dialogCtx).showSnackBar(
                    SnackBar(
                      content: Text(auth.error ?? 'Error'),
                      backgroundColor: AppColors.error,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              },
              child: Text(t(dialogCtx, 'auth.legal_accept_cta')),
            ),
          ],
        );
      },
    );
  }

  Future<void> _resend() async {
    final auth = context.read<AuthProvider>();
    await auth.sendOtp(widget.phone);
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _termsTap.dispose();
    _privacyTap.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canSubmit = _code.length == 6 && _acceptedLegal && !_isLoading;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              Text(
                'SMS kod',
                style: Theme.of(context).textTheme.displayMedium,
              ),
              const SizedBox(height: 8),
              RichText(
                text: TextSpan(
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                  children: [
                    const TextSpan(text: 'Kod yuborildi: '),
                    TextSpan(
                      text: widget.phone,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),

              // PIN input
              PinCodeTextField(
                appContext: context,
                length: 6,
                keyboardType: TextInputType.number,
                animationType: AnimationType.fade,
                pinTheme: PinTheme(
                  shape: PinCodeFieldShape.box,
                  borderRadius: BorderRadius.circular(12),
                  fieldHeight: 56,
                  fieldWidth: 48,
                  activeFillColor: AppColors.surface,
                  inactiveFillColor: AppColors.surface,
                  selectedFillColor: AppColors.primaryLight,
                  activeColor: AppColors.primary,
                  inactiveColor: AppColors.border,
                  selectedColor: AppColors.primary,
                ),
                enableActiveFill: true,
                cursorColor: AppColors.primary,
                onChanged: (v) => setState(() => _code = v),
                onCompleted: (v) {
                  if (_acceptedLegal) _verify(v);
                },
              ),
              const SizedBox(height: 16),

              // Phase 13.1.5 — explicit T&C / Privacy Policy consent.
              _buildLegalConsent(context),
              const SizedBox(height: 16),

              // Loading / Button
              if (_isLoading)
                const Center(child: CircularProgressIndicator(
                  color: AppColors.primary,
                ))
              else
                Tooltip(
                  message: canSubmit
                      ? ''
                      : t(context, 'auth.legal_submit_blocked'),
                  child: ElevatedButton(
                    onPressed: canSubmit ? () => _verify(_code) : null,
                    child: Text(t(context, 'otp.verify')),
                  ),
                ),

              const SizedBox(height: 24),

              // Resend
              Center(
                child: _resendSeconds > 0
                  ? Text(
                      'Qayta yuborish: $_resendSeconds s',
                      style: Theme.of(context).textTheme.bodyMedium,
                    )
                  : TextButton(
                      onPressed: _resend,
                      child: const Text(
                        'Kodni qayta yuborish',
                        style: TextStyle(color: AppColors.primary),
                      ),
                    ),
              ),

              // Dev hint
              const Spacer(),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: AppColors.primary, size: 16),
                    SizedBox(width: 8),
                    Text(
                      'Прототип: используйте код 123456',
                      style: TextStyle(
                        color: AppColors.primaryDark,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLegalConsent(BuildContext context) {
    final base = Theme.of(context).textTheme.bodyMedium ?? const TextStyle();
    final linkStyle = base.copyWith(
      color: AppColors.primary,
      decoration: TextDecoration.underline,
    );

    // We pull all four pieces from l10n so translations match each locale.
    final intro = t(context, 'auth.legal_consent_intro');
    final termsLabel = t(context, 'auth.terms_link');
    final and = t(context, 'auth.legal_consent_and');
    final privacyLabel = t(context, 'auth.privacy_link');

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Checkbox(
          value: _acceptedLegal,
          onChanged: (v) => setState(() => _acceptedLegal = v ?? false),
        ),
        Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _acceptedLegal = !_acceptedLegal),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: RichText(
                text: TextSpan(
                  style: base.copyWith(color: AppColors.textPrimary),
                  children: [
                    TextSpan(text: '$intro '),
                    TextSpan(
                      text: termsLabel,
                      style: linkStyle,
                      recognizer: _termsTap,
                    ),
                    TextSpan(text: ' $and '),
                    TextSpan(
                      text: privacyLabel,
                      style: linkStyle,
                      recognizer: _privacyTap,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
