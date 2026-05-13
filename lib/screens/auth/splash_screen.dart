import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../models/models.dart';
import '../../providers/auth_provider.dart';
import '../../providers/order_provider.dart';
import '../../theme/app_theme.dart';

/// SPLASH — master.html .splash (lines 5786-5805 / 370-382).
///
/// Layered radial lime spotlights on ink-deep canvas. Lime 140×140 mark
/// with bold tz wordmark + black bolt-disc top-right. Playfair-italic
/// "Tez*Ketkaz*" wordmark. Uppercase tracked tagline. 3-dot lime loader
/// bouncing at the bottom.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late final AnimationController _float;
  late final AnimationController _dots;

  @override
  void initState() {
    super.initState();
    _float = AnimationController(
      vsync: this, duration: const Duration(seconds: 4),
    )..repeat(reverse: true);
    _dots = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1400),
    )..repeat();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    final auth = context.read<AuthProvider>();
    await auth.tryRestoreSession();
    await Future.delayed(const Duration(milliseconds: 1400));
    if (!mounted) return;
    if (auth.isAuthenticated) {
      context.read<OrderProvider>().connectSockets();
      if (auth.user?.name == null) {
        context.go('/auth/name');
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
  void dispose() {
    _float.dispose();
    _dots.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Container(
      decoration: const BoxDecoration(
        // Triple-radial lime spotlight stack — exact tokens from master.html.
        gradient: LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [Color(0xFF0A0A10), Color(0xFF050507)],
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Ambient radial spots
          Positioned.fill(child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center, radius: 0.6,
                colors: [const Color(0xFF06C167).withValues(alpha: 0.15), Colors.transparent],
              ),
            ),
          )),
          Positioned.fill(child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0.6, -0.8), radius: 0.7,
                colors: [const Color(0xFF06C167).withValues(alpha: 0.08), Colors.transparent],
              ),
            ),
          )),
          Positioned.fill(child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(-0.6, 0.8), radius: 0.5,
                colors: [const Color(0xFF06C167).withValues(alpha: 0.06), Colors.transparent],
              ),
            ),
          )),

          // Brand mark + wordmark
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ScaleTransition(
                scale: Tween<double>(begin: 0.98, end: 1.02).animate(
                  CurvedAnimation(parent: _float, curve: Curves.easeInOut),
                ),
                child: Container(
                  width: 140, height: 140,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(38),
                    boxShadow: [
                      BoxShadow(color: AppColors.primary.withValues(alpha: 0.08),
                          blurRadius: 0, spreadRadius: 12),
                      BoxShadow(color: AppColors.primary.withValues(alpha: 0.04),
                          blurRadius: 0, spreadRadius: 24),
                      BoxShadow(color: AppColors.primary.withValues(alpha: 0.40),
                          blurRadius: 80, offset: const Offset(0, 40)),
                    ],
                  ),
                  child: Stack(
                    children: [
                      Center(child: Text('tz',
                          style: TextStyle(
                            fontWeight: FontWeight.w900, fontSize: 78,
                            color: AppColors.bg, letterSpacing: -5, height: 1,
                          ))),
                      Positioned(
                        top: 16, right: 16,
                        child: Container(
                          width: 22, height: 22,
                          decoration: BoxDecoration(
                            color: AppColors.bg, shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.bolt_rounded,
                              color: AppColors.primary, size: 14),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),
              RichText(
                text: TextSpan(
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 36, fontWeight: FontWeight.w500,
                    letterSpacing: -0.7, color: Colors.white,
                  ),
                  children: [
                    const TextSpan(text: 'Tez'),
                    TextSpan(
                      text: 'Ketkaz',
                      style: GoogleFonts.playfairDisplay(
                        fontStyle: FontStyle.italic,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'БЫСТРО · НАДЁЖНО · ДОСТАВКА',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12, letterSpacing: 2, fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),

          // 3-dot bouncing loader
          Positioned(
            bottom: 80,
            child: AnimatedBuilder(
              animation: _dots,
              builder: (_, __) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < 3; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Opacity(
                        opacity: _dotOpacity(i),
                        child: Container(
                          width: 8, height: 8,
                          decoration: const BoxDecoration(
                            color: AppColors.primary, shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );

  double _dotOpacity(int i) {
    final t = (_dots.value + i * 0.18) % 1.0;
    return 0.3 + 0.7 * (1 - (t * 2 - 1).abs()).clamp(0.0, 1.0);
  }
}
