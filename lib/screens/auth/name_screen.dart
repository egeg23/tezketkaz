import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_theme.dart';

/// NAME — master.html .name-scr (lines 5901-5934).
///
/// Back chip + "3 / 3" counter top row, Playfair-italic "Sizning *ismingiz?*",
/// description, glass field with the typed name + lime cursor, helper line,
/// lime CTA pinned to the bottom.
class NameScreen extends StatefulWidget {
  const NameScreen({super.key});
  @override
  State<NameScreen> createState() => _NameScreenState();
}

class _NameScreenState extends State<NameScreen> {
  final _ctrl = TextEditingController();
  bool get _isValid {
    final t = _ctrl.text.trim();
    return t.length >= 2 && t.length <= 32;
  }

  void _continue() {
    if (!_isValid) return;
    context.read<AuthProvider>().setName(_ctrl.text.trim());
    context.go('/buyer');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Color(0xFF0A0A10), Color(0xFF050507)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Material(
                      color: AppColors.surfaceMuted,
                      shape: const CircleBorder(),
                      child: InkWell(
                        onTap: () => Navigator.of(context).maybePop(),
                        customBorder: const CircleBorder(),
                        child: Container(
                          width: 36, height: 36,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Icon(Icons.chevron_left_rounded,
                              size: 18, color: AppColors.textSecondary),
                        ),
                      ),
                    ),
                    Text(
                      '3 / 3',
                      style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w500,
                        color: AppColors.textHint,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 48),
                Text(
                  'Последний шаг',
                  style: TextStyle(
                    fontSize: 11, letterSpacing: 1.8,
                    color: AppColors.primary, fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                RichText(
                  text: TextSpan(
                    style: GoogleFonts.playfairDisplay(
                      fontSize: 36, fontWeight: FontWeight.w500,
                      letterSpacing: -0.8, color: Colors.white, height: 1.1,
                    ),
                    children: [
                      const TextSpan(text: 'Как вас '),
                      TextSpan(
                        text: 'зовут?',
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
                Text(
                  'Курьер и рестораны будут обращаться к вам по этому имени. В профиле можно изменить.',
                  style: TextStyle(
                    fontSize: 15, color: AppColors.textSecondary, height: 1.5,
                  ),
                ),
                const SizedBox(height: 32),

                Text(
                  'Ваше имя',
                  style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary, letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  height: 60,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceMuted,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border),
                  ),
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    controller: _ctrl,
                    textCapitalization: TextCapitalization.words,
                    cursorColor: AppColors.primary,
                    style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w500,
                      color: Colors.white,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Асаль',
                      hintStyle: TextStyle(
                        color: AppColors.textHint, fontWeight: FontWeight.w400,
                      ),
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                      isDense: true,
                    ),
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _continue(),
                    autofocus: true,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '2–32 символа · только буквы',
                  style: TextStyle(
                    fontSize: 11, color: AppColors.textHint,
                  ),
                ),
                const Spacer(),
                ElevatedButton(
                  onPressed: _isValid ? _continue : null,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('Продолжить'),
                      const SizedBox(width: 8),
                      Icon(Icons.arrow_forward_rounded,
                          size: 18, color: AppColors.bg),
                    ],
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
