import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:download_manager/features/downloads/models/download_file_info.dart';
import 'package:download_manager/features/downloads/models/download_progress_state.dart';
import 'package:download_manager/features/downloads/services/go_engine_process.dart';

class GoSavedProgress {
  final int downloadedBytes;
  final List<DownloadConnectionProgress> connections;
  final bool hasSegmentedState;

  const GoSavedProgress({
    required this.downloadedBytes,
    required this.connections,
    required this.hasSegmentedState,
  });
}

class GoEngineClient {
  final String baseUrl;

  GoEngineClient({String? baseUrl})
    : baseUrl = baseUrl ?? GoEngineProcess.instance.baseUrl;

  Future<bool> isHealthy({
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

  Future<Map<String, dynamic>> _postJson(
    String path,
    Map<String, dynamic> payload, {
    Duration timeout = const Duration(seconds: 25),
  }) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client
          .postUrl(Uri.parse('$baseUrl$path'))
          .timeout(timeout);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(payload));
      final response = await request.close().timeout(timeout);
      final raw = await utf8.decoder.bind(response).join().timeout(timeout);

      Map<String, dynamic> decoded = {};
      if (raw.trim().isNotEmpty) {
        final parsed = jsonDecode(raw);
        if (parsed is Map<String, dynamic>) {
          decoded = parsed;
        }
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        final message = decoded['error']?.toString().trim();
        throw Exception(
          (message != null && message.isNotEmpty)
              ? message
              : 'Go engine returned HTTP ${response.statusCode}',
        );
      }

      return decoded;
    } finally {
      client.close(force: true);
    }
  }

  Future<DownloadFileInfo> probe(
    String url, {
    String? username,
    String? password,
  }) async {
    final data = await _postJson('/api/probe', {
      'url': url,
      'username': username ?? '',
      'password': password ?? '',
    });

    final rawSize = data['fileSize'];
    final fileSize = rawSize is num ? rawSize.toInt() : null;

    return DownloadFileInfo(
      fileName: data['fileName']?.toString() ?? 'download',
      fileSize: fileSize,
      fileType: data['fileType']?.toString() ?? 'Unknown',
      supportsResume: data['supportsResume'] == true,
      protocol: data['protocol']?.toString() ?? 'HTTP',
      isDirectDownload: data['isDirectDownload'] != false,
      directDownloadReason:
          data['directDownloadReason']?.toString() ?? 'Direct download',
      contentType: data['contentType']?.toString(),
    );
  }

  Future<void> setSpeedLimit(String id, int bytesPerSecond) async {
    await _postJson('/api/downloads/limit', {
      'id': id,
      'bytesPerSecond': bytesPerSecond < 0 ? 0 : bytesPerSecond,
    }, timeout: const Duration(seconds: 3));
  }

  Future<void> pauseDownload(String id) async {
    await _postJson('/api/downloads/pause', {
      'id': id,
    }, timeout: const Duration(seconds: 3));
  }

  Future<void> cancelDownload(String id) async {
    await _postJson('/api/downloads/cancel', {
      'id': id,
    }, timeout: const Duration(seconds: 3));
  }

  Future<void> cleanupPartialFiles(String savePath) async {
    await _postJson('/api/downloads/cleanup', {
      'savePath': savePath,
    }, timeout: const Duration(seconds: 5));
  }

  Future<GoSavedProgress> getSavedProgress(
    String savePath, {
    String pausedLabel = 'Paused',
  }) async {
    final data = await _postJson('/api/downloads/saved-progress', {
      'savePath': savePath,
      'pausedLabel': pausedLabel,
    }, timeout: const Duration(seconds: 5));

    final dlBytes = (data['downloadedBytes'] as num?)?.toInt() ?? 0;
    final hasSeg = data['hasSegmentedState'] == true;
    final conns = _parseConnections(data['connections']);

    return GoSavedProgress(
      downloadedBytes: dlBytes,
      connections: conns,
      hasSegmentedState: hasSeg,
    );
  }

  Future<void> streamDownload({
    required String id,
    required String url,
    required String savePath,
    int totalBytes = 0,
    int connectionCount = 8,
    bool resumeExisting = false,
    int initialOffset = 0,
    bool segmented = false,
    int speedLimitBytesPerSec = 0,
    String? username,
    String? password,
    int maxReconnectAttempts = 10,
    CancelToken? cancelToken,
    bool Function()? isPauseRequested,
    void Function(int received, int total)? onProgress,
    void Function(List<DownloadConnectionProgress> connections)?
    onConnectionsChanged,
    void Function(
      int received,
      int total,
      List<DownloadConnectionProgress> connections,
    )?
    onSegmentedProgress,
    void Function(int attempt)? onReconnecting,
    void Function()? onRebuilding,
  }) async {
    if (cancelToken?.isCancelled ?? false) {
      throw DioException.requestCancelled(
        requestOptions: RequestOptions(path: url),
        reason: cancelToken?.cancelError?.error ?? 'Cancelled',
      );
    }

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    bool streamFinished = false;

    if (cancelToken != null) {
      unawaited(
        cancelToken.whenCancel.then((cancelError) async {
          if (streamFinished) return;
          final reasonText = cancelError.error?.toString().toLowerCase() ?? '';
          final isPause =
              (isPauseRequested?.call() ?? false) ||
              reasonText.contains('paused');
          try {
            if (isPause) {
              await pauseDownload(id);
            } else {
              await cancelDownload(id);
            }
          } catch (_) {}
        }),
      );
    }

    try {
      final request = await client.postUrl(
        Uri.parse('$baseUrl/api/downloads/stream'),
      );
      request.headers.contentType = ContentType.json;
      request.write(
        jsonEncode({
          'id': id,
          'url': url,
          'savePath': savePath,
          'totalBytes': totalBytes,
          'connectionCount': connectionCount,
          'resumeExisting': resumeExisting,
          'initialOffset': initialOffset,
          'segmented': segmented,
          'speedLimitBytesPerSec': speedLimitBytesPerSec < 0
              ? 0
              : speedLimitBytesPerSec,
          if (username != null && username.isNotEmpty) 'username': username,
          if (password != null && password.isNotEmpty) 'password': password,
          'maxReconnectAttempts': maxReconnectAttempts,
        }),
      );

      final response = await request.close();
      if (response.statusCode != 200) {
        final raw = await utf8.decoder.bind(response).join();
        String msg = 'Go engine stream failed (HTTP ${response.statusCode})';
        try {
          final parsed = jsonDecode(raw);
          if (parsed is Map<String, dynamic> && parsed['error'] != null) {
            msg = parsed['error'].toString();
          }
        } catch (_) {}
        throw Exception(msg);
      }

      bool completed = false;

      await for (final line
          in response.transform(utf8.decoder).transform(const LineSplitter())) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;

        final decoded = jsonDecode(trimmed);
        if (decoded is! Map<String, dynamic>) continue;

        final type = decoded['type']?.toString() ?? '';
        final received = (decoded['received'] as num?)?.toInt() ?? 0;
        final total = (decoded['total'] as num?)?.toInt() ?? -1;
        final connections = _parseConnections(decoded['connections']);

        switch (type) {
          case 'progress':
            if (connections.isNotEmpty) {
              if (onSegmentedProgress != null) {
                onSegmentedProgress(received, total, connections);
              } else {
                onConnectionsChanged?.call(connections);
                onProgress?.call(received, total);
              }
            } else {
              onProgress?.call(received, total);
            }
          case 'reconnecting':
            final attempt = (decoded['attempt'] as num?)?.toInt() ?? 1;
            onReconnecting?.call(attempt);
          case 'rebuilding':
            onRebuilding?.call();
          case 'completed':
            completed = true;
            if (received > 0 || total > 0) {
              onProgress?.call(
                total > 0 ? total : received,
                total > 0 ? total : received,
              );
            }
          case 'paused':
            throw DioException.requestCancelled(
              requestOptions: RequestOptions(path: url),
              reason: 'Paused by user',
            );
          case 'stopped':
            throw DioException.requestCancelled(
              requestOptions: RequestOptions(path: url),
              reason: 'Stopped by user',
            );
          case 'error':
            final errText =
                decoded['error']?.toString() ?? 'Go download engine error';
            throw Exception(errText);
        }
      }

      if (!completed) {
        if (cancelToken?.isCancelled ?? false) {
          throw DioException.requestCancelled(
            requestOptions: RequestOptions(path: url),
            reason: cancelToken?.cancelError?.error ?? 'Cancelled',
          );
        }
        throw Exception('Go download stream ended unexpectedly');
      }
    } finally {
      streamFinished = true;
      client.close(force: true);
    }
  }

  List<DownloadConnectionProgress> _parseConnections(dynamic raw) {
    if (raw is! List) return const [];
    final result = <DownloadConnectionProgress>[];
    for (final item in raw) {
      if (item is! Map<String, dynamic>) continue;
      result.add(
        DownloadConnectionProgress(
          number: (item['number'] as num?)?.toInt() ?? (result.length + 1),
          startByte: (item['startByte'] as num?)?.toInt() ?? 0,
          endByte: (item['endByte'] as num?)?.toInt(),
          downloadedBytes: (item['downloadedBytes'] as num?)?.toInt() ?? 0,
          info: item['info']?.toString() ?? '',
          isActive: item['isActive'] == true,
          isCompleted: item['isCompleted'] == true,
          hasError: item['hasError'] == true,
        ),
      );
    }
    return result;
  }
}
