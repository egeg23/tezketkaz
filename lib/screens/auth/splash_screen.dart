import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../models/models.dart';
import '../../providers/auth_provider.dart';
import '../../providers/order_provider.dart';
import '../../theme/app_theme.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale, _fade, _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));
    _scale = Tween(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack),
    );
    _fade = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: const Interval(0.0, 0.5)),
    );
    _slide = Tween(begin: 30.0, end: 0.0).animate(
      CurvedAnimation(parent: _ctrl, curve: const Interval(0.3, 0.9, curve: Curves.easeOutCubic)),
    );
    _ctrl.forward();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    final auth = context.read<AuthProvider>();
    await auth.tryRestoreSession();
    await Future.delayed(const Duration(milliseconds: 1300));
    if (!mounted) return;

    if (auth.isAuthenticated) {
      context.read<OrderProvider>().connectSockets();
      if (auth.user?.name == null) {
        context.go('/auth/name');
      } else if (auth.user?.activeRole == UserRole.buyer &&
          auth.user?.onboardedAt == null) {
        // Phase 11 — first-time buyers see the tutorial before the shell.
        context.go('/onboarding');
      } else {
        switch (auth.user?.activeRole) {
          case UserRole.courier: context.go('/courier'); break;
          case UserRole.shop:    context.go('/shop'); break;
          default:               context.go('/buyer');
        }
      }
    } else {
      context.go('/auth/login');
    }
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.neutralInk,
    body: Container(
      decoration: const BoxDecoration(color: AppColors.neutralInk),
      child: Stack(
        children: [
          // Decorative lime glows on near-black canvas
          Positioned(
            top: -120, right: -80,
            child: Container(
              width: 320, height: 320,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            bottom: -140, left: -60,
            child: Container(
              width: 260, height: 260,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.06),
                shape: BoxShape.circle,
              ),
            ),
          ),

          Center(
            child: AnimatedBuilder(
              animation: _ctrl,
              builder: (_, __) => Opacity(
                opacity: _fade.value,
                child: Transform.translate(
                  offset: Offset(0, _slide.value),
                  child: Transform.scale(
                    scale: _scale.value,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Logo mark — lime rounded square with bold TZ wordmark
                        // and a small lightning glyph baseline-aligned to the
                        // right, all in near-black ink.
                        Container(
                          width: 128, height: 128,
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(36),
                            boxShadow: [BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.45),
                              blurRadius: 60, offset: const Offset(0, 20),
                              spreadRadius: 2,
                            )],
                          ),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              const Text(
                                'tz',
                                style: TextStyle(
                                  fontSize: 72, height: 1.0,
                                  fontWeight: FontWeight.w900,
                                  color: AppColors.neutralInk,
                                  letterSpacing: -4,
                                ),
                              ),
                              Positioned(
                                top: 16, right: 16,
                                child: Container(
                                  width: 18, height: 18,
                                  decoration: const BoxDecoration(
                                    color: AppColors.neutralInk,
                                    shape: BoxShape.circle,
                                  ),
                                  alignment: Alignment.center,
                                  child: const Icon(
                                    Icons.bolt_rounded,
                                    color: AppColors.primary,
                                    size: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 28),
                        const Text(
                          'TezKetKaz',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 40, fontWeight: FontWeight.w900,
                            letterSpacing: -1,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Yaqin atrofingizdagi do\'kondan\nbir-ikki klikda',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 15, fontWeight: FontWeight.w500, height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Bottom progress indicator
          Positioned(
            bottom: 60, left: 0, right: 0,
            child: Center(
              child: SizedBox(
                width: 28, height: 28,
                child: CircularProgressIndicator(
                  color: Colors.white.withValues(alpha: 0.9),
                  strokeWidth: 2.5,
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
