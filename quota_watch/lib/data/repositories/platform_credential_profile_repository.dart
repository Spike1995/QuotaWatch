import 'package:http/http.dart' as http;

import 'credential_profile_repository.dart';
import 'platform_credential_profile_repository_web.dart'
    if (dart.library.io) 'platform_credential_profile_repository_io.dart'
    as implementation;

CredentialProfileStore createPlatformCredentialProfileRepository({
  required http.Client client,
  required String baseUrl,
}) {
  return implementation.createPlatformCredentialProfileRepository(
    client: client,
    baseUrl: baseUrl,
  );
}
