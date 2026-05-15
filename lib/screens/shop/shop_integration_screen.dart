import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/api_client.dart';
import '../../theme/app_theme.dart';

/// SHOP → API & ИНТЕГРАЦИИ — Phase 14 wave 2.
///
/// Three sections:
///
///   1) Подключите свой POS — provider picker grid (iiko / Poster / Custom REST),
///      each card opens a sheet with provider-specific fields + "Test"
///   2) Активные интеграции — list of installed connectors with status pill,
///      sync-now button, syncMenu/Stock/Orders toggles, disconnect
///   3) Для разработчиков — the existing tz_live_* + webhook surface, kept
///      compact at the bottom for tech-savvy partners who build their own
///      client against our raw API
class ShopIntegrationScreen extends StatefulWidget {
  const ShopIntegrationScreen({super.key});
  @override
  State<ShopIntegrationScreen> createState() => _ShopIntegrationScreenState();
}

class _ShopIntegrationScreenState extends State<ShopIntegrationScreen> {
  bool _loading = true;
  String? _error;

  Map<String, dynamic>? _info;
  List<Map<String, dynamic>> _providers = [];
  List<Map<String, dynamic>> _integrations = [];
  List<dynamic> _events = [];

  // One-time-secret reveal banners
  String? _justMintedApiKey;
  String? _justMintedWebhookSecret;

  final _webhookCtl = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _webhookCtl.dispose();
    super.dispose();
  }

  // ─── Loading ──────────────────────────────────────────────────────────────
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        ApiClient.instance.get('/api/shops/me/integration'),
        ApiClient.instance.get('/api/shops/me/integrations/providers'),
        ApiClient.instance.get('/api/shops/me/integrations'),
        ApiClient.instance.get('/api/shops/me/integration/log',
            query: {'limit': 25}),
      ]);
      if (!mounted) return;
      setState(() {
        _info = Map<String, dynamic>.from(results[0].data);
        _providers = List<Map<String, dynamic>>.from(
            (results[1].data['providers'] as List).cast<Map>());
        _integrations = List<Map<String, dynamic>>.from(
            (results[2].data['integrations'] as List).cast<Map>());
        _events = (results[3].data['events'] as List?) ?? [];
        _webhookCtl.text = _info?['webhookUrl'] ?? '';
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

  // ─── Actions: dev API ─────────────────────────────────────────────────────
  Future<void> _rotateApiKey() async {
    if (!await _confirm('Перевыпустить API-ключ?',
        'Старый ключ сразу перестанет работать. Убедитесь, что у вас есть доступ обновить '
        'его в вашей POS-системе.')) return;
    try {
      final r = await ApiClient.instance
          .post('/api/shops/me/integration/api-key/rotate');
      setState(() => _justMintedApiKey = r.data['apiKey'] as String?);
      await _load();
    } catch (e) {
      _snack('Ошибка: $e');
    }
  }

  Future<void> _saveWebhook() async {
    final url = _webhookCtl.text.trim();
    if (url.isEmpty || (!url.startsWith('http://') && !url.startsWith('https://'))) {
      _snack('Нужен валидный URL, например https://shop.example.com/hooks/tz');
      return;
    }
    try {
      final r = await ApiClient.instance
          .post('/api/shops/me/integration/webhook', {'url': url});
      setState(() => _justMintedWebhookSecret = r.data['webhookSecret'] as String?);
      await _load();
    } catch (e) {
      _snack('Ошибка: $e');
    }
  }

  Future<void> _removeWebhook() async {
    if (!await _confirm('Удалить webhook?',
        'Мы перестанем отправлять события на ваш сервер.')) return;
    try {
      await ApiClient.instance
          .delete('/api/shops/me/integration/webhook');
      setState(() {
        _webhookCtl.clear();
        _justMintedWebhookSecret = null;
      });
      await _load();
    } catch (e) {
      _snack('Ошибка: $e');
    }
  }

  // ─── Actions: connector ──────────────────────────────────────────────────
  Future<void> _connectProvider(Map<String, dynamic> provider) async {
    final result = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ProviderConnectSheet(provider: provider),
    );
    if (result == null) return;
    try {
      final r = await ApiClient.instance.post(
        '/api/shops/me/integrations',
        {'provider': provider['id'], 'creds': result},
      );
      final test = (r.data['test'] as Map?) ?? {};
      _snack(test['ok'] == true
          ? '✅ Подключено: ${test['message']}'
          : '⚠ Подключено, но проверка не прошла: ${test['message']}');
      await _load();
    } catch (e) {
      _snack('Ошибка подключения: $e');
    }
  }

  Future<void> _testIntegration(String id) async {
    try {
      final r =
          await ApiClient.instance.post('/api/shops/me/integrations/$id/test');
      final t = (r.data['test'] as Map?) ?? {};
      _snack(t['ok'] == true
          ? '✅ ${t['message']}'
          : '⚠ ${t['message']}');
      await _load();
    } catch (e) {
      _snack('Ошибка: $e');
    }
  }

  Future<void> _syncNow(String id) async {
    try {
      final r = await ApiClient.instance
          .post('/api/shops/me/integrations/$id/sync-now');
      final res = (r.data['result'] as Map?) ?? {};
      _snack('🔄 Меню синхронизировано: ${res['message']}');
      await _load();
    } catch (e) {
      _snack('Ошибка: $e');
    }
  }

  Future<void> _toggleSync(String id, Map<String, dynamic> patch) async {
    try {
      await ApiClient.instance.patch('/api/shops/me/integrations/$id', patch);
      await _load();
    } catch (e) {
      _snack('Ошибка: $e');
    }
  }

  Future<void> _disconnect(String id, String label) async {
    if (!await _confirm('Отключить $label?',
        'Меню останется, но автоматическая синхронизация прекратится.')) return;
    try {
      await ApiClient.instance.delete('/api/shops/me/integrations/$id');
      await _load();
    } catch (e) {
      _snack('Ошибка: $e');
    }
  }

  Future<bool> _confirm(String title, String body) async =>
      (await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text(title, style: const TextStyle(color: Colors.white)),
          content:
              Text(body, style: TextStyle(color: AppColors.textSecondary)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Отмена')),
            TextButton(
                onPressed: () => Navigator.pop(context, true),
                style:
                    TextButton.styleFrom(foregroundColor: AppColors.warning),
                child: const Text('Подтвердить')),
          ],
        ),
      )) ??
      false;

  void _snack(String s) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(s)));
  }

  Future<void> _copy(String s, String label) async {
    await Clipboard.setData(ClipboardData(text: s));
    if (mounted) _snack('Скопировано · $label');
  }

  // ─── Build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0A0A10), Color(0xFF050507)],
          ),
        ),
        child: SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(_error!,
                            style: TextStyle(color: AppColors.error)),
                      ),
                    )
                  : Column(
                      children: [
                        _Header(onBack: () => Navigator.of(context).maybePop()),
                        Expanded(
                          child: ListView(
                            padding:
                                const EdgeInsets.fromLTRB(20, 8, 20, 32),
                            children: [
                              _Title(),
                              const SizedBox(height: 20),
                              _SectionLabel('Подключите свою POS-систему'),
                              const SizedBox(height: 12),
                              _ProviderGrid(
                                providers: _providers,
                                installed: _integrations
                                    .map((i) => i['provider'] as String)
                                    .toSet(),
                                onTap: _connectProvider,
                              ),
                              if (_integrations.isNotEmpty) ...[
                                const SizedBox(height: 24),
                                _SectionLabel(
                                    'Активные интеграции (${_integrations.length})'),
                                const SizedBox(height: 12),
                                for (final ig in _integrations)
                                  _IntegrationCard(
                                    integration: ig,
                                    onTest: () =>
                                        _testIntegration(ig['id']),
                                    onSync: () => _syncNow(ig['id']),
                                    onToggle: (patch) =>
                                        _toggleSync(ig['id'], patch),
                                    onDisconnect: () => _disconnect(
                                        ig['id'],
                                        ig['providerLabel'] ?? ig['provider']),
                                  ),
                              ],
                              const SizedBox(height: 24),
                              _SectionLabel('Для разработчиков'),
                              const SizedBox(height: 8),
                              Text(
                                'Если у вас есть свой backend — генерите ключ и '
                                'дёргайте наш API напрямую.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                  height: 1.4,
                                ),
                              ),
                              const SizedBox(height: 12),
                              _DevApiSection(
                                info: _info,
                                justMintedKey: _justMintedApiKey,
                                onRotate: _rotateApiKey,
                                onCopyMinted: () =>
                                    _copy(_justMintedApiKey!, 'API key'),
                                onDismissMinted: () => setState(
                                    () => _justMintedApiKey = null),
                              ),
                              const SizedBox(height: 12),
                              _WebhookSection(
                                controller: _webhookCtl,
                                info: _info,
                                justMintedSecret:
                                    _justMintedWebhookSecret,
                                onSave: _saveWebhook,
                                onDelete: _removeWebhook,
                                onCopyMinted: () => _copy(
                                    _justMintedWebhookSecret!,
                                    'webhook secret'),
                                onDismissMinted: () => setState(
                                    () => _justMintedWebhookSecret = null),
                              ),
                              const SizedBox(height: 12),
                              _CurlExamples(
                                  apiBase: _info?['apiBase'] as String? ?? ''),
                              const SizedBox(height: 24),
                              _SectionLabel('Журнал событий'),
                              const SizedBox(height: 8),
                              _SyncLog(
                                  events: _events,
                                  lastSyncAt:
                                      _info?['lastSyncAt'] as String?),
                            ],
                          ),
                        ),
                      ],
                    ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Header + title
// ═══════════════════════════════════════════════════════════════════════════
class _Header extends StatelessWidget {
  final VoidCallback onBack;
  const _Header({required this.onBack});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
        child: Row(
          children: [
            GestureDetector(
              onTap: onBack,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.surfaceMuted,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.border),
                ),
                child: Icon(Icons.chevron_left_rounded,
                    size: 18, color: AppColors.textSecondary),
              ),
            ),
            const Spacer(),
            const Text(
              'API и интеграции',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.white),
            ),
            const Spacer(),
            const SizedBox(width: 36),
          ],
        ),
      );
}

class _Title extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RichText(
              text: TextSpan(
                style: GoogleFonts.playfairDisplay(
                  fontSize: 28,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                  letterSpacing: -0.4,
                  height: 1.1,
                ),
                children: [
                  const TextSpan(text: 'Двусторонняя '),
                  TextSpan(
                    text: 'синхронизация',
                    style: GoogleFonts.playfairDisplay(
                      fontStyle: FontStyle.italic,
                      color: AppColors.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Подключите свою POS — мы тащим меню, шлём заказы. '
              'Или генерируйте API-ключ и пишите свой клиент.',
              style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  height: 1.5),
            ),
          ],
        ),
      );
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          letterSpacing: 1.5,
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary,
        ),
      );
}

// ═══════════════════════════════════════════════════════════════════════════
//  Provider grid (cards picker)
// ═══════════════════════════════════════════════════════════════════════════
class _ProviderGrid extends StatelessWidget {
  final List<Map<String, dynamic>> providers;
  final Set<String> installed;
  final ValueChanged<Map<String, dynamic>> onTap;
  const _ProviderGrid({
    required this.providers,
    required this.installed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Column(
        children: [
          for (final p in providers)
            _ProviderCard(
              provider: p,
              isInstalled: installed.contains(p['id']),
              onTap: () => onTap(p),
            ),
        ],
      );
}

class _ProviderCard extends StatelessWidget {
  final Map<String, dynamic> provider;
  final bool isInstalled;
  final VoidCallback onTap;
  const _ProviderCard({
    required this.provider,
    required this.isInstalled,
    required this.onTap,
  });

  static const _icons = {
    'iiko': Icons.restaurant_rounded,
    'poster': Icons.local_cafe_rounded,
    'custom_rest': Icons.code_rounded,
    'rkeeper': Icons.point_of_sale_rounded,
    'onec': Icons.dataset_rounded,
  };

  static const _colors = {
    'iiko': Color(0xFFE94B3C),       // iiko red-orange
    'poster': Color(0xFF38A1DB),     // poster blue
    'custom_rest': Color(0xFF06C167), // our lime
    'rkeeper': Color(0xFF7841FF),
    'onec': Color(0xFFFFC107),
  };

  @override
  Widget build(BuildContext context) {
    final providerId = provider['id'] as String;
    final color = _colors[providerId] ?? AppColors.primary;
    final icon = _icons[providerId] ?? Icons.cloud_outlined;
    final tier = provider['tier'] as String? ?? 'stable';
    final caps =
        ((provider['capabilities'] as List?) ?? []).cast<String>().join(', ');

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isInstalled
                ? AppColors.primary.withValues(alpha: 0.30)
                : AppColors.border,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(14),
                border:
                    Border.all(color: color.withValues(alpha: 0.30)),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        provider['label'] ?? providerId,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (tier == 'beta') _Pill('beta', AppColors.warning),
                      if (tier == 'scaffold')
                        _Pill('alpha', AppColors.textHint),
                      if (isInstalled) ...[
                        const SizedBox(width: 6),
                        _Pill('подключено', AppColors.primary),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    provider['summary'] ?? '',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                      height: 1.4,
                    ),
                  ),
                  if (caps.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Возможности: $caps',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textHint,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              isInstalled
                  ? Icons.settings_rounded
                  : Icons.arrow_forward_rounded,
              size: 16,
              color: AppColors.textHint,
            ),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final Color color;
  const _Pill(this.label, this.color);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(100),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
          ),
        ),
      );
}

// ═══════════════════════════════════════════════════════════════════════════
//  Connect sheet (provider-specific fields)
// ═══════════════════════════════════════════════════════════════════════════
class _ProviderConnectSheet extends StatefulWidget {
  final Map<String, dynamic> provider;
  const _ProviderConnectSheet({required this.provider});

  @override
  State<_ProviderConnectSheet> createState() => _ProviderConnectSheetState();
}

class _ProviderConnectSheetState extends State<_ProviderConnectSheet> {
  final Map<String, TextEditingController> _ctls = {};

  @override
  void initState() {
    super.initState();
    for (final f in (widget.provider['fields'] as List? ?? [])) {
      _ctls[f['id']] = TextEditingController();
    }
  }

  @override
  void dispose() {
    for (final c in _ctls.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    final result = <String, String>{};
    for (final entry in _ctls.entries) {
      result[entry.key] = entry.value.text.trim();
    }
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final fields = (widget.provider['fields'] as List? ?? []).cast<Map>();
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF0F0F16),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              RichText(
                text: TextSpan(
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 24,
                    fontWeight: FontWeight.w500,
                    color: Colors.white,
                  ),
                  children: [
                    const TextSpan(text: 'Подключить '),
                    TextSpan(
                      text: widget.provider['label'] ?? '',
                      style: GoogleFonts.playfairDisplay(
                        fontStyle: FontStyle.italic,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                widget.provider['summary'] ?? '',
                style: TextStyle(
                  fontSize: 12.5,
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
              ),
              if (widget.provider['docsUrl'] != null &&
                  (widget.provider['docsUrl'] as String).isNotEmpty &&
                  (widget.provider['docsUrl'] as String).startsWith('http')) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.menu_book_outlined,
                        size: 12, color: AppColors.primary),
                    const SizedBox(width: 4),
                    Text(
                      widget.provider['docsUrl'] as String,
                      style: TextStyle(
                        color: AppColors.primary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 20),
              for (final f in fields) ...[
                Text(
                  f['label'] ?? '',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _ctls[f['id']],
                  obscureText: f['secret'] == true,
                  style: GoogleFonts.jetBrainsMono(
                    color: Colors.white,
                    fontSize: 13,
                  ),
                  decoration: InputDecoration(
                    hintText: f['placeholder'] ?? '',
                    hintStyle: TextStyle(
                        color: AppColors.textHint,
                        fontFamily: 'JetBrainsMono'),
                    filled: true,
                    fillColor: AppColors.surfaceMuted,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: AppColors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: AppColors.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                          color: AppColors.primary, width: 1.5),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Отмена'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.bg,
                      ),
                      icon: const Icon(Icons.cable_rounded),
                      label: const Text('Подключить и проверить',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Installed integration card
// ═══════════════════════════════════════════════════════════════════════════
class _IntegrationCard extends StatelessWidget {
  final Map<String, dynamic> integration;
  final VoidCallback onTest;
  final VoidCallback onSync;
  final ValueChanged<Map<String, dynamic>> onToggle;
  final VoidCallback onDisconnect;
  const _IntegrationCard({
    required this.integration,
    required this.onTest,
    required this.onSync,
    required this.onToggle,
    required this.onDisconnect,
  });

  @override
  Widget build(BuildContext context) {
    final providerLabel =
        integration['providerLabel'] as String? ?? integration['provider'];
    final ok = integration['lastTestOk'] == true;
    final meta = integration['publicMeta'] as Map?;
    final metaLine = meta == null || meta.isEmpty
        ? ''
        : meta.entries
            .map((e) =>
                '${e.key}=${e.value.toString().length > 16 ? "${e.value.toString().substring(0, 16)}…" : e.value}')
            .join(' · ');

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ok
            ? AppColors.primary.withValues(alpha: 0.06)
            : AppColors.warning.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: ok
              ? AppColors.primary.withValues(alpha: 0.25)
              : AppColors.warning.withValues(alpha: 0.30),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: ok ? AppColors.primary : AppColors.warning,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: (ok
                              ? AppColors.primary
                              : AppColors.warning)
                          .withValues(alpha: 0.5),
                      blurRadius: 8,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  providerLabel,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              Text(
                _formatRelative(integration['lastSyncAt'] as String?),
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.textHint,
                ),
              ),
            ],
          ),
          if (metaLine.isNotEmpty) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 16),
              child: Text(
                metaLine,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 10.5,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
          if (integration['lastSyncError'] != null) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(left: 16),
              child: Text(
                'Ошибка: ${integration['lastSyncError']}',
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.warning,
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _Toggle(
                label: 'Меню',
                value: integration['syncMenu'] == true,
                onChanged: (v) => onToggle({'syncMenu': v}),
              ),
              _Toggle(
                label: 'Остатки',
                value: integration['syncStock'] == true,
                onChanged: (v) => onToggle({'syncStock': v}),
              ),
              _Toggle(
                label: 'Заказы',
                value: integration['syncOrders'] == true,
                onChanged: (v) => onToggle({'syncOrders': v}),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onTest,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    side: BorderSide(color: AppColors.border),
                  ),
                  icon: const Icon(Icons.network_check_rounded, size: 14),
                  label: const Text('Тест', style: TextStyle(fontSize: 12)),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: onSync,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.bg,
                  ),
                  icon: const Icon(Icons.sync_rounded, size: 14),
                  label: const Text('Синхронизировать',
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                onPressed: onDisconnect,
                icon: Icon(Icons.link_off_rounded,
                    size: 16, color: AppColors.error),
                tooltip: 'Отключить',
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatRelative(String? iso) {
    if (iso == null) return 'не синкалось';
    try {
      final d = DateTime.parse(iso).toLocal();
      final diff = DateTime.now().difference(d);
      if (diff.inMinutes < 1) return 'только что';
      if (diff.inMinutes < 60) return '${diff.inMinutes} мин назад';
      if (diff.inHours < 24) return '${diff.inHours} ч назад';
      return '${diff.inDays} д назад';
    } catch (_) {
      return iso;
    }
  }
}

class _Toggle extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _Toggle({
    required this.label,
    required this.value,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () => onChanged(!value),
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: value
                ? AppColors.primary.withValues(alpha: 0.15)
                : AppColors.surfaceMuted,
            borderRadius: BorderRadius.circular(100),
            border: Border.all(
              color: value
                  ? AppColors.primary.withValues(alpha: 0.40)
                  : AppColors.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                value
                    ? Icons.check_circle_rounded
                    : Icons.circle_outlined,
                size: 12,
                color:
                    value ? AppColors.primary : AppColors.textHint,
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: value ? AppColors.primary : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      );
}

// ═══════════════════════════════════════════════════════════════════════════
//  Dev API (our token)
// ═══════════════════════════════════════════════════════════════════════════
class _DevApiSection extends StatelessWidget {
  final Map<String, dynamic>? info;
  final String? justMintedKey;
  final VoidCallback onRotate;
  final VoidCallback onCopyMinted;
  final VoidCallback onDismissMinted;
  const _DevApiSection({
    required this.info,
    required this.justMintedKey,
    required this.onRotate,
    required this.onCopyMinted,
    required this.onDismissMinted,
  });

  @override
  Widget build(BuildContext context) {
    final hasKey = info?['hasApiKey'] == true;
    final prefix = info?['apiKeyPrefix'] as String?;
    return _Card(
      title: 'Наш API key',
      icon: Icons.vpn_key_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!hasKey)
            Text(
              'Создайте ключ, чтобы вызывать наш REST API из своего сервера.',
              style: TextStyle(
                  fontSize: 12, color: AppColors.textSecondary),
            )
          else
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceMuted,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Text(
                    '${prefix ?? ''}···············',
                    style: GoogleFonts.jetBrainsMono(
                        color: Colors.white, fontSize: 12),
                  ),
                ),
              ],
            ),
          if (justMintedKey != null) ...[
            const SizedBox(height: 10),
            _SecretBanner(
              label: 'Новый ключ — скопируйте сейчас',
              value: justMintedKey!,
              onCopy: onCopyMinted,
              onDismiss: onDismissMinted,
            ),
          ],
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: onRotate,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: BorderSide(
                  color: AppColors.primary.withValues(alpha: 0.5)),
            ),
            icon: Icon(hasKey
                ? Icons.autorenew_rounded
                : Icons.add_rounded),
            label: Text(hasKey ? 'Перевыпустить' : 'Создать ключ'),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Webhook
// ═══════════════════════════════════════════════════════════════════════════
class _WebhookSection extends StatelessWidget {
  final TextEditingController controller;
  final Map<String, dynamic>? info;
  final String? justMintedSecret;
  final VoidCallback onSave;
  final VoidCallback onDelete;
  final VoidCallback onCopyMinted;
  final VoidCallback onDismissMinted;
  const _WebhookSection({
    required this.controller,
    required this.info,
    required this.justMintedSecret,
    required this.onSave,
    required this.onDelete,
    required this.onCopyMinted,
    required this.onDismissMinted,
  });

  @override
  Widget build(BuildContext context) {
    final has = info?['hasWebhook'] == true;
    return _Card(
      title: 'Webhook (заказы → к вам)',
      icon: Icons.webhook_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: controller,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'https://shop.example.com/hooks/tz',
              hintStyle: TextStyle(color: AppColors.textHint, fontSize: 12),
              filled: true,
              fillColor: AppColors.surfaceMuted,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    BorderSide(color: AppColors.primary, width: 1.5),
              ),
            ),
          ),
          if (justMintedSecret != null) ...[
            const SizedBox(height: 10),
            _SecretBanner(
              label: 'Webhook secret (показан один раз)',
              value: justMintedSecret!,
              onCopy: onCopyMinted,
              onDismiss: onDismissMinted,
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              if (has)
                Expanded(
                  child: OutlinedButton(
                    onPressed: onDelete,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                      side: BorderSide(
                          color:
                              AppColors.error.withValues(alpha: 0.5)),
                    ),
                    child: const Text('Удалить'),
                  ),
                ),
              if (has) const SizedBox(width: 8),
              Expanded(
                flex: has ? 1 : 1,
                child: ElevatedButton.icon(
                  onPressed: onSave,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.bg,
                  ),
                  icon: const Icon(Icons.save_rounded, size: 14),
                  label: Text(has ? 'Обновить' : 'Сохранить'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  cURL example
// ═══════════════════════════════════════════════════════════════════════════
class _CurlExamples extends StatelessWidget {
  final String apiBase;
  const _CurlExamples({required this.apiBase});

  @override
  Widget build(BuildContext context) {
    final example = '''curl -X POST $apiBase/products/upsert \\
  -H "Authorization: Bearer tz_live_..." \\
  -H "Content-Type: application/json" \\
  -d '{ "items": [{ "externalId": "sku-1",
                   "name": "Маргарита",
                   "price": 60000,
                   "unit": "шт",
                   "category": "pizza" }] }'
''';
    return _Card(
      title: 'cURL пример',
      icon: Icons.terminal_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF050507),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: SelectableText(
              example,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 10.5,
                color: Colors.white,
                height: 1.55,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: example));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Скопировано')));
                }
              },
              icon: Icon(Icons.copy_rounded,
                  size: 13, color: AppColors.primary),
              label: Text('Копировать',
                  style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Sync log
// ═══════════════════════════════════════════════════════════════════════════
class _SyncLog extends StatelessWidget {
  final List<dynamic> events;
  final String? lastSyncAt;
  const _SyncLog({required this.events, this.lastSyncAt});

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Text(
          'Здесь появятся последние 200 событий: тесты, синки, ошибки.',
          style: TextStyle(fontSize: 12, color: AppColors.textHint),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          for (final e in events.take(20))
            _LogRow(event: e as Map<String, dynamic>),
        ],
      ),
    );
  }
}

class _LogRow extends StatelessWidget {
  final Map<String, dynamic> event;
  const _LogRow({required this.event});

  @override
  Widget build(BuildContext context) {
    final ok = event['ok'] == true;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
              color: AppColors.border.withValues(alpha: 0.4)),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            ok ? Icons.check_circle : Icons.error_outline,
            size: 13,
            color: ok ? AppColors.primary : AppColors.error,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event['kind'] ?? '',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10.5,
                    color: AppColors.textSecondary,
                  ),
                ),
                if ((event['message'] ?? '').toString().isNotEmpty)
                  Text(
                    event['message'] ?? '',
                    style: const TextStyle(
                        fontSize: 12, color: Colors.white),
                  ),
              ],
            ),
          ),
          Text(
            _hhmm(event['createdAt']),
            style: TextStyle(fontSize: 10, color: AppColors.textHint),
          ),
        ],
      ),
    );
  }

  String _hhmm(dynamic iso) {
    if (iso == null) return '';
    try {
      final d = DateTime.parse(iso.toString()).toLocal();
      return '${d.hour.toString().padLeft(2, "0")}:${d.minute.toString().padLeft(2, "0")}';
    } catch (_) {
      return '';
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Shared
// ═══════════════════════════════════════════════════════════════════════════
class _Card extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  const _Card({required this.title, required this.icon, required this.child});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.white),
                ),
              ],
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      );
}

class _SecretBanner extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onCopy;
  final VoidCallback onDismiss;
  const _SecretBanner({
    required this.label,
    required this.value,
    required this.onCopy,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
          border:
              Border.all(color: AppColors.primary.withValues(alpha: 0.40)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber_rounded,
                    size: 12, color: AppColors.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: onDismiss,
                  child: Icon(Icons.close_rounded,
                      size: 14, color: AppColors.primary),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF050507),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SelectableText(
                      value,
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 11.5,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: onCopy,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.copy_rounded,
                        size: 14, color: AppColors.bg),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
}
