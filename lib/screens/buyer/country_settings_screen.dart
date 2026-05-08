import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/l10n.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_theme.dart';

/// Phase 7.1 — country + locale settings.
///
/// Persists locale in `SharedPreferences` via `L10n.setLocale` and pushes the
/// pair to the backend via `PATCH /api/users/me`. Country drives currency
/// inference on the backend; the Flutter side just stores and renders the
/// selected flag.
class CountrySettingsScreen extends StatefulWidget {
  const CountrySettingsScreen({super.key});

  @override
  State<CountrySettingsScreen> createState() => _CountrySettingsScreenState();
}

class _CountrySettingsScreenState extends State<CountrySettingsScreen> {
  static const _countries = [
    _CountryOpt('UZ', '🇺🇿', 'O\'zbekiston'),
    _CountryOpt('KZ', '🇰🇿', 'Qazaqstan'),
    _CountryOpt('KG', '🇰🇬', 'Kyrgyzstan'),
    _CountryOpt('RU', '🇷🇺', 'Russia'),
  ];

  static const _locales = [
    _LocaleOpt('uz', 'O\'zbekcha'),
    _LocaleOpt('ru', 'Русский'),
    _LocaleOpt('en', 'English'),
    _LocaleOpt('kk', 'Қазақша'),
  ];

  String _country = 'UZ';
  String _locale = 'uz';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthProvider>().user;
    _country = user?.country ?? 'UZ';
    _locale = L10n.instance.locale.languageCode;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      // Locale change is purely local — apply immediately so the rest of the
      // app reflects the choice as soon as the user taps Save.
      await L10n.instance.setLocale(Locale(_locale));
      // Best-effort push to backend.
      await context.read<AuthProvider>().updateCountryLocale(
            country: _country,
            locale: _locale,
          );
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t(context, 'common.save'))),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: Text(t(context, 'settings.country_locale'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Text(t(context, 'settings.country'),
              style: const TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 14)),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadii.lg),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                for (var i = 0; i < _countries.length; i++) ...[
                  RadioListTile<String>(
                    value: _countries[i].code,
                    groupValue: _country,
                    onChanged: (v) => setState(() => _country = v ?? 'UZ'),
                    title: Row(
                      children: [
                        Text(_countries[i].flag,
                            style: const TextStyle(fontSize: 22)),
                        const SizedBox(width: 12),
                        Text(_countries[i].label,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                    activeColor: AppColors.primary,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  if (i < _countries.length - 1)
                    const Divider(height: 1, indent: 60),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(t(context, 'settings.locale'),
              style: const TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 14)),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadii.lg),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                for (var i = 0; i < _locales.length; i++) ...[
                  RadioListTile<String>(
                    value: _locales[i].code,
                    groupValue: _locale,
                    onChanged: (v) => setState(() => _locale = v ?? 'uz'),
                    title: Text(_locales[i].label,
                        style:
                            const TextStyle(fontWeight: FontWeight.w600)),
                    activeColor: AppColors.primary,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  if (i < _locales.length - 1)
                    const Divider(height: 1, indent: 16),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _saving ? null : _save,
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              backgroundColor: AppColors.primary,
            ),
            child: _saving
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2.5),
                  )
                : Text(
                    t(context, 'common.save'),
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 16),
                  ),
          ),
        ],
      ),
    );
  }
}

class _CountryOpt {
  final String code, flag, label;
  const _CountryOpt(this.code, this.flag, this.label);
}

class _LocaleOpt {
  final String code, label;
  const _LocaleOpt(this.code, this.label);
}
