import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/l10n.dart';
import '../../services/api_client.dart';
import '../../services/socket_service.dart';
import '../../services/support_api.dart';
import '../../theme/app_theme.dart';

/// Phase 10.2 — chat-style thread for a single support ticket.
///
/// Subscribes to the socket `support:message` event and appends any incoming
/// message that targets the current ticket. The buyer can reply with text;
/// attachment uploads are out of scope for this slice (the API still accepts
/// `attachments`, so a follow-up can wire image picker + upload).
class SupportThreadScreen extends StatefulWidget {
  final String ticketId;
  const SupportThreadScreen({super.key, required this.ticketId});

  @override
  State<SupportThreadScreen> createState() => _SupportThreadScreenState();
}

class _SupportThreadScreenState extends State<SupportThreadScreen> {
  SupportTicket? _ticket;
  bool _loading = true;
  String? _error;
  bool _sending = false;
  bool _closing = false;

  final _replyCtrl = TextEditingController();
  final _scroll = ScrollController();

  late final void Function(dynamic) _onSocketMessage;

  @override
  void initState() {
    super.initState();
    _onSocketMessage = (raw) {
      try {
        if (raw is! Map) return;
        final ticketId =
            raw['ticketId'] as String? ?? raw['ticket']?['id'] as String?;
        if (ticketId != widget.ticketId) return;
        final m = raw['message'] is Map
            ? Map<String, dynamic>.from(raw['message'] as Map)
            : Map<String, dynamic>.from(raw);
        final msg = SupportMessage.fromJson(m);
        if (!mounted) return;
        final existing = _ticket;
        if (existing == null) return;
        // The backend broadcasts every new message to the room without
        // excluding the sender — so a buyer-sent message arrives both via
        // the REST response (already appended in _send) and via this socket
        // event. Dedupe on id so we don't render it twice.
        if (existing.messages.any((x) => x.id == msg.id)) return;
        setState(() {
          _ticket = SupportTicket(
            id: existing.id,
            subject: existing.subject,
            category: existing.category,
            priority: existing.priority,
            status: existing.status,
            orderId: existing.orderId,
            createdAt: existing.createdAt,
            lastReplyAt: msg.createdAt,
            unread: false,
            messages: [...existing.messages, msg],
          );
        });
        _scrollToBottom();
      } catch (_) {/* malformed payload — ignore */}
    };
    SocketService.instance.on('support:message', _onSocketMessage);
    _load();
  }

  @override
  void dispose() {
    SocketService.instance.off('support:message', _onSocketMessage);
    _replyCtrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final fetched = await SupportApi.instance.get(widget.ticketId);
      if (!mounted) return;
      setState(() {
        _ticket = fetched;
        _loading = false;
        _error = null;
      });
      _scrollToBottom();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    final body = _replyCtrl.text.trim();
    if (body.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final msg = await SupportApi.instance.reply(widget.ticketId, body: body);
      if (!mounted) return;
      _replyCtrl.clear();
      setState(() {
        final existing = _ticket;
        if (existing != null) {
          _ticket = SupportTicket(
            id: existing.id,
            subject: existing.subject,
            category: existing.category,
            priority: existing.priority,
            status: existing.status,
            orderId: existing.orderId,
            createdAt: existing.createdAt,
            lastReplyAt: msg.createdAt,
            unread: false,
            messages: [...existing.messages, msg],
          );
        }
      });
      _scrollToBottom();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _close() async {
    if (_closing || _ticket == null || _ticket!.isClosed) return;
    setState(() => _closing = true);
    try {
      await SupportApi.instance.close(widget.ticketId);
      if (!mounted) return;
      // Refetch to get the updated status.
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _closing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ticket = _ticket;
    return Scaffold(
      appBar: AppBar(
        title: Text(ticket?.subject ?? t(context, 'support.title'),
            maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (ticket != null && !ticket.isClosed)
            TextButton(
              onPressed: _closing ? null : _close,
              child: Text(t(context, 'support.close_ticket')),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ticket == null
              ? Center(
                  child: Text(_error ?? t(context, 'common.error')),
                )
              : Column(
                  children: [
                    Expanded(
                      child: ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.all(16),
                        itemCount: ticket.messages.length,
                        itemBuilder: (_, i) =>
                            _MessageBubble(message: ticket.messages[i]),
                      ),
                    ),
                    if (ticket.isClosed)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        color: AppColors.surfaceMuted,
                        child: Text(
                          t(context, 'support.status_closed'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w600),
                        ),
                      )
                    else
                      _ReplyBar(
                        controller: _replyCtrl,
                        sending: _sending,
                        onSend: _send,
                      ),
                  ],
                ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final SupportMessage message;
  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isMe = message.isFromBuyer;
    final align = isMe ? Alignment.centerRight : Alignment.centerLeft;
    final bg = isMe ? AppColors.primary : AppColors.surfaceMuted;
    final fg = isMe ? Colors.white : AppColors.textPrimary;
    return Align(
      alignment: align,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(AppRadii.md),
            topRight: const Radius.circular(AppRadii.md),
            bottomLeft: Radius.circular(isMe ? AppRadii.md : 4),
            bottomRight: Radius.circular(isMe ? 4 : AppRadii.md),
          ),
        ),
        child: Column(
          crossAxisAlignment:
              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(message.body,
                style: TextStyle(color: fg, fontSize: 14, height: 1.4)),
            const SizedBox(height: 2),
            Text(
              _fmtTime(message.createdAt),
              style: TextStyle(
                  color: fg.withValues(alpha: 0.7), fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }

  static String _fmtTime(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

class _ReplyBar extends StatelessWidget {
  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;
  const _ReplyBar({
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color ?? AppColors.surface,
          border: Border(
            top: BorderSide(color: AppColors.border, width: 1),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: t(context, 'chat.input_hint'),
                ),
                onSubmitted: (_) => onSend(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: sending ? null : onSend,
              icon: sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send_rounded),
            ),
          ],
        ),
      ),
    );
  }
}
