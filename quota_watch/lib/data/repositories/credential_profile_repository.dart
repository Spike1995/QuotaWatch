import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/credential_profile.dart';
import '../models/quota_models.dart';
import 'backend_endpoint_policy.dart';

class CredentialProfileRepository {
  final http.Client client;
  final String baseUrl;
  final Duration timeout;

  const CredentialProfileRepository({
    required this.client,
    required this.baseUrl,
    this.timeout = const Duration(seconds: 10),
  });

  Future<List<CredentialProfileSummary>> all() async {
    final response = await _send(
      () => client.get(
        _endpoint(),
        headers: const {'Accept': 'application/json'},
      ),
    );
    final decoded = _decodeJson(response);
    if (decoded is! List) {
      throw const CredentialProfileException('配置状态格式不正确');
    }
    try {
      return decoded.map((item) {
        if (item is! Map<String, dynamic>) {
          throw const FormatException('配置项必须是对象');
        }
        return CredentialProfileSummary.fromJson(item);
      }).toList();
    } on Object {
      throw const CredentialProfileException('配置状态格式不正确');
    }
  }

  Future<CredentialProfileSummary> saveApiKey({
    required Provider provider,
    required String label,
    required String apiKey,
  }) {
    if (provider == Provider.codex) {
      throw const CredentialProfileException('Codex 不接受手动 Token');
    }
    return _save(
      provider,
      <String, Object?>{
        'label': label,
        'apiKey': apiKey,
      },
    );
  }

  Future<CredentialProfileSummary> saveCodexNote({
    required String label,
    required int? resetCount,
    required DateTime? resetExpiresAt,
  }) {
    return _save(
      Provider.codex,
      <String, Object?>{
        'label': label,
        'resetCount': resetCount,
        'resetExpiresAt': resetExpiresAt?.toUtc().toIso8601String(),
      },
    );
  }

  Future<CredentialProfileSummary> delete(Provider provider) async {
    final response = await _send(
      () => client.delete(
        _endpoint(provider),
        headers: const {'Accept': 'application/json'},
      ),
    );
    return _decodeSummary(response);
  }

  Future<CredentialProfileSummary> _save(
    Provider provider,
    Map<String, Object?> payload,
  ) async {
    final response = await _send(
      () => client.put(
        _endpoint(provider),
        headers: const {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(payload),
      ),
    );
    return _decodeSummary(response);
  }

  Future<http.Response> _send(
    Future<http.Response> Function() request,
  ) async {
    final http.Response response;
    try {
      response = await request().timeout(timeout);
    } on TimeoutException {
      throw const CredentialProfileException('安全配置请求超时');
    } on http.ClientException {
      throw const CredentialProfileException('无法连接本机后端');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CredentialProfileException(_readServerError(response));
    }
    return response;
  }

  CredentialProfileSummary _decodeSummary(http.Response response) {
    final decoded = _decodeJson(response);
    if (decoded is! Map<String, dynamic>) {
      throw const CredentialProfileException('配置状态格式不正确');
    }
    try {
      return CredentialProfileSummary.fromJson(decoded);
    } on Object {
      throw const CredentialProfileException('配置状态格式不正确');
    }
  }

  Object? _decodeJson(http.Response response) {
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } on Object {
      throw const CredentialProfileException('后端返回的数据格式不正确');
    }
  }

  String _readServerError(http.Response response) {
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, dynamic>) {
        final detail = decoded['detail'];
        if (detail is Map<String, dynamic> && detail['message'] is String) {
          return detail['message'] as String;
        }
      }
    } on Object {
      // 不回显非 JSON 错误页或原始响应。
    }
    return '安全配置失败（HTTP ${response.statusCode}）';
  }

  Uri _endpoint([Provider? provider]) {
    final base = Uri.tryParse(baseUrl.trim());
    if (base == null || !isLoopbackBackendUrl(baseUrl)) {
      throw const CredentialProfileException(
        '安全配置只允许连接本机 127.0.0.1/localhost',
      );
    }
    final path = provider == null
        ? '/api/v1/credential-profiles'
        : '/api/v1/credential-profiles/${provider.name}';
    return base.resolve(path);
  }
}

class CredentialProfileException implements Exception {
  final String message;

  const CredentialProfileException(this.message);

  @override
  String toString() => message;
}
