import 'dart:async';
import 'dart:convert';
import 'dart:io';

class GoEngineProcess {
  static const int defaultPort = 45822;

  static final GoEngineProcess instance = GoEngineProcess();

  final int port;
  final String? executablePathOverride;

  Process? _process;
  bool _isRunning = false;
  Future<bool>? _startingFuture;

  GoEngineProcess({
    this.port = defaultPort,
    this.executablePathOverride,
  });

  bool get isRunning => _isRunning;

  String get baseUrl => 'http://127.0.0.1:$port';

  Future<bool> checkHealth({
    Duration timeout = const Duration(milliseconds: 500),
  }) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client
          .getUrl(Uri.parse('$baseUrl/health'))
          .timeout(timeout);
      final response = await request.close().timeout(timeout);
      if (response.statusCode != 200) {
        await response.drain<void>();
        return false;
      }
      final body = await utf8.decoder.bind(response).join().timeout(timeout);
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> && decoded['ok'] == true;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  Future<bool> ensureStarted({
    Duration timeout = const Duration(seconds: 4),
  }) {
    if (_isRunning) {
      return Future<bool>.value(true);
    }
    return _startingFuture ??= _startInternal(timeout).whenComplete(() {
      _startingFuture = null;
    });
  }

  Future<bool> _startInternal(Duration timeout) async {
    if (await checkHealth()) {
      _isRunning = true;
      return true;
    }

    final exePath = await _locateExecutable();
    if (exePath == null) {
      _isRunning = false;
      return false;
    }

    try {
      final proc = await Process.start(
        exePath,
        ['-port', '$port'],
        runInShell: false,
      );
      _process = proc;

      // Drain stdout/stderr so child process never blocks on full OS pipe buffers.
      proc.stdout.drain<void>();
      proc.stderr.drain<void>();

      unawaited(
        proc.exitCode.then((_) {
          if (identical(_process, proc)) {
            _process = null;
            _isRunning = false;
          }
        }),
      );

      final deadline = DateTime.now().add(timeout);
      while (DateTime.now().isBefore(deadline)) {
        if (await checkHealth(timeout: const Duration(milliseconds: 250))) {
          _isRunning = true;
          return true;
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    } catch (_) {
      _isRunning = false;
    }

    return false;
  }

  Future<String?> _locateExecutable() async {
    final binaryName = Platform.isWindows ? 'dm_engine.exe' : 'dm_engine';
    final candidates = <String>[];

    if (executablePathOverride != null && executablePathOverride!.isNotEmpty) {
      candidates.add(executablePathOverride!);
    }

    final exeDir = File(Platform.resolvedExecutable).parent.path;
    candidates.add('$exeDir${Platform.pathSeparator}$binaryName');

    final cwd = Directory.current.path;
    candidates.add(
      '$cwd${Platform.pathSeparator}go_backend${Platform.pathSeparator}$binaryName',
    );
    candidates.add('$cwd${Platform.pathSeparator}$binaryName');

    // Walk up from resolved executable (e.g., build/windows/x64/runner/Debug/)
    // to locate project root's go_backend/dm_engine.exe during development.
    Directory cursor = File(Platform.resolvedExecutable).parent;
    for (int i = 0; i < 7; i++) {
      candidates.add(
        '${cursor.path}${Platform.pathSeparator}go_backend${Platform.pathSeparator}$binaryName',
      );
      final parent = cursor.parent;
      if (parent.path == cursor.path) break;
      cursor = parent;
    }

    for (final path in candidates) {
      if (await File(path).exists()) {
        return path;
      }
    }
    return null;
  }

  Future<void> stop() async {
    final proc = _process;
    _isRunning = false;

    final client = HttpClient()
      ..connectionTimeout = const Duration(milliseconds: 400);
    try {
      final request = await client
          .postUrl(Uri.parse('$baseUrl/shutdown'))
          .timeout(const Duration(milliseconds: 400));
      final response = await request.close().timeout(
        const Duration(milliseconds: 400),
      );
      await response.drain<void>();
    } catch (_) {
    } finally {
      client.close(force: true);
    }

    if (proc != null) {
      try {
        await proc.exitCode.timeout(const Duration(milliseconds: 800));
      } catch (_) {
        proc.kill();
      }
      if (identical(_process, proc)) {
        _process = null;
      }
    }
  }
}
