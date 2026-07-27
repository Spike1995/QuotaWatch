// ============================================================================
// quota_repository.dart - 额度数据来源的最小接口
// ============================================================================
//
// Repository 是“数据仓库”的抽象：页面只约定如何取数据，不关心数据来自
// Mock、JSON 文件还是 HTTP 后端。这样替换数据来源时，页面可以保持不动。
//
// ============================================================================

import '../models/quota_models.dart';

// `abstract class` 只定义合同，不直接提供具体数据。
// 任何实现这个接口的类都必须提供 all() 方法。
abstract class QuotaRepository {
  // Future 表示数据可能稍后才返回。本地文件和后续 HTTP 请求都需要等待，
  // 所以页面从现在开始统一使用异步接口。
  Future<List<ProviderQuota>> all();
}

// 数据层统一抛出这个异常，页面不需要识别 http.ClientException 等底层类型。
class QuotaRepositoryException implements Exception {
  final String message;
  final int? statusCode;

  const QuotaRepositoryException(this.message, {this.statusCode});

  @override
  String toString() => message;
}
