/// Shared client-side network boundary.
///
/// Remote quota backends can expose account usage, so only HTTPS is accepted.
/// Plain HTTP is limited to loopback for the bundled local backend and Android
/// `adb reverse` development path.
bool isLoopbackBackendUrl(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null) return false;
  final host = uri.host.toLowerCase();
  return host == 'localhost' || host == '::1' || _isIpv4Loopback(host);
}

bool isAllowedBackendUrl(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null || uri.host.isEmpty) return false;
  if (uri.scheme == 'https') return true;
  return uri.scheme == 'http' && isLoopbackBackendUrl(value);
}

bool _isIpv4Loopback(String host) {
  final octets = host.split('.');
  if (octets.length != 4 || octets.first != '127') return false;
  return octets.every((octet) {
    if (octet.isEmpty) return false;
    final value = int.tryParse(octet);
    return value != null && value >= 0 && value <= 255;
  });
}
