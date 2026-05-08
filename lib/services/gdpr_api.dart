import 'api_client.dart';

/// Phase 9.1 — buyer data-export job.
///
/// Mirrors the row stored on the backend's `data_exports` table. Statuses
/// follow the lifecycle `pending → processing → ready → expired`.
class DataExport {
  final String id;
  final String status;
  final String? fileUrl;
  final DateTime? expiresAt;
  final DateTime? requestedAt;
  final DateTime? completedAt;

  const DataExport({
    required this.id,
    required this.status,
    this.fileUrl,
    this.expiresAt,
    this.requestedAt,
    this.completedAt,
  });

  bool get isReady => status == 'ready' && (fileUrl ?? '').isNotEmpty;
  bool get isPending => status == 'pending' || status == 'processing';
  bool get isExpired {
    if (status == 'expired') return true;
    final exp = expiresAt;
    return exp != null && exp.isBefore(DateTime.now());
  }

  factory DataExport.fromJson(Map<String, dynamic> j) => DataExport(
        id: j['id'] as String? ?? '',
        status: j['status'] as String? ?? 'pending',
        fileUrl: j['fileUrl'] as String?,
        expiresAt: _parseDate(j['expiresAt']),
        requestedAt: _parseDate(j['requestedAt']),
        completedAt: _parseDate(j['completedAt']),
      );
}

/// Phase 9.2 — pending account deletion. Statuses: `pending` (within the
/// 30-day grace window), `cancelled`, `completed`.
class AccountDeletionRequest {
  final String id;
  final String status;
  final DateTime requestedAt;
  final DateTime scheduledFor;
  final String? reason;

  const AccountDeletionRequest({
    required this.id,
    required this.status,
    required this.requestedAt,
    required this.scheduledFor,
    this.reason,
  });

  bool get isPending => status == 'pending';
  Duration get timeUntilDeletion =>
      scheduledFor.difference(DateTime.now());

  factory AccountDeletionRequest.fromJson(Map<String, dynamic> j) =>
      AccountDeletionRequest(
        id: j['id'] as String? ?? '',
        status: j['status'] as String? ?? 'pending',
        requestedAt:
            _parseDate(j['requestedAt']) ?? DateTime.now(),
        scheduledFor: _parseDate(j['scheduledFor']) ??
            DateTime.now().add(const Duration(days: 30)),
        reason: j['reason'] as String?,
      );
}

DateTime? _parseDate(dynamic v) {
  if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
  return null;
}

/// Wrapper around the GDPR endpoints exposed by Phase 9 backend Agent A.
class GdprApi {
  GdprApi._();
  static final GdprApi instance = GdprApi._();

  final _api = ApiClient.instance;

  /// Kick off a fresh export job. Returns the new row's id and status.
  Future<({String exportId, String status})> requestExport() async {
    final res = await _api.post('/api/users/me/export-data');
    final data = res.data;
    if (data is Map) {
      return (
        exportId: (data['exportId'] ?? data['id'] ?? '') as String,
        status: (data['status'] ?? 'pending') as String,
      );
    }
    return (exportId: '', status: 'pending');
  }

  Future<List<DataExport>> myExports() async {
    final res = await _api.get('/api/users/me/exports');
    final body = res.data;
    final List list = body is List
        ? body
        : (body is Map ? (body['exports'] as List? ?? const []) : const []);
    return list
        .whereType<Map>()
        .map((m) => DataExport.fromJson(Map<String, dynamic>.from(m)))
        .toList();
  }

  Future<DataExport> getExport(String id) async {
    final res = await _api.get('/api/users/me/exports/$id');
    final body = res.data;
    final map = body is Map && body['export'] is Map
        ? Map<String, dynamic>.from(body['export'] as Map)
        : Map<String, dynamic>.from(body as Map);
    return DataExport.fromJson(map);
  }

  Future<AccountDeletionRequest> requestAccountDeletion({
    String? reason,
  }) async {
    final res = await _api.post('/api/users/me/delete-account', {
      if (reason != null && reason.isNotEmpty) 'reason': reason,
    });
    final body = res.data;
    final map = body is Map && body['request'] is Map
        ? Map<String, dynamic>.from(body['request'] as Map)
        : Map<String, dynamic>.from(body as Map);
    return AccountDeletionRequest.fromJson(map);
  }

  Future<void> cancelAccountDeletion() async {
    await _api.post('/api/users/me/delete-account/cancel');
  }

  /// `null` when no pending deletion exists.
  Future<AccountDeletionRequest?> deletionStatus() async {
    final res = await _api.get('/api/users/me/deletion-status');
    final body = res.data;
    if (body == null) return null;
    if (body is Map && body.isEmpty) return null;
    Map? raw;
    if (body is Map && body['request'] is Map) {
      raw = body['request'] as Map;
    } else if (body is Map && body.containsKey('id')) {
      raw = body;
    }
    if (raw == null) return null;
    return AccountDeletionRequest.fromJson(Map<String, dynamic>.from(raw));
  }
}
