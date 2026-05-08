import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/l10n.dart';
import '../../services/api_client.dart';
import '../../services/gdpr_api.dart';
import '../../theme/app_theme.dart';

/// Phase 9 GDPR — buyer-facing privacy controls. Bundles the two flows
/// into a single screen reachable from `Profile → Privacy & data`:
///
/// • **Data export** — request a ZIP of orders / addresses / messages,
///   download it once the worker emails it back, see expiry.
/// • **Account deletion** — schedule a 30-day soft-delete with optional
///   reason, cancel during the grace window.
///
/// Order history is retained 5 years for tax compliance — the bottom
/// note tells the buyer why their orders may persist past deletion.
class DataPrivacyScreen extends StatefulWidget {
  const DataPrivacyScreen({super.key});

  @override
  State<DataPrivacyScreen> createState() => _DataPrivacyScreenState();
}

class _DataPrivacyScreenState extends State<DataPrivacyScreen> {
  final _api = GdprApi.instance;

  bool _loading = true;
  String? _error;

  List<DataExport> _exports = const [];
  AccountDeletionRequest? _deletion;

  bool _exporting = false;
  bool _deleteSubmitting = false;
  bool _cancelDeleteSubmitting = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _api.myExports(),
        _api.deletionStatus(),
      ]);
      if (!mounted) return;
      setState(() {
        _exports = results[0] as List<DataExport>;
        _deletion = results[1] as AccountDeletionRequest?;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = t(context, 'common.error');
        _loading = false;
      });
    }
  }

  // ─── Export ───────────────────────────────────────────────────────────

  Future<void> _requestExport() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      await _api.requestExport();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(t(context, 'privacy.export_pending')),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.info,
        ),
      );
      await _refresh();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _downloadExport(DataExport exp) async {
    final url = exp.fileUrl;
    if (url == null || url.isEmpty) return;
    final ok = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(t(context, 'common.error')),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // ─── Deletion ─────────────────────────────────────────────────────────

  Future<void> _confirmDeleteAccount() async {
    final reasonCtl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t(ctx, 'privacy.delete_account')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t(ctx, 'privacy.delete_confirm')),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtl,
              maxLines: 3,
              maxLength: 500,
              decoration: InputDecoration(
                hintText: t(ctx, 'privacy.delete_reason_hint'),
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t(ctx, 'common.cancel')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t(ctx, 'privacy.delete_account')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _deleteSubmitting = true);
    try {
      final req = await _api.requestAccountDeletion(
        reason: reasonCtl.text.trim().isEmpty ? null : reasonCtl.text.trim(),
      );
      if (!mounted) return;
      setState(() => _deletion = req);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _deleteSubmitting = false);
    }
  }

  Future<void> _cancelDelete() async {
    if (_cancelDeleteSubmitting) return;
    setState(() => _cancelDeleteSubmitting = true);
    try {
      await _api.cancelAccountDeletion();
      if (!mounted) return;
      setState(() => _deletion = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(t(context, 'privacy.no_deletion')),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.success,
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _cancelDeleteSubmitting = false);
    }
  }

  // ─── Build ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(t(context, 'privacy.title'))),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_error != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.errorLight,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _error!,
                        style: const TextStyle(color: AppColors.error),
                      ),
                    ),
                  _buildExportSection(),
                  const SizedBox(height: 16),
                  _buildDeletionSection(),
                  const SizedBox(height: 24),
                  _buildLegalNote(),
                ],
              ),
      ),
    );
  }

  Widget _buildExportSection() {
    final pending = _exports.where((e) => e.isPending).toList();
    final ready = _exports.where((e) => e.isReady && !e.isExpired).toList();
    final past = _exports
        .where((e) => !pending.contains(e) && !ready.contains(e))
        .toList();

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Mening ma'lumotlarim",
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),

          if (pending.isNotEmpty) ...[
            _PendingBanner(
              text: t(context, 'privacy.export_pending'),
              onRefresh: _refresh,
            ),
            const SizedBox(height: 12),
          ],

          if (ready.isNotEmpty) ...[
            for (final exp in ready) ...[
              _ReadyExportTile(
                export: exp,
                onDownload: () => _downloadExport(exp),
              ),
              const SizedBox(height: 8),
            ],
          ],

          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed:
                  _exporting || pending.isNotEmpty ? null : _requestExport,
              icon: _exporting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download_outlined, size: 18),
              label: Text(t(context, 'privacy.export_data')),
            ),
          ),

          if (past.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 8),
            for (final exp in past)
              _PastExportTile(export: exp),
          ],
        ],
      ),
    );
  }

  Widget _buildDeletionSection() {
    final hasPending = _deletion != null && _deletion!.isPending;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hasPending ? AppColors.error : AppColors.border,
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Hisob o'chirish",
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),

          if (hasPending) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.errorLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t(context, 'privacy.delete_scheduled').replaceFirst(
                      '{date}',
                      _formatDate(_deletion!.scheduledFor),
                    ),
                    style: const TextStyle(
                      color: AppColors.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _formatCountdown(_deletion!.timeUntilDeletion),
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed:
                    _cancelDeleteSubmitting ? null : _cancelDelete,
                child: _cancelDeleteSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(t(context, 'privacy.cancel_deletion')),
              ),
            ),
          ] else ...[
            Text(
              t(context, 'privacy.no_deletion'),
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                ),
                onPressed:
                    _deleteSubmitting ? null : _confirmDeleteAccount,
                icon: _deleteSubmitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.delete_forever, size: 18),
                label: Text(t(context, 'privacy.delete_account')),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLegalNote() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        t(context, 'privacy.legal_note'),
        style: const TextStyle(
          color: AppColors.textHint,
          fontSize: 12,
          height: 1.5,
        ),
      ),
    );
  }

  String _formatDate(DateTime d) =>
      DateFormat('yyyy-MM-dd').format(d.toLocal());

  String _formatCountdown(Duration d) {
    if (d.isNegative) {
      return DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
    }
    final days = d.inDays;
    final hours = d.inHours.remainder(24);
    return '$days kun, $hours soat';
  }
}

class _PendingBanner extends StatelessWidget {
  final String text;
  final Future<void> Function() onRefresh;
  const _PendingBanner({required this.text, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warningLight,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.hourglass_top, color: AppColors.warning, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: AppColors.warning, fontSize: 13),
            ),
          ),
          IconButton(
            tooltip: t(context, 'common.retry'),
            icon: const Icon(Icons.refresh, color: AppColors.warning),
            onPressed: () => onRefresh(),
          ),
        ],
      ),
    );
  }
}

class _ReadyExportTile extends StatelessWidget {
  final DataExport export;
  final VoidCallback onDownload;
  const _ReadyExportTile({required this.export, required this.onDownload});

  @override
  Widget build(BuildContext context) {
    final exp = export.expiresAt;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle,
                  color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  t(context, 'privacy.export_ready'),
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (exp != null)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 28),
              child: Text(
                '${t(context, 'privacy.export_expired')}: ${DateFormat('yyyy-MM-dd').format(exp.toLocal())}',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onDownload,
              icon: const Icon(Icons.file_download, size: 18),
              label: Text(t(context, 'privacy.download')),
            ),
          ),
        ],
      ),
    );
  }
}

class _PastExportTile extends StatelessWidget {
  final DataExport export;
  const _PastExportTile({required this.export});

  @override
  Widget build(BuildContext context) {
    final reqAt = export.requestedAt;
    final isExpired = export.isExpired;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(
        isExpired ? Icons.history_toggle_off : Icons.history,
        color: AppColors.textHint,
      ),
      title: Text(
        reqAt != null
            ? DateFormat('yyyy-MM-dd HH:mm').format(reqAt.toLocal())
            : export.id,
        style: const TextStyle(fontSize: 13),
      ),
      subtitle: Text(
        isExpired
            ? t(context, 'privacy.export_expired')
            : export.status,
        style: const TextStyle(fontSize: 11),
      ),
    );
  }
}
