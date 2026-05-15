import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/api_client.dart';
import '../../theme/app_theme.dart';

/// Shop → Integrations / API screen. Phase 14.
///
/// One destination for everything a chain/POS integrator needs:
///   • Mint or rotate a `tz_live_…` API key (shown once after rotation)
///   • Register a webhook URL with HMAC signing secret (shown once)
///   • cURL example snippets they can copy
///   • Live log of recent sync events (insert/update/delete/webhook delivery)
class ShopIntegrationScreen extends StatefulWidget {
  const ShopIntegrationScreen({super.key});
  @override
  State<ShopIntegrationScreen> createState() => _ShopIntegrationScreenState();
}

class _ShopIntegrationScreenState extends State<ShopIntegrationScreen> {
  Map<String, dynamic>? _info;
  List<dynamic> _events = [];
  bool _loading = true;
  String? _error;
  String? _justMintedKey;     // surfaces the plaintext API key once
  String? _justMintedSecret;  // surfaces the webhook secret once
  bool _busy = false;

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

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final infoResp =
          await ApiClient.instance.get('/api/shops/me/integration');
      final logResp = await ApiClient.instance
          .get('/api/shops/me/integration/log', query: {'limit': 30});
      if (!mounted) return;
      setState(() {
        _info = Map<String, dynamic>.from(infoResp.data);
        _webhookCtl.text = _info?['webhookUrl'] ?? '';
        _events = (logResp.data['events'] as List?) ?? [];
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

  Future<void> _rotateKey() async {
    final ok = await _confirm('Перевыпустить API-ключ?',
        'Старый ключ сразу перестанет работать. Убедитесь, что у вас есть доступ обновить '
        'его в вашей POS-системе.');
    if (!ok) return;
    setState(() => _busy = true);
    try {
      final r = await ApiClient.instance
          .post('/api/shops/me/integration/api-key/rotate');
      if (!mounted) return;
      setState(() {
        _justMintedKey = r.data['apiKey'] as String?;
        _busy = false;
      });
      await _load();
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        _snack('Ошибка: $e');
      }
    }
  }

  Future<void> _saveWebhook() async {
    final url = _webhookCtl.text.trim();
    if (url.isEmpty || (!url.startsWith('http://') && !url.startsWith('https://'))) {
      _snack('Нужен валидный URL, например https://shop.example.com/hooks/tz');
      return;
    }
    setState(() => _busy = true);
    try {
      final r = await ApiClient.instance
          .post('/api/shops/me/integration/webhook', {'url': url});
      if (!mounted) return;
      setState(() {
        _justMintedSecret = r.data['webhookSecret'] as String?;
        _busy = false;
      });
      await _load();
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        _snack('Ошибка: $e');
      }
    }
  }

  Future<void> _removeWebhook() async {
    final ok = await _confirm('Удалить webhook?',
        'Мы перестанем отправлять события заказов на ваш сервер.');
    if (!ok) return;
    setState(() => _busy = true);
    try {
      await ApiClient.instance
          .delete('/api/shops/me/integration/webhook');
      if (!mounted) return;
      setState(() {
        _webhookCtl.clear();
        _justMintedSecret = null;
        _busy = false;
      });
      await _load();
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        _snack('Ошибка: $e');
      }
    }
  }

  Future<bool> _confirm(String title, String body) async {
    return await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: AppColors.surface,
            title: Text(title, style: const TextStyle(color: Colors.white)),
            content: Text(body,
                style: TextStyle(color: AppColors.textSecondary)),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Отмена')),
              TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: TextButton.styleFrom(
                      foregroundColor: AppColors.warning),
                  child: const Text('Подтвердить')),
            ],
          ),
        ) ??
        false;
  }

  void _snack(String s) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(s)));

  Future<void> _copy(String s, String label) async {
    await Clipboard.setData(ClipboardData(text: s));
    if (mounted) _snack('Скопировано · $label');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('API и интеграции',
            style: TextStyle(color: Colors.white)),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!,
                        style: TextStyle(color: AppColors.error)),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                  children: [
                    _IntroCard(),
                    const SizedBox(height: 16),
                    _ApiKeySection(
                      hasKey: _info?['hasApiKey'] == true,
                      prefix: _info?['apiKeyPrefix'] as String?,
                      createdAt: _info?['apiKeyCreatedAt'] as String?,
                      apiBase: _info?['apiBase'] as String? ?? '',
                      justMinted: _justMintedKey,
                      onRotate: _busy ? null : _rotateKey,
                      onCopyMinted: () =>
                          _copy(_justMintedKey!, 'API key'),
                      onDismissMinted: () =>
                          setState(() => _justMintedKey = null),
                    ),
                    const SizedBox(height: 16),
                    _WebhookSection(
                      controller: _webhookCtl,
                      hasWebhook: _info?['hasWebhook'] == true,
                      events: _info?['webhookEvents'] as String? ?? '*',
                      justMintedSecret: _justMintedSecret,
                      onSave: _busy ? null : _saveWebhook,
                      onDelete: _busy ? null : _removeWebhook,
                      onCopyMinted: () =>
                          _copy(_justMintedSecret!, 'webhook secret'),
                      onDismissMinted: () =>
                          setState(() => _justMintedSecret = null),
                    ),
                    const SizedBox(height: 16),
                    _CurlExamples(
                      apiBase: _info?['apiBase'] as String? ?? '',
                    ),
                    const SizedBox(height: 16),
                    _SyncLog(events: _events, lastSyncAt: _info?['lastSyncAt']),
                  ],
                ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Intro
// ═══════════════════════════════════════════════════════════════════════════
class _IntroCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.cloud_sync_outlined,
                    color: AppColors.primary, size: 22),
                const SizedBox(width: 8),
                Text('Подключите свою POS-систему',
                    style: GoogleFonts.playfairDisplay(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    )),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'iiko, 1С, R-Keeper, Poster или ваш самописный backend — мы поддерживаем '
              'REST API для двусторонней синхронизации. Меню и остатки летят к нам '
              'через `POST /api/v1/products/upsert`, заказы — обратно к вам '
              'через webhook. Идеально для сетей с несколькими точками.',
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
          ],
        ),
      );
}

// ═══════════════════════════════════════════════════════════════════════════
//  API key
// ═══════════════════════════════════════════════════════════════════════════
class _ApiKeySection extends StatelessWidget {
  final bool hasKey;
  final String? prefix;
  final String? createdAt;
  final String apiBase;
  final String? justMinted;
  final VoidCallback? onRotate;
  final VoidCallback onCopyMinted;
  final VoidCallback onDismissMinted;
  const _ApiKeySection({
    required this.hasKey,
    required this.prefix,
    required this.createdAt,
    required this.apiBase,
    required this.justMinted,
    required this.onRotate,
    required this.onCopyMinted,
    required this.onDismissMinted,
  });

  @override
  Widget build(BuildContext context) => _Card(
        title: 'API-ключ',
        icon: Icons.vpn_key_rounded,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!hasKey)
              Text(
                'Ключ ещё не создан. Нажмите «Создать», чтобы получить токен — '
                'мы покажем его один раз.',
                style: TextStyle(
                    fontSize: 13, color: AppColors.textSecondary),
              )
            else ...[
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
                      '${prefix ?? ''}····················',
                      style: GoogleFonts.jetBrainsMono(
                        color: Colors.white,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (createdAt != null)
                    Text(
                      _formatDate(createdAt!),
                      style: TextStyle(
                          fontSize: 12, color: AppColors.textHint),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Полное значение показывается только один раз — при создании. '
                'Храните его в секрете.',
                style: TextStyle(
                    fontSize: 11, color: AppColors.textHint, height: 1.4),
              ),
            ],
            if (justMinted != null) ...[
              const SizedBox(height: 12),
              _SecretBanner(
                label: 'Новый ключ — скопируйте сейчас',
                value: justMinted!,
                onCopy: onCopyMinted,
                onDismiss: onDismissMinted,
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
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
                ),
              ],
            ),
          ],
        ),
      );

  String _formatDate(String iso) {
    try {
      final d = DateTime.parse(iso).toLocal();
      return 'создан ${d.day.toString().padLeft(2, "0")}.${d.month.toString().padLeft(2, "0")}.${d.year}';
    } catch (_) {
      return '';
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Webhook
// ═══════════════════════════════════════════════════════════════════════════
class _WebhookSection extends StatelessWidget {
  final TextEditingController controller;
  final bool hasWebhook;
  final String events;
  final String? justMintedSecret;
  final VoidCallback? onSave;
  final VoidCallback? onDelete;
  final VoidCallback onCopyMinted;
  final VoidCallback onDismissMinted;
  const _WebhookSection({
    required this.controller,
    required this.hasWebhook,
    required this.events,
    required this.justMintedSecret,
    required this.onSave,
    required this.onDelete,
    required this.onCopyMinted,
    required this.onDismissMinted,
  });

  @override
  Widget build(BuildContext context) => _Card(
        title: 'Webhook',
        icon: Icons.webhook_rounded,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Мы будем слать POST на этот URL при событиях заказа. '
              'Каждый запрос подписан HMAC-SHA256 в заголовке `X-TZ-Signature`.',
              style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  height: 1.4),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'https://shop.example.com/hooks/tezketkaz',
                hintStyle: TextStyle(color: AppColors.textHint),
                prefixIcon: Icon(Icons.link_rounded,
                    color: AppColors.textSecondary, size: 18),
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
            if (hasWebhook) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.check_circle,
                      size: 14, color: AppColors.primary),
                  const SizedBox(width: 6),
                  Text('Активный webhook · события: $events',
                      style: TextStyle(
                          fontSize: 11, color: AppColors.textSecondary)),
                ],
              ),
            ],
            if (justMintedSecret != null) ...[
              const SizedBox(height: 12),
              _SecretBanner(
                label: 'Секрет для проверки подписи (показан один раз)',
                value: justMintedSecret!,
                onCopy: onCopyMinted,
                onDismiss: onDismissMinted,
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                if (hasWebhook)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onDelete,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.error,
                        side: BorderSide(
                            color:
                                AppColors.error.withValues(alpha: 0.5)),
                      ),
                      icon: const Icon(Icons.delete_outline_rounded),
                      label: const Text('Удалить'),
                    ),
                  ),
                if (hasWebhook) const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: onSave,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.bg,
                    ),
                    icon: const Icon(Icons.save_rounded),
                    label:
                        Text(hasWebhook ? 'Обновить' : 'Сохранить webhook'),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
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
  -d '{
    "items": [
      {
        "externalId": "sku-123",
        "name": "Маргарита 30 см",
        "nameUz": "Margherita",
        "price": 60000,
        "discountPrice": 48000,
        "unit": "шт",
        "category": "pizza",
        "stock": 50,
        "imageUrl": "https://cdn.shop.ru/p/123.jpg"
      }
    ]
  }'
''';
    return _Card(
      title: 'Пример вызова',
      icon: Icons.code_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Идемпотентный upsert: повторный вызов с тем же `externalId` обновит '
            'товар. Лимит — 1000 строк за один запрос.',
            style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
                height: 1.4),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF050507),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: SelectableText(
              example,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 11,
                color: Colors.white,
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: example));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('cURL скопирован')));
                }
              },
              icon: Icon(Icons.copy_rounded,
                  size: 14, color: AppColors.primary),
              label: Text('Копировать',
                  style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 12,
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
  Widget build(BuildContext context) => _Card(
        title: 'Журнал синхронизации',
        icon: Icons.history_rounded,
        subtitle: lastSyncAt != null
            ? 'Последняя синхронизация: ${_format(lastSyncAt!)}'
            : 'Синхронизаций ещё не было',
        child: events.isEmpty
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Здесь появятся последние 200 событий: загрузки меню, '
                  'отправки webhook, ротации ключа.',
                  style: TextStyle(
                      fontSize: 12, color: AppColors.textHint),
                ),
              )
            : Column(
                children: [
                  for (final e in events.take(15)) _LogRow(event: e),
                ],
              ),
      );

  String _format(String iso) {
    try {
      final d = DateTime.parse(iso).toLocal();
      final dd = d.day.toString().padLeft(2, '0');
      final mm = d.month.toString().padLeft(2, '0');
      final hh = d.hour.toString().padLeft(2, '0');
      final mi = d.minute.toString().padLeft(2, '0');
      return '$dd.$mm.${d.year} $hh:$mi';
    } catch (_) {
      return iso;
    }
  }
}

class _LogRow extends StatelessWidget {
  final dynamic event;
  const _LogRow({required this.event});

  @override
  Widget build(BuildContext context) {
    final ok = event['ok'] == true;
    final kind = event['kind'] as String? ?? 'unknown';
    final msg = event['message'] as String? ?? '';
    final created = event['createdAt'] as String? ?? '';
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
              color: AppColors.border.withValues(alpha: 0.5)),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            ok ? Icons.check_circle : Icons.error_outline,
            size: 14,
            color: ok ? AppColors.primary : AppColors.error,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(kind,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    )),
                if (msg.isNotEmpty)
                  Text(msg,
                      style: const TextStyle(
                          fontSize: 12, color: Colors.white)),
              ],
            ),
          ),
          Text(_short(created),
              style: TextStyle(
                  fontSize: 10, color: AppColors.textHint)),
        ],
      ),
    );
  }

  String _short(String iso) {
    try {
      final d = DateTime.parse(iso).toLocal();
      final hh = d.hour.toString().padLeft(2, '0');
      final mi = d.minute.toString().padLeft(2, '0');
      return '$hh:$mi';
    } catch (_) {
      return '';
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Shared building blocks
// ═══════════════════════════════════════════════════════════════════════════
class _Card extends StatelessWidget {
  final String title;
  final IconData icon;
  final String? subtitle;
  final Widget child;
  const _Card({
    required this.title,
    required this.icon,
    required this.child,
    this.subtitle,
  });

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
                Icon(icon, size: 18, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    )),
              ],
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(left: 26),
                child: Text(subtitle!,
                    style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary)),
              ),
            ],
            const SizedBox(height: 12),
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
        padding: const EdgeInsets.all(12),
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
                    size: 14, color: AppColors.primary),
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
                      size: 16, color: AppColors.primary),
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
                        fontSize: 12,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: onCopy,
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.copy_rounded,
                        size: 16, color: AppColors.bg),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
}
