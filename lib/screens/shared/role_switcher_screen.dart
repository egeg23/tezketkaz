import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../models/models.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_theme.dart';

const _kShopColor = Color(0xFF3B5BDB);
const _kShopLight = Color(0xFFEEF2FF);

class RoleSwitcherScreen extends StatelessWidget {
  const RoleSwitcherScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user!;
    final role = user.activeRole;

    return Scaffold(
      backgroundColor: Colors.black54,
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text('Rejimni tanlang',
                              style: Theme.of(context).textTheme.headlineMedium),
                        ),
                        // Current role pill
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.primaryLight,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            _roleLabel(role),
                            style: const TextStyle(
                              color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      'Ilovani yopmasdan rol almashtiring',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── Buyer ────────────────────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _RoleOption(
                      emoji: '🛒',
                      title: 'Xaridor',
                      subtitle: 'Mahsulot buyurtma qilish',
                      color: AppColors.primary,
                      isActive: role == UserRole.buyer,
                      onTap: () async {
                        await auth.switchRole(UserRole.buyer);
                        if (context.mounted) context.go('/buyer');
                      },
                    ),
                  ),
                  const SizedBox(height: 10),

                  // ── Courier ──────────────────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _RoleOption(
                      emoji: '🛵',
                      title: 'Kuryer',
                      subtitle: _courierSub(user),
                      color: AppColors.courier,
                      isActive: role == UserRole.courier,
                      badge: _courierBadge(user),
                      onTap: () async {
                        if (user.courierStatus == CourierVerificationStatus.none) {
                          context.go('/courier-verification'); return;
                        }
                        if (user.courierStatus == CourierVerificationStatus.pending) {
                          _pendingDialog(context); return;
                        }
                        if (user.courierStatus == CourierVerificationStatus.rejected) {
                          context.go('/courier-verification'); return;
                        }
                        final ok = await auth.switchRole(UserRole.courier);
                        if (ok && context.mounted) context.go('/courier');
                      },
                    ),
                  ),
                  const SizedBox(height: 10),

                  // ── Shop ─────────────────────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _RoleOption(
                      emoji: '🏪',
                      title: 'Do\'kon',
                      subtitle: user.isShopOwner
                        ? user.shopName ?? 'Do\'kon boshqaruvi'
                        : 'Do\'kon egasi? Ulaning',
                      color: _kShopColor,
                      isActive: role == UserRole.shop,
                      badge: user.isShopOwner ? _Badge('Ulangan', AppColors.success) : null,
                      onTap: () async {
                        if (!user.isShopOwner) {
                          _shopConnectSheet(context, auth);
                          return;
                        }
                        await auth.switchRole(UserRole.shop);
                        if (context.mounted) context.go('/shop');
                      },
                    ),
                  ),

                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: OutlinedButton(
                      onPressed: () => context.pop(),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.border),
                        foregroundColor: AppColors.textSecondary,
                      ),
                      child: const Text('Bekor qilish'),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  String _roleLabel(UserRole role) {
    switch (role) {
      case UserRole.buyer:   return '🛒 Xaridor';
      case UserRole.courier: return '🛵 Kuryer';
      case UserRole.shop:    return '🏪 Do\'kon';
    }
  }

  String _courierSub(User user) {
    switch (user.courierStatus) {
      case CourierVerificationStatus.none:     return 'Ro\'yxatdan o\'ting va daromad oling';
      case CourierVerificationStatus.pending:  return 'Ariza ko\'rib chiqilmoqda...';
      case CourierVerificationStatus.approved: return 'Buyurtma qabul qilib ishlang';
      case CourierVerificationStatus.rejected: return 'Rad etildi — qayta ariza bering';
    }
  }

  Widget? _courierBadge(User user) {
    switch (user.courierStatus) {
      case CourierVerificationStatus.pending:  return _Badge('Tekshirilmoqda', AppColors.warning);
      case CourierVerificationStatus.approved: return _Badge('Faol', AppColors.success);
      case CourierVerificationStatus.rejected: return _Badge('Rad etildi', AppColors.error);
      default: return null;
    }
  }

  void _pendingDialog(BuildContext ctx) {
    showDialog(
      context: ctx,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Ariza tekshirilmoqda'),
        content: const Text(
          'Arizangiz 1-2 ish kuni ichida ko\'rib chiqiladi. '
          'Natija haqida SMS yuboramiz.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Tushunarli'),
          ),
        ],
      ),
    );
  }

  void _shopConnectSheet(BuildContext ctx, AuthProvider auth) {
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          left: 24, right: 24, top: 24,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 32,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Do\'konni ulash', style: Theme.of(ctx).textTheme.headlineMedium),
            const SizedBox(height: 6),
            const Text(
              'Do\'koningizni TezKetKaz ga ulang va buyurtma qabul qiling.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
            ),
            const SizedBox(height: 20),
            // Demo: mock shop connect
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _kShopLight,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _kShopColor.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Prototip: demo do\'kon',
                      style: TextStyle(fontWeight: FontWeight.w700, color: _kShopColor)),
                  const SizedBox(height: 4),
                  const Text('«Korzinka — Yunusobod» do\'koni sifatida ulaning',
                      style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                ],
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                auth.connectShop('shop_korzinka');
                Navigator.pop(ctx);
                ctx.go('/shop');
              },
              style: ElevatedButton.styleFrom(backgroundColor: _kShopColor),
              child: const Text('Do\'konni ulash'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Widgets ───────────────────────────────────────────────────────────────────

class _RoleOption extends StatelessWidget {
  final String emoji, title, subtitle;
  final Color color;
  final bool isActive;
  final Widget? badge;
  final VoidCallback onTap;

  const _RoleOption({
    required this.emoji, required this.title, required this.subtitle,
    required this.color, required this.isActive, required this.onTap, this.badge,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isActive ? color.withValues(alpha: 0.07) : AppColors.bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isActive ? color : AppColors.border,
          width: isActive ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 50, height: 50,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(child: Text(emoji, style: const TextStyle(fontSize: 24))),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(title,
                        style: TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15,
                          color: isActive ? color : AppColors.textPrimary,
                        )),
                    if (badge != null) ...[const SizedBox(width: 8), badge!],
                  ],
                ),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 12,
                    )),
              ],
            ),
          ),
          Icon(
            isActive ? Icons.check_circle : Icons.chevron_right,
            color: isActive ? color : AppColors.textHint,
            size: isActive ? 22 : 20,
          ),
        ],
      ),
    ),
  );
}

class _Badge extends StatelessWidget {
  final String text;
  final Color color;
  const _Badge(this.text, this.color);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(text,
        style: TextStyle(
          color: color, fontSize: 10, fontWeight: FontWeight.w700,
        )),
  );
}
