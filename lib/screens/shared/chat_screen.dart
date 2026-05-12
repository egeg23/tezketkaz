import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../l10n/l10n.dart';
import '../../models/chat.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_client.dart';
import '../../services/chat_api.dart';
import '../../services/socket_service.dart';
import '../../theme/app_theme.dart';

/// WhatsApp-style chat for an order. Supports text messages and (when
/// `image_picker` is available) image attachments. Listens to the
/// `chat:message` socket event to append realtime messages and calls
/// `chat/read` whenever an inbound message arrives while the screen is open.
class ChatScreen extends StatefulWidget {
  final String orderId;
  final String? receiverName;
  final bool? receiverOnline;

  const ChatScreen({
    super.key,
    required this.orderId,
    this.receiverName,
    this.receiverOnline,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final List<ChatMessage> _messages = [];
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  bool _loading = true;
  bool _sending = false;
  String? _error;
  late final void Function(dynamic) _socketHandler;

  String? get _myUserId => context.read<AuthProvider>().user?.id;

  @override
  void initState() {
    super.initState();
    final socket = SocketService.instance;
    socket.joinOrderChat(widget.orderId);
    _socketHandler = (data) {
      if (!mounted) return;
      if (data is! Map) return;
      try {
        final m = ChatMessage.fromJson(Map<String, dynamic>.from(data));
        if (m.orderId != widget.orderId) return;
        // Drop pending local-echo when the server confirms.
        setState(() {
          _messages.removeWhere(
              (x) => x.pending && x.text == m.text && x.imageUrl == m.imageUrl);
          _messages.add(m);
        });
        _scrollToBottom();
        // Mark read if the message came from someone else.
        if (_myUserId != null && m.senderId != _myUserId) {
          ChatApi.instance.markRead(widget.orderId).catchError((_) {});
        }
      } catch (e) {
        // Malformed payload — log so we can spot backend regressions
        // without crashing the chat surface.
        debugPrint('chat:message parse error: $e');
      }
    };
    socket.onChatMessage(_socketHandler);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadHistory());
  }

  @override
  void dispose() {
    SocketService.instance.offChatMessage(_socketHandler);
    SocketService.instance.leaveOrderChat(widget.orderId);
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final history = await ChatApi.instance.history(widget.orderId);
      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(history);
        _loading = false;
      });
      _scrollToBottom(animate: false);
      // Anything that arrived while we were away is now visible — mark as read.
      ChatApi.instance.markRead(widget.orderId).catchError((_) {});
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

  void _scrollToBottom({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final pos = _scroll.position.maxScrollExtent;
      if (animate) {
        _scroll.animateTo(pos,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      } else {
        _scroll.jumpTo(pos);
      }
    });
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;
    final my = _myUserId ?? 'me';
    final placeholder = ChatMessage(
      id: 'local-${DateTime.now().microsecondsSinceEpoch}',
      orderId: widget.orderId,
      senderId: my,
      text: text,
      createdAt: DateTime.now(),
      pending: true,
    );
    setState(() {
      _messages.add(placeholder);
      _ctrl.clear();
      _sending = true;
    });
    _scrollToBottom();
    try {
      final saved = await ChatApi.instance.send(widget.orderId, text: text);
      if (!mounted) return;
      setState(() {
        // Replace the local placeholder with the server message (in case the
        // socket event hasn't already done so).
        final i = _messages.indexWhere((m) => m.id == placeholder.id);
        if (i >= 0) _messages[i] = saved;
        _sending = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${t(context, 'chat.send_failed')}: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final myId = _myUserId;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.receiverName ?? t(context, 'chat.title'),
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700)),
            if (widget.receiverOnline != null)
              Text(
                widget.receiverOnline == true
                    ? t(context, 'chat.online')
                    : t(context, 'chat.offline'),
                style: TextStyle(
                  fontSize: 12,
                  color: widget.receiverOnline == true
                      ? AppColors.success
                      : AppColors.textHint,
                  fontWeight: FontWeight.w400,
                ),
              ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(_error!,
                                    style: const TextStyle(
                                        color: AppColors.error)),
                                const SizedBox(height: 8),
                                OutlinedButton(
                                    onPressed: _loadHistory,
                                    child: Text(t(context, 'common.retry'))),
                              ],
                            ),
                          ),
                        )
                      : ListView.builder(
                          controller: _scroll,
                          padding:
                              const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          itemCount: _messages.length,
                          itemBuilder: (_, i) {
                            final m = _messages[i];
                            final isMine = myId != null && m.senderId == myId;
                            return _Bubble(message: m, isMine: isMine);
                          },
                        ),
            ),
            _InputBar(
              controller: _ctrl,
              sending: _sending,
              onSend: _send,
            ),
          ],
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final ChatMessage message;
  final bool isMine;
  const _Bubble({required this.message, required this.isMine});

  String _fmtTime(DateTime d) {
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    final align = isMine ? Alignment.centerRight : Alignment.centerLeft;
    final bg = isMine
        ? (message.pending ? AppColors.surfaceMuted : AppColors.primaryLight)
        : AppColors.surface;
    final fg = isMine ? AppColors.textPrimary : AppColors.textPrimary;
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(14),
      topRight: const Radius.circular(14),
      bottomLeft: Radius.circular(isMine ? 14 : 4),
      bottomRight: Radius.circular(isMine ? 4 : 14),
    );

    return Align(
      alignment: align,
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: radius,
            boxShadow: AppShadows.card,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isMine && message.senderName != null) ...[
                Text(message.senderName!,
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary)),
                const SizedBox(height: 2),
              ],
              if (message.imageUrl != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(
                    imageUrl: message.imageUrl!,
                    width: 200,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => Container(
                      width: 200,
                      height: 120,
                      color: AppColors.surfaceMuted,
                      child: const Icon(Icons.image_outlined,
                          color: AppColors.textHint),
                    ),
                  ),
                ),
              if (message.text != null && message.text!.isNotEmpty)
                Text(message.text!,
                    style: TextStyle(fontSize: 14, color: fg, height: 1.3)),
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_fmtTime(message.createdAt),
                      style: const TextStyle(
                          fontSize: 10, color: AppColors.textHint)),
                  if (isMine) ...[
                    const SizedBox(width: 4),
                    Icon(
                      message.pending
                          ? Icons.schedule
                          : message.readByOther
                              ? Icons.done_all
                              : Icons.done,
                      size: 12,
                      color: message.readByOther
                          ? AppColors.primary
                          : AppColors.textHint,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;
  const _InputBar({
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        boxShadow: [
          BoxShadow(
              color: Color(0x10000000),
              blurRadius: 12,
              offset: Offset(0, -2)),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.add_photo_alternate_outlined,
                color: AppColors.textSecondary),
            // Image upload requires uploading to a CDN before sending the URL
            // to chat/send. Hooked up at backend integration time.
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(t(context, 'chat.image_unavailable'))),
              );
            },
          ),
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 5,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              decoration: InputDecoration(
                hintText: t(context, 'chat.input_hint'),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: AppColors.surfaceMuted,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Material(
            color: AppColors.primary,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: sending ? null : onSend,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: sending
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2),
                      )
                    : const Icon(Icons.send_rounded, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
