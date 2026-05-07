import '../models/chat.dart';
import 'api_client.dart';

/// Chat endpoints (Phase 3, Agent B backend).
class ChatApi {
  ChatApi._();
  static final ChatApi instance = ChatApi._();

  final _api = ApiClient.instance;

  /// `GET /api/orders/:orderId/chat?cursor=&limit=`
  Future<List<ChatMessage>> history(
    String orderId, {
    String? cursor,
    int limit = 50,
  }) async {
    final res = await _api.get('/api/orders/$orderId/chat', query: {
      'limit': limit,
      if (cursor != null) 'cursor': cursor,
    });
    final data = res.data;
    final list = (data is List)
        ? data
        : (data is Map && data['messages'] is List
            ? data['messages'] as List
            : const []);
    return list
        .map((m) =>
            ChatMessage.fromJson(Map<String, dynamic>.from(m as Map)))
        .toList();
  }

  /// `POST /api/orders/:orderId/chat`
  Future<ChatMessage> send(
    String orderId, {
    String? text,
    String? imageUrl,
  }) async {
    final res = await _api.post('/api/orders/$orderId/chat', {
      if (text != null && text.isNotEmpty) 'text': text,
      if (imageUrl != null && imageUrl.isNotEmpty) 'imageUrl': imageUrl,
    });
    final data = res.data;
    final m = (data is Map && data['message'] is Map)
        ? Map<String, dynamic>.from(data['message'] as Map)
        : Map<String, dynamic>.from(data as Map);
    return ChatMessage.fromJson(m);
  }

  /// `POST /api/orders/:orderId/chat/read`
  Future<void> markRead(String orderId) async {
    await _api.post('/api/orders/$orderId/chat/read');
  }
}
