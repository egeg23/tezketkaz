// Phase 13.3.4 — reusable loading skeleton.
//
// A Wolt-style shimmer placeholder used while list data is loading.
// Renders N gray rounded rectangles laid out vertically. Used across the
// buyer, courier and shop screens so the loading shape matches the real
// content shape (avoids layout shift when items arrive).
//
// Usage:
//   if (provider.loading && provider.items.isEmpty) return const LoadingShimmer();
//
// For non-card lists (e.g. orders timeline rows) pass a custom `itemHeight`.

import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

class LoadingShimmer extends StatelessWidget {
  /// How many skeleton rows to render. Defaults to 6 — usually enough to
  /// fill one screen on a mid-range Android.
  final int itemCount;

  /// Per-row height. Match the height of the real card rendered by the
  /// screen (96 for buyer shops/products, 120 for orders, etc.).
  final double itemHeight;

  /// Horizontal padding around each row.
  final double horizontalPadding;

  /// Vertical gap between rows.
  final double verticalSpacing;

  /// Corner radius of the placeholder.
  final double borderRadius;

  const LoadingShimmer({
    super.key,
    this.itemCount = 6,
    this.itemHeight = 96,
    this.horizontalPadding = 16,
    this.verticalSpacing = 8,
    this.borderRadius = 12,
  });

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade300,
      highlightColor: Colors.grey.shade100,
      child: ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        itemCount: itemCount,
        padding: EdgeInsets.symmetric(vertical: verticalSpacing),
        itemBuilder: (_, __) => Container(
          margin: EdgeInsets.symmetric(
            horizontal: horizontalPadding,
            vertical: verticalSpacing,
          ),
          height: itemHeight,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(borderRadius),
          ),
        ),
      ),
    );
  }
}

/// Grid variant — for catalog / product screens that render in a 2-column
/// staggered grid. Same shimmer palette and corner radius as
/// [LoadingShimmer].
class LoadingShimmerGrid extends StatelessWidget {
  final int itemCount;
  final double aspectRatio;
  final int crossAxisCount;
  final EdgeInsetsGeometry padding;

  const LoadingShimmerGrid({
    super.key,
    this.itemCount = 6,
    this.aspectRatio = 0.78,
    this.crossAxisCount = 2,
    this.padding = const EdgeInsets.all(12),
  });

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade300,
      highlightColor: Colors.grey.shade100,
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: padding,
        itemCount: itemCount,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: aspectRatio,
        ),
        itemBuilder: (_, __) => Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }
}
