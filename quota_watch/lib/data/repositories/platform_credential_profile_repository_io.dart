import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'credential_profile_repository.dart';
import 'windows_credential_profile_repository.dart';

CredentialProfileStore createPlatformCredentialProfileRepository({
  required http.Client client,
  required String baseUrl,
}) {
  const forceNative = bool.fromEnvironment('QUOTA_NATIVE_PROVIDERS');
  if (Platform.isWindows && (!kDebugMode || forceNative)) {
    return WindowsCredentialProfileRepository.production();
  }
  return CredentialProfileRepository(client: client, baseUrl: baseUrl);
}
