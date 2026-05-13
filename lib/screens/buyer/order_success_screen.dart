import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../theme/app_theme.dart';

/// Brief celebration screen shown right after an order is placed. Auto-routes
/// to the tracking screen after ~1.8s. Animates a lime check mark that scales
/// in with a spring + radiating ripples.
class OrderSuccessScreen extends StatefulWidget {
  final String orderId;
  const OrderSuccessScreen({super.key, required this.orderId});
  @override
  State<OrderSuccessScreen> createState() => _OrderSuccessScreenState();
}

class _OrderSuccessScreenState extends State<OrderSuccessScreen>
    with TickerProviderStateMixin {
  late final AnimationController _bumpCtl;
  late final AnimationController _rippleCtl;
  Timer? _navTimer;

  @override
  void initState() {
    super.initState();
    HapticFeedback.heavyImpact();
    _bumpCtl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 700),
    )..forward();
    _rippleCtl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1500),
    )..repeat();
    _navTimer = Timer(const Duration(milliseconds: 1800), () {
      if (!mounted) return;
      context.go('/buyer/tracking/${widget.orderId}');
    });
  }

  @override
  void dispose() {
    _bumpCtl.dispose();
    _rippleCtl.dispose();
    _navTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _bumpCtl, curve: Curves.elasticOut),
    );
    final fade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _bumpCtl, curve: const Interval(0.3, 1.0)),
    );
    return Scaffold(
      backgroundColor: AppColors.neutralInk,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 220, height: 220,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Ripple rings
                  for (var i = 0; i < 3; i++)
                    AnimatedBuilder(
                      animation: _rippleCtl,
                      builder: (_, __) {
                        final t = (_rippleCtl.value + i / 3) % 1.0;
                        return Opacity(
                          opacity: (1 - t).clamp(0.0, 1.0) * 0.35,
                          child: Container(
                            width: 80 + t * 140,
                            height: 80 + t * 140,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: AppColors.primary, width: 2),
                            ),
                          ),
                        );
                      },
                    ),
                  // Check disk
                  ScaleTransition(
                    scale: scale,
                    child: Container(
                      width: 120, height: 120,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.5),
                          blurRadius: 36, spreadRadius: 2,
                        )],
                      ),
                      child: const Icon(
                        Icons.check_rounded,
                        color: AppColors.neutralInk,
                        size: 72,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 36),
            FadeTransition(
              opacity: fade,
              child: const Text(
                "Buyurtma qabul qilindi",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: -0.4,
                ),
              ),
            ),
            const SizedBox(height: 6),
            FadeTransition(
              opacity: fade,
              child: Text(
                "Do'kon yig'ishni boshlaydi...",
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 14, fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
