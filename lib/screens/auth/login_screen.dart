import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';
import 'package:provider/provider.dart';
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

  String get _rawPhone =>
    '+998${_phoneMask.getUnmaskedText()}';

  bool get _isPhoneFilled =>
    _phoneMask.getUnmaskedText().length == 9;

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
                'Kirish',
                style: Theme.of(context).textTheme.displayMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Telefon raqamingizni kiriting\nva SMS kod oling',
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
                  onPressed: _isPhoneFilled && !_isLoading ? _sendOtp : null,
                  child: _isLoading
                    ? const SizedBox(
                        width: 22, height: 22,
                        child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2.5,
                        ),
                      )
                    : const Text('SMS kod olish'),
                ),
              ),

              const Spacer(flex: 3),

              // Terms
              Center(
                child: Text(
                  'Kirish orqali siz\nFoydalanish shartlarimizga rozilik bildirasiz',
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
