import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../services/api_client.dart';
import '../../theme/app_theme.dart';
import '../../widgets/map_tile_layer.dart';

/// Address picker — master.html .addr-pick (lines 7093-7188).
///
/// Layout matches the mockup:
///   • Yandex dark tiles fill the screen
///   • A glass back chip + search field overlay sits at the top
///     • Typing fires /api/geocode/suggest with debounce; dropdown shows
///       up to 5 ranked hits — tap to fly the map there
///   • Fixed center pin in the middle of the map
///     • Panning the map fires /api/geocode/reverse to refresh the text
///   • Bottom glass card shows the current address + lime "Confirm" CTA
///
/// Returns `{lat, lng, address}` via Navigator.pop.
class AddressPickerScreen extends StatefulWidget {
  final LatLng? initial;
  const AddressPickerScreen({super.key, this.initial});

  @override
  State<AddressPickerScreen> createState() => _AddressPickerScreenState();
}

class _AddressPickerScreenState extends State<AddressPickerScreen> {
  static const _tashkentCenter = LatLng(41.3617, 69.2877);

  late final MapController _mapCtl = MapController();
  late LatLng _center = widget.initial ?? _tashkentCenter;

  final _searchCtl = TextEditingController();
  final _searchFocus = FocusNode();

  String _addressText = '...';
  bool _loadingAddress = false;
  List<_Suggestion> _suggestions = [];
  bool _searching = false;
  Timer? _moveDebounce;
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reverse(_center));
  }

  @override
  void dispose() {
    _moveDebounce?.cancel();
    _searchDebounce?.cancel();
    _searchCtl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  // ─── Map → reverse geocode ────────────────────────────────────────────────
  void _onMapMoved(MapCamera cam) {
    _center = cam.center;
    _moveDebounce?.cancel();
    _moveDebounce = Timer(const Duration(milliseconds: 500), () => _reverse(_center));
  }

  Future<void> _reverse(LatLng p) async {
    setState(() => _loadingAddress = true);
    try {
      final r = await ApiClient.instance.get(
        '/api/geocode/reverse',
        query: {
          'lat': p.latitude.toStringAsFixed(6),
          'lng': p.longitude.toStringAsFixed(6),
        },
      );
      final res = r.data['result'] as Map<String, dynamic>?;
      if (!mounted) return;
      setState(() {
        _addressText = (res?['full'] as String?) ??
            '${p.latitude.toStringAsFixed(5)}, ${p.longitude.toStringAsFixed(5)}';
        _loadingAddress = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _addressText =
            '${p.latitude.toStringAsFixed(5)}, ${p.longitude.toStringAsFixed(5)}';
        _loadingAddress = false;
      });
    }
  }

  // ─── Search box → suggestions ─────────────────────────────────────────────
  void _onSearchChanged(String q) {
    _searchDebounce?.cancel();
    final trimmed = q.trim();
    if (trimmed.length < 2) {
      setState(() => _suggestions = []);
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 350), () async {
      setState(() => _searching = true);
      try {
        final r = await ApiClient.instance.get(
          '/api/geocode/suggest',
          query: {
            'q': trimmed,
            'lat': _center.latitude.toStringAsFixed(4),
            'lng': _center.longitude.toStringAsFixed(4),
          },
        );
        final list =
            (r.data['suggestions'] as List?)?.cast<Map>() ?? const [];
        if (!mounted) return;
        setState(() {
          _suggestions = list
              .map((m) => _Suggestion.fromJson(m.cast<String, dynamic>()))
              .where((s) => s.lat != null && s.lng != null)
              .toList();
          _searching = false;
        });
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _suggestions = [];
          _searching = false;
        });
      }
    });
  }

  void _pickSuggestion(_Suggestion s) {
    HapticFeedback.lightImpact();
    final p = LatLng(s.lat!, s.lng!);
    _mapCtl.move(p, 17);
    _center = p;
    _searchCtl.text = s.full;
    _searchFocus.unfocus();
    setState(() {
      _suggestions = [];
      _addressText = s.full;
    });
  }

  void _confirm() {
    HapticFeedback.mediumImpact();
    Navigator.of(context).pop({
      'lat': _center.latitude,
      'lng': _center.longitude,
      'address': _addressText,
    });
  }

  // ─── Build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          // 1. Map fills the screen
          FlutterMap(
            mapController: _mapCtl,
            options: MapOptions(
              initialCenter: _center,
              initialZoom: 16,
              onMapEvent: (event) {
                if (event.source == MapEventSource.mapController) return;
                _onMapMoved(event.camera);
              },
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
            ),
            children: [tezketkazTiles()],
          ),

          // 2. Center pin
          const Center(child: IgnorePointer(child: _CenterPin())),

          // 3. Top overlay — back chip + search field + suggestions
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Column(
                children: [
                  Row(
                    children: [
                      _GlassChip(
                        icon: Icons.chevron_left_rounded,
                        onTap: () => Navigator.of(context).maybePop(),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Container(
                          height: 46,
                          padding:
                              const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xCC0F0F16),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.search_rounded,
                                  size: 18,
                                  color: AppColors.textSecondary),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  controller: _searchCtl,
                                  focusNode: _searchFocus,
                                  onChanged: _onSearchChanged,
                                  textInputAction: TextInputAction.search,
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 14),
                                  decoration: InputDecoration(
                                    hintText:
                                        'Поиск адреса в Ташкенте',
                                    hintStyle: TextStyle(
                                        color: AppColors.textHint,
                                        fontSize: 14),
                                    border: InputBorder.none,
                                    enabledBorder: InputBorder.none,
                                    focusedBorder: InputBorder.none,
                                    isDense: true,
                                  ),
                                ),
                              ),
                              if (_searching)
                                const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2),
                                )
                              else if (_searchCtl.text.isNotEmpty)
                                GestureDetector(
                                  onTap: () {
                                    _searchCtl.clear();
                                    setState(() => _suggestions = []);
                                  },
                                  child: Icon(Icons.close_rounded,
                                      size: 18,
                                      color: AppColors.textSecondary),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_suggestions.isNotEmpty)
                    _SuggestionDropdown(
                      suggestions: _suggestions,
                      onPick: _pickSuggestion,
                    ),
                ],
              ),
            ),
          ),

          // 4. Bottom card — address + confirm CTA
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: SafeArea(
              top: false,
              child: Container(
                padding:
                    const EdgeInsets.fromLTRB(16, 16, 16, 16),
                decoration: BoxDecoration(
                  color: const Color(0xF20F0F16),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppColors.border),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x66000000),
                      blurRadius: 28,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(Icons.location_on_rounded,
                              color: AppColors.primary, size: 18),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'ВЫБРАННЫЙ АДРЕС',
                                style: TextStyle(
                                  fontSize: 10,
                                  letterSpacing: 1.2,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _addressText,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                  height: 1.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_loadingAddress)
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _confirm,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: AppColors.bg,
                          padding:
                              const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(100),
                          ),
                          elevation: 0,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Text(
                              'Выбрать этот адрес',
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700),
                            ),
                            SizedBox(width: 8),
                            Icon(Icons.arrow_forward_rounded, size: 18),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Helpers ────────────────────────────────────────────────────────────────

class _Suggestion {
  final String name;
  final String full;
  final double? lat;
  final double? lng;
  final String? kind;
  _Suggestion({
    required this.name,
    required this.full,
    required this.lat,
    required this.lng,
    this.kind,
  });

  factory _Suggestion.fromJson(Map<String, dynamic> m) => _Suggestion(
        name: (m['name'] as String?) ?? '',
        full: (m['full'] as String?) ?? '',
        lat: (m['lat'] as num?)?.toDouble(),
        lng: (m['lng'] as num?)?.toDouble(),
        kind: m['kind'] as String?,
      );
}

class _SuggestionDropdown extends StatelessWidget {
  final List<_Suggestion> suggestions;
  final ValueChanged<_Suggestion> onPick;
  const _SuggestionDropdown({
    required this.suggestions,
    required this.onPick,
  });

  IconData _iconFor(String? kind) {
    switch (kind) {
      case 'house':
        return Icons.home_rounded;
      case 'street':
        return Icons.alt_route_rounded;
      case 'locality':
        return Icons.location_city_rounded;
      case 'metro':
        return Icons.directions_subway_rounded;
      default:
        return Icons.place_outlined;
    }
  }

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(top: 8),
        decoration: BoxDecoration(
          color: const Color(0xF20F0F16),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
          boxShadow: const [
            BoxShadow(
                color: Color(0x66000000),
                blurRadius: 20,
                offset: Offset(0, 6)),
          ],
        ),
        child: Column(
          children: [
            for (var i = 0; i < suggestions.length; i++)
              InkWell(
                onTap: () => onPick(suggestions[i]),
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    border: i == suggestions.length - 1
                        ? null
                        : Border(
                            bottom: BorderSide(
                                color:
                                    AppColors.border.withValues(alpha: 0.5)),
                          ),
                  ),
                  child: Row(
                    children: [
                      Icon(_iconFor(suggestions[i].kind),
                          size: 16, color: AppColors.textSecondary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              suggestions[i].name,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (suggestions[i].full != suggestions[i].name)
                              Text(
                                suggestions[i].full,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textHint,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );
}

class _GlassChip extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _GlassChip({required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: const Color(0xCC0F0F16),
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.border),
          ),
          child: Icon(icon, size: 18, color: Colors.white),
        ),
      );
}

class _CenterPin extends StatelessWidget {
  const _CenterPin();
  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.50),
                  blurRadius: 18,
                  spreadRadius: 2,
                ),
              ],
            ),
            alignment: Alignment.center,
            child: Icon(Icons.home_rounded, color: AppColors.bg, size: 22),
          ),
          const SizedBox(height: 2),
          Container(width: 3, height: 20, color: AppColors.bg),
        ],
      );
}
