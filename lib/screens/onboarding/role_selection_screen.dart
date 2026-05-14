import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../l10n/l10n.dart';
import '../../models/models.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_client.dart';
import '../../theme/app_theme.dart';

/// Phase 13.2.3 — first-run role selection.
///
/// Surfaced once after the very first OTP login, before the buyer / courier /
/// shop shell takes over. The user picks one of three modes; we record the
/// preference locally (SharedPreferences flag + AuthProvider.switchRole) and
/// best-effort PATCH `/api/users/me` so the backend has the latest role for
/// segmentation. All three cards are equally weighted glass surfaces; the
/// active selection only gains the lime border/shadow once the user taps.
///
/// The screen is reachable from `/select-role` (push) and from the router
/// redirect that runs after OTP verify when the
/// `role_select.completed` flag is missing.
class RoleSelectionScreen extends StatefulWidget {
  const RoleSelectionScreen({super.key});

  @override
  State<RoleSelectionScreen> createState() => _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends State<RoleSelectionScreen> {
  UserRole? _picked;
  bool _saving = false;

  Future<void> _select(UserRole role) async {
    HapticFeedback.selectionClick();
    setState(() {
      _picked = role;
    });
  }

  Future<void> _confirm() async {
    final role = _picked;
    if (role == null || _saving) return;
    setState(() => _saving = true);

    final auth = context.read<AuthProvider>();
    // Flip the local active role immediately so the router sends the user
    // to the right shell. We bypass the [switchRole] prerequisite checks
    // (which require an approved-courier flag / connected-shop) because
    // this *is* the user's first declaration of intent — the courier /
    // shop shells already handle the "not yet approved" empty state.
    auth.markRoleSelected(andSetRole: role);

    // Persist the "completed" flag locally so the router redirect doesn't
    // bounce us back here on the next cold start.
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(kRoleSelectedPrefsKey, true);
      await prefs.setString(kRoleSelectedValueKey, _roleSlug(role));
    } catch (_) {
      // SharedPreferences write failed (eg secure-mode quirk) — not fatal,
      // we just may re-prompt next launch which is acceptable.
    }

    // Best-effort backend write so segmentation / analytics know the user's
    // preferred mode. We don't block navigation on success — the local
    // state already covers the routing decision.
    unawaited(_pushActiveRoleToServer(role));

    if (!mounted) return;
    setState(() => _saving = false);
    HapticFeedback.mediumImpact();
    context.go(_homeForRole(role));
  }

  Future<void> _pushActiveRoleToServer(UserRole role) async {
    try {
      await ApiClient.instance.patch('/api/users/me', {
        'activeRole': _roleSlug(role),
      });
    } catch (_) {
      // Older backends will 400 on unknown field; that's fine.
    }
  }

  static String _roleSlug(UserRole role) {
    switch (role) {
      case UserRole.buyer:
        return 'buyer';
      case UserRole.courier:
        return 'courier';
      case UserRole.shop:
        return 'shop';
    }
  }

  static String _homeForRole(UserRole role) {
    switch (role) {
      case UserRole.courier:
        return '/courier';
      case UserRole.shop:
        return '/shop';
      default:
        return '/buyer';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t(context, 'role_select.title').toUpperCase(),
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 1.6,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 12),
              RichText(
                text: TextSpan(
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 30,
                    fontWeight: FontWeight.w500,
                    color: Colors.white,
                    height: 1.15,
                    letterSpacing: -0.6,
                  ),
                  children: [
                    TextSpan(text: t(context, 'role_select.title')),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                t(context, 'role_select.subtitle'),
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 28),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    _RoleCard(
                      icon: Icons.shopping_basket_rounded,
                      label: _label(context, UserRole.buyer),
                      desc: t(context, 'role_select.buyer_desc'),
                      selected: _picked == UserRole.buyer,
                      onTap: () => _select(UserRole.buyer),
                    ),
                    const SizedBox(height: 12),
                    _RoleCard(
                      icon: Icons.delivery_dining_rounded,
                      label: _label(context, UserRole.courier),
                      desc: t(context, 'role_select.courier_desc'),
                      selected: _picked == UserRole.courier,
                      onTap: () => _select(UserRole.courier),
                    ),
                    const SizedBox(height: 12),
                    _RoleCard(
                      icon: Icons.storefront_rounded,
                      label: _label(context, UserRole.shop),
                      desc: t(context, 'role_select.shop_desc'),
                      selected: _picked == UserRole.shop,
                      onTap: () => _select(UserRole.shop),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      t(context, 'role_select.switch_later_hint'),
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textHint,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              ElevatedButton(
                onPressed: _picked == null || _saving ? null : _confirm,
                child: _saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          color: AppColors.bg,
                          strokeWidth: 2.4,
                        ),
                      )
                    : Text(t(context, 'otp.verify')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _label(BuildContext context, UserRole role) {
    // Reuse the labels already defined for the role switcher. These have all
    // four locales (uz/ru/en/kk) so no extra keys needed.
    switch (role) {
      case UserRole.buyer:
        // role_switcher hint key isn't ideal; fall back to a hard-coded
        // localized label that mirrors the descriptions above.
        return _localized(context, {
          'uz': 'Xaridor',
          'ru': 'Покупатель',
          'en': 'Buyer',
          'kk': 'Тұтынушы',
        });
      case UserRole.courier:
        return _localized(context, {
          'uz': 'Kuryer',
          'ru': 'Курьер',
          'en': 'Courier',
          'kk': 'Курьер',
        });
      case UserRole.shop:
        return _localized(context, {
          'uz': "Do'kon",
          'ru': 'Магазин',
          'en': 'Shop',
          'kk': 'Дүкен',
        });
    }
  }

  String _localized(BuildContext context, Map<String, String> map) {
    final lang = L10n.instance.locale.languageCode;
    return map[lang] ?? map['ru'] ?? map['en'] ?? map.values.first;
  }
}

void unawaited(Future<void> future) {
  // Same idea as dart:async's `unawaited`, inlined to avoid the import.
  future.catchError((_) {});
}

class _RoleCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String desc;
  final bool selected;
  final VoidCallback onTap;

  const _RoleCard({
    required this.icon,
    required this.label,
    required this.desc,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primary.withValues(alpha: 0.08)
                : Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(AppRadii.lg),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
              width: selected ? 1.5 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.18),
                      blurRadius: 24,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.primary.withValues(alpha: 0.20)
                      : AppColors.surfaceMuted,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: selected ? AppColors.primary : AppColors.border,
                  ),
                ),
                alignment: Alignment.center,
                child: Icon(
                  icon,
                  size: 22,
                  color: selected ? AppColors.primary : Colors.white,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      desc,
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                color:
                    selected ? AppColors.primary : AppColors.textHint,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
