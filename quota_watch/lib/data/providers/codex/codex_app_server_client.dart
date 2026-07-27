import 'dart:async';
import 'dart:convert';
import 'dart:io';

enum CodexClientFailure {
  authentication,
  rateLimit,
  contract,
  timeout,
  connection,
}

class CodexClientException implements Exception {
  const CodexClientException(this.failure);

  final CodexClientFailure failure;

  String get userMessage => switch (failure) {
        CodexClientFailure.authentication => '需要重新登录或检查凭据',
        CodexClientFailure.rateLimit => '查询过于频繁，请稍后重试',
        CodexClientFailure.contract => '服务商接口可能已变化',
        CodexClientFailure.timeout => '查询超时',
        CodexClientFailure.connection => '无法连接到服务商',
      };
}

abstract interface class CodexRateLimitsClient {
  Future<Map<String, dynamic>> readRateLimits();
}

class CodexAppServerClient implements CodexRateLimitsClient {
  CodexAppServerClient({
    List<String>? command,
    this.timeout = const Duration(seconds: 15),
    Map<String, String>? environment,
  })  : _command = command == null ? null : List.unmodifiable(command),
        _environment = environment;

  static const int maxJsonLineBytes = 1024 * 1024;

  final List<String>? _command;
  final Duration timeout;
  final Map<String, String>? _environment;

  @override
  Future<Map<String, dynamic>> readRateLimits() async {
    if (timeout <= Duration.zero) {
      throw const CodexClientException(CodexClientFailure.timeout);
    }
    final command = _command ?? resolveCodexCommand(environment: _environment);
    if (command.isEmpty) {
      throw const CodexClientException(CodexClientFailure.connection);
    }

    final Process process;
    try {
      process = await Process.start(
        command.first,
        [
          ...command.skip(1),
          'app-server',
          '--listen',
          'stdio://',
        ],
        runInShell: false,
        mode: ProcessStartMode.normal,
      );
    } on ProcessException {
      throw const CodexClientException(CodexClientFailure.connection);
    } on OSError {
      throw const CodexClientException(CodexClientFailure.connection);
    }

    // Drain and discard stderr. Never decode, retain, print, or surface it.
    unawaited(process.stderr.drain<void>());
    final reader = _BoundedJsonLineReader(
      process.stdout,
      maxBytes: maxJsonLineBytes,
    );
    try {
      await _request(
        process,
        reader,
        id: 1,
        method: 'initialize',
        params: const {
          'clientInfo': {
            'name': 'quota_watch_local',
            'title': 'Quota Watch Local',
            'version': '0.1.0',
          },
        },
      );
      await _writeMessage(process, const {'method': 'initialized'});
      return await _request(
        process,
        reader,
        id: 2,
        method: 'account/rateLimits/read',
      );
    } on TimeoutException {
      throw const CodexClientException(CodexClientFailure.timeout);
    } on CodexClientException {
      rethrow;
    } on Object {
      throw const CodexClientException(CodexClientFailure.connection);
    } finally {
      await reader.cancel();
      await _closeProcess(process);
    }
  }

  Future<Map<String, dynamic>> _request(
    Process process,
    _BoundedJsonLineReader reader, {
    required int id,
    required String method,
    Object? params = _missing,
  }) async {
    final message = <String, Object?>{'id': id, 'method': method};
    if (!identical(params, _missing)) message['params'] = params;
    await _writeMessage(process, message);

    return _waitForResponse(reader, id).timeout(timeout);
  }

  Future<Map<String, dynamic>> _waitForResponse(
    _BoundedJsonLineReader reader,
    int id,
  ) async {
    while (true) {
      final raw = await reader.nextLine();
      if (raw == null) {
        throw const CodexClientException(CodexClientFailure.connection);
      }
      final Object? decoded;
      try {
        decoded = jsonDecode(utf8.decode(raw));
      } on Object {
        throw const CodexClientException(CodexClientFailure.contract);
      }
      if (decoded is! Map<String, dynamic>) {
        throw const CodexClientException(CodexClientFailure.contract);
      }
      if (decoded['id'] != id) continue;
      if (decoded.containsKey('error')) {
        throw _mapRpcError(decoded['error']);
      }
      final result = decoded['result'];
      if (result is! Map<String, dynamic>) {
        throw const CodexClientException(CodexClientFailure.contract);
      }
      return result;
    }
  }

  Future<void> _writeMessage(
    Process process,
    Map<String, Object?> message,
  ) async {
    try {
      process.stdin
        ..add(utf8.encode(jsonEncode(message)))
        ..add(const [10]);
      await process.stdin.flush();
    } on Object {
      throw const CodexClientException(CodexClientFailure.connection);
    }
  }
}

const Object _missing = Object();

List<String> resolveCodexCommand({
  Map<String, String>? environment,
  bool Function(String path)? fileExists,
}) {
  final source = environment ?? Platform.environment;
  final exists = fileExists ?? ((path) => File(path).existsSync());
  final override = source['QUOTA_WATCH_CODEX_COMMAND']?.trim() ?? '';
  if (override.isNotEmpty) {
    if (!_isAbsolutePath(override) || !exists(override)) {
      throw const CodexClientException(CodexClientFailure.connection);
    }
    return [override];
  }

  final localAppData = source['LOCALAPPDATA']?.trim() ?? '';
  if (localAppData.isNotEmpty) {
    final bundled = '$localAppData${Platform.pathSeparator}OpenAI'
        '${Platform.pathSeparator}Codex${Platform.pathSeparator}bin'
        '${Platform.pathSeparator}codex.exe';
    if (exists(bundled)) return [bundled];
  }

  final pathValue = source['PATH'] ?? '';
  for (final directory in pathValue.split(Platform.isWindows ? ';' : ':')) {
    final trimmed = directory.trim();
    if (trimmed.isEmpty) continue;
    for (final fileName
        in Platform.isWindows ? const ['codex.exe'] : const ['codex']) {
      final candidate = '$trimmed${Platform.pathSeparator}$fileName';
      if (exists(candidate)) return [candidate];
    }
  }
  throw const CodexClientException(CodexClientFailure.connection);
}

bool _isAbsolutePath(String path) {
  if (Platform.isWindows) {
    return RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path) || path.startsWith(r'\\');
  }
  return path.startsWith('/');
}

CodexClientException _mapRpcError(Object? rawError) {
  String text;
  try {
    text = jsonEncode(rawError).toLowerCase();
  } on Object {
    text = '';
  }
  if (const [
    'not logged in',
    'authentication',
    'unauthorized',
    'openai auth',
    'login required',
  ].any(text.contains)) {
    return const CodexClientException(CodexClientFailure.authentication);
  }
  if (text.contains('429') || text.contains('rate limit')) {
    return const CodexClientException(CodexClientFailure.rateLimit);
  }
  if (text.contains('not initialized') || text.contains('method not found')) {
    return const CodexClientException(CodexClientFailure.contract);
  }
  return const CodexClientException(CodexClientFailure.connection);
}

Future<void> _closeProcess(Process process) async {
  try {
    await process.stdin.close();
  } on Object {
    // The process may already have closed its input.
  }
  try {
    await process.exitCode.timeout(const Duration(milliseconds: 500));
    return;
  } on TimeoutException {
    process.kill();
  }
  try {
    await process.exitCode.timeout(const Duration(milliseconds: 500));
    return;
  } on TimeoutException {
    process.kill(ProcessSignal.sigkill);
  }
  try {
    await process.exitCode.timeout(const Duration(milliseconds: 500));
  } on TimeoutException {
    // Process.kill is best-effort on Windows; no raw process output is kept.
  }
}

class _BoundedJsonLineReader {
  _BoundedJsonLineReader(Stream<List<int>> stream, {required this.maxBytes})
      : _iterator = StreamIterator(stream);

  final int maxBytes;
  final StreamIterator<List<int>> _iterator;
  final List<int> _buffer = [];

  Future<List<int>?> nextLine() async {
    while (true) {
      final newline = _buffer.indexOf(10);
      if (newline >= 0) {
        final line = _buffer.sublist(0, newline);
        _buffer.removeRange(0, newline + 1);
        if (line.isNotEmpty && line.last == 13) line.removeLast();
        if (line.length > maxBytes) {
          throw const CodexClientException(CodexClientFailure.contract);
        }
        return line;
      }
      if (_buffer.length > maxBytes) {
        throw const CodexClientException(CodexClientFailure.contract);
      }
      if (!await _iterator.moveNext()) {
        if (_buffer.isEmpty) return null;
        final line = List<int>.of(_buffer);
        _buffer.clear();
        if (line.length > maxBytes) {
          throw const CodexClientException(CodexClientFailure.contract);
        }
        return line;
      }
      _buffer.addAll(_iterator.current);
    }
  }

  Future<void> cancel() => _iterator.cancel();
}
