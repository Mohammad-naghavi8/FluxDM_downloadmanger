import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:download_manager/features/downloads/models/download_file_info.dart';
import 'package:download_manager/features/downloads/services/speed_limiter.dart';

class _FtpReply {
  final int code;
  final String message;

  const _FtpReply(this.code, this.message);
}

class _FtpControlConnection {
  final Socket socket;
  final StreamIterator<String> _lines;

  _FtpControlConnection._(this.socket, this._lines);

  static Future<_FtpControlConnection> connect(
    String host,
    int port, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final socket = await Socket.connect(host, port, timeout: timeout);
    final lineStream = socket
        .cast<List<int>>()
        .transform(const Latin1Decoder(allowInvalid: true))
        .transform(const LineSplitter());
    final iterator = StreamIterator<String>(lineStream);
    return _FtpControlConnection._(socket, iterator);
  }

  Future<_FtpReply> readReply() async {
    final buffer = StringBuffer();
    int? expectedCode;

    while (await _lines.moveNext()) {
      final line = _lines.current;
      if (buffer.isNotEmpty) buffer.writeln();
      buffer.write(line);

      if (line.length >= 4 &&
          _isThreeDigits(line.substring(0, 3)) &&
          expectedCode == null) {
        final code = int.parse(line.substring(0, 3));
        if (line[3] == ' ') {
          return _FtpReply(code, buffer.toString());
        }
        if (line[3] == '-') {
          expectedCode = code;
        }
      } else if (expectedCode != null &&
          line.length >= 4 &&
          line.startsWith('$expectedCode ')) {
        return _FtpReply(expectedCode, buffer.toString());
      } else if (line.length == 3 && _isThreeDigits(line)) {
        return _FtpReply(int.parse(line), buffer.toString());
      }
    }

    throw const HttpException('FTP control connection closed unexpectedly');
  }

  Future<_FtpReply> sendCommand(String command) async {
    socket.write('$command\r\n');
    await socket.flush();
    return readReply();
  }

  Future<void> close() async {
    try {
      await _lines.cancel();
    } catch (_) {}
    try {
      socket.destroy();
    } catch (_) {}
  }

  static bool _isThreeDigits(String s) {
    if (s.length != 3) return false;
    for (int i = 0; i < 3; i++) {
      final c = s.codeUnitAt(i);
      if (c < 48 || c > 57) return false;
    }
    return true;
  }
}

class FtpClientService {
  (String user, String pass) _credentialsFromUri(Uri uri) {
    if (uri.userInfo.isEmpty) {
      return ('anonymous', 'download_manager@local');
    }
    final colonIndex = uri.userInfo.indexOf(':');
    if (colonIndex == -1) {
      return (Uri.decodeComponent(uri.userInfo), '');
    }
    return (
      Uri.decodeComponent(uri.userInfo.substring(0, colonIndex)),
      Uri.decodeComponent(uri.userInfo.substring(colonIndex + 1)),
    );
  }

  String _remotePathFromUri(Uri uri) {
    final decoded = Uri.decodeFull(uri.path);
    if (decoded.isEmpty) return '/';
    return decoded;
  }

  Future<_FtpControlConnection> _openAuthenticated(Uri uri) async {
    final port = uri.hasPort ? uri.port : 21;
    final control = await _FtpControlConnection.connect(uri.host, port);

    try {
      final greeting = await control.readReply();
      if (greeting.code < 200 || greeting.code >= 300) {
        throw Exception('FTP greeting failed: ${greeting.message}');
      }

      final (user, pass) = _credentialsFromUri(uri);
      final userReply = await control.sendCommand('USER $user');
      if (userReply.code == 331) {
        final passReply = await control.sendCommand('PASS $pass');
        if (passReply.code < 200 || passReply.code >= 300) {
          throw Exception('FTP login failed: ${passReply.message}');
        }
      } else if (userReply.code < 200 || userReply.code >= 300) {
        throw Exception('FTP USER failed: ${userReply.message}');
      }

      await control.sendCommand('TYPE I');
      return control;
    } catch (_) {
      await control.close();
      rethrow;
    }
  }

  (String host, int port) _parsePasvReply(_FtpReply reply, String fallbackHost) {
    final match = RegExp(
      r'\((\d+),(\d+),(\d+),(\d+),(\d+),(\d+)\)',
    ).firstMatch(reply.message);
    if (match == null) {
      throw Exception('Invalid FTP PASV reply: ${reply.message}');
    }

    final ip =
        '${match.group(1)}.${match.group(2)}.${match.group(3)}.${match.group(4)}';
    final p1 = int.parse(match.group(5)!);
    final p2 = int.parse(match.group(6)!);
    final port = (p1 * 256) + p2;
    final targetHost = ip == '0.0.0.0' ? fallbackHost : ip;
    return (targetHost, port);
  }

  Future<DownloadFileInfo> getFileInfo(Uri uri) async {
    final control = await _openAuthenticated(uri);
    try {
      final remotePath = _remotePathFromUri(uri);

      int? fileSize;
      final sizeReply = await control.sendCommand('SIZE $remotePath');
      if (sizeReply.code == 213) {
        final parts = sizeReply.message.trim().split(RegExp(r'\s+'));
        if (parts.length >= 2) {
          fileSize = int.tryParse(parts[1]);
        }
      }

      final restReply = await control.sendCommand('REST 0');
      final supportsResume = restReply.code == 350;

      try {
        await control.sendCommand('QUIT');
      } catch (_) {}

      final fileName = uri.pathSegments.isNotEmpty && uri.pathSegments.last.isNotEmpty
          ? Uri.decodeComponent(uri.pathSegments.last)
          : 'ftp_download_${DateTime.now().millisecondsSinceEpoch}';

      final fileType = fileName.contains('.')
          ? fileName.split('.').last.toUpperCase()
          : 'Unknown';

      return DownloadFileInfo(
        fileName: fileName,
        fileSize: fileSize,
        fileType: fileType,
        supportsResume: supportsResume,
        protocol: 'FTP',
        isDirectDownload: true,
        directDownloadReason: 'Direct FTP file link',
      );
    } finally {
      await control.close();
    }
  }

  Future<bool> supportsResume(Uri uri) async {
    try {
      final info = await getFileInfo(uri);
      return info.supportsResume;
    } catch (_) {
      return false;
    }
  }

  Future<void> downloadFile({
    required Uri uri,
    required String savePath,
    required void Function(int received, int total) onProgress,
    int initialOffset = 0,
    SpeedLimiter? speedLimiter,
    void Function(int attempt)? onReconnecting,
    CancelToken? cancelToken,
    int maxReconnectAttempts = 8,
  }) async {
    final file = File(savePath);
    await file.parent.create(recursive: true);

    final remotePath = _remotePathFromUri(uri);
    final stopwatch = Stopwatch()..start();
    var lastEmitMs = -200;
    var received = initialOffset;
    var total = -1;
    var attempt = 0;

    while (true) {
      if (cancelToken?.isCancelled ?? false) {
        throw DioException.requestCancelled(
          requestOptions: RequestOptions(path: uri.toString()),
          reason: cancelToken?.cancelError?.error ?? 'Cancelled',
        );
      }

      _FtpControlConnection? control;
      Socket? dataSocket;
      IOSink? sink;

      void abortSockets() {
        try {
          dataSocket?.destroy();
        } catch (_) {}
        try {
          control?.socket.destroy();
        } catch (_) {}
      }

      cancelToken?.whenCancel.then((_) => abortSockets());

      try {
        control = await _openAuthenticated(uri);

        final sizeReply = await control.sendCommand('SIZE $remotePath');
        if (sizeReply.code == 213) {
          final parts = sizeReply.message.trim().split(RegExp(r'\s+'));
          if (parts.length >= 2) {
            total = int.tryParse(parts[1]) ?? total;
          }
        }

        final pasvReply = await control.sendCommand('PASV');
        if (pasvReply.code != 227) {
          throw Exception('FTP PASV failed: ${pasvReply.message}');
        }
        final (dataHost, dataPort) = _parsePasvReply(pasvReply, uri.host);

        dataSocket = await Socket.connect(
          dataHost,
          dataPort,
          timeout: const Duration(seconds: 15),
        );

        final isResuming = received > 0;
        if (isResuming) {
          final restReply = await control.sendCommand('REST $received');
          if (restReply.code != 350) {
            throw Exception('FTP server does not support resume (REST)');
          }
        }

        final retrReply = await control.sendCommand('RETR $remotePath');
        if (retrReply.code != 125 && retrReply.code != 150) {
          throw Exception('FTP RETR failed: ${retrReply.message}');
        }

        sink = file.openWrite(
          mode: isResuming ? FileMode.append : FileMode.write,
        );

        await for (final chunk in dataSocket) {
          if (cancelToken?.isCancelled ?? false) {
            throw DioException.requestCancelled(
              requestOptions: RequestOptions(path: uri.toString()),
              reason: cancelToken?.cancelError?.error ?? 'Cancelled',
            );
          }

          sink.add(chunk);
          received += chunk.length;

          final nowMs = stopwatch.elapsedMilliseconds;
          if ((total > 0 && received >= total) || nowMs - lastEmitMs >= 150) {
            lastEmitMs = nowMs;
            onProgress(received, total);
          }

          if (speedLimiter != null) {
            await speedLimiter.throttle(chunk.length, cancelToken: cancelToken);
          }
        }

        await sink.flush();
        await sink.close();
        sink = null;

        try {
          dataSocket.destroy();
        } catch (_) {}
        dataSocket = null;

        // Read final 226 transfer complete reply if available
        try {
          await control.readReply();
        } catch (_) {}

        try {
          await control.sendCommand('QUIT');
        } catch (_) {}

        await control.close();
        control = null;

        if (total > 0 && received < total) {
          throw const HttpException('FTP connection closed prematurely');
        }

        onProgress(received, total > 0 ? total : received);
        return;
      } catch (error) {
        if (sink != null) {
          try {
            await sink.flush();
          } catch (_) {}
          try {
            await sink.close();
          } catch (_) {}
          sink = null;
        }
        try {
          dataSocket?.destroy();
        } catch (_) {}
        await control?.close();

        final isCancelled =
            (cancelToken?.isCancelled ?? false) ||
            (error is DioException && error.type == DioExceptionType.cancel);

        final retryable =
            error is SocketException ||
            error is HttpException ||
            error is TimeoutException;

        if (isCancelled || !retryable || attempt >= maxReconnectAttempts) {
          rethrow;
        }

        attempt++;
        onReconnecting?.call(attempt);
        await SpeedLimiter.cancellableDelay(
          Duration(seconds: attempt.clamp(1, 5)),
          cancelToken: cancelToken,
        );
      }
    }
  }
}
