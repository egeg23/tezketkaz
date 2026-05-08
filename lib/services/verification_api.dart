import 'dart:io';

import 'package:dio/dio.dart';
import 'api_client.dart';

/// Phase 6 — courier KYC document upload API.
///
/// Endpoints:
///   GET    /api/verification/me       → list of own documents
///   POST   /api/verification/upload   → multipart {type, file}
///   DELETE /api/verification/:id
class VerificationApi {
  VerificationApi._();
  static final VerificationApi instance = VerificationApi._();

  final _api = ApiClient.instance;

  Future<List<VerificationDocument>> myDocs() async {
    final res = await _api.get('/api/verification/me');
    final raw = res.data;
    final list = raw is Map
        ? (raw['documents'] ?? raw['docs'] ?? raw['data'] ?? const [])
        : (raw ?? const []);
    if (list is! List) return const [];
    return list
        .map((d) => VerificationDocument.fromJson(
              d is Map ? Map<String, dynamic>.from(d) : <String, dynamic>{},
            ))
        .toList();
  }

  Future<VerificationDocument> upload(String type, File file) async {
    // Strip both POSIX and Windows separators so the filename is sane on
    // every platform without depending on Platform.pathSeparator.
    final filename = file.path.split(RegExp(r'[\\/]+')).last;
    final formData = FormData.fromMap({
      'type': type,
      'file': await MultipartFile.fromFile(file.path, filename: filename),
    });
    final res = await _api.postMultipart('/api/verification/upload', formData);
    final raw = res.data;
    final doc = raw is Map ? (raw['document'] ?? raw['doc'] ?? raw) : raw;
    return VerificationDocument.fromJson(
      doc is Map ? Map<String, dynamic>.from(doc) : <String, dynamic>{},
    );
  }

  Future<void> delete(String id) async {
    await _api.delete('/api/verification/$id');
  }
}

/// Document types known to the courier verification flow. The backend may
/// accept additional types — we just round-trip the string.
class VerificationDocType {
  static const passportFront = 'passport_front';
  static const passportBack = 'passport_back';
  static const selfie = 'selfie';
  static const selfEmployedCert = 'self_employed_cert';

  static const all = <String>[
    passportFront,
    passportBack,
    selfie,
    selfEmployedCert,
  ];
}

class VerificationDocument {
  final String id;
  final String type;
  final String url;
  final String status; // pending | approved | rejected
  final String? rejectionReason;

  const VerificationDocument({
    required this.id,
    required this.type,
    required this.url,
    required this.status,
    this.rejectionReason,
  });

  factory VerificationDocument.fromJson(Map<String, dynamic> json) {
    return VerificationDocument(
      id: (json['id'] ?? '').toString(),
      type: (json['type'] ?? '').toString(),
      url: (json['url'] ?? json['fileUrl'] ?? '').toString(),
      status: (json['status'] ?? 'pending').toString(),
      rejectionReason: json['rejectionReason'] as String?,
    );
  }

  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';
  bool get isPending => status == 'pending';
}
