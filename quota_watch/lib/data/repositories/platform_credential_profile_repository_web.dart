import 'package:http/http.dart' as http;

import 'credential_profile_repository.dart';

CredentialProfileStore createPlatformCredentialProfileRepository({
  required http.Client client,
  required String baseUrl,
}) {
  return CredentialProfileRepository(client: client, baseUrl: baseUrl);
}
