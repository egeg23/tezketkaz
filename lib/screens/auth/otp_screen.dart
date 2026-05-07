import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pin_code_fields/pin_code_fields.dart';
import 'package:provider/provider.dart';
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

  @override
  void initState() {
    super.initState();
    _startTimer();
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
    setState(() => _isLoading = true);

    final auth = context.read<AuthProvider>();
    final ok = await auth.verifyOtp(widget.phone, code);

    if (mounted) {
      setState(() => _isLoading = false);
      if (ok) {
        if (auth.user?.name == null) {
          context.go('/auth/name');
        } else {
          context.go('/buyer');
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(auth.error ?? 'Неверный код'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _resend() async {
    final auth = context.read<AuthProvider>();
    await auth.sendOtp(widget.phone);
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                onCompleted: _verify,
              ),
              const SizedBox(height: 24),

              // Loading / Button
              if (_isLoading)
                const Center(child: CircularProgressIndicator(
                  color: AppColors.primary,
                ))
              else if (_code.length == 6)
                ElevatedButton(
                  onPressed: () => _verify(_code),
                  child: const Text('Tasdiqlash'),
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
}
