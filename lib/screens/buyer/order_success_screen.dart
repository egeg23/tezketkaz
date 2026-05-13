import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';

/// ORDER SUCCESS — master.html .success (lines 6638-6682).
///
/// Triple expanding lime rings + 100×100 lime check disc, Playfair
/// "Заказ *принят*" with italic lime word, description, order details card
/// (3 rows: number / ETA / paid), lime CTA "Отслеживать заказ →",
/// ghost CTA "На главную". After 5 seconds auto-routes to tracking.
class OrderSuccessScreen extends StatefulWidget {
  final String orderId;
  const OrderSuccessScreen({super.key, required this.orderId});
  @override
  State<OrderSuccessScreen> createState() => _OrderSuccessScreenState();
}

class _OrderSuccessScreenState extends State<OrderSuccessScreen>
    with TickerProviderStateMixin {
  late final AnimationController _bump;
  late final AnimationController _rings;
  Timer? _navTimer;

  @override
  void initState() {
    super.initState();
    HapticFeedback.heavyImpact();
    _bump = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..forward();
    _rings = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
    _navTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted) return;
      context.go('/buyer/tracking/${widget.orderId}');
    });
  }

  @override
  void dispose() {
    _bump.dispose();
    _rings.dispose();
    _navTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scale = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _bump, curve: Curves.elasticOut),
    );
    final fade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _bump, curve: const Interval(0.3, 1)),
    );
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0A0A10), Color(0xFF050507)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
            child: Column(
              children: [
                const SizedBox(height: 40),
                _SuccessStage(rings: _rings, scale: scale),
                const SizedBox(height: 40),
                FadeTransition(
                  opacity: fade,
                  child: RichText(
                    textAlign: TextAlign.center,
                    text: TextSpan(
                      style: GoogleFonts.playfairDisplay(
                        fontSize: 32,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                        letterSpacing: -0.5,
                        height: 1.1,
                      ),
                      children: [
                        const TextSpan(text: 'Заказ\n'),
                        TextSpan(
                          text: 'принят',
                          style: GoogleFonts.playfairDisplay(
                            fontStyle: FontStyle.italic,
                            color: AppColors.primary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                FadeTransition(
                  opacity: fade,
                  child: Text(
                    'Ресторан начал собирать ваш заказ. Курьер скоро отправится.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                FadeTransition(
                  opacity: fade,
                  child: _OrderCard(orderId: widget.orderId),
                ),
                const Spacer(),
                FadeTransition(
                  opacity: fade,
                  child: Column(
                    children: [
                      _LimeCta(
                        label: 'Отслеживать заказ',
                        onTap: () =>
                            context.go('/buyer/tracking/${widget.orderId}'),
                      ),
                      const SizedBox(height: 10),
                      _GhostCta(
                        label: 'На главную',
                        onTap: () => context.go('/buyer'),
                      ),
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

class _SuccessStage extends StatelessWidget {
  final AnimationController rings;
  final Animation<double> scale;
  const _SuccessStage({required this.rings, required this.scale});
  @override
  Widget build(BuildContext context) => SizedBox(
        width: 220,
        height: 220,
        child: Stack(
          alignment: Alignment.center,
          children: [
            for (var i = 0; i < 3; i++)
              AnimatedBuilder(
                animation: rings,
                builder: (_, __) {
                  final t = (rings.value + i / 3) % 1.0;
                  return Opacity(
                    opacity: (1 - t).clamp(0.0, 1.0) * 0.5,
                    child: Container(
                      width: 100 + t * 120,
                      height: 100 + t * 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.primary,
                          width: 1.5,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ScaleTransition(
              scale: scale,
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.5),
                      blurRadius: 36,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Icon(
                  Icons.check_rounded,
                  color: AppColors.bg,
                  size: 56,
                ),
              ),
            ),
          ],
        ),
      );
}

class _OrderCard extends StatelessWidget {
  final String orderId;
  const _OrderCard({required this.orderId});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          color: AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            _Row(
              label: 'Номер заказа',
              value: '#TK-${orderId.substring(0, orderId.length.clamp(0, 6))}',
            ),
            const SizedBox(height: 10),
            _Row(label: 'Доставка', value: '~25 мин', valueLime: true),
            const SizedBox(height: 10),
            _Row(label: 'Оплачено', value: '140 000 сум'),
          ],
        ),
      );
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  final bool valueLime;
  const _Row({
    required this.label,
    required this.value,
    this.valueLime = false,
  });
  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
          Text(
            value,
            style: GoogleFonts.jetBrainsMono(
              fontSize: valueLime ? 14 : 13,
              fontWeight: FontWeight.w600,
              color: valueLime ? AppColors.primary : Colors.white,
            ),
          ),
        ],
      );
}

class _LimeCta extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _LimeCta({required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 16),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(100),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.30),
                blurRadius: 24,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: AppColors.bg,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.arrow_forward_rounded,
                  size: 18, color: AppColors.bg),
            ],
          ),
        ),
      );
}

class _GhostCta extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _GhostCta({required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(100),
            border: Border.all(color: AppColors.border),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
}
