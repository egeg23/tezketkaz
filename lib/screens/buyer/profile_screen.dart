import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../l10n/l10n.dart';
import '../../providers/auth_provider.dart';
import '../../providers/order_provider.dart';
import '../../providers/theme_provider.dart';
import '../../theme/app_theme.dart';
import '../../models/models.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth   = context.watch<AuthProvider>();
    final orders = context.watch<OrderProvider>();
    final user   = auth.user!;

    final totalOrders    = orders.all.length;
    final activeOrders   = orders.all.where((o) =>
        o.status != AppOrderStatus.delivered &&
        o.status != AppOrderStatus.cancelled).length;
    final deliveredCount = orders.all.where((o) => o.status == AppOrderStatus.delivered).length;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
        children: [
          // ── UberEats-style hero: near-black card with lime accent stats ──
          SafeArea(
            bottom: false,
            child: Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
              decoration: BoxDecoration(
                color: AppColors.neutralInk,
                borderRadius: BorderRadius.circular(AppRadii.xl),
                boxShadow: AppShadows.elevated,
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 64, height: 64,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                          boxShadow: [BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.35),
                            blurRadius: 20, offset: const Offset(0, 6),
                          )],
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          user.name?.isNotEmpty == true ? user.name![0].toUpperCase() : '?',
                          style: const TextStyle(
                            fontSize: 26, fontWeight: FontWeight.w800,
                            color: AppColors.neutralInk,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user.name ?? 'Foydalanuvchi',
                              style: const TextStyle(
                                color: Colors.white, fontSize: 20,
                                fontWeight: FontWeight.w800, letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              user.phone,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.7),
                                fontSize: 13, fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.edit_outlined,
                              color: Colors.white, size: 18),
                          onPressed: () {},
                          padding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Container(height: 1, color: Colors.white.withValues(alpha: 0.1)),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _HeroStat(value: '$totalOrders', label: 'Jami'),
                      _HeroDivider(),
                      _HeroStat(value: '$activeOrders', label: 'Faol', accent: true),
                      _HeroDivider(),
                      _HeroStat(value: '$deliveredCount', label: 'Yetkazildi'),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 14),

          // ── Role switch ────────────────────────────────────────────────────
          _Card(
            children: [
              _Tile(
                icon: '🔄',
                title: 'Rejimni almashtirish',
                subtitle: 'Xaridor · Kuryer · Do\'kon',
                color: AppColors.primary,
                onTap: () => context.push('/switch-role'),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // ── Orders ─────────────────────────────────────────────────────────
          _Card(children: [
            _Tile(
              icon: '📦',
              title: 'Mening buyurtmalarim',
              subtitle: activeOrders > 0 ? '$activeOrders ta faol' : 'Tarix',
              trailing: activeOrders > 0
                ? Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.courierLight, borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('$activeOrders', style: const TextStyle(
                        color: AppColors.courier, fontWeight: FontWeight.w700, fontSize: 12)),
                  )
                : null,
              onTap: () => context.go('/buyer/orders'),
            ),
            _Tile(
              icon: '❤️',
              title: t(context, 'profile.favorites'),
              onTap: () => context.push('/buyer/favorites'),
            ),
            _Tile(
              icon: '📍',
              title: 'Manzillarim',
              onTap: () => context.push('/buyer/address-book'),
            ),
          ]),

          const SizedBox(height: 10),

          // ── Phase 7.2 — subscription tile ──────────────────────────────────
          _Card(children: [
            _Tile(
              icon: '⭐',
              title: t(context, 'subscription.tile_title'),
              subtitle: auth.membership?.isActive == true
                  ? (auth.membership!.tier == 'pro'
                      ? t(context, 'subscription.tier_pro')
                      : t(context, 'subscription.tier_plus'))
                  : t(context, 'subscription.tile_subtitle'),
              onTap: () => context.push('/buyer/subscription'),
            ),
          ]),

          const SizedBox(height: 10),

          // ── Loyalty / promo ────────────────────────────────────────────────
          _Card(children: [
            _Tile(
              icon: '⭐',
              title: 'Bonuslar va daraja',
              subtitle: 'Cashback · ballar · referal',
              onTap: () => context.push('/buyer/loyalty'),
            ),
            _Tile(
              icon: '🎟️',
              title: 'Promo kodlar',
              onTap: () => context.push('/buyer/promo'),
            ),
          ]),

          const SizedBox(height: 10),

          _Card(children: [
            _Tile(icon: '🔔', title: 'Bildirishnomalar', onTap: () {}),
            _Tile(
              icon: '🌐',
              title: t(context, 'settings.country_locale'),
              subtitle: '${user.country ?? 'UZ'} · ${L10n.instance.locale.languageCode}',
              onTap: () => context.push('/buyer/country-settings'),
            ),
            // Phase 10.3 — theme picker (Auto / Light / Dark).
            _ThemeTile(),
            _Tile(
              icon: '🔒',
              title: t(context, 'privacy.title'),
              subtitle: 'GDPR · Export · Delete',
              onTap: () => context.push('/buyer/data-privacy'),
            ),
            // Phase 10.2 — customer support inbox.
            _Tile(
              icon: '💬',
              title: t(context, 'support.title'),
              onTap: () => context.push('/buyer/support'),
            ),
          ]),

          const SizedBox(height: 10),

          // ── Dev: mock courier approve ───────────────────────────────────────
          if (user.courierStatus == CourierVerificationStatus.pending)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: OutlinedButton.icon(
                onPressed: () {
                  auth.mockApproveCourier();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('✅ Kuryer tasdiqlandi (dev)'),
                      backgroundColor: AppColors.success,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                icon: const Icon(Icons.check, color: AppColors.success, size: 16),
                label: const Text('[Dev] Kuryerni tasdiqlash',
                    style: TextStyle(color: AppColors.success)),
                style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.success)),
              ),
            ),

          // ── Logout ─────────────────────────────────────────────────────────
          OutlinedButton.icon(
            onPressed: () {
              auth.logout();
              context.go('/auth/login');
            },
            icon: const Icon(Icons.logout, color: AppColors.error, size: 18),
            label: const Text('Chiqish', style: TextStyle(color: AppColors.error)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppColors.error),
              minimumSize: const Size(double.infinity, 48),
            ),
          ),

          const SizedBox(height: 20),
          const Center(
            child: Text('TezKetKaz v1.0.0',
                style: TextStyle(color: AppColors.textHint, fontSize: 12)),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  final String value, label;
  final bool accent;
  const _HeroStat({required this.value, required this.label, this.accent = false});
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(value, style: TextStyle(
        fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -0.4,
        color: accent ? AppColors.primary : Colors.white,
      )),
      const SizedBox(height: 2),
      Text(label, style: TextStyle(
        color: Colors.white.withValues(alpha: 0.6),
        fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.3,
      )),
    ],
  );
}

class _HeroDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    width: 1, height: 28,
    color: Colors.white.withValues(alpha: 0.12),
  );
}

class _Card extends StatelessWidget {
  final List<Widget> children;
  const _Card({required this.children});
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        boxShadow: isDark ? null : AppShadows.card,
      ),
      child: Column(
        children: children.asMap().entries.map((e) => Column(
          children: [
            e.value,
            if (e.key < children.length - 1)
              Padding(
                padding: const EdgeInsets.only(left: 54),
                child: Divider(height: 1, color: Theme.of(context).dividerColor),
              ),
          ],
        )).toList(),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final String icon, title;
  final String? subtitle;
  final Color? color;
  final Widget? trailing;
  final VoidCallback onTap;
  const _Tile({required this.icon, required this.title, this.subtitle, this.color, this.trailing, required this.onTap});
  @override
  Widget build(BuildContext context) => ListTile(
    leading: Text(icon, style: const TextStyle(fontSize: 22)),
    title: Text(title, style: TextStyle(fontWeight: FontWeight.w500, color: color ?? AppColors.textPrimary, fontSize: 14)),
    subtitle: subtitle != null ? Text(subtitle!, style: const TextStyle(fontSize: 12)) : null,
    trailing: trailing ?? const Icon(Icons.chevron_right, color: AppColors.textHint),
    onTap: onTap,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
  );
}

/// Phase 10.3 — picker for `ThemeMode.system` / `light` / `dark`. Rendered as
/// a 3-segment pill (UberEats-style segmented control) so the choice is
/// always visible at a glance, not hidden behind a dropdown.
class _ThemeTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('🌙', style: TextStyle(fontSize: 22)),
              const SizedBox(width: 12),
              Text(
                t(context, 'theme.title'),
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(AppRadii.pill),
            ),
            child: Row(
              children: [
                _ThemeSegment(
                  selected: theme.themeMode == ThemeMode.system,
                  icon: Icons.brightness_auto_rounded,
                  label: t(context, 'theme.system'),
                  onTap: () => theme.setThemeMode(ThemeMode.system),
                ),
                _ThemeSegment(
                  selected: theme.themeMode == ThemeMode.light,
                  icon: Icons.wb_sunny_rounded,
                  label: t(context, 'theme.light'),
                  onTap: () => theme.setThemeMode(ThemeMode.light),
                ),
                _ThemeSegment(
                  selected: theme.themeMode == ThemeMode.dark,
                  icon: Icons.nightlight_round,
                  label: t(context, 'theme.dark'),
                  onTap: () => theme.setThemeMode(ThemeMode.dark),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ThemeSegment extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ThemeSegment({
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? AppColors.neutralInk : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadii.pill),
            boxShadow: selected
                ? [BoxShadow(color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 8, offset: const Offset(0, 2))]
                : null,
          ),
          child: Column(
            children: [
              Icon(
                icon,
                size: 18,
                color: selected ? Colors.white : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
