import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../models/models.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_theme.dart';

/// ROLE SWITCHER — master.html .role-sw (lines 9298-9398).
///
/// Top-right close X, lime pre-line, Playfair italic "Sizning *rolingiz*",
/// description, three .role-card rows (current = lime border + glow + corner
/// checkmark; others = glass border + chev), dashed "+ Yangi rol uchun ariza"
/// button at the bottom.
class RoleSwitcherScreen extends StatelessWidget {
  const RoleSwitcherScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user!;
    final role = user.activeRole;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Color(0xFF0A0A10), Color(0xFF050507)],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ─ Close-X chip (top-right) ───────────────────────────────
                Align(
                  alignment: Alignment.centerRight,
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).maybePop(),
                    child: Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceMuted,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.border),
                      ),
                      child: const Icon(Icons.close_rounded,
                          size: 18, color: AppColors.textSecondary),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // ─ Intro ──────────────────────────────────────────────────
                Text(
                  'В КАКОЙ РОЛИ ВХОДИТЕ?',
                  style: TextStyle(
                    fontSize: 11, letterSpacing: 1.8,
                    color: AppColors.primary, fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                RichText(
                  text: TextSpan(
                    style: GoogleFonts.playfairDisplay(
                      fontSize: 32, fontWeight: FontWeight.w500,
                      letterSpacing: -0.6, color: Colors.white, height: 1.1,
                    ),
                    children: [
                      const TextSpan(text: 'Ваша '),
                      TextSpan(
                        text: 'роль',
                        style: GoogleFonts.playfairDisplay(
                          fontStyle: FontStyle.italic,
                          color: AppColors.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: 280,
                  child: Text(
                    'В одном аккаунте могут быть разные роли. Переключайтесь в любой момент.',
                    style: TextStyle(
                      fontSize: 14, height: 1.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(height: 28),

                // ─ Buyer ──────────────────────────────────────────────────
                _RoleCard(
                  iconBg: AppColors.primary,
                  iconColor: AppColors.bg,
                  iconBorder: null,
                  icon: Icons.shopping_bag_rounded,
                  name: 'Покупатель',
                  desc: 'Заказывайте и получайте доставку',
                  status: _StatusChip(
                    text: 'Активна · сейчас',
                    color: AppColors.primary,
                    bg: AppColors.primary.withValues(alpha: 0.10),
                  ),
                  isCurrent: role == UserRole.buyer,
                  onTap: () async {
                    if (role == UserRole.buyer) {
                      context.pop();
                      return;
                    }
                    final ok = await auth.switchRole(UserRole.buyer);
                    if (ok && context.mounted) context.go('/buyer');
                  },
                ),

                // ─ Courier ────────────────────────────────────────────────
                _RoleCard(
                  iconBg: AppColors.primary.withValues(alpha: 0.15),
                  iconColor: AppColors.primary,
                  iconBorder: AppColors.primary.withValues(alpha: 0.30),
                  icon: Icons.delivery_dining_rounded,
                  name: 'Курьер',
                  desc: _courierDesc(user),
                  status: _courierStatusChip(user),
                  isCurrent: role == UserRole.courier,
                  onTap: () async {
                    if (user.courierStatus == CourierVerificationStatus.none ||
                        user.courierStatus == CourierVerificationStatus.rejected) {
                      context.go('/courier-verification');
                      return;
                    }
                    if (user.courierStatus == CourierVerificationStatus.pending) {
                      _pendingDialog(context);
                      return;
                    }
                    final ok = await auth.switchRole(UserRole.courier);
                    if (ok && context.mounted) context.go('/courier');
                  },
                ),

                // ─ Shop ───────────────────────────────────────────────────
                _RoleCard(
                  iconBg: AppColors.gold.withValues(alpha: 0.15),
                  iconColor: AppColors.gold,
                  iconBorder: AppColors.gold.withValues(alpha: 0.30),
                  icon: Icons.storefront_rounded,
                  name: 'Ресторан',
                  desc: user.isShopOwner
                      ? (user.shopName ?? 'Управление заведением')
                      : 'Принимайте заказы от клиентов',
                  status: user.isShopOwner
                      ? _StatusChip(
                          text: 'Активна',
                          color: AppColors.primary,
                          bg: AppColors.primary.withValues(alpha: 0.10),
                        )
                      : _StatusChip(
                          text: 'На проверке',
                          color: AppColors.warning,
                          bg: AppColors.warning.withValues(alpha: 0.15),
                        ),
                  isCurrent: role == UserRole.shop,
                  onTap: () async {
                    if (!user.isShopOwner) {
                      _shopConnectSheet(context, auth);
                      return;
                    }
                    final ok = await auth.switchRole(UserRole.shop);
                    if (ok && context.mounted) context.go('/shop');
                  },
                ),

                const SizedBox(height: 12),

                // ─ Apply for new role ─────────────────────────────────────
                _DashedAddButton(
                  label: 'Подать заявку на новую роль',
                  onTap: () => _shopConnectSheet(context, auth),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────

  String _courierDesc(User u) {
    switch (u.courierStatus) {
      case CourierVerificationStatus.none:
        return 'Доставляйте заказы и зарабатывайте';
      case CourierVerificationStatus.pending:
        return 'Заявка на рассмотрении';
      case CourierVerificationStatus.approved:
        return 'Доставляйте заказы и зарабатывайте';
      case CourierVerificationStatus.rejected:
        return 'Подайте заявку повторно';
    }
  }

  _StatusChip _courierStatusChip(User u) {
    switch (u.courierStatus) {
      case CourierVerificationStatus.approved:
        return _StatusChip(
          text: 'Активна · 312 заказов',
          color: AppColors.primary,
          bg: AppColors.primary.withValues(alpha: 0.10),
        );
      case CourierVerificationStatus.pending:
        return _StatusChip(
          text: 'На проверке',
          color: AppColors.warning,
          bg: AppColors.warning.withValues(alpha: 0.15),
        );
      case CourierVerificationStatus.rejected:
        return _StatusChip(
          text: 'Отклонено',
          color: AppColors.error,
          bg: AppColors.error.withValues(alpha: 0.15),
        );
      case CourierVerificationStatus.none:
        return _StatusChip(
          text: 'Не подавали',
          color: AppColors.textSecondary,
          bg: AppColors.surfaceMuted,
        );
    }
  }

  void _pendingDialog(BuildContext ctx) {
    showDialog(
      context: ctx,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Заявка на проверке',
            style: TextStyle(color: Colors.white)),
        content: Text(
          'Ваша заявка будет рассмотрена в течение 1–2 рабочих дней. О результате сообщим в SMS.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Понятно',
                style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );
  }

  void _shopConnectSheet(BuildContext ctx, AuthProvider auth) {
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
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
            RichText(
              text: TextSpan(
                style: GoogleFonts.playfairDisplay(
                  fontSize: 24, fontWeight: FontWeight.w500,
                  color: Colors.white,
                ),
                children: [
                  const TextSpan(text: 'Подключите '),
                  TextSpan(
                    text: 'ресторан',
                    style: GoogleFonts.playfairDisplay(
                      fontStyle: FontStyle.italic,
                      color: AppColors.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Подключите своё заведение к TezKetKaz и начните принимать заказы.',
              style: TextStyle(
                color: AppColors.textSecondary, fontSize: 14, height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.gold.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.gold.withValues(alpha: 0.30)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.gold.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.storefront_rounded,
                        color: AppColors.gold, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Демо-ресторан',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppColors.gold, fontSize: 14,
                            )),
                        const SizedBox(height: 2),
                        Text('«Корзинка — Юнусабад»',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            )),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  auth.connectShop('shop_korzinka');
                  Navigator.pop(ctx);
                  ctx.go('/shop');
                },
                child: const Text('Подключить'),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _RoleCard extends StatelessWidget {
  final Color iconBg;
  final Color iconColor;
  final Color? iconBorder;
  final IconData icon;
  final String name;
  final String desc;
  final _StatusChip status;
  final bool isCurrent;
  final VoidCallback onTap;

  const _RoleCard({
    required this.iconBg,
    required this.iconColor,
    required this.iconBorder,
    required this.icon,
    required this.name,
    required this.desc,
    required this.status,
    required this.isCurrent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isCurrent
            ? AppColors.primary.withValues(alpha: 0.06)
            : AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isCurrent ? AppColors.primary : AppColors.border,
          width: 1.5,
        ),
        boxShadow: isCurrent
            ? [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.10),
                  blurRadius: 30, spreadRadius: 0,
                ),
              ]
            : null,
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Icon block
              Container(
                width: 52, height: 52,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(16),
                  border: iconBorder != null
                      ? Border.all(color: iconBorder!)
                      : null,
                ),
                child: Icon(icon, color: iconColor, size: 24),
              ),
              const SizedBox(width: 14),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: GoogleFonts.playfairDisplay(
                        fontSize: 19, fontWeight: FontWeight.w500,
                        color: Colors.white, height: 1.1,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      desc,
                      style: TextStyle(
                        fontSize: 12, height: 1.4,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    status,
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Chev (hidden when current — replaced by corner mark)
              if (!isCurrent)
                Icon(Icons.chevron_right_rounded,
                    size: 18, color: AppColors.textHint),
            ],
          ),
          // Lime corner-mark for current role
          if (isCurrent)
            Positioned(
              top: -4, right: -4,
              child: Container(
                width: 24, height: 24,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.check_rounded,
                    color: AppColors.bg, size: 14),
              ),
            ),
        ],
      ),
    ),
  );
}

class _StatusChip extends StatelessWidget {
  final String text;
  final Color color;
  final Color bg;
  const _StatusChip({required this.text, required this.color, required this.bg});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(100),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 5, height: 5,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          text.toUpperCase(),
          style: TextStyle(
            color: color, fontSize: 10,
            fontWeight: FontWeight.w700, letterSpacing: 1,
          ),
        ),
      ],
    ),
  );
}

class _DashedAddButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _DashedAddButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: DottedBorder(
      color: AppColors.border,
      strokeWidth: 1.5,
      borderRadius: 18,
      dashWidth: 6, gapWidth: 4,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_rounded, size: 18, color: AppColors.primary),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: AppColors.primary,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Lightweight dashed-border container (no extra pkg required).
/// Renders a 1.5-px dashed rounded rectangle using a CustomPainter.
class DottedBorder extends StatelessWidget {
  final Widget child;
  final Color color;
  final double strokeWidth;
  final double borderRadius;
  final double dashWidth;
  final double gapWidth;
  const DottedBorder({
    super.key,
    required this.child,
    this.color = Colors.white24,
    this.strokeWidth = 1,
    this.borderRadius = 12,
    this.dashWidth = 5,
    this.gapWidth = 3,
  });

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _DashedRectPainter(
      color: color,
      strokeWidth: strokeWidth,
      radius: borderRadius,
      dashWidth: dashWidth,
      gapWidth: gapWidth,
    ),
    child: child,
  );
}

class _DashedRectPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double radius;
  final double dashWidth;
  final double gapWidth;
  _DashedRectPainter({
    required this.color,
    required this.strokeWidth,
    required this.radius,
    required this.dashWidth,
    required this.gapWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size, Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    final metrics = path.computeMetrics();
    for (final m in metrics) {
      double dist = 0;
      while (dist < m.length) {
        final next = (dist + dashWidth).clamp(0.0, m.length);
        canvas.drawPath(m.extractPath(dist, next), paint);
        dist = next + gapWidth;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRectPainter old) =>
      old.color != color || old.strokeWidth != strokeWidth ||
      old.radius != radius || old.dashWidth != dashWidth ||
      old.gapWidth != gapWidth;
}
