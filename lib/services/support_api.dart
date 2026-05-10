import 'api_client.dart';

/// Phase 10.2 — customer-support tickets backend client.
///
/// Backend Agent B exposes a CRUD-ish ticket API plus a `support:message`
/// socket event for live admin replies.
class SupportApi {
  SupportApi._();
  static final SupportApi instance = SupportApi._();

  final _api = ApiClient.instance;

  Future<SupportTicket> create({
    required String subject,
    String? category,
    String? orderId,
    required String body,
  }) async {
    final res = await _api.post('/api/support/tickets', {
      'subject': subject,
      if (category != null && category.isNotEmpty) 'category': category,
      if (orderId != null && orderId.isNotEmpty) 'orderId': orderId,
      'body': body,
    });
    return SupportTicket.fromJson(_unwrap(res.data));
  }

  Future<List<SupportTicket>> myTickets() async {
    final res = await _api.get('/api/support/tickets/me');
    final data = res.data;
    final list = data is List
        ? data
        : (data is Map && data['tickets'] is List
            ? data['tickets'] as List
            : const <dynamic>[]);
    return list
        .map((t) => SupportTicket.fromJson(Map<String, dynamic>.from(t as Map)))
        .toList();
  }

  Future<SupportTicket> get(String id) async {
    final res = await _api.get('/api/support/tickets/me/$id');
    return SupportTicket.fromJson(_unwrap(res.data));
  }

  Future<SupportMessage> reply(
    String id, {
    required String body,
    List<String>? attachments,
  }) async {
    final res = await _api.post('/api/support/tickets/$id/messages', {
      'body': body,
      if (attachments != null && attachments.isNotEmpty)
        'attachments': attachments,
    });
    final data = res.data;
    final m = data is Map && data['message'] is Map
        ? Map<String, dynamic>.from(data['message'] as Map)
        : Map<String, dynamic>.from(data as Map);
    return SupportMessage.fromJson(m);
  }

  Future<void> close(String id) async {
    await _api.post('/api/support/tickets/$id/close');
  }

  Map<String, dynamic> _unwrap(dynamic data) {
    if (data is Map) {
      if (data['ticket'] is Map) {
        return Map<String, dynamic>.from(data['ticket'] as Map);
      }
      return Map<String, dynamic>.from(data);
    }
    // Non-Map response (error string, list, null) — surface a clear
    // FormatException with the runtime type instead of a raw TypeError.
    throw FormatException(
      'Support API: expected a JSON object, got ${data.runtimeType}: $data',
    );
  }
}

/// Categories the buyer can attach to a ticket. Synced with l10n keys
/// `support.category_*` so the dropdown labels stay localised.
const supportCategories = ['order', 'payment', 'delivery', 'account', 'other'];
const supportPriorities = ['low', 'normal', 'high', 'urgent'];

class SupportTicket {
  final String id;
  final String subject;
  final String? category;
  final String? priority;
  final String status; // open | pending | resolved | closed
  final String? orderId;
  final DateTime createdAt;
  final DateTime? lastReplyAt;
  /// `true` when the most recent message is from an admin and the buyer
  /// hasn't viewed the thread since.
  final bool unread;
  final List<SupportMessage> messages;

  const SupportTicket({
    required this.id,
    required this.subject,
    this.category,
    this.priority,
    required this.status,
    this.orderId,
    required this.createdAt,
    this.lastReplyAt,
    this.unread = false,
    this.messages = const [],
  });

  bool get isClosed => status == 'closed' || status == 'resolved';

  factory SupportTicket.fromJson(Map<String, dynamic> j) {
    DateTime? parse(String key) {
      final raw = j[key];
      if (raw == null || raw is! String || raw.isEmpty) return null;
      return DateTime.tryParse(raw);
    }

    final messages = (j['messages'] as List? ?? const [])
        .map((m) =>
            SupportMessage.fromJson(Map<String, dynamic>.from(m as Map)))
        .toList();

    return SupportTicket(
      id: j['id'] as String,
      subject: j['subject'] as String? ?? '',
      category: j['category'] as String?,
      priority: j['priority'] as String?,
      status: j['status'] as String? ?? 'open',
      orderId: j['orderId'] as String?,
      createdAt: parse('createdAt') ?? DateTime.now(),
      lastReplyAt: parse('lastReplyAt'),
      unread: j['unread'] as bool? ?? false,
      messages: messages,
    );
  }
}

class SupportMessage {
  final String id;
  final String ticketId;
  final String authorRole; // buyer | admin | system
  final String body;
  final List<String> attachments;
  final DateTime createdAt;

  const SupportMessage({
    required this.id,
    required this.ticketId,
    required this.authorRole,
    required this.body,
    this.attachments = const [],
    required this.createdAt,
  });

  bool get isFromAdmin => authorRole == 'admin';
  bool get isFromBuyer => authorRole == 'buyer';

  factory SupportMessage.fromJson(Map<String, dynamic> j) {
    DateTime? parse(String key) {
      final raw = j[key];
      if (raw == null || raw is! String || raw.isEmpty) return null;
      return DateTime.tryParse(raw);
    }

    return SupportMessage(
      id: j['id'] as String? ?? '',
      ticketId: j['ticketId'] as String? ?? '',
      authorRole: j['authorRole'] as String? ?? j['role'] as String? ?? 'buyer',
      body: j['body'] as String? ?? j['text'] as String? ?? '',
      attachments: ((j['attachments'] as List?) ?? const [])
          .map((a) => a.toString())
          .toList(),
      createdAt: parse('createdAt') ?? DateTime.now(),
    );
  }
}
