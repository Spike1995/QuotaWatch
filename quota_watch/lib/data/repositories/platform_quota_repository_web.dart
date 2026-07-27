import 'package:http/http.dart' as http;

import 'backend_quota_repository.dart';
import 'quota_repository.dart';

QuotaRepository createPlatformQuotaRepository({
  required http.Client client,
  required String baseUrl,
  required String scenario,
}) {
  return BackendQuotaRepository(
    client: client,
    baseUrl: baseUrl,
    scenario: scenario,
  );
}
