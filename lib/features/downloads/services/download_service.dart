import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:download_manager/features/downloads/models/download_file_info.dart';
import 'package:download_manager/features/downloads/models/download_progress_state.dart';

class _SegmentSpec {
  final int index;
  final int startByte;
  final int endByte;

  const _SegmentSpec({
    required this.index,
    required this.startByte,
    required this.endByte,
  });

  int get length => endByte - startByte + 1;

  Map<String, dynamic> toJson() => {
    'index': index,
    'startByte': startByte,
    'endByte': endByte,
  };

  factory _SegmentSpec.fromJson(Map<String, dynamic> json) {
    return _SegmentSpec(
      index: json['index'] as int,
      startByte: json['startByte'] as int,
      endByte: json['endByte'] as int,
    );
  }
}

class DownloadService {
  static const int defaultConnectionCount = 8;
  static const int minSegmentedSizeBytes = 1024 * 1024;

  Dio _dio = _createDio();

  static Dio _createDio() {
    return Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        followRedirects: true,
        maxRedirects: 10,
        headers: const {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
          'Accept': '*/*',
        },
      ),
    );
  }

  void _resetClient() {
    _dio.close(force: false);
    _dio = _createDio();
  }

  bool _isRetryableNodeError(Object error) {
    if (error is DioException) {
      if (error.error is HandshakeException || error.error is SocketException) {
        return true;
      }
      return error.type == DioExceptionType.badCertificate ||
          error.type == DioExceptionType.connectionError ||
          error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.receiveTimeout;
    }
    return error is HandshakeException || error is SocketException;
  }

  Future<T> _runWithNodeFailover<T>(
    Uri uri,
    Future<T> Function() action, {
    CancelToken? cancelToken,
    int maxAttempts = 4,
  }) async {
    Object? lastError;
    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      if (cancelToken?.isCancelled ?? false) {
        throw DioException.requestCancelled(
          requestOptions: RequestOptions(path: uri.toString()),
          reason: cancelToken?.cancelError?.error ?? 'Cancelled',
        );
      }
      try {
        return await action();
      } catch (error) {
        lastError = error;
        if (!_isRetryableNodeError(error) || attempt == maxAttempts - 1) {
          rethrow;
        }
        // Reset HttpClient so the retry performs a fresh DNS/TCP/TLS connection
        // (avoids sticking to a broken round-robin CDN edge node).
        _resetClient();
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    }
    throw lastError!;
  }

  String _stateFilePath(String savePath) => '$savePath.dmstate';

  String _partFilePath(String savePath, int index) => '$savePath.part$index';

  Future<bool> hasSegmentedState(String savePath) async {
    return File(_stateFilePath(savePath)).exists();
  }

  Future<void> cleanupPartialFiles(String savePath) async {
    int segmentCount = defaultConnectionCount;

    final stateFile = File(_stateFilePath(savePath));
    if (await stateFile.exists()) {
      try {
        final decoded =
            jsonDecode(await stateFile.readAsString()) as Map<String, dynamic>;
        final segments = decoded['segments'] as List<dynamic>?;
        if (segments != null && segments.length > segmentCount) {
          segmentCount = segments.length;
        }
      } catch (_) {}

      try {
        await stateFile.delete();
      } catch (_) {}
    }

    for (int i = 0; i < segmentCount; i++) {
      final partFile = File(_partFilePath(savePath, i));
      if (await partFile.exists()) {
        try {
          await partFile.delete();
        } catch (_) {}
      }
    }

    final targetFile = File(savePath);
    if (await targetFile.exists()) {
      try {
        await targetFile.delete();
      } catch (_) {}
    }
  }

  Future<List<DownloadConnectionProgress>> getSavedConnectionProgress(
    String savePath, {
    String pausedLabel = 'Paused',
  }) async {
    final stateFile = File(_stateFilePath(savePath));
    if (!await stateFile.exists()) {
      return const [];
    }

    try {
      final decoded =
          jsonDecode(await stateFile.readAsString()) as Map<String, dynamic>;
      final rawSegments = decoded['segments'] as List<dynamic>? ?? const [];
      final specs = rawSegments
          .map((e) => _SegmentSpec.fromJson(e as Map<String, dynamic>))
          .toList();

      final result = <DownloadConnectionProgress>[];
      for (final spec in specs) {
        final partFile = File(_partFilePath(savePath, spec.index));
        final saved = await partFile.exists() ? await partFile.length() : 0;
        final clamped = saved.clamp(0, spec.length);
        final done = clamped >= spec.length;
        result.add(
          DownloadConnectionProgress(
            number: spec.index + 1,
            startByte: spec.startByte,
            endByte: spec.endByte,
            downloadedBytes: clamped,
            info: done ? 'Completed' : pausedLabel,
            isActive: false,
            isCompleted: done,
          ),
        );
      }
      return result;
    } catch (_) {
      return const [];
    }
  }

  Future<DownloadFileInfo> getFileInfo(String url) async {
    final uri = Uri.tryParse(url);

    if (uri == null ||
        !uri.hasAuthority ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw ArgumentError('Invalid download URL');
    }

    Response<dynamic> response;
    try {
      response = await _runWithNodeFailover(
        uri,
        () => _dio.head(
          url,
          options: Options(
            followRedirects: true,
            validateStatus: (status) =>
                status != null && status >= 200 && status < 400,
          ),
        ),
      );
    } on DioException catch (error) {
      final code = error.response?.statusCode;
      // Fallback to a 1-byte Range GET when servers reject HEAD requests.
      if (code == 403 || code == 405 || code == 501) {
        response = await _runWithNodeFailover(
          uri,
          () => _dio.get<List<int>>(
            url,
            options: Options(
              responseType: ResponseType.bytes,
              followRedirects: true,
              headers: const {'Range': 'bytes=0-0'},
              validateStatus: (status) =>
                  status != null && (status == 200 || status == 206),
            ),
          ),
        );
      } else {
        rethrow;
      }
    }

    int? fileSize;
    final contentRange = response.headers.value('content-range');
    if (contentRange != null && contentRange.contains('/')) {
      fileSize = int.tryParse(contentRange.split('/').last.trim());
    }
    if (fileSize == null) {
      final contentLength = response.headers.value('content-length');
      fileSize = int.tryParse(contentLength ?? '');
    }

    final disposition = response.headers.value('content-disposition');
    final effectiveUri = response.realUri.pathSegments.isNotEmpty
        ? response.realUri
        : uri;

    String fileName = effectiveUri.pathSegments.isNotEmpty
        ? Uri.decodeComponent(effectiveUri.pathSegments.last)
        : '';

    if (disposition != null) {
      final match = RegExp(
        r'''filename\*?=(?:UTF-8''|")?([^";]+)''',
        caseSensitive: false,
      ).firstMatch(disposition);

      if (match != null) {
        fileName = Uri.decodeComponent(
          match.group(1)!.replaceAll('"', '').trim(),
        );
      }
    }

    if (fileName.isEmpty) {
      fileName = 'download_${DateTime.now().millisecondsSinceEpoch}';
    }

    final fileType = fileName.contains('.')
        ? fileName.split('.').last.toUpperCase()
        : 'Unknown';

    final acceptRanges = response.headers.value('accept-ranges');
    final supportsResume =
        acceptRanges?.toLowerCase() == 'bytes' || response.statusCode == 206;

    return DownloadFileInfo(
      fileName: fileName,
      fileSize: fileSize,
      fileType: fileType,
      supportsResume: supportsResume,
    );
  }

  Future<void> downloadFile({
    required String url,
    required String savePath,
    required void Function(int received, int total) onProgress,
    CancelToken? cancelToken,
  }) async {
    final uri = Uri.tryParse(url);

    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      throw ArgumentError('Invalid download URL');
    }

    final file = File(savePath);

    await file.parent.create(recursive: true);

    final stopwatch = Stopwatch()..start();
    var lastEmitMs = -200;

    await _runWithNodeFailover(
      uri,
      () => _dio.download(
        url,
        savePath,
        cancelToken: cancelToken,
        deleteOnError: false,
        onReceiveProgress: (received, total) {
          final nowMs = stopwatch.elapsedMilliseconds;
          final isComplete = total > 0 && received >= total;
          if (!isComplete && nowMs - lastEmitMs < 150) {
            return;
          }
          lastEmitMs = nowMs;
          onProgress(received, total);
        },
      ),
      cancelToken: cancelToken,
    );
  }

  Future<void> downloadFileSegmented({
    required String url,
    required String savePath,
    required int totalBytes,
    required void Function(int received, int total) onProgress,
    void Function(List<DownloadConnectionProgress> connections)?
    onConnectionsChanged,
    void Function(
      int received,
      int total,
      List<DownloadConnectionProgress> connections,
    )?
    onSegmentedProgress,
    void Function()? onRebuilding,
    CancelToken? cancelToken,
    int connectionCount = defaultConnectionCount,
    bool resumeExisting = false,
  }) async {
    final uri = Uri.tryParse(url);

    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      throw ArgumentError('Invalid download URL');
    }

    if (totalBytes <= 0) {
      throw ArgumentError('Total bytes must be positive for segmented download');
    }

    final targetFile = File(savePath);
    await targetFile.parent.create(recursive: true);

    final stateFile = File(_stateFilePath(savePath));
    late List<_SegmentSpec> segments;
    int resolvedTotalBytes = totalBytes;

    if (resumeExisting && await stateFile.exists()) {
      final decoded =
          jsonDecode(await stateFile.readAsString()) as Map<String, dynamic>;
      final savedTotal = decoded['totalBytes'] as int?;
      final rawSegments = decoded['segments'] as List<dynamic>?;
      if (savedTotal != null &&
          savedTotal > 0 &&
          rawSegments != null &&
          rawSegments.isNotEmpty) {
        resolvedTotalBytes = savedTotal;
        segments = rawSegments
            .map((e) => _SegmentSpec.fromJson(e as Map<String, dynamic>))
            .toList();
      } else {
        segments = _buildSegments(resolvedTotalBytes, connectionCount);
        await _writeStateFile(stateFile, url, resolvedTotalBytes, segments);
      }
    } else {
      await cleanupPartialFiles(savePath);
      segments = _buildSegments(resolvedTotalBytes, connectionCount);
      await _writeStateFile(stateFile, url, resolvedTotalBytes, segments);
    }

    final segCount = segments.length;
    final segDownloaded = List<int>.filled(segCount, 0);
    final segInfo = List<String>.filled(segCount, 'Connecting...');
    final segActive = List<bool>.filled(segCount, true);
    final segCompleted = List<bool>.filled(segCount, false);
    final segError = List<bool>.filled(segCount, false);

    for (final spec in segments) {
      final idx = spec.index;
      final partFile = File(_partFilePath(savePath, idx));
      int existingBytes = await partFile.exists() ? await partFile.length() : 0;
      if (existingBytes > spec.length) {
        await partFile.delete();
        existingBytes = 0;
      }
      final alreadyDone = existingBytes >= spec.length;
      segDownloaded[idx] = existingBytes;
      segInfo[idx] = alreadyDone ? 'Completed' : 'Connecting...';
      segActive[idx] = !alreadyDone;
      segCompleted[idx] = alreadyDone;
    }

    final stopwatch = Stopwatch()..start();
    var lastEmitMs = -200;

    void emitProgress({bool force = false}) {
      final nowMs = stopwatch.elapsedMilliseconds;
      if (!force && nowMs - lastEmitMs < 150) {
        return;
      }
      lastEmitMs = nowMs;

      int totalReceived = 0;
      final snapshot = List<DownloadConnectionProgress>.generate(segCount, (i) {
        final spec = segments[i];
        final downloaded = segDownloaded[i];
        totalReceived += downloaded;
        return DownloadConnectionProgress(
          number: i + 1,
          startByte: spec.startByte,
          endByte: spec.endByte,
          downloadedBytes: downloaded,
          info: segInfo[i],
          isActive: segActive[i],
          isCompleted: segCompleted[i],
          hasError: segError[i],
        );
      }, growable: false);

      if (onSegmentedProgress != null) {
        onSegmentedProgress(totalReceived, resolvedTotalBytes, snapshot);
      } else {
        onConnectionsChanged?.call(snapshot);
        onProgress(totalReceived, resolvedTotalBytes);
      }
    }

    emitProgress(force: true);

    // Resolve any initial CDN redirects once so all 8 segments target the
    // resolved edge host directly instead of hitting round-robin redirectors
    // 8 separate times.
    String effectiveUrl = url;
    try {
      final headResp = await _runWithNodeFailover(
        uri,
        () => _dio.head(
          url,
          cancelToken: cancelToken,
          options: Options(
            followRedirects: true,
            validateStatus: (status) =>
                status != null && status >= 200 && status < 400,
          ),
        ),
        cancelToken: cancelToken,
      );
      final resolved = headResp.realUri.toString();
      if (resolved.startsWith('http://') || resolved.startsWith('https://')) {
        effectiveUrl = resolved;
      }
    } catch (_) {
      if (cancelToken?.isCancelled ?? false) {
        rethrow;
      }
    }

    final sharedCancelToken = CancelToken();
    cancelToken?.whenCancel.then((err) {
      if (!sharedCancelToken.isCancelled) {
        sharedCancelToken.cancel(err.error);
      }
    });

    Future<void> runSegment(_SegmentSpec spec) async {
      final idx = spec.index;
      final partFile = File(_partFilePath(savePath, idx));
      int currentSaved = await partFile.exists() ? await partFile.length() : 0;

      if (currentSaved >= spec.length) {
        segDownloaded[idx] = spec.length;
        segInfo[idx] = 'Completed';
        segActive[idx] = false;
        segCompleted[idx] = true;
        emitProgress(force: true);
        return;
      }

      const maxRetries = 4;
      int attempt = 0;

      while (true) {
        if (sharedCancelToken.isCancelled) {
          throw DioException.requestCancelled(
            requestOptions: RequestOptions(path: url),
            reason: sharedCancelToken.cancelError?.error ?? 'Cancelled',
          );
        }

        currentSaved = await partFile.exists() ? await partFile.length() : 0;
        if (currentSaved >= spec.length) {
          segDownloaded[idx] = spec.length;
          segInfo[idx] = 'Completed';
          segActive[idx] = false;
          segCompleted[idx] = true;
          emitProgress(force: true);
          return;
        }

        final rangeStart = spec.startByte + currentSaved;
        final rangeEnd = spec.endByte;

        segDownloaded[idx] = currentSaved;
        segInfo[idx] = attempt == 0 ? 'Connecting...' : 'Reconnecting...';
        segActive[idx] = true;
        segError[idx] = false;
        emitProgress(force: true);

        IOSink? sink;
        try {
          final response = await _dio.get<ResponseBody>(
            effectiveUrl,
            options: Options(
              responseType: ResponseType.stream,
              followRedirects: true,
              headers: {'Range': 'bytes=$rangeStart-$rangeEnd'},
              validateStatus: (status) => status == 206,
            ),
            cancelToken: sharedCancelToken,
          );

          final contentRange = response.headers.value('content-range');
          if (contentRange == null ||
              !contentRange.startsWith('bytes $rangeStart-')) {
            throw Exception(
              'Server returned an invalid Content-Range for connection ${idx + 1}',
            );
          }

          segInfo[idx] = 'Receiving data...';
          segActive[idx] = true;
          segError[idx] = false;
          emitProgress(force: true);

          sink = partFile.openWrite(mode: FileMode.append);

          await for (final chunk in response.data!.stream) {
            if (sharedCancelToken.isCancelled) {
              throw DioException.requestCancelled(
                requestOptions: response.requestOptions,
                reason: sharedCancelToken.cancelError?.error ?? 'Cancelled',
              );
            }

            final remaining = spec.length - currentSaved;
            if (remaining <= 0) break;

            final bytesToWrite = chunk.length > remaining
                ? chunk.sublist(0, remaining)
                : chunk;

            sink.add(bytesToWrite);
            currentSaved += bytesToWrite.length;
            segDownloaded[idx] = currentSaved;
            emitProgress();

            if (currentSaved >= spec.length) break;
          }

          await sink.flush();
          await sink.close();
          sink = null;

          if (currentSaved >= spec.length) {
            segDownloaded[idx] = spec.length;
            segInfo[idx] = 'Completed';
            segActive[idx] = false;
            segCompleted[idx] = true;
            segError[idx] = false;
            emitProgress(force: true);
            return;
          }

          if (attempt < maxRetries && !sharedCancelToken.isCancelled) {
            attempt++;
            await Future<void>.delayed(const Duration(milliseconds: 350));
            continue;
          }

          throw Exception(
            'Connection ${idx + 1} ended early ($currentSaved / ${spec.length} bytes)',
          );
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

          final isCancelled =
              sharedCancelToken.isCancelled ||
              (cancelToken?.isCancelled ?? false) ||
              (error is DioException &&
                  error.type == DioExceptionType.cancel);

          if (isCancelled) {
            segDownloaded[idx] = currentSaved.clamp(0, spec.length);
            segInfo[idx] = 'Disconnected';
            segActive[idx] = false;
            emitProgress(force: true);
            rethrow;
          }

          if (attempt < maxRetries) {
            if (_isRetryableNodeError(error)) {
              _resetClient();
            }
            attempt++;
            await Future<void>.delayed(const Duration(milliseconds: 450));
            continue;
          }

          segDownloaded[idx] = currentSaved.clamp(0, spec.length);
          segInfo[idx] = 'Error';
          segActive[idx] = false;
          segError[idx] = true;
          emitProgress(force: true);

          if (!sharedCancelToken.isCancelled) {
            sharedCancelToken.cancel('Sibling connection failed');
          }
          rethrow;
        }
      }
    }

    await Future.wait(segments.map(runSegment));

    if (cancelToken?.isCancelled ?? false) {
      throw DioException.requestCancelled(
        requestOptions: RequestOptions(path: url),
        reason: cancelToken?.cancelError?.error ?? 'Cancelled',
      );
    }

    onRebuilding?.call();

    final outSink = targetFile.openWrite(mode: FileMode.write);
    try {
      for (final spec in segments) {
        final partFile = File(_partFilePath(savePath, spec.index));
        await outSink.addStream(partFile.openRead());
      }
      await outSink.flush();
    } finally {
      await outSink.close();
    }

    for (final spec in segments) {
      final partFile = File(_partFilePath(savePath, spec.index));
      if (await partFile.exists()) {
        try {
          await partFile.delete();
        } catch (_) {}
      }
    }
    if (await stateFile.exists()) {
      try {
        await stateFile.delete();
      } catch (_) {}
    }

    emitProgress(force: true);
  }

  List<_SegmentSpec> _buildSegments(int totalBytes, int requestedConnections) {
    final count = requestedConnections.clamp(1, 16);
    final actualCount = totalBytes < count ? 1 : count;
    final baseSize = totalBytes ~/ actualCount;
    final remainder = totalBytes % actualCount;

    final result = <_SegmentSpec>[];
    int offset = 0;
    for (int i = 0; i < actualCount; i++) {
      final size = baseSize + (i < remainder ? 1 : 0);
      final end = offset + size - 1;
      result.add(_SegmentSpec(index: i, startByte: offset, endByte: end));
      offset = end + 1;
    }
    return result;
  }

  Future<void> _writeStateFile(
    File stateFile,
    String url,
    int totalBytes,
    List<_SegmentSpec> segments,
  ) async {
    final payload = jsonEncode({
      'url': url,
      'totalBytes': totalBytes,
      'segments': segments.map((s) => s.toJson()).toList(),
    });
    await stateFile.writeAsString(payload, flush: true);
  }

  Future<int> getDownloadedBytes(String savePath) async {
    final stateFile = File(_stateFilePath(savePath));
    if (await stateFile.exists()) {
      try {
        final decoded =
            jsonDecode(await stateFile.readAsString()) as Map<String, dynamic>;
        final rawSegments = decoded['segments'] as List<dynamic>? ?? const [];
        int total = 0;
        for (final entry in rawSegments) {
          final index = (entry as Map<String, dynamic>)['index'] as int;
          final partFile = File(_partFilePath(savePath, index));
          if (await partFile.exists()) {
            total += await partFile.length();
          }
        }
        return total;
      } catch (_) {}
    }

    final file = File(savePath);

    if (!await file.exists()) {
      return 0;
    }

    return await file.length();
  }

  Future<bool> supportsResume(String url, {CancelToken? cancelToken}) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasAuthority) return false;

    try {
      final response = await _runWithNodeFailover(
        uri,
        () => _dio.head(
          url,
          cancelToken: cancelToken,
          options: Options(
            followRedirects: true,
            validateStatus: (status) =>
                status != null && status >= 200 && status < 400,
          ),
        ),
        cancelToken: cancelToken,
      );

      final acceptRanges = response.headers.value('accept-ranges');

      return acceptRanges?.toLowerCase() == 'bytes';
    } catch (_) {
      return false;
    }
  }

  Future<void> resumeDownload({
    required String url,
    required String savePath,
    required int downloadedBytes,
    required void Function(int received, int total) onProgress,
    CancelToken? cancelToken,
  }) async {
    final file = File(savePath);

    if (downloadedBytes <= 0) {
      throw Exception('Invalid resume position');
    }

    if (!await file.exists()) {
      throw Exception('Partial download file does not exist');
    }

    final actualBytes = await file.length();

    if (actualBytes != downloadedBytes) {
      throw Exception('Downloaded file size does not match resume position');
    }

    final uri = Uri.parse(url);
    final response = await _runWithNodeFailover(
      uri,
      () => _dio.get<ResponseBody>(
        url,
        options: Options(
          responseType: ResponseType.stream,
          headers: {'Range': 'bytes=$downloadedBytes-'},
          validateStatus: (status) => status == 206,
        ),
        cancelToken: cancelToken,
      ),
      cancelToken: cancelToken,
    );

    final contentRange = response.headers.value('content-range');

    if (contentRange == null ||
        !contentRange.startsWith('bytes $downloadedBytes-')) {
      throw Exception('Server returned an invalid Content-Range');
    }

    final total = int.tryParse(contentRange.split('/').last);

    if (total == null) {
      throw Exception('Could not determine file size');
    }

    final sink = file.openWrite(mode: FileMode.append);
    final stopwatch = Stopwatch()..start();
    var lastEmitMs = -200;

    var received = downloadedBytes;

    try {
      await for (final chunk in response.data!.stream) {
        sink.add(chunk);
        received += chunk.length;
        final nowMs = stopwatch.elapsedMilliseconds;
        if (received >= total || nowMs - lastEmitMs >= 150) {
          lastEmitMs = nowMs;
          onProgress(received, total);
        }
      }

      await sink.flush();
      onProgress(received, total);
    } finally {
      await sink.close();
    }
  }
}
