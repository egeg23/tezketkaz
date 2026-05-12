import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../l10n/l10n.dart';
import '../../models/models.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_theme.dart';

/// Phase 13.2.3 — first-run role-selection.
///
/// After OTP verification + the 4-slide intro the user picks how they intend
/// to use the app:
///   • Buyer    → existing `/buyer` shell.
///   • Courier  → `/courier/onboarding` info screen → courier KYC flow.
///   • Shop     → `/shop/onboarding` info screen → shop settings/setup.
///
/// The choice is persisted under `SharedPreferences['role_choice']` so the
/// router redirect can skip this screen on subsequent launches. The buyer
/// path is also flipped in [AuthProvider.switchRole] so navigation works
/// immediately even before the next app restart.
class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key});

  static const _kRoleChoiceKey = 'role_choice';

  /// Returns the role the user last selected, or `null` if they have never
  /// completed role selection.
  static Future<UserRole?> readChoice() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kRoleChoiceKey);
      switch (raw) {
        case 'buyer':
          return UserRole.buyer;
        case 'courier':
          return UserRole.courier;
        case 'shop':
          return UserRole.shop;
        default:
          return null;
      }
    } catch (_) {
      return null;
    }
  }

  static Future<void> _saveChoice(UserRole r) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = switch (r) {
        UserRole.buyer => 'buyer',
        UserRole.courier => 'courier',
        UserRole.shop => 'shop',
      };
      await prefs.setString(_kRoleChoiceKey, value);
    } catch (_) {/* best effort */}
  }

  Future<void> _pick(BuildContext context, UserRole role) async {
    HapticFeedback.selectionClick();
    await _saveChoice(role);
    final auth = context.read<AuthProvider>();
    // Flip local activeRole when the role is allowed; for courier/shop the
    // user must still complete verification / shop link, so we leave
    // activeRole as buyer until the destination screen flips it.
    if (role == UserRole.buyer) {
      await auth.switchRole(UserRole.buyer);
      if (context.mounted) context.go('/buyer');
      return;
    }
    if (role == UserRole.courier) {
      if (context.mounted) context.go('/courier/onboarding');
      return;
    }
    if (role == UserRole.shop) {
      if (context.mounted) context.go('/shop/onboarding');
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                t(context, 'role_select.title'),
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.4,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                t(context, 'role_select.subtitle'),
                style: TextStyle(
                  fontSize: 15,
                  height: 1.4,
                  color: scheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 28),
              Expanded(
                child: ListView(
                  children: [
                    _RoleCard(
                      emoji: '🛒',
                      title: t(context, 'role.buyer'),
                      description: t(context, 'role_select.buyer_desc'),
                      accent: AppColors.primary,
                      onTap: () => _pick(context, UserRole.buyer),
                    ),
                    const SizedBox(height: 14),
                    _RoleCard(
                      emoji: '🛵',
                      title: t(context, 'role.courier'),
                      description: t(context, 'role_select.courier_desc'),
                      accent: AppColors.courier,
                      onTap: () => _pick(context, UserRole.courier),
                    ),
                    const SizedBox(height: 14),
                    _RoleCard(
                      emoji: '🏪',
                      title: t(context, 'role.shop'),
                      description: t(context, 'role_select.shop_desc'),
                      accent: AppColors.shop,
                      onTap: () => _pick(context, UserRole.shop),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                t(context, 'role_select.switch_later_hint'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurface.withValues(alpha: 0.55),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  final String emoji;
  final String title;
  final String description;
  final Color accent;
  final VoidCallback onTap;

  const _RoleCard({
    required this.emoji,
    required this.title,
    required this.description,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border, width: 1),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: 0.06),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Center(
                  child: Text(emoji, style: const TextStyle(fontSize: 28)),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        color: scheme.onSurface.withValues(alpha: 0.65),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right,
                  color: scheme.onSurface.withValues(alpha: 0.35)),
            ],
          ),
        ),
      ),
    );
  }
}
