import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../l10n/l10n.dart';
import '../services/analytics_service.dart';
import '../services/banner_api.dart';
import '../theme/app_theme.dart';

/// Phase 7.3 — horizontal carousel of `HomeBanner` cards.
///
/// Auto-advances every 5 seconds when there are 2+ banners. Tapping a card
/// records a click on the backend and follows `deepLink` via GoRouter when
/// it's an in-app path (starts with `/`); external links fall through to a
/// no-op (extending later with url_launcher is straightforward).
class BannerCarousel extends StatefulWidget {
  final String? vertical;
  final String? country;
  final double aspectRatio;

  const BannerCarousel({
    super.key,
    this.vertical,
    this.country,
    this.aspectRatio = 16 / 9,
  });

  @override
  State<BannerCarousel> createState() => _BannerCarouselState();
}

class _BannerCarouselState extends State<BannerCarousel> {
  final _ctrl = PageController(viewportFraction: 0.92);
  Timer? _autoAdvance;
  List<HomeBanner> _banners = const [];
  bool _loading = true;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void didUpdateWidget(BannerCarousel old) {
    super.didUpdateWidget(old);
    if (old.vertical != widget.vertical || old.country != widget.country) {
      _load();
    }
  }

  @override
  void dispose() {
    _autoAdvance?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await BannerApi.instance.list(
        vertical: widget.vertical,
        country: widget.country,
      );
      if (!mounted) return;
      setState(() {
        _banners = list;
        _loading = false;
      });
      _scheduleAutoAdvance();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _banners = const [];
        _loading = false;
      });
    }
  }

  void _scheduleAutoAdvance() {
    _autoAdvance?.cancel();
    if (_banners.length < 2) return;
    _autoAdvance = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || !_ctrl.hasClients) return;
      final next = (_index + 1) % _banners.length;
      _ctrl.animateToPage(
        next,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOut,
      );
    });
  }

  void _onTap(HomeBanner b) {
    BannerApi.instance.click(b.id);
    AnalyticsService.instance.logEvent('banner_click', {
      'bannerId': b.id,
      if (b.vertical != null) 'vertical': b.vertical!,
    });
    final link = b.deepLink;
    if (link == null || link.isEmpty) return;
    if (link.startsWith('/')) {
      try {
        GoRouter.of(context).go(link);
      } catch (_) {/* unknown route — silent */}
    }
    // External `https://…` links would route through url_launcher; we
    // intentionally drop them here so the carousel never crashes.
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return AspectRatio(
        aspectRatio: widget.aspectRatio,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: AppColors.surfaceMuted,
            borderRadius: BorderRadius.circular(AppRadii.lg),
          ),
        ),
      );
    }
    if (_banners.isEmpty) return const SizedBox.shrink();
    final locale = L10n.instance.locale.languageCode;
    return Column(
      children: [
        AspectRatio(
          aspectRatio: widget.aspectRatio,
          child: PageView.builder(
            controller: _ctrl,
            itemCount: _banners.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (_, i) {
              final b = _banners[i];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: _BannerCard(
                  banner: b,
                  title: b.titleFor(locale),
                  onTap: () => _onTap(b),
                ),
              );
            },
          ),
        ),
        if (_banners.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_banners.length, (i) {
                final selected = i == _index;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: selected ? 18 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: selected ? AppColors.primary : AppColors.border,
                    borderRadius: BorderRadius.circular(3),
                  ),
                );
              }),
            ),
          ),
      ],
    );
  }
}

class _BannerCard extends StatelessWidget {
  final HomeBanner banner;
  final String title;
  final VoidCallback onTap;
  const _BannerCard({
    required this.banner,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadii.lg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(color: AppColors.surfaceMuted),
            if (banner.imageUrl.isNotEmpty)
              CachedNetworkImage(
                imageUrl: banner.imageUrl,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) =>
                    Container(color: AppColors.surfaceMuted),
              ),
            // Bottom-up gradient + title overlay.
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.center,
                    colors: [
                      Colors.black.withValues(alpha: 0.55),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            if (title.isNotEmpty)
              Positioned(
                left: 16,
                right: 16,
                bottom: 14,
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                    shadows: [Shadow(blurRadius: 6, color: Colors.black54)],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
