import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../l10n/l10n.dart';
import '../../models/review.dart';
import '../../services/api_client.dart';
import '../../services/review_api.dart';
import '../../theme/app_theme.dart';

/// Public list of reviews for a target (shop / product / courier).
///
/// Use the named route `/reviews/:targetType/:targetId` or instantiate
/// directly. Tabs let the buyer filter by rating.
class ReviewsScreen extends StatefulWidget {
  final String targetType;
  final String targetId;
  final String? title;

  const ReviewsScreen({
    super.key,
    required this.targetType,
    required this.targetId,
    this.title,
  });

  @override
  State<ReviewsScreen> createState() => _ReviewsScreenState();
}

class _ReviewsScreenState extends State<ReviewsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  int _filter = 0; // 0 = all, 5..3
  bool _loading = true;
  String? _error;
  List<Review> _all = const [];

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 4, vsync: this);
    _tab.addListener(() {
      setState(() => _filter = _filterFromIndex(_tab.index));
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  int _filterFromIndex(int i) {
    switch (i) {
      case 1:
        return 5;
      case 2:
        return 4;
      case 3:
        return 3;
      default:
        return 0;
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ReviewApi.instance.list(
        targetType: widget.targetType,
        targetId: widget.targetId,
        limit: 50,
      );
      if (!mounted) return;
      setState(() {
        _all = res;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  List<Review> get _filtered {
    if (_filter == 0) return _all;
    if (_filter == 3) return _all.where((r) => r.rating <= 3).toList();
    return _all.where((r) => r.rating == _filter).toList();
  }

  double get _avg {
    if (_all.isEmpty) return 0;
    return _all.fold<int>(0, (s, r) => s + r.rating) / _all.length;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Text(widget.title ?? t(context, 'reviews.title')),
        bottom: TabBar(
          controller: _tab,
          isScrollable: true,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textSecondary,
          indicatorColor: AppColors.primary,
          tabs: [
            Tab(text: t(context, 'reviews.tab_all')),
            const Tab(text: '5★'),
            const Tab(text: '4★'),
            const Tab(text: '3★ ↓'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!,
                            style:
                                const TextStyle(color: AppColors.error)),
                        const SizedBox(height: 8),
                        OutlinedButton(
                            onPressed: _load,
                            child: Text(t(context, 'common.retry'))),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                    children: [
                      _Header(avg: _avg, count: _all.length),
                      const SizedBox(height: 12),
                      if (_filtered.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 48),
                          child: Center(
                            child: Text(
                              t(context, 'reviews.empty'),
                              style: const TextStyle(
                                  color: AppColors.textSecondary),
                            ),
                          ),
                        )
                      else
                        for (final r in _filtered) ...[
                          _ReviewItem(review: r),
                          const SizedBox(height: 10),
                        ],
                    ],
                  ),
                ),
    );
  }
}

class _Header extends StatelessWidget {
  final double avg;
  final int count;
  const _Header({required this.avg, required this.count});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        boxShadow: AppShadows.card,
      ),
      child: Row(
        children: [
          Text(avg.toStringAsFixed(1),
              style: const TextStyle(
                fontSize: 36, fontWeight: FontWeight.w900,
              )),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: List.generate(5, (i) {
                  final filled = i < avg.round();
                  return Icon(
                    filled
                        ? Icons.star_rounded
                        : Icons.star_border_rounded,
                    size: 18,
                    color: AppColors.warning,
                  );
                }),
              ),
              const SizedBox(height: 4),
              Text('$count ${t(context, 'reviews.count_suffix')}',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 13)),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReviewItem extends StatelessWidget {
  final Review review;
  const _ReviewItem({required this.review});

  String _fmtDate(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '$dd.$mm.${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: AppColors.primaryLight,
                backgroundImage: review.authorAvatar != null
                    ? CachedNetworkImageProvider(review.authorAvatar!)
                    : null,
                child: review.authorAvatar == null
                    ? Text(
                        (review.authorName?.isNotEmpty == true
                                ? review.authorName![0]
                                : '?')
                            .toUpperCase(),
                        style: const TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700))
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(review.authorName ?? 'Foydalanuvchi',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 14)),
                    Text(_fmtDate(review.createdAt),
                        style: const TextStyle(
                            color: AppColors.textHint, fontSize: 11)),
                  ],
                ),
              ),
              Row(
                children: List.generate(5, (i) {
                  final filled = i < review.rating;
                  return Icon(
                    filled
                        ? Icons.star_rounded
                        : Icons.star_border_rounded,
                    size: 14,
                    color: AppColors.warning,
                  );
                }),
              ),
            ],
          ),
          if (review.text != null && review.text!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(review.text!,
                style: const TextStyle(fontSize: 14, height: 1.4)),
          ],
          if (review.photos.isNotEmpty) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 72,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: review.photos.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (_, i) => ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadii.sm),
                  child: SizedBox(
                    width: 72, height: 72,
                    child: CachedNetworkImage(
                      imageUrl: review.photos[i],
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => Container(
                        color: AppColors.surfaceMuted,
                        child: const Icon(Icons.image_outlined,
                            color: AppColors.textHint),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
