import 'api_client.dart';

/// Phase 10.1 — group order ("split bill") backend client.
///
/// Mirrors backend Agent A's `/api/order-groups` family. Wire format expected:
///
/// ```jsonc
/// {
///   "id": "grp_…",
///   "hostUserId": "usr_…",
///   "shopId": "shp_…",
///   "joinCode": "ABCD12",
///   "status": "open" | "locked" | "paid" | "cancelled" | "expired",
///   "paymentMode": "split" | "host",
///   "maxMembers": 6,
///   "expiresAt": "2026-01-01T12:00:00Z",
///   "lockedAt": "…",  "paidAt": "…",  "cancelledAt": "…",
///   "orderId": "ord_…",
///   "members": [
///     { "userId": "usr_…", "userName": "Aziz",
///       "status": "joined" | "ready" | "paid" | "left",
///       "cartJson": [...], "amountOwed": 64500,
///       "joinedAt": "…", "paidAt": "…" }
///   ]
/// }
/// ```
class OrderGroupApi {
  OrderGroupApi._();
  static final OrderGroupApi instance = OrderGroupApi._();

  final _api = ApiClient.instance;

  Future<OrderGroup> create({
    required String shopId,
    String paymentMode = 'split',
    int? maxMembers,
    int? expiresInMin,
  }) async {
    final res = await _api.post('/api/order-groups', {
      'shopId': shopId,
      'paymentMode': paymentMode,
      if (maxMembers != null) 'maxMembers': maxMembers,
      if (expiresInMin != null) 'expiresInMin': expiresInMin,
    });
    return OrderGroup.fromJson(_unwrap(res.data));
  }

  Future<OrderGroup> join(String joinCode) async {
    final res = await _api.post('/api/order-groups/join', {
      'joinCode': joinCode,
    });
    return OrderGroup.fromJson(_unwrap(res.data));
  }

  Future<List<OrderGroup>> myGroups() async {
    final res = await _api.get('/api/order-groups/me');
    final data = res.data;
    final list = data is List
        ? data
        : (data is Map && data['groups'] is List
            ? data['groups'] as List
            : const <dynamic>[]);
    return list
        .map((g) => OrderGroup.fromJson(Map<String, dynamic>.from(g as Map)))
        .toList();
  }

  Future<OrderGroup> getById(String id) async {
    final res = await _api.get('/api/order-groups/$id');
    return OrderGroup.fromJson(_unwrap(res.data));
  }

  Future<OrderGroupMember> setMyCart(
    String groupId,
    List<Map<String, dynamic>> cartJson,
  ) async {
    final res = await _api.patch('/api/order-groups/$groupId/me/cart', {
      'cartJson': cartJson,
    });
    final data = res.data;
    final m = data is Map && data['member'] is Map
        ? Map<String, dynamic>.from(data['member'] as Map)
        : Map<String, dynamic>.from(data as Map);
    return OrderGroupMember.fromJson(m);
  }

  Future<OrderGroup> lock(String groupId) async {
    final res = await _api.post('/api/order-groups/$groupId/lock');
    return OrderGroup.fromJson(_unwrap(res.data));
  }

  Future<void> payMyShare(String groupId, String paymentMethodId) async {
    await _api.post('/api/order-groups/$groupId/me/pay', {
      'paymentMethodId': paymentMethodId,
    });
  }

  Future<void> hostPay(String groupId, String paymentMethodId) async {
    await _api.post('/api/order-groups/$groupId/host-pay', {
      'paymentMethodId': paymentMethodId,
    });
  }

  Future<void> cancel(String groupId) async {
    await _api.post('/api/order-groups/$groupId/cancel');
  }

  Future<void> leave(String groupId) async {
    await _api.post('/api/order-groups/$groupId/leave');
  }

  /// Backend may wrap the entity under `group`/`orderGroup` or return it bare.
  /// The non-Map fallback used to be `Map.from(data as Map)` which throws a
  /// raw TypeError on error/HTML responses; surface a descriptive
  /// FormatException instead so the UI can show the actual problem.
  Map<String, dynamic> _unwrap(dynamic data) {
    if (data is Map) {
      if (data['group'] is Map) {
        return Map<String, dynamic>.from(data['group'] as Map);
      }
      if (data['orderGroup'] is Map) {
        return Map<String, dynamic>.from(data['orderGroup'] as Map);
      }
      return Map<String, dynamic>.from(data);
    }
    throw FormatException(
      'OrderGroup API: expected a JSON object, got ${data.runtimeType}: $data',
    );
  }
}

class OrderGroup {
  final String id;
  final String hostUserId;
  final String shopId;
  final String? shopName;
  final String joinCode;
  final String status; // open | locked | paid | cancelled | expired
  final String paymentMode; // split | host
  final int? maxMembers;
  final DateTime expiresAt;
  final DateTime? lockedAt;
  final DateTime? paidAt;
  final DateTime? cancelledAt;
  final String? orderId;
  final List<OrderGroupMember> members;

  const OrderGroup({
    required this.id,
    required this.hostUserId,
    required this.shopId,
    this.shopName,
    required this.joinCode,
    required this.status,
    required this.paymentMode,
    this.maxMembers,
    required this.expiresAt,
    this.lockedAt,
    this.paidAt,
    this.cancelledAt,
    this.orderId,
    this.members = const [],
  });

  bool isHost(String userId) => userId == hostUserId;

  bool get isOpen => status == 'open';
  bool get isLocked => status == 'locked';
  bool get isPaid => status == 'paid';
  bool get isCancelled => status == 'cancelled';
  bool get isExpired => status == 'expired';
  bool get isTerminal => isPaid || isCancelled || isExpired;

  factory OrderGroup.fromJson(Map<String, dynamic> j) {
    DateTime? parse(String key) {
      final raw = j[key];
      if (raw == null || raw is! String || raw.isEmpty) return null;
      return DateTime.tryParse(raw);
    }

    final shopMap = j['shop'] is Map
        ? Map<String, dynamic>.from(j['shop'] as Map)
        : null;

    final members = (j['members'] as List? ?? const [])
        .map((m) =>
            OrderGroupMember.fromJson(Map<String, dynamic>.from(m as Map)))
        .toList();

    return OrderGroup(
      id: j['id'] as String,
      hostUserId: j['hostUserId'] as String? ?? '',
      shopId: j['shopId'] as String? ?? shopMap?['id'] as String? ?? '',
      shopName: shopMap?['name'] as String?,
      joinCode: j['joinCode'] as String? ?? '',
      status: j['status'] as String? ?? 'open',
      paymentMode: j['paymentMode'] as String? ?? 'split',
      maxMembers: (j['maxMembers'] as num?)?.toInt(),
      expiresAt:
          parse('expiresAt') ?? DateTime.now().add(const Duration(hours: 1)),
      lockedAt: parse('lockedAt'),
      paidAt: parse('paidAt'),
      cancelledAt: parse('cancelledAt'),
      orderId: j['orderId'] as String?,
      members: members,
    );
  }
}

class OrderGroupMember {
  final String userId;
  final String? userName;
  final String status; // joined | ready | paid | left
  final List<dynamic> cartJson;
  final num amountOwed;
  final DateTime joinedAt;
  final DateTime? paidAt;

  const OrderGroupMember({
    required this.userId,
    this.userName,
    required this.status,
    required this.cartJson,
    required this.amountOwed,
    required this.joinedAt,
    this.paidAt,
  });

  bool get isPaid => status == 'paid';
  bool get isLeft => status == 'left';

  /// Total quantity in this member's cart (sums `quantity` keys).
  int get itemCount {
    var c = 0;
    for (final item in cartJson) {
      if (item is Map) {
        final q = item['quantity'];
        if (q is num) c += q.toInt();
      }
    }
    return c;
  }

  factory OrderGroupMember.fromJson(Map<String, dynamic> j) {
    DateTime? parse(String key) {
      final raw = j[key];
      if (raw == null || raw is! String || raw.isEmpty) return null;
      return DateTime.tryParse(raw);
    }

    final user = j['user'] is Map
        ? Map<String, dynamic>.from(j['user'] as Map)
        : null;

    return OrderGroupMember(
      userId: j['userId'] as String? ?? user?['id'] as String? ?? '',
      userName: j['userName'] as String? ?? user?['name'] as String?,
      status: j['status'] as String? ?? 'joined',
      cartJson:
          (j['cartJson'] as List?)?.toList() ?? const <dynamic>[],
      amountOwed: (j['amountOwed'] as num?) ?? 0,
      joinedAt: parse('joinedAt') ?? DateTime.now(),
      paidAt: parse('paidAt'),
    );
  }
}
