import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../l10n/l10n.dart';
import '../theme/app_theme.dart';

/// Reusable debounced search bar with recent-searches chips.
class AppSearchBar extends StatefulWidget {
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final String? hint;
  final TextEditingController? controller;
  final Duration debounce;

  const AppSearchBar({
    super.key,
    this.onChanged,
    this.onSubmitted,
    this.hint,
    this.controller,
    this.debounce = const Duration(milliseconds: 300),
  });

  @override
  State<AppSearchBar> createState() => _AppSearchBarState();
}

class _AppSearchBarState extends State<AppSearchBar> {
  static const _kStoreKey = 'search.history';
  static const _kMaxRecent = 10;

  late final TextEditingController _ctrl;
  final _focus = FocusNode();
  Timer? _debounce;
  List<String> _history = const [];
  bool _ownsController = false;

  @override
  void initState() {
    super.initState();
    _ctrl = widget.controller ?? TextEditingController();
    _ownsController = widget.controller == null;
    _focus.addListener(() {
      if (mounted) setState(() {});
    });
    _ctrl.addListener(() {
      if (mounted) setState(() {});
    });
    _loadHistory();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    if (_ownsController) _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_kStoreKey) ?? const [];
      if (mounted) setState(() => _history = list);
    } catch (_) {/* ignore */}
  }

  Future<void> _persistHistory(String value) async {
    final v = value.trim();
    if (v.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final current = List<String>.from(prefs.getStringList(_kStoreKey) ?? const []);
      current.removeWhere((e) => e.toLowerCase() == v.toLowerCase());
      current.insert(0, v);
      while (current.length > _kMaxRecent) {
        current.removeLast();
      }
      await prefs.setStringList(_kStoreKey, current);
      if (mounted) setState(() => _history = current);
    } catch (_) {/* ignore */}
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(widget.debounce, () {
      widget.onChanged?.call(value);
    });
  }

  void _onSubmitted(String value) {
    final v = value.trim();
    if (v.isNotEmpty) _persistHistory(v);
    widget.onSubmitted?.call(v);
  }

  void _pickRecent(String value) {
    _ctrl.text = value;
    _ctrl.selection = TextSelection.collapsed(offset: value.length);
    _onSubmitted(value);
    _focus.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final showRecents =
        _focus.hasFocus && _ctrl.text.isEmpty && _history.isNotEmpty;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceMuted,
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
          child: TextField(
            controller: _ctrl,
            focusNode: _focus,
            textInputAction: TextInputAction.search,
            onChanged: _onChanged,
            onSubmitted: _onSubmitted,
            decoration: InputDecoration(
              hintText: widget.hint ?? t(context, 'buyer.search_placeholder'),
              prefixIcon: const Icon(Icons.search_rounded,
                  size: 20, color: AppColors.textHint),
              suffixIcon: _ctrl.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded,
                          size: 18, color: AppColors.textHint),
                      onPressed: () {
                        _ctrl.clear();
                        widget.onChanged?.call('');
                      },
                    ),
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
        if (showRecents) ...[
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Text(
              t(context, 'recent_searches'),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
                letterSpacing: 0.4,
              ),
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _history
                .map((q) => InputChip(
                      label: Text(q),
                      avatar: const Icon(Icons.history_rounded, size: 16),
                      onPressed: () => _pickRecent(q),
                      backgroundColor: AppColors.surface,
                      side: const BorderSide(color: AppColors.border),
                    ))
                .toList(),
          ),
        ],
      ],
    );
  }
}
