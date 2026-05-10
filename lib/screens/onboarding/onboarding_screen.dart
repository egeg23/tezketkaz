import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../l10n/l10n.dart';
import '../../providers/auth_provider.dart';
import '../../services/onboarding_api.dart';
import '../../theme/app_theme.dart';

/// Phase 11 — 4-slide intro shown to first-time buyers.
///
/// Each slide is purely emoji + text so we don't need to ship illustration
/// assets. The last slide's CTA marks the user as onboarded (best-effort) and
/// routes to `/buyer`.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pager = PageController();
  int _index = 0;
  bool _finishing = false;

  static const _slides = <_Slide>[
    _Slide(
      emoji: '⚡',
      titleKey: 'onboarding.slide1_title',
      bodyKey: 'onboarding.slide1_body',
      accent: AppColors.primary,
    ),
    _Slide(
      emoji: '🛒',
      titleKey: 'onboarding.slide2_title',
      bodyKey: 'onboarding.slide2_body',
      accent: AppColors.shop,
    ),
    _Slide(
      emoji: '🛵',
      titleKey: 'onboarding.slide3_title',
      bodyKey: 'onboarding.slide3_body',
      accent: AppColors.courier,
    ),
    _Slide(
      emoji: '📱',
      titleKey: 'onboarding.slide4_title',
      bodyKey: 'onboarding.slide4_body',
      accent: AppColors.primary,
    ),
  ];

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    if (_finishing) return;
    setState(() => _finishing = true);
    HapticFeedback.mediumImpact();
    // Optimistic — flip local state immediately so the router redirect stops
    // sending us back to /onboarding. The PATCH is fire-and-forget; a
    // failure just means we'll retry on next launch.
    if (mounted) context.read<AuthProvider>().markOnboardedLocally();
    // Best-effort by design: a 4xx/5xx here just means we'll retry on next
    // launch when AuthProvider re-fetches `User.onboardedAt`. Catch any
    // exception so an unawaited Future doesn't propagate.
    unawaited(
      OnboardingApi.instance.markOnboarded().catchError((_) {}),
    );
    if (!mounted) return;
    context.go('/buyer');
  }

  void _next() {
    if (_index == _slides.length - 1) {
      _finish();
      return;
    }
    _pager.nextPage(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _index == _slides.length - 1;
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            // Skip
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 12, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _finishing ? null : _finish,
                    child: Text(t(context, 'onboarding.skip')),
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pager,
                itemCount: _slides.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (_, i) => _SlideView(slide: _slides[i]),
              ),
            ),
            // Dot indicator
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < _slides.length; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 240),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: i == _index ? 22 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: i == _index
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _finishing ? null : _next,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Text(
                      isLast
                          ? t(context, 'onboarding.continue')
                          : t(context, 'onboarding.next'),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Slide {
  final String emoji;
  final String titleKey;
  final String bodyKey;
  final Color accent;
  const _Slide({
    required this.emoji,
    required this.titleKey,
    required this.bodyKey,
    required this.accent,
  });
}

class _SlideView extends StatelessWidget {
  final _Slide slide;
  const _SlideView({required this.slide});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 168,
            height: 168,
            decoration: BoxDecoration(
              color: slide.accent.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(slide.emoji, style: const TextStyle(fontSize: 84)),
          ),
          const SizedBox(height: 36),
          Text(
            t(context, slide.titleKey),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.4,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            t(context, slide.bodyKey),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              height: 1.45,
              color: scheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}
