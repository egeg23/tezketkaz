import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../l10n/l10n.dart';
import '../models/money.dart';
import '../providers/cart_provider.dart';
import '../services/cart_draft_api.dart';
import '../theme/app_theme.dart';

/// Phase 11 — horizontal chip rail surfaced above the cart items list.
///
/// One chip per persisted draft. Active chip is filled with the brand colour;
/// inactive chips show a faint outline. Each chip carries an item-count badge
/// and a localised subtotal.
class CartShopSwitcher extends StatelessWidget {
  const CartShopSwitcher({super.key});

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();
    final drafts = cart.drafts;
    if (drafts.length < 2) return const SizedBox.shrink();

    final activeId = cart.activeShopId;

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
            child: Text(
              t(context, 'cart.switcher_label'),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
                letterSpacing: 0.4,
              ),
            ),
          ),
          SizedBox(
            height: 64,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: drafts.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, i) {
                final d = drafts[i];
                final isActive = d.shopId == activeId;
                return _ShopChip(
                  draft: d,
                  active: isActive,
                  onTap: () {
                    HapticFeedback.lightImpact();
                    cart.switchShop(d.shopId);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ShopChip extends StatelessWidget {
  final CartDraftSummary draft;
  final bool active;
  final VoidCallback onTap;
  const _ShopChip({
    required this.draft,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fg = active ? scheme.onPrimary : scheme.onSurface;
    final bg = active ? scheme.primary : scheme.surface;
    final border = active ? scheme.primary : theme.dividerColor;
    final locale = L10n.instance.locale.languageCode;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(AppRadii.lg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.lg),
            border: Border.all(color: border, width: active ? 0 : 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Logo(url: draft.shopLogoUrl, active: active),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 130),
                        child: Text(
                          draft.shopName.isEmpty ? '—' : draft.shopName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: fg,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: active
                              ? Colors.white.withValues(alpha: 0.22)
                              : scheme.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(AppRadii.pill),
                        ),
                        child: Text(
                          '${draft.itemCount}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: active ? Colors.white : scheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    Money(draft.subtotal, draft.shopCurrency).format(locale),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: active
                          ? Colors.white.withValues(alpha: 0.85)
                          : scheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  final String? url;
  final bool active;
  const _Logo({required this.url, required this.active});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.sm),
      child: SizedBox(
        width: 36,
        height: 36,
        child: url != null && url!.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: url!,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => _LogoFallback(active: active),
              )
            : _LogoFallback(active: active),
      ),
    );
  }
}

class _LogoFallback extends StatelessWidget {
  final bool active;
  const _LogoFallback({required this.active});
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: active
          ? Colors.white.withValues(alpha: 0.18)
          : scheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(
        Icons.storefront_rounded,
        size: 20,
        color: active ? Colors.white : scheme.onSurface.withValues(alpha: 0.5),
      ),
    );
  }
}
