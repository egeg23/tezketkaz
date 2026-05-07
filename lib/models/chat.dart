/// Chat message — matches `GET /api/orders/:orderId/chat` and the
/// `chat:message` socket event.
class ChatMessage {
  final String id;
  final String orderId;
  final String senderId;
  final String? senderName;
  final String? senderRole; // 'buyer' | 'courier' | 'shop' | 'system'
  final String? text;
  final String? imageUrl;
  final DateTime createdAt;
  final bool readByOther;
  /// Set client-side for optimistic local-echo bubbles.
  final bool pending;

  const ChatMessage({
    required this.id,
    required this.orderId,
    required this.senderId,
    this.senderName,
    this.senderRole,
    this.text,
    this.imageUrl,
    required this.createdAt,
    this.readByOther = false,
    this.pending = false,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        id: (j['id'] ?? j['_id'] ?? '').toString(),
        orderId: (j['orderId'] ?? '').toString(),
        senderId: (j['senderId'] ?? j['from']?['id'] ?? '').toString(),
        senderName: j['senderName'] as String? ??
            j['from']?['name'] as String?,
        senderRole: j['senderRole'] as String? ??
            j['from']?['role'] as String?,
        text: j['text'] as String?,
        imageUrl: j['imageUrl'] as String?,
        createdAt: DateTime.tryParse(
                (j['createdAt'] ?? j['ts'] ?? '').toString()) ??
            DateTime.now(),
        readByOther: j['readByOther'] as bool? ?? false,
      );

  ChatMessage copyWith({
    String? id,
    bool? readByOther,
    bool? pending,
  }) =>
      ChatMessage(
        id: id ?? this.id,
        orderId: orderId,
        senderId: senderId,
        senderName: senderName,
        senderRole: senderRole,
        text: text,
        imageUrl: imageUrl,
        createdAt: createdAt,
        readByOther: readByOther ?? this.readByOther,
        pending: pending ?? this.pending,
      );
}
