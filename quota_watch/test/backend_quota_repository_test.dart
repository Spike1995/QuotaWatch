import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:quota_watch/data/models/quota_models.dart';
import 'package:quota_watch/data/repositories/backend_quota_repository.dart';
import 'package:quota_watch/data/repositories/quota_repository.dart';

void main() {
  test('HTTP 200 会解析统一额度 JSON', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/api/v1/quotas');
      expect(request.url.queryParameters['scenario'], 'partial');
      return http.Response.bytes(
        utf8.encode(
          '[{"provider":"codex","planName":"中文测试套餐",'
          '"status":"ok","windows":[]}]',
        ),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final repository = BackendQuotaRepository(
      client: client,
      baseUrl: 'http://127.0.0.1:8000',
      scenario: 'partial',
    );

    final quotas = await repository.all();

    expect(quotas, hasLength(1));
    expect(quotas.single.provider, Provider.codex);
    expect(quotas.single.planName, '中文测试套餐');
  });

  test('结构化 HTTP 错误会保留安全提示', () async {
    final client = MockClient((_) async {
      return http.Response.bytes(
        utf8.encode(
          '{"detail":{"code":"simulated_backend_failure",'
          '"message":"模拟后端暂时不可用"}}',
        ),
        503,
        headers: {'content-type': 'application/json'},
      );
    });
    final repository = BackendQuotaRepository(
      client: client,
      baseUrl: 'http://127.0.0.1:8000',
      scenario: 'server_error',
    );

    expect(
      repository.all,
      throwsA(
        isA<QuotaRepositoryException>()
            .having((error) => error.message, 'message', '模拟后端暂时不可用')
            .having((error) => error.statusCode, 'statusCode', 503),
      ),
    );
  });

  test('损坏 JSON 转换为统一数据错误', () async {
    final client = MockClient((_) async => http.Response('{broken', 200));
    final repository = BackendQuotaRepository(
      client: client,
      baseUrl: 'http://127.0.0.1:8000',
      scenario: 'normal',
    );

    expect(
      repository.all,
      throwsA(
        isA<QuotaRepositoryException>().having(
          (error) => error.message,
          'message',
          '后端返回的数据格式不正确',
        ),
      ),
    );
  });

  test('连接失败转换为可操作提示', () async {
    final client = MockClient((_) async {
      throw http.ClientException('offline');
    });
    final repository = BackendQuotaRepository(
      client: client,
      baseUrl: 'http://127.0.0.1:8000',
      scenario: 'normal',
    );

    expect(
      repository.all,
      throwsA(
        isA<QuotaRepositoryException>().having(
          (error) => error.message,
          'message',
          contains('无法连接本地后端'),
        ),
      ),
    );
  });

  test('请求超时转换为可操作提示', () async {
    final completer = Completer<http.Response>();
    final client = MockClient((_) => completer.future);
    final repository = BackendQuotaRepository(
      client: client,
      baseUrl: 'http://127.0.0.1:8000',
      scenario: 'normal',
      timeout: const Duration(milliseconds: 1),
    );

    expect(
      repository.all,
      throwsA(
        isA<QuotaRepositoryException>().having(
          (error) => error.message,
          'message',
          contains('请求超时'),
        ),
      ),
    );
  });
}
