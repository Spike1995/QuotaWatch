import 'package:http/http.dart' as http;

import 'quota_repository.dart';
import 'platform_quota_repository_web.dart'
    if (dart.library.io) 'platform_quota_repository_io.dart' as implementation;

QuotaRepository createPlatformQuotaRepository({
  required http.Client client,
  required String baseUrl,
  required String scenario,
}) {
  return implementation.createPlatformQuotaRepository(
    client: client,
    baseUrl: baseUrl,
    scenario: scenario,
  );
}
