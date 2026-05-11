import 'package:flutter/material.dart';
import '../../l10n/l10n.dart';
import '../../services/legal_api.dart';
import '../../theme/app_theme.dart';

/// Phase 12 — read-only viewer for Privacy Policy + Terms of Service.
///
/// Loads both docs from the backend (`GET /api/legal/all?locale=<locale>`) for
/// the user's current locale. Renders the markdown via simple `Text` widgets
/// so we don't have to bundle `flutter_markdown` until the design team wants
/// rich formatting; the heading detection logic is good enough for the kind
/// of plain-prose policy text we ship.
class LegalScreen extends StatefulWidget {
  const LegalScreen({super.key});

  @override
  State<LegalScreen> createState() => _LegalScreenState();
}

class _LegalScreenState extends State<LegalScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  LegalDoc? _privacy;
  LegalDoc? _terms;
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final locale = L10n.instance.locale.languageCode;
      final docs = await LegalApi.instance.all(locale);
      if (!mounted) return;
      setState(() {
        _privacy = docs.privacy;
        _terms = docs.terms;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(t(context, 'profile.legal_tile')),
        bottom: TabBar(
          controller: _tabs,
          tabs: [
            Tab(text: t(context, 'legal.privacy_tab')),
            Tab(text: t(context, 'legal.terms_tab')),
          ],
        ),
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: AppColors.primary),
            const SizedBox(height: 12),
            Text(t(context, 'legal.loading'),
                style: const TextStyle(color: AppColors.textSecondary)),
          ],
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: AppColors.error, size: 48),
              const SizedBox(height: 12),
              Text(t(context, 'legal.error'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: Text(t(context, 'common.retry')),
              ),
            ],
          ),
        ),
      );
    }
    return TabBarView(
      controller: _tabs,
      children: [
        _DocView(doc: _privacy),
        _DocView(doc: _terms),
      ],
    );
  }
}

class _DocView extends StatelessWidget {
  final LegalDoc? doc;
  const _DocView({required this.doc});

  @override
  Widget build(BuildContext context) {
    final d = doc;
    if (d == null || d.content.isEmpty) {
      return Center(
        child: Text(t(context, 'legal.error'),
            style: const TextStyle(color: AppColors.textSecondary)),
      );
    }
    final blocks = _parseMarkdown(d.content);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        if (d.updatedAt != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              '${d.updatedAt!.toIso8601String().substring(0, 10)} · ${d.locale}',
              style: const TextStyle(
                  color: AppColors.textHint, fontSize: 12),
            ),
          ),
        ...blocks,
      ],
    );
  }

  /// Minimal markdown renderer — handles `#`, `##`, `###` headings and treats
  /// every other paragraph as plain text. Good enough for prose policies; if
  /// we ever ship lists or tables, swap in `flutter_markdown`.
  List<Widget> _parseMarkdown(String src) {
    final lines = src.replaceAll('\r\n', '\n').split('\n');
    final widgets = <Widget>[];
    final buf = StringBuffer();

    void flushParagraph() {
      final text = buf.toString().trim();
      buf.clear();
      if (text.isEmpty) return;
      widgets.add(Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(text,
            style: const TextStyle(
                fontSize: 14, height: 1.5, color: AppColors.textPrimary)),
      ));
    }

    for (final raw in lines) {
      final line = raw.trimRight();
      if (line.isEmpty) {
        flushParagraph();
        continue;
      }
      if (line.startsWith('### ')) {
        flushParagraph();
        widgets.add(Padding(
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
          child: Text(line.substring(4),
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w700)),
        ));
      } else if (line.startsWith('## ')) {
        flushParagraph();
        widgets.add(Padding(
          padding: const EdgeInsets.fromLTRB(0, 12, 0, 8),
          child: Text(line.substring(3),
              style: const TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w800)),
        ));
      } else if (line.startsWith('# ')) {
        flushParagraph();
        widgets.add(Padding(
          padding: const EdgeInsets.fromLTRB(0, 16, 0, 10),
          child: Text(line.substring(2),
              style: const TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w800)),
        ));
      } else {
        if (buf.isNotEmpty) buf.write(' ');
        buf.write(line);
      }
    }
    flushParagraph();
    return widgets;
  }
}
