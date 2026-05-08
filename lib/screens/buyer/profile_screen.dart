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
      appBar: AppBar(title: const Text('Profil')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Avatar + name ─────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Stack(
                      children: [
                        CircleAvatar(
                          radius: 32,
                          backgroundColor: AppColors.primaryLight,
                          child: Text(
                            user.name?.isNotEmpty == true ? user.name![0].toUpperCase() : '?',
                            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.primary),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(user.name ?? 'Foydalanuvchi',
                              style: Theme.of(context).textTheme.titleLarge),
                          const SizedBox(height: 2),
                          Text(user.phone,
                              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, color: AppColors.textSecondary),
                      onPressed: () {},
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 16),
                // Stats row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _Stat(value: '$totalOrders', label: 'Jami buyurtma'),
                    _Stat(value: '$activeOrders', label: 'Faol', color: AppColors.primary),
                    _Stat(value: '$deliveredCount', label: 'Yetkazildi', color: AppColors.success),
                  ],
                ),
              ],
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

class _Stat extends StatelessWidget {
  final String value, label;
  final Color? color;
  const _Stat({required this.value, required this.label, this.color});
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(value, style: TextStyle(
        fontSize: 20, fontWeight: FontWeight.w800,
        color: color ?? AppColors.textPrimary,
      )),
      Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
    ],
  );
}

class _Card extends StatelessWidget {
  final List<Widget> children;
  const _Card({required this.children});
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.border),
    ),
    child: Column(
      children: children.asMap().entries.map((e) => Column(
        children: [
          e.value,
          if (e.key < children.length - 1) const Divider(height: 1, indent: 54, endIndent: 16),
        ],
      )).toList(),
    ),
  );
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

/// Phase 10.3 — picker for `ThemeMode.system` / `light` / `dark`. The change
/// is persisted by [ThemeProvider] and re-renders the whole `MaterialApp`
/// tree thanks to the AnimatedBuilder in main.dart.
class _ThemeTile extends StatelessWidget {
  String _label(BuildContext context, ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return t(context, 'theme.light');
      case ThemeMode.dark:
        return t(context, 'theme.dark');
      case ThemeMode.system:
        return t(context, 'theme.system');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    return ListTile(
      leading: const Text('🌙', style: TextStyle(fontSize: 22)),
      title: Text(t(context, 'theme.title'),
          style: const TextStyle(
              fontWeight: FontWeight.w500, fontSize: 14)),
      subtitle: Text(_label(context, theme.themeMode),
          style: const TextStyle(fontSize: 12)),
      trailing: DropdownButton<ThemeMode>(
        value: theme.themeMode,
        underline: const SizedBox.shrink(),
        items: [
          DropdownMenuItem(
              value: ThemeMode.system,
              child: Text(t(context, 'theme.system'))),
          DropdownMenuItem(
              value: ThemeMode.light,
              child: Text(t(context, 'theme.light'))),
          DropdownMenuItem(
              value: ThemeMode.dark,
              child: Text(t(context, 'theme.dark'))),
        ],
        onChanged: (mode) {
          if (mode != null) theme.setThemeMode(mode);
        },
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
    );
  }
}
