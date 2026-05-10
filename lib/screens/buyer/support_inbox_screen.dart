import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/l10n.dart';
import '../../services/api_client.dart';
import '../../services/support_api.dart';
import '../../theme/app_theme.dart';

/// Phase 10.2 — list of the buyer's support tickets.
///
/// Tap a row to open the thread; FAB pushes the new-ticket form. Refreshes
/// on pull-to-refresh and when the route is re-entered.
class SupportInboxScreen extends StatefulWidget {
  const SupportInboxScreen({super.key});

  @override
  State<SupportInboxScreen> createState() => _SupportInboxScreenState();
}

class _SupportInboxScreenState extends State<SupportInboxScreen> {
  bool _loading = true;
  String? _error;
  List<SupportTicket> _tickets = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await SupportApi.instance.myTickets();
      if (!mounted) return;
      setState(() {
        _tickets = list;
        _error = null;
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

  String _statusLabel(BuildContext c, String status) =>
      t(c, 'support.status_$status');

  Color _statusColor(String status) {
    switch (status) {
      case 'open':
        return AppColors.primary;
      case 'pending':
        return AppColors.warning;
      case 'resolved':
        return AppColors.success;
      case 'closed':
      default:
        return AppColors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(t(context, 'support.title'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await context.push('/buyer/support/new');
          _load();
        },
        icon: const Icon(Icons.add_rounded),
        label: Text(t(context, 'support.new_ticket')),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _tickets.isEmpty
                ? _EmptyState(error: _error)
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _tickets.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final ticket = _tickets[i];
                      return Container(
                        decoration: BoxDecoration(
                          color: Theme.of(context).cardTheme.color ??
                              AppColors.surface,
                          borderRadius: BorderRadius.circular(AppRadii.md),
                          boxShadow: AppShadows.card,
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 6),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  ticket.subject,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (ticket.unread)
                                Container(
                                  width: 8,
                                  height: 8,
                                  margin: const EdgeInsets.only(left: 8),
                                  decoration: const BoxDecoration(
                                    color: AppColors.error,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                            ],
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: _statusColor(ticket.status)
                                        .withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    _statusLabel(context, ticket.status),
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: _statusColor(ticket.status),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _fmtDate(ticket.lastReplyAt ?? ticket.createdAt),
                                    style: const TextStyle(
                                        fontSize: 12,
                                        color: AppColors.textSecondary),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () async {
                            await context.push('/buyer/support/${ticket.id}');
                            _load();
                          },
                        ),
                      );
                    },
                  ),
      ),
    );
  }

  String _fmtDate(DateTime d) {
    final now = DateTime.now();
    if (d.year == now.year && d.month == now.month && d.day == now.day) {
      return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    }
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}';
  }
}

class _EmptyState extends StatelessWidget {
  final String? error;
  const _EmptyState({required this.error});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 80),
      children: [
        const Center(
          child: Text('💬', style: TextStyle(fontSize: 56)),
        ),
        const SizedBox(height: 12),
        Center(
          child: Text(
            t(context, 'support.no_tickets'),
            style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.w600),
            textAlign: TextAlign.center,
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 8),
          Center(
            child: Text(error!,
                style: const TextStyle(color: AppColors.error)),
          ),
        ],
      ],
    );
  }
}
