import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/order_provider.dart';
import '../../providers/theme_provider.dart';
import '../../theme/app_theme.dart';
import '../../models/models.dart';

/// PROFILE — master.html .profile (lines 6970-7088 / 2525-2694).
///
/// Layout
///   profile-top   → "Профиль" Playfair + "Изменить" glass pill
///   profile-hero  → radial-lime gradient card with lime 64px avatar, name +
///                   masked phone, three glass stats (Заказы / Сэкономлено /
///                   Рейтинг). Lime stat for savings.
///   theme-toggle  → 3-segment pill Auto / Light / Dark (active = lime fill).
///   settings group 1 → Адреса · Способы оплаты · Уведомления
///   settings group 2 → Язык · Помощь · Выход (red tint)
///   app-version   → "TezKetKaz v…" mono-font footer
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final orders = context.watch<OrderProvider>();
    final user = auth.user!;

    final totalOrders = orders.all.length;
    final delivered = orders.all
        .where((o) =>
            o.status == AppOrderStatus.delivered ||
            o.status == AppOrderStatus.confirmedByBuyer)
        .length;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 120),
          children: [
            _ProfileTop(),
            const SizedBox(height: 4),
            _ProfileHero(user: user, totalOrders: totalOrders),
            const SizedBox(height: 20),
            _ThemeToggle(),
            const SizedBox(height: 20),
            _SettingsGroup(rows: [
              _SettingsRow(
                icon: Icons.place_outlined,
                label: 'Адреса',
                onTap: () => context.push('/buyer/address-book'),
              ),
              _SettingsRow(
                icon: Icons.credit_card_rounded,
                label: 'Способы оплаты',
                value: 'Click, Payme',
                onTap: () => context.push('/buyer/payment-methods'),
              ),
              _SettingsRow(
                icon: Icons.notifications_none_rounded,
                label: 'Уведомления',
                value: 'Включены',
                onTap: () => context.push('/buyer/notifications'),
              ),
              _SettingsRow(
                icon: Icons.favorite_border_rounded,
                label: 'Избранное',
                onTap: () => context.push('/buyer/favorites'),
              ),
            ]),
            const SizedBox(height: 14),
            _SettingsGroup(rows: [
              _SettingsRow(
                icon: Icons.card_giftcard_rounded,
                label: 'Промокоды',
                onTap: () => context.push('/buyer/promo'),
              ),
              _SettingsRow(
                icon: Icons.workspace_premium_outlined,
                label: 'Подписка TezKetKaz+',
                value: auth.membership?.isActive == true ? 'Активна' : 'Подключить',
                onTap: () => context.push('/buyer/subscription'),
              ),
              _SettingsRow(
                icon: Icons.loyalty_outlined,
                label: 'Бонусы',
                onTap: () => context.push('/buyer/loyalty'),
              ),
            ]),
            const SizedBox(height: 14),
            _SettingsGroup(rows: [
              _SettingsRow(
                icon: Icons.language_rounded,
                label: 'Язык',
                value: 'Русский',
                onTap: () => context.push('/buyer/country-settings'),
              ),
              _SettingsRow(
                icon: Icons.shield_outlined,
                label: 'Конфиденциальность',
                onTap: () => context.push('/buyer/data-privacy'),
              ),
              // Phase 12 — Privacy Policy + Terms tabbed viewer. App Store /
              // Play Store reviewers reach legal text without creating an
              // account; required for store compliance.
              _SettingsRow(
                icon: Icons.gavel_rounded,
                label: 'Условия и политика',
                onTap: () => context.push('/legal'),
              ),
              _SettingsRow(
                icon: Icons.chat_bubble_outline_rounded,
                label: 'Помощь',
                onTap: () => context.push('/buyer/support'),
              ),
              _SettingsRow(
                icon: Icons.swap_horiz_rounded,
                label: 'Сменить роль',
                value: _activeRoleLabel(user.activeRole),
                onTap: () => context.push('/switch-role'),
              ),
              _SettingsRow(
                icon: Icons.logout_rounded,
                label: 'Выйти',
                danger: true,
                onTap: () {
                  auth.logout();
                  context.go('/auth/login');
                },
              ),
            ]),
            const SizedBox(height: 18),
            Center(
              child: Text(
                'TezKetKaz v1.0.4 · build 4821',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 11, color: AppColors.textHint, letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _activeRoleLabel(UserRole role) {
    switch (role) {
      case UserRole.courier: return 'Курьер';
      case UserRole.shop:    return 'Магазин';
      default:                return 'Покупатель';
    }
  }
}

// ── Components ───────────────────────────────────────────────────────────

class _ProfileTop extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'Профиль',
          style: GoogleFonts.playfairDisplay(
            fontSize: 28, fontWeight: FontWeight.w500,
            letterSpacing: -0.5, color: Colors.white,
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.surfaceMuted,
            borderRadius: BorderRadius.circular(100),
            border: Border.all(color: AppColors.border),
          ),
          child: Text(
            'Изменить',
            style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ),
      ],
    ),
  );
}

class _ProfileHero extends StatelessWidget {
  final User user;
  final int totalOrders;
  const _ProfileHero({required this.user, required this.totalOrders});

  @override
  Widget build(BuildContext context) {
    final name = user.name ?? 'Покупатель';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final phone = _maskPhone(user.phone);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
        gradient: const LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Color(0xFF1A1A22), Color(0xFF0A0A10)],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -20, right: -20,
            child: Container(
              width: 200, height: 200,
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center, radius: 0.6,
                  colors: [
                    AppColors.primary.withValues(alpha: 0.18),
                    Colors.transparent,
                  ],
                ),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 64, height: 64,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.3),
                          blurRadius: 24, offset: const Offset(0, 8),
                        )],
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        initial,
                        style: TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 22,
                          color: AppColors.bg, letterSpacing: -1,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: GoogleFonts.playfairDisplay(
                              fontSize: 22, fontWeight: FontWeight.w600,
                              letterSpacing: -0.4, color: Colors.white,
                              height: 1.1,
                            ),
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            phone,
                            style: GoogleFonts.jetBrainsMono(
                              color: AppColors.textSecondary, fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(child: _StatCell(
                      value: '$totalOrders',
                      label: 'ЗАКАЗЫ',
                    )),
                    const SizedBox(width: 8),
                    Expanded(child: _StatCell(
                      value: '${(totalOrders * 3.6).toInt()}k',
                      label: 'СЭКОНОМЛЕНО', lime: true,
                    )),
                    const SizedBox(width: 8),
                    Expanded(child: _StatCell(
                      value: '★ 5.0',
                      label: 'РЕЙТИНГ',
                    )),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _maskPhone(String raw) {
    // "+998901234567" → "+998 90 ••• 45 67"
    if (raw.length < 9) return raw;
    final cc = raw.substring(0, 4);  // +998
    final op = raw.substring(4, 6);  // 90
    final last4 = raw.substring(raw.length - 4);
    return '$cc $op ••• ${last4.substring(0, 2)} ${last4.substring(2)}';
  }
}

class _StatCell extends StatelessWidget {
  final String value, label;
  final bool lime;
  const _StatCell({required this.value, required this.label, this.lime = false});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.04),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.border),
    ),
    child: Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 18, fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
            color: lime ? AppColors.primary : Colors.white,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 9.5, fontWeight: FontWeight.w700,
            letterSpacing: 0.7, color: AppColors.textSecondary,
          ),
        ),
      ],
    ),
  );
}

class _ThemeToggle extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final tp = context.watch<ThemeProvider>();
    final current = tp.themeMode;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          _seg(context, ThemeMode.light, Icons.wb_sunny_outlined, 'Светлая', current),
          _seg(context, ThemeMode.dark, Icons.dark_mode_outlined, 'Тёмная', current),
          _seg(context, ThemeMode.system, Icons.brightness_auto_outlined, 'Авто', current),
        ],
      ),
    );
  }

  Widget _seg(BuildContext context, ThemeMode mode, IconData icon, String label, ThemeMode current) {
    final active = mode == current;
    return Expanded(
      child: GestureDetector(
        onTap: () => context.read<ThemeProvider>().setThemeMode(mode),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: active ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14,
                  color: active ? const Color(0xFF00321A) : AppColors.textSecondary),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700,
                  color: active ? const Color(0xFF00321A) : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  final List<_SettingsRow> rows;
  const _SettingsGroup({required this.rows});

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.03),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: AppColors.border),
    ),
    clipBehavior: Clip.hardEdge,
    child: Column(
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          rows[i],
          if (i < rows.length - 1)
            const Divider(height: 1, color: AppColors.border),
        ],
      ],
    ),
  );
}

class _SettingsRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? value;
  final bool danger;
  final VoidCallback onTap;
  const _SettingsRow({
    required this.icon, required this.label, this.value,
    this.danger = false, required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: danger
                    ? const Color(0x26FF6464)
                    : AppColors.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Icon(icon,
                  size: 16,
                  color: danger ? AppColors.error : AppColors.primary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w500,
                  color: danger ? const Color(0xFFFF8080) : Colors.white,
                ),
              ),
            ),
            if (value != null) ...[
              Text(
                value!,
                style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(width: 8),
            ],
            Text(
              '›',
              style: TextStyle(
                fontSize: 18, height: 1, color: AppColors.textHint,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
