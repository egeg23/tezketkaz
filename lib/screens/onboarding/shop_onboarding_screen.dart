import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../l10n/l10n.dart';
import '../../models/models.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_theme.dart';

/// Phase 13.2.3 — shop role marketing / perks screen.
///
/// Shown right after the user picks "Shop" on `/select-role`. Describes the
/// shop-side benefits and offers a CTA that either:
///   • opens the existing shop settings if the user is already linked to a
///     shop (via `ShopMember`); or
///   • offers a sample/demo shop link via the existing role-switcher path.
class ShopOnboardingScreen extends StatelessWidget {
  const ShopOnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final user = context.watch<AuthProvider>().user;
    final isLinked = user?.isShopOwner ?? false;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        backgroundColor: scheme.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/select-role'),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 112,
                height: 112,
                decoration: BoxDecoration(
                  color: AppColors.shop.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const Text('🏪', style: TextStyle(fontSize: 56)),
              ),
              const SizedBox(height: 24),
              Text(
                t(context, 'shop_onboarding.title'),
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                t(context, 'shop_onboarding.subtitle'),
                style: TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: scheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 28),
              Expanded(
                child: ListView(
                  children: [
                    _Perk(
                      icon: '📦',
                      title: t(context, 'shop_onboarding.perk1_title'),
                      body: t(context, 'shop_onboarding.perk1_body'),
                    ),
                    _Perk(
                      icon: '📈',
                      title: t(context, 'shop_onboarding.perk2_title'),
                      body: t(context, 'shop_onboarding.perk2_body'),
                    ),
                    _Perk(
                      icon: '💳',
                      title: t(context, 'shop_onboarding.perk3_title'),
                      body: t(context, 'shop_onboarding.perk3_body'),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.shop,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  onPressed: () async {
                    if (isLinked) {
                      // Already a shop member — switch active role and jump
                      // straight into the shop dashboard so the user can
                      // tweak settings if they need to.
                      await context.read<AuthProvider>()
                          .switchRole(UserRole.shop);
                      if (context.mounted) context.go('/shop/settings');
                      return;
                    }
                    if (context.mounted) {
                      // No ShopMember yet — route to the role switcher which
                      // exposes the "connect shop" bottom-sheet flow.
                      context.go('/switch-role');
                    }
                  },
                  child: Text(
                    isLinked
                        ? t(context, 'shop_onboarding.cta_open_dashboard')
                        : t(context, 'shop_onboarding.cta_create'),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Perk extends StatelessWidget {
  final String icon;
  final String title;
  final String body;
  const _Perk({required this.icon, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.shopLight,
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Text(icon, style: const TextStyle(fontSize: 22)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700,
                    )),
                const SizedBox(height: 2),
                Text(body,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.35,
                      color: AppColors.textSecondary,
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
