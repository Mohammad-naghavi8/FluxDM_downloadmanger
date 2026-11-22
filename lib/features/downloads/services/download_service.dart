import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:download_manager/features/downloads/models/download_file_info.dart';
import 'package:download_manager/features/downloads/models/download_progress_state.dart';
import 'package:download_manager/features/downloads/services/ftp_client_service.dart';
import 'package:download_manager/features/downloads/services/go_engine_client.dart';
import 'package:download_manager/features/downloads/services/go_engine_process.dart';
import 'package:download_manager/features/downloads/services/speed_limiter.dart';
import 'package:download_manager/features/downloads/utils/download_link_helper.dart';

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

  static final Map<String, String> _resolvedHttpsRedirectCache = {};

  Dio _dio = _createDio();
  final FtpClientService _ftpClient = FtpClientService();
  final GoEngineClient? _customGoClient;
  final GoEngineClient _defaultGoClient = GoEngineClient();

  DownloadService({GoEngineClient? goClient}) : _customGoClient = goClient;

  bool get _useGoEngine =>
      _customGoClient != null || GoEngineProcess.instance.isRunning;

  GoEngineClient get _goClient => _customGoClient ?? _defaultGoClient;

  Future<void> setLiveSpeedLimit(String taskId, int bytesPerSecond) async {
    if (!_useGoEngine) return;
    try {
      await _goClient.setSpeedLimit(taskId, bytesPerSecond);
    } catch (_) {}
  }

  Map<String, dynamic> _buildRequestHeaders({
    String? username,
    String? password,
    Map<String, dynamic>? extra,
  }) {
    final headers = <String, dynamic>{...?extra};
    if (username != null && username.isNotEmpty) {
      final token = base64Encode(utf8.encode('$username:${password ?? ''}'));
      headers['Authorization'] = 'Basic $token';
    }
    return headers;
  }

  Uri _applyFtpCredentials(Uri uri, String? username, String? password) {
    if (username == null || username.isEmpty || uri.userInfo.isEmpty == false) {
      return uri;
    }
    final userEncoded = Uri.encodeComponent(username);
    final passEncoded = Uri.encodeComponent(password ?? '');
    return uri.replace(userInfo: '$userEncoded:$passEncoded');
  }

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

  /// If an HTTPS redirector host fails TLS handshake (e.g., an expired CDN edge
  /// node in round-robin DNS), checks whether the same host redirects to a
  /// healthy HTTPS CDN origin (strictly requiring an HTTPS target on a
  /// different host so TLS verification is never weakened or downgraded).
  Future<String?> _resolveHttpsCdnRedirect(
    Uri uri, {
    CancelToken? cancelToken,
  }) async {
    if (uri.scheme.toLowerCase() != 'https') return null;
    final key = uri.toString();
    final cached = _resolvedHttpsRedirectCache[key];
    if (cached != null) return cached;

    try {
      final probeUri = uri.replace(scheme: 'http');
      final response = await _dio.head<dynamic>(
        probeUri.toString(),
        cancelToken: cancelToken,
        options: Options(
          followRedirects: false,
          validateStatus: (status) =>
              status != null && status >= 300 && status < 400,
        ),
      );
      final location = response.headers.value('location');
      if (location == null || location.isEmpty) return null;

      final target = probeUri.resolve(location);
      if (target.scheme.toLowerCase() == 'https' &&
          target.host.isNotEmpty &&
          target.host.toLowerCase() != uri.host.toLowerCase()) {
        final resolved = target.toString();
        _resolvedHttpsRedirectCache[key] = resolved;
        return resolved;
      }
    } catch (_) {}
    return null;
  }

  String _effectiveUrl(String url) => _resolvedHttpsRedirectCache[url] ?? url;

  bool _isRetryableNodeError(Object error) {
    if (error is DioException) {
      if (error.error is HandshakeException ||
          error.error is SocketException ||
          error.error is HttpException) {
        return true;
      }
      return error.type == DioExceptionType.badCertificate ||
          error.type == DioExceptionType.connectionError ||
          error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.receiveTimeout;
    }
    return error is HandshakeException ||
        error is SocketException ||
        error is HttpException;
  }

  Duration _reconnectBackoff(int attempt) {
    return switch (attempt) {
      <= 1 => const Duration(milliseconds: 600),
      2 => const Duration(seconds: 1),
      3 => const Duration(seconds: 2),
      4 => const Duration(seconds: 3),
      _ => const Duration(seconds: 5),
    };
  }

  Future<T> _runWithNodeFailover<T>(
    Uri uri,
    Future<T> Function(String targetUrl) action, {
    CancelToken? cancelToken,
    int maxAttempts = 4,
  }) async {
    Object? lastError;
    String currentUrl = _effectiveUrl(uri.toString());

    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      if (cancelToken?.isCancelled ?? false) {
        throw DioException.requestCancelled(
          requestOptions: RequestOptions(path: currentUrl),
          reason: cancelToken?.cancelError?.error ?? 'Cancelled',
        );
      }
      try {
        return await action(currentUrl);
      } catch (error) {
        lastError = error;
        if (!_isRetryableNodeError(error) || attempt == maxAttempts - 1) {
          rethrow;
        }
        final isHandshake =
            error is HandshakeException ||
            (error is DioException && error.error is HandshakeException);
        if (isHandshake && currentUrl == uri.toString()) {
          final redirected = await _resolveHttpsCdnRedirect(
            uri,
            cancelToken: cancelToken,
          );
          if (redirected != null) {
            currentUrl = redirected;
            continue;
          }
        }
        _resetClient();
        await Future<void>.delayed(const Duration(milliseconds: 200));
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
    if (_useGoEngine) {
      try {
        await _goClient.cleanupPartialFiles(savePath);
        return;
      } catch (_) {}
    }

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
    if (_useGoEngine) {
      try {
        final saved = await _goClient.getSavedProgress(
          savePath,
          pausedLabel: pausedLabel,
        );
        return saved.connections;
      } catch (_) {}
    }

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

  Future<DownloadFileInfo> getFileInfo(
    String url, {
    String? username,
    String? password,
  }) async {
    final uri = Uri.tryParse(url);

    if (!DownloadLinkHelper.isSupportedUri(uri)) {
      throw ArgumentError('Invalid download URL');
    }

    if (_useGoEngine) {
      return _goClient.probe(url, username: username, password: password);
    }

    if (uri!.scheme.toLowerCase() == 'ftp') {
      return _ftpClient.getFileInfo(
        _applyFtpCredentials(uri, username, password),
      );
    }

    final authHeaders = _buildRequestHeaders(
      username: username,
      password: password,
    );

    Response<dynamic> response;
    try {
      response = await _runWithNodeFailover(
        uri,
        (targetUrl) => _dio.head(
          targetUrl,
          options: Options(
            followRedirects: true,
            headers: authHeaders.isNotEmpty ? authHeaders : null,
            validateStatus: (status) =>
                status != null && status >= 200 && status < 400,
          ),
        ),
      );
    } on DioException catch (error) {
      final code = error.response?.statusCode;
      // Fallback to a 1-byte Range GET when servers reject HEAD requests.
      if (code == 403 || code == 405 || code == 501) {
        final rangeHeaders = _buildRequestHeaders(
          username: username,
          password: password,
          extra: const {'Range': 'bytes=0-0'},
        );
        response = await _runWithNodeFailover(
          uri,
          (targetUrl) => _dio.get<List<int>>(
            targetUrl,
            options: Options(
              responseType: ResponseType.bytes,
              followRedirects: true,
              headers: rangeHeaders,
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
    final contentType = response.headers.value('content-type');
    final directCheck = DownloadLinkHelper.evaluateDirectDownload(
      uri: effectiveUri,
      contentType: contentType,
      contentDisposition: disposition,
    );

    return DownloadFileInfo(
      fileName: fileName,
      fileSize: fileSize,
      fileType: fileType,
      supportsResume: supportsResume,
      protocol: DownloadLinkHelper.protocolLabel(effectiveUri),
      isDirectDownload: directCheck.isDirect,
      directDownloadReason: directCheck.reason,
      contentType: contentType,
    );
  }

  Future<void> downloadFile({
    required String url,
    required String savePath,
    required void Function(int received, int total) onProgress,
    String? taskId,
    String? username,
    String? password,
    SpeedLimiter? speedLimiter,
    void Function(int attempt)? onReconnecting,
    bool Function()? isPauseRequested,
    CancelToken? cancelToken,
    int maxReconnectAttempts = 10,
  }) async {
    final uri = Uri.tryParse(url);

    if (!DownloadLinkHelper.isSupportedUri(uri)) {
      throw ArgumentError('Invalid download URL');
    }

    if (_useGoEngine) {
      await _goClient.streamDownload(
        id: taskId ?? savePath,
        url: url,
        savePath: savePath,
        segmented: false,
        speedLimitBytesPerSec: speedLimiter?.getMaxBytesPerSecond() ?? 0,
        username: username,
        password: password,
        maxReconnectAttempts: maxReconnectAttempts,
        cancelToken: cancelToken,
        isPauseRequested: isPauseRequested,
        onProgress: onProgress,
        onReconnecting: onReconnecting,
      );
      return;
    }

    if (uri!.scheme.toLowerCase() == 'ftp') {
      await _ftpClient.downloadFile(
        uri: _applyFtpCredentials(uri, username, password),
        savePath: savePath,
        onProgress: onProgress,
        speedLimiter: speedLimiter,
        onReconnecting: onReconnecting,
        cancelToken: cancelToken,
        maxReconnectAttempts: maxReconnectAttempts,
      );
      return;
    }

    final file = File(savePath);
    await file.parent.create(recursive: true);

    final stopwatch = Stopwatch()..start();
    var lastEmitMs = -200;
    int received = 0;
    int total = -1;
    bool serverSupportsRange = false;
    int attempt = 0;

    while (true) {
      if (cancelToken?.isCancelled ?? false) {
        throw DioException.requestCancelled(
          requestOptions: RequestOptions(path: url),
          reason: cancelToken?.cancelError?.error ?? 'Cancelled',
        );
      }

      final isResumingAfterDrop = received > 0 && serverSupportsRange;
      IOSink? sink;

      try {
        final targetUrl = _effectiveUrl(url);
        final reqHeaders = _buildRequestHeaders(
          username: username,
          password: password,
          extra: isResumingAfterDrop ? {'Range': 'bytes=$received-'} : null,
        );
        final response = await _dio.get<ResponseBody>(
          targetUrl,
          options: Options(
            responseType: ResponseType.stream,
            followRedirects: true,
            headers: reqHeaders.isNotEmpty ? reqHeaders : null,
            validateStatus: (status) => isResumingAfterDrop
                ? status == 206
                : (status != null && status >= 200 && status < 300),
          ),
          cancelToken: cancelToken,
        );

        final acceptRanges = response.headers.value('accept-ranges');
        if (acceptRanges?.toLowerCase() == 'bytes' ||
            response.statusCode == 206) {
          serverSupportsRange = true;
        }

        if (isResumingAfterDrop) {
          final contentRange = response.headers.value('content-range');
          if (contentRange != null && contentRange.contains('/')) {
            final parsedTotal = int.tryParse(contentRange.split('/').last);
            if (parsedTotal != null && parsedTotal > 0) {
              total = parsedTotal;
            }
          }
        } else {
          received = 0;
          final contentLength = response.headers.value('content-length');
          total = int.tryParse(contentLength ?? '') ?? -1;
        }

        sink = file.openWrite(
          mode: isResumingAfterDrop ? FileMode.append : FileMode.write,
        );

        await for (final chunk in response.data!.stream) {
          if (cancelToken?.isCancelled ?? false) {
            throw DioException.requestCancelled(
              requestOptions: response.requestOptions,
              reason: cancelToken?.cancelError?.error ?? 'Cancelled',
            );
          }

          sink.add(chunk);
          received += chunk.length;

          final nowMs = stopwatch.elapsedMilliseconds;
          final isComplete = total > 0 && received >= total;
          if (isComplete || nowMs - lastEmitMs >= 150) {
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

        if (total > 0 && received < total) {
          throw const HttpException('Connection closed prematurely');
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

        final isCancelled =
            (cancelToken?.isCancelled ?? false) ||
            (error is DioException && error.type == DioExceptionType.cancel);

        if (isCancelled ||
            !_isRetryableNodeError(error) ||
            attempt >= maxReconnectAttempts) {
          rethrow;
        }

        attempt++;
        onReconnecting?.call(attempt);
        _resetClient();
        await SpeedLimiter.cancellableDelay(
          _reconnectBackoff(attempt),
          cancelToken: cancelToken,
        );
      }
    }
  }

  Future<void> downloadFileSegmented({
    required String url,
    required String savePath,
    required int totalBytes,
    required void Function(int received, int total) onProgress,
    String? taskId,
    String? username,
    String? password,
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
    bool Function()? isPauseRequested,
    SpeedLimiter? speedLimiter,
    CancelToken? cancelToken,
    int connectionCount = defaultConnectionCount,
    bool resumeExisting = false,
    int maxReconnectAttempts = 10,
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

    if (_useGoEngine) {
      await _goClient.streamDownload(
        id: taskId ?? savePath,
        url: url,
        savePath: savePath,
        totalBytes: totalBytes,
        connectionCount: connectionCount,
        resumeExisting: resumeExisting,
        segmented: true,
        speedLimitBytesPerSec: speedLimiter?.getMaxBytesPerSecond() ?? 0,
        username: username,
        password: password,
        maxReconnectAttempts: maxReconnectAttempts,
        cancelToken: cancelToken,
        isPauseRequested: isPauseRequested,
        onProgress: onProgress,
        onConnectionsChanged: onConnectionsChanged,
        onSegmentedProgress: onSegmentedProgress,
        onReconnecting: onReconnecting,
        onRebuilding: onRebuilding,
      );
      return;
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
    String effectiveUrl = _effectiveUrl(url);
    final authHeaders = _buildRequestHeaders(
      username: username,
      password: password,
    );
    try {
      final headResp = await _runWithNodeFailover(
        uri,
        (targetUrl) => _dio.head(
          targetUrl,
          cancelToken: cancelToken,
          options: Options(
            followRedirects: true,
            headers: authHeaders.isNotEmpty ? authHeaders : null,
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

      final maxRetries = maxReconnectAttempts;
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
        segInfo[idx] = attempt == 0
            ? 'Connecting...'
            : 'Reconnecting ($attempt/$maxRetries)...';
        segActive[idx] = true;
        segError[idx] = false;
        emitProgress(force: true);

        IOSink? sink;
        try {
          final segHeaders = _buildRequestHeaders(
            username: username,
            password: password,
            extra: {'Range': 'bytes=$rangeStart-$rangeEnd'},
          );
          final response = await _dio.get<ResponseBody>(
            effectiveUrl,
            options: Options(
              responseType: ResponseType.stream,
              followRedirects: true,
              headers: segHeaders,
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

            if (speedLimiter != null) {
              await speedLimiter.throttle(
                bytesToWrite.length,
                cancelToken: sharedCancelToken,
              );
            }

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
            segInfo[idx] = 'Reconnecting ($attempt/$maxRetries)...';
            emitProgress(force: true);
            onReconnecting?.call(attempt);
            await SpeedLimiter.cancellableDelay(
              _reconnectBackoff(attempt),
              cancelToken: sharedCancelToken,
            );
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

          if (attempt < maxRetries && _isRetryableNodeError(error)) {
            attempt++;
            _resetClient();
            segDownloaded[idx] = currentSaved.clamp(0, spec.length);
            segInfo[idx] = 'Waiting for network ($attempt/$maxRetries)...';
            emitProgress(force: true);
            onReconnecting?.call(attempt);
            await SpeedLimiter.cancellableDelay(
              _reconnectBackoff(attempt),
              cancelToken: sharedCancelToken,
            );
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
    if (_useGoEngine) {
      try {
        final saved = await _goClient.getSavedProgress(savePath);
        return saved.downloadedBytes;
      } catch (_) {}
    }

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

  Future<bool> supportsResume(
    String url, {
    String? username,
    String? password,
    CancelToken? cancelToken,
  }) async {
    final uri = Uri.tryParse(url);
    if (!DownloadLinkHelper.isSupportedUri(uri)) return false;

    if (_useGoEngine) {
      try {
        final info = await _goClient.probe(
          url,
          username: username,
          password: password,
        );
        return info.supportsResume;
      } catch (_) {
        return false;
      }
    }

    if (uri!.scheme.toLowerCase() == 'ftp') {
      return _ftpClient.supportsResume(
        _applyFtpCredentials(uri, username, password),
      );
    }

    final authHeaders = _buildRequestHeaders(
      username: username,
      password: password,
    );

    try {
      final response = await _runWithNodeFailover(
        uri,
        (targetUrl) => _dio.head(
          targetUrl,
          cancelToken: cancelToken,
          options: Options(
            followRedirects: true,
            headers: authHeaders.isNotEmpty ? authHeaders : null,
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
    String? taskId,
    String? username,
    String? password,
    SpeedLimiter? speedLimiter,
    void Function(int attempt)? onReconnecting,
    bool Function()? isPauseRequested,
    CancelToken? cancelToken,
    int maxReconnectAttempts = 10,
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

    final uri = Uri.tryParse(url);
    if (!DownloadLinkHelper.isSupportedUri(uri)) {
      throw ArgumentError('Invalid download URL');
    }

    if (_useGoEngine) {
      await _goClient.streamDownload(
        id: taskId ?? savePath,
        url: url,
        savePath: savePath,
        resumeExisting: true,
        initialOffset: downloadedBytes,
        segmented: false,
        speedLimitBytesPerSec: speedLimiter?.getMaxBytesPerSecond() ?? 0,
        username: username,
        password: password,
        maxReconnectAttempts: maxReconnectAttempts,
        cancelToken: cancelToken,
        isPauseRequested: isPauseRequested,
        onProgress: onProgress,
        onReconnecting: onReconnecting,
      );
      return;
    }

    if (uri!.scheme.toLowerCase() == 'ftp') {
      await _ftpClient.downloadFile(
        uri: _applyFtpCredentials(uri, username, password),
        savePath: savePath,
        initialOffset: downloadedBytes,
        onProgress: onProgress,
        speedLimiter: speedLimiter,
        onReconnecting: onReconnecting,
        cancelToken: cancelToken,
        maxReconnectAttempts: maxReconnectAttempts,
      );
      return;
    }

    final stopwatch = Stopwatch()..start();
    var lastEmitMs = -200;
    var received = downloadedBytes;
    int? total;
    int attempt = 0;

    while (true) {
      if (cancelToken?.isCancelled ?? false) {
        throw DioException.requestCancelled(
          requestOptions: RequestOptions(path: url),
          reason: cancelToken?.cancelError?.error ?? 'Cancelled',
        );
      }

      IOSink? sink;
      try {
        final targetUrl = _effectiveUrl(url);
        final resumeHeaders = _buildRequestHeaders(
          username: username,
          password: password,
          extra: {'Range': 'bytes=$received-'},
        );
        final response = await _dio.get<ResponseBody>(
          targetUrl,
          options: Options(
            responseType: ResponseType.stream,
            followRedirects: true,
            headers: resumeHeaders,
            validateStatus: (status) => status == 206,
          ),
          cancelToken: cancelToken,
        );

        final contentRange = response.headers.value('content-range');

        if (contentRange == null ||
            !contentRange.startsWith('bytes $received-')) {
          throw Exception('Server returned an invalid Content-Range');
        }

        total = int.tryParse(contentRange.split('/').last);

        if (total == null) {
          throw Exception('Could not determine file size');
        }

        sink = file.openWrite(mode: FileMode.append);

        await for (final chunk in response.data!.stream) {
          if (cancelToken?.isCancelled ?? false) {
            throw DioException.requestCancelled(
              requestOptions: response.requestOptions,
              reason: cancelToken?.cancelError?.error ?? 'Cancelled',
            );
          }

          sink.add(chunk);
          received += chunk.length;
          final nowMs = stopwatch.elapsedMilliseconds;
          if (received >= total || nowMs - lastEmitMs >= 150) {
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

        if (received < total) {
          throw const HttpException('Connection closed prematurely');
        }

        onProgress(received, total);
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

        final isCancelled =
            (cancelToken?.isCancelled ?? false) ||
            (error is DioException && error.type == DioExceptionType.cancel);

        if (isCancelled ||
            !_isRetryableNodeError(error) ||
            attempt >= maxReconnectAttempts) {
          rethrow;
        }

        attempt++;
        onReconnecting?.call(attempt);
        _resetClient();
        await SpeedLimiter.cancellableDelay(
          _reconnectBackoff(attempt),
          cancelToken: cancelToken,
        );
      }
    }
  }
}
