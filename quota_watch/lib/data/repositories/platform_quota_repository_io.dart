import 'dart:io';

import 'package:http/http.dart' as http;

import '../../app/desktop/window_native_io.dart';
import 'all_real_quota_repository.dart';
import 'backend_quota_repository.dart';
import 'codex_quota_repository.dart';
import 'glm_quota_repository.dart';
import 'kimi_quota_repository.dart';
import 'quota_repository.dart';
import 'windows_credential_profile_repository.dart';

QuotaRepository createPlatformQuotaRepository({
  required http.Client client,
  required String baseUrl,
  required String scenario,
}) {
  String? environmentKey(String name) {
    final value = Platform.environment[name]?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  Future<String?> kimiKey() async {
    return environmentKey('QUOTA_WATCH_KIMI_API_KEY') ??
        await WindowNative.readProviderApiKey('kimi');
  }

  Future<String?> glmKey() async {
    return environmentKey('QUOTA_WATCH_GLM_API_KEY') ??
        await WindowNative.readProviderApiKey('glm');
  }

  if (Platform.isWindows && scenario == 'all_real') {
    final codex = CodexQuotaRepository();
    final kimi = KimiQuotaRepository(
      client: client,
      apiKeyResolver: kimiKey,
    );
    final glm = GlmQuotaRepository(
      client: client,
      apiKeyResolver: glmKey,
    );
    final profiles = WindowsCredentialProfileRepository.production();
    return AllRealQuotaRepository(
      fetchCodex: codex.fetchOne,
      fetchKimi: kimi.fetchOne,
      fetchGlm: glm.fetchOne,
      resolveCodexResetAllowance: profiles.resolveCodexResetAllowance,
    );
  }
  if (Platform.isWindows && scenario == 'codex_real') {
    return CodexQuotaRepository();
  }
  if (Platform.isWindows && scenario == 'kimi_real') {
    return KimiQuotaRepository(
      client: client,
      apiKeyResolver: kimiKey,
    );
  }
  if (Platform.isWindows && scenario == 'glm_real') {
    return GlmQuotaRepository(
      client: client,
      apiKeyResolver: glmKey,
    );
  }
  return BackendQuotaRepository(
    client: client,
    baseUrl: baseUrl,
    scenario: scenario,
  );
}
