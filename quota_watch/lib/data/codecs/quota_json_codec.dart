import 'dart:convert';

import '../models/quota_models.dart';

// Fixture 文件和 HTTP 响应共用同一个 JSON 解码入口，避免两套映射规则漂移。
class QuotaJsonCodec {
  const QuotaJsonCodec._();

  static List<ProviderQuota> decodeList(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! List) {
      throw const FormatException('额度 JSON 的根节点必须是数组');
    }

    return decoded.map((item) {
      if (item is! Map<String, dynamic>) {
        throw const FormatException('额度 JSON 的每一项都必须是对象');
      }
      return ProviderQuota.fromJson(item);
    }).toList();
  }
}
