import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../codecs/quota_json_codec.dart';
import '../models/quota_models.dart';
import 'backend_endpoint_policy.dart';
import 'quota_repository.dart';

class BackendQuotaRepository implements QuotaRepository {
  final http.Client client;
  final String baseUrl;
  final String scenario;
  final Duration timeout;

  const BackendQuotaRepository({
    required this.client,
    required this.baseUrl,
    required this.scenario,
    // 必须长过后端最坏情况：Codex app-server 冷启动实测可达 15 秒以上，
    // 5 秒会在真实额度场景下误报超时；30 秒仍有界，不会无限等待。
    this.timeout = const Duration(seconds: 30),
  });

  @override
  Future<List<ProviderQuota>> all() async {
    final endpoint = _buildEndpoint();
    final http.Response response;

    try {
      response = await client.get(
        endpoint,
        headers: const {'Accept': 'application/json'},
      ).timeout(timeout);
    } on TimeoutException {
      throw const QuotaRepositoryException('本地后端请求超时，请确认服务正在运行');
    } on http.ClientException {
      throw const QuotaRepositoryException('无法连接本地后端，请确认地址和服务状态');
    }

    if (response.statusCode != 200) {
      throw QuotaRepositoryException(
        _readServerError(response),
        statusCode: response.statusCode,
      );
    }

    try {
      return QuotaJsonCodec.decodeList(_decodeUtf8(response));
    } on Object {
      throw const QuotaRepositoryException('后端返回的数据格式不正确');
    }
  }

  Uri _buildEndpoint() {
    final base = Uri.tryParse(baseUrl.trim());
    if (base == null || !isAllowedBackendUrl(baseUrl)) {
      throw const QuotaRepositoryException(
        '后端地址必须使用 HTTPS；仅本机 127.0.0.1/localhost 可使用 HTTP',
      );
    }
    return base.resolve('/api/v1/quotas').replace(
      queryParameters: {'scenario': scenario},
    );
  }

  String _readServerError(http.Response response) {
    try {
      final decoded = jsonDecode(_decodeUtf8(response));
      if (decoded is Map<String, dynamic>) {
        final detail = decoded['detail'];
        if (detail is Map<String, dynamic> && detail['message'] is String) {
          return detail['message'] as String;
        }
        if (detail is String) return detail;
      }
    } on FormatException {
      // 非 JSON 错误页不回显给 UI，只保留安全的状态码提示。
    }
    return '本地后端返回错误（HTTP ${response.statusCode}）';
  }

  String _decodeUtf8(http.Response response) {
    return utf8.decode(response.bodyBytes);
  }
}
