import 'dart:io';

import 'package:dio/dio.dart';
import 'package:download_manager/features/downloads/models/download_file_info.dart';
import 'package:download_manager/features/downloads/models/download_progress_state.dart';
import 'package:download_manager/features/downloads/services/download_path_service.dart';
import 'package:download_manager/features/downloads/services/download_service.dart';
import 'package:flutter/foundation.dart';

class DownloadManagerController extends ChangeNotifier {
  static const List<String> categories = [
    'All Downloads',
    'Compressed',
    'Documents',
    'Music',
    'Program',
    'Video',
    'Unfinished',
    'Finished',
    'Queues',
  ];

  final DownloadService downloadService;
  final DownloadPathService downloadPathService;
  final void Function(String message)? onMessage;

  DownloadManagerController({
    DownloadService? downloadService,
    DownloadPathService? downloadPathService,
    this.onMessage,
  }) : downloadService = downloadService ?? DownloadService(),
       downloadPathService = downloadPathService ?? DownloadPathService();

  String selectedCategory = 'All Downloads';
  int selectedFileIndex = 0;
  String downloadDirectory = '';

  int? _activeDownloadIndex;
  bool _isDownloadRunning = false;
  int _lastReceivedBytes = 0;
  DateTime? _lastProgressTime;
  bool _isPauseRequested = false;
  bool _disposed = false;

  CancelToken? _downloadCancelToken;
  final ValueNotifier<DownloadProgressState?> progressNotifier =
      ValueNotifier<DownloadProgressState?>(null);
  List<String>? _progressWindowFile;
  bool isProgressWindowVisible = false;

  final Map<String, bool> _resumeCapabilityByUrl = {};
  final Map<String, int> _knownTotalBytesByUrl = {};
  final Map<String, int> _downloadedBytesByUrl = {};

  final List<List<String>> files = [];

  int get queuedCount => files.where((file) => file[2] == 'Queued').length;

  List<String>? get progressWindowFile => _progressWindowFile;

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  void _emitMessage(String message) {
    if (!_disposed) {
      onMessage?.call(message);
    }
  }

  Future<void> loadDownloadDirectory() async {
    final path = await downloadPathService.getSavedPath();
    if (_disposed) return;

    downloadDirectory = path;
    _notify();
    _emitMessage('Download location updated successfully');
  }

  void updateDownloadDirectory(String path) {
    downloadDirectory = path;
    _notify();
  }

  void selectCategory(String category) {
    if (selectedCategory == category) return;
    selectedCategory = category;
    _notify();
  }

  void selectFile(int index) {
    if (index < 0 || index >= files.length || selectedFileIndex == index) {
      return;
    }
    selectedFileIndex = index;
    _notify();
  }

  void closeProgressWindow() {
    if (!isProgressWindowVisible) return;
    isProgressWindowVisible = false;
    _notify();
  }

  String formatErrorMessage(Object error) {
    if (error is DioException) {
      final statusCode = error.response?.statusCode;
      if (statusCode != null) {
        return 'Server returned HTTP $statusCode';
      }
      if (error.message != null && error.message!.trim().isNotEmpty) {
        return error.message!.trim();
      }
      return 'Network error (${error.type.name})';
    }

    final text = error.toString();
    if (text.startsWith('Exception: ')) {
      return text.substring('Exception: '.length);
    }
    return text;
  }

  void _openProgressWindowForFile(
    List<String> file,
    DownloadProgressState state,
  ) {
    if (_disposed) return;

    _progressWindowFile = file;
    progressNotifier.value = state;

    if (!isProgressWindowVisible) {
      isProgressWindowVisible = true;
      _notify();
    }
  }

  void _updateProgressWindowForFile(
    List<String> file,
    DownloadProgressState Function(DownloadProgressState current) updater,
  ) {
    if (_disposed || !identical(_progressWindowFile, file)) return;

    final current = progressNotifier.value;
    if (current == null) return;

    progressNotifier.value = updater(current);
  }

  Future<void> _probeResumeCapability(
    String url,
    List<String> file,
    CancelToken cancelToken,
  ) async {
    final supported = await downloadService.supportsResume(
      url,
      cancelToken: cancelToken,
    );

    if (_disposed || cancelToken.isCancelled) return;

    _resumeCapabilityByUrl[url] = supported;
    _updateProgressWindowForFile(
      file,
      (current) => current.copyWith(supportsResume: supported),
    );
  }

  Future<void> openFolderForPath(String savePath) async {
    if (savePath.isEmpty) return;

    try {
      final file = File(savePath);
      if (Platform.isWindows) {
        if (await file.exists()) {
          await Process.run('explorer.exe', ['/select,$savePath']);
        } else if (await file.parent.exists()) {
          await Process.run('explorer.exe', [file.parent.path]);
        } else {
          _emitMessage('Download folder does not exist yet.');
        }
      }
    } catch (error) {
      _emitMessage('Could not open folder: $error');
    }
  }

  void openExistingProgressWindow(int index) {
    if (index < 0 || index >= files.length) return;
    selectedFileIndex = index;
    final file = files[index];
    _notify();

    if (file.length < 7 || file[6].isEmpty) return;

    if (identical(_progressWindowFile, file) && progressNotifier.value != null) {
      if (!isProgressWindowVisible) {
        isProgressWindowVisible = true;
        _notify();
      }
      return;
    }

    final url = file[6];
    final fileName = file[0];
    final savePath = file.length >= 8 ? file[7] : '';
    final category = downloadPathService.getCategoryForFile(fileName);
    final status = switch (file[2]) {
      'Downloading' => DownloadProgressStatus.downloading,
      'Paused' => DownloadProgressStatus.paused,
      'Stopped' => DownloadProgressStatus.stopped,
      'Failed' => DownloadProgressStatus.failed,
      'Finished' => DownloadProgressStatus.completed,
      _ => DownloadProgressStatus.connecting,
    };

    final totalBytes = _knownTotalBytesByUrl[url];
    final downloadedBytes = status == DownloadProgressStatus.completed
        ? (totalBytes ?? _downloadedBytesByUrl[url] ?? 0)
        : (_downloadedBytesByUrl[url] ?? 0);

    _openProgressWindowForFile(
      file,
      DownloadProgressState(
        url: url,
        fileName: fileName,
        savePath: savePath,
        category: category,
        status: status,
        downloadedBytes: downloadedBytes,
        totalBytes: totalBytes,
        supportsResume: _resumeCapabilityByUrl[url],
        startedAt: DateTime.now(),
      ),
    );

    if (savePath.isNotEmpty && status == DownloadProgressStatus.paused) {
      downloadService.getSavedConnectionProgress(savePath).then((segments) {
        if (_disposed || segments.isEmpty) return;
        _updateProgressWindowForFile(
          file,
          (current) => current.copyWith(connectionSegments: segments),
        );
      });
    }
  }

  Future<void> addDownload({
    required String url,
    DownloadFileInfo? fileInfo,
  }) async {
    final uri = Uri.tryParse(url);

    if (uri == null ||
        !uri.hasAuthority ||
        !uri.hasScheme ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      _emitMessage('Please enter a valid HTTP or HTTPS URL');
      return;
    }

    final isDuplicate = files.any(
      (file) => file.length >= 7 && file[6] == url,
    );

    if (isDuplicate) {
      _emitMessage('This download already exists in the list');
      return;
    }

    final fileName =
        fileInfo?.fileName ??
        (uri.pathSegments.isNotEmpty && uri.pathSegments.last.isNotEmpty
            ? Uri.decodeComponent(uri.pathSegments.last)
            : 'download_${DateTime.now().millisecondsSinceEpoch}');

    final fileSize = fileInfo?.formattedSize ?? 'Unknown';

    if (fileInfo != null) {
      _resumeCapabilityByUrl[url] = fileInfo.supportsResume;
      if (fileInfo.fileSize != null && fileInfo.fileSize! > 0) {
        _knownTotalBytesByUrl[url] = fileInfo.fileSize!;
      }
    }

    final shouldStartNow = !_isDownloadRunning;

    files.add([fileName, fileSize, 'Queued', '—', '—', '0', url]);
    if (shouldStartNow) {
      selectedFileIndex = files.length - 1;
    }
    _notify();

    _emitMessage('Download added to queue');

    if (shouldStartNow) {
      await startSelectedDownload();
    }
  }

  Future<void> startSelectedDownload() async {
    if (files.isEmpty) return;
    await _startDownloadAt(selectedFileIndex);
  }

  Future<void> _startDownloadAt(int index) async {
    if (files.isEmpty || index < 0 || index >= files.length) return;

    if (_isDownloadRunning) {
      _emitMessage('Please wait until the previous download stops.');
      return;
    }

    final file = files[index];
    if (file[2] == 'Finished') return;

    if (file.length < 7 || file[6].isEmpty) {
      _emitMessage('Please add a download URL first.');
      return;
    }

    final url = file[6];
    final displayFileName = file[0];
    final safeFileName = displayFileName.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
    final category = downloadPathService.getCategoryForFile(safeFileName);

    final savePath = file.length >= 8 && file[7].isNotEmpty
        ? file[7]
        : await downloadPathService.getFilePath(
            fileName: safeFileName,
            category: category,
          );

    if (_disposed) return;

    final currentIndex = files.indexOf(file);
    if (currentIndex == -1 || _isDownloadRunning) return;

    if (file.length < 8) {
      file.add(savePath);
    } else {
      file[7] = savePath;
    }

    final shouldResume = file[2] == 'Paused';
    final cancelToken = CancelToken();
    final knownTotalBytes = _knownTotalBytesByUrl[url];
    final initialDownloadedBytes =
        shouldResume ? (_downloadedBytesByUrl[url] ?? 0) : 0;

    _isDownloadRunning = true;
    _downloadCancelToken = cancelToken;
    _activeDownloadIndex = currentIndex;
    _isPauseRequested = false;
    _lastReceivedBytes = initialDownloadedBytes;
    _lastProgressTime = null;

    file[2] = 'Downloading';
    file[3] = 'Connecting...';
    file[4] = 'Calculating...';
    if (!shouldResume) {
      file[5] = '0';
    }
    _notify();

    _openProgressWindowForFile(
      file,
      DownloadProgressState(
        url: url,
        fileName: displayFileName,
        savePath: savePath,
        category: category,
        status: DownloadProgressStatus.connecting,
        downloadedBytes: initialDownloadedBytes,
        totalBytes: knownTotalBytes,
        supportsResume: _resumeCapabilityByUrl[url],
        isResumedTransfer: shouldResume && initialDownloadedBytes > 0,
        resumeStartBytes: shouldResume ? initialDownloadedBytes : 0,
        startedAt: DateTime.now(),
      ),
    );

    bool downloadCompleted = false;
    double currentSpeed = 0;
    Duration? currentRemaining;
    int latestReceived = initialDownloadedBytes;
    int latestTotal = knownTotalBytes ?? -1;

    try {
      int downloadedBytes = 0;

      if (shouldResume) {
        downloadedBytes = await downloadService.getDownloadedBytes(savePath);
        if (_disposed) return;

        latestReceived = downloadedBytes;
        _downloadedBytesByUrl[url] = downloadedBytes;

        final savedSegments = await downloadService.getSavedConnectionProgress(
          savePath,
          pausedLabel: 'Connecting...',
        );
        if (_disposed) return;

        _updateProgressWindowForFile(
          file,
          (current) => current.copyWith(
            downloadedBytes: downloadedBytes,
            isResumedTransfer: downloadedBytes > 0,
            resumeStartBytes: downloadedBytes,
            connectionSegments: savedSegments.isNotEmpty
                ? savedSegments
                : current.connectionSegments,
          ),
        );
      }

      if (_resumeCapabilityByUrl[url] == null ||
          _knownTotalBytesByUrl[url] == null) {
        try {
          final info = await downloadService.getFileInfo(url);
          if (_disposed || cancelToken.isCancelled) return;

          _resumeCapabilityByUrl[url] = info.supportsResume;
          if (info.fileSize != null && info.fileSize! > 0) {
            _knownTotalBytesByUrl[url] = info.fileSize!;
            latestTotal = info.fileSize!;
            file[1] = info.formattedSize;
            _notify();
          }

          _updateProgressWindowForFile(
            file,
            (current) => current.copyWith(
              supportsResume: info.supportsResume,
              totalBytes: info.fileSize ?? current.totalBytes,
            ),
          );
        } catch (_) {
          if (!shouldResume && _resumeCapabilityByUrl[url] == null) {
            _probeResumeCapability(url, file, cancelToken);
          }
        }
      }

      void handleProgress(
        int received,
        int total, {
        List<DownloadConnectionProgress>? connections,
      }) {
        if (_disposed || !identical(_downloadCancelToken, cancelToken)) return;

        latestReceived = received;
        _downloadedBytesByUrl[url] = received;

        if (total > 0) {
          latestTotal = total;
          _knownTotalBytesByUrl[url] = total;
        }

        bool listRowChanged = false;
        final now = DateTime.now();
        final previousTime = _lastProgressTime;

        if (previousTime != null) {
          final elapsed = now.difference(previousTime).inMilliseconds / 1000;

          if (elapsed >= 0.75) {
            final deltaBytes = received - _lastReceivedBytes;
            final speed = deltaBytes / elapsed;

            if (speed > 0) {
              currentSpeed = speed;
              final formattedSpeed = DownloadProgressState.formatSpeed(speed);
              if (file[3] != formattedSpeed) {
                file[3] = formattedSpeed;
                listRowChanged = true;
              }

              if (total > 0 && received <= total) {
                final remainingSeconds = ((total - received) / speed).ceil();
                currentRemaining = Duration(seconds: remainingSeconds);
                final formattedRemaining = DownloadProgressState.formatDuration(
                  currentRemaining!,
                );
                if (file[4] != formattedRemaining) {
                  file[4] = formattedRemaining;
                  listRowChanged = true;
                }
              } else {
                currentRemaining = null;
                if (file[4] != 'Unknown') {
                  file[4] = 'Unknown';
                  listRowChanged = true;
                }
              }
            }

            _lastReceivedBytes = received;
            _lastProgressTime = now;
          }
        } else {
          _lastReceivedBytes = received;
          _lastProgressTime = now;
        }

        if (total > 0) {
          final nextPct = ((received / total) * 100)
              .clamp(0, 100)
              .toStringAsFixed(0);
          final nextSize = DownloadProgressState.formatBytes(total);
          if (file[5] != nextPct) {
            file[5] = nextPct;
            listRowChanged = true;
          }
          if (file[1] != nextSize) {
            file[1] = nextSize;
            listRowChanged = true;
          }
        }

        // Only rebuild the main window file list when visible list cells changed.
        if (listRowChanged) {
          _notify();
        }

        _updateProgressWindowForFile(
          file,
          (current) => current.copyWith(
            status: current.status == DownloadProgressStatus.rebuilding
                ? DownloadProgressStatus.rebuilding
                : DownloadProgressStatus.downloading,
            downloadedBytes: received,
            totalBytes: total > 0 ? total : current.totalBytes,
            speedBytesPerSecond: currentSpeed,
            remainingTime: currentRemaining,
            clearRemainingTime: currentRemaining == null,
            supportsResume: _resumeCapabilityByUrl[url] ?? current.supportsResume,
            connectionSegments: connections ?? current.connectionSegments,
          ),
        );
      }

      void rebuildingCallback() {
        if (_disposed || !identical(_downloadCancelToken, cancelToken)) return;

        file[3] = 'Rebuilding...';
        file[4] = '—';
        _notify();

        _updateProgressWindowForFile(
          file,
          (current) => current.copyWith(
            status: DownloadProgressStatus.rebuilding,
            speedBytesPerSecond: 0,
            clearRemainingTime: true,
          ),
        );
      }

      final hasSegmented = await downloadService.hasSegmentedState(savePath);
      if (_disposed) return;

      final resolvedTotal = _knownTotalBytesByUrl[url];
      final canUseSegmented =
          _resumeCapabilityByUrl[url] == true &&
          resolvedTotal != null &&
          resolvedTotal >= DownloadService.minSegmentedSizeBytes;

      if (shouldResume && hasSegmented && resolvedTotal != null) {
        final canResume = await downloadService.supportsResume(
          url,
          cancelToken: cancelToken,
        );
        if (_disposed) return;

        _resumeCapabilityByUrl[url] = canResume;
        _updateProgressWindowForFile(
          file,
          (current) => current.copyWith(supportsResume: canResume),
        );

        if (!canResume) {
          throw Exception('Server does not support download resume.');
        }

        _lastReceivedBytes = downloadedBytes;

        await downloadService.downloadFileSegmented(
          url: url,
          savePath: savePath,
          totalBytes: resolvedTotal,
          cancelToken: cancelToken,
          resumeExisting: true,
          onProgress: (r, t) => handleProgress(r, t),
          onSegmentedProgress: (r, t, conns) =>
              handleProgress(r, t, connections: conns),
          onRebuilding: rebuildingCallback,
        );
      } else if (shouldResume && downloadedBytes > 0) {
        final canResume = await downloadService.supportsResume(
          url,
          cancelToken: cancelToken,
        );
        if (_disposed) return;

        _resumeCapabilityByUrl[url] = canResume;
        _updateProgressWindowForFile(
          file,
          (current) => current.copyWith(supportsResume: canResume),
        );

        if (!canResume) {
          throw Exception('Server does not support download resume.');
        }

        _lastReceivedBytes = downloadedBytes;

        await downloadService.resumeDownload(
          url: url,
          savePath: savePath,
          downloadedBytes: downloadedBytes,
          cancelToken: cancelToken,
          onProgress: (r, t) => handleProgress(r, t),
        );
      } else if (canUseSegmented) {
        await downloadService.downloadFileSegmented(
          url: url,
          savePath: savePath,
          totalBytes: resolvedTotal,
          cancelToken: cancelToken,
          resumeExisting: false,
          onProgress: (r, t) => handleProgress(r, t),
          onSegmentedProgress: (r, t, conns) =>
              handleProgress(r, t, connections: conns),
          onRebuilding: rebuildingCallback,
        );
      } else {
        await downloadService.downloadFile(
          url: url,
          savePath: savePath,
          cancelToken: cancelToken,
          onProgress: (r, t) => handleProgress(r, t),
        );
      }

      if (_disposed) return;

      int finalTotalBytes = latestTotal > 0
          ? latestTotal
          : await downloadService.getDownloadedBytes(savePath);
      if (_disposed) return;

      if (finalTotalBytes <= 0 && latestReceived > 0) {
        finalTotalBytes = latestReceived;
      }

      if (finalTotalBytes > 0) {
        _knownTotalBytesByUrl[url] = finalTotalBytes;
        _downloadedBytesByUrl[url] = finalTotalBytes;
      }

      if (finalTotalBytes > 0) {
        file[1] = DownloadProgressState.formatBytes(finalTotalBytes);
      }
      file[2] = 'Finished';
      file[3] = '—';
      file[4] = '—';
      file[5] = '100';
      _notify();

      _updateProgressWindowForFile(
        file,
        (current) => current.copyWith(
          status: DownloadProgressStatus.completed,
          downloadedBytes: finalTotalBytes > 0
              ? finalTotalBytes
              : current.downloadedBytes,
          totalBytes: finalTotalBytes > 0 ? finalTotalBytes : current.totalBytes,
          speedBytesPerSecond: 0,
          clearRemainingTime: true,
          clearErrorMessage: true,
        ),
      );

      downloadCompleted = true;
      _emitMessage('Download completed: $displayFileName');
    } catch (error) {
      if (_disposed) return;

      final cancelled =
          (error is DioException && error.type == DioExceptionType.cancel) ||
          cancelToken.isCancelled;

      final paused = cancelled && _isPauseRequested;
      int pausedBytes = latestReceived;
      List<DownloadConnectionProgress> savedSegments = const [];

      if (cancelled && !paused) {
        await downloadService.cleanupPartialFiles(savePath);
        _downloadedBytesByUrl[url] = 0;
      } else if (paused) {
        pausedBytes = await downloadService.getDownloadedBytes(savePath);
        savedSegments = await downloadService.getSavedConnectionProgress(
          savePath,
          pausedLabel: 'Paused',
        );
        _downloadedBytesByUrl[url] = pausedBytes;
      }

      if (_disposed) return;

      file[2] = paused
          ? 'Paused'
          : cancelled
          ? 'Stopped'
          : 'Failed';
      file[3] = '—';
      file[4] = '—';
      if (!paused) {
        file[5] = '0';
      }
      _notify();

      if (paused) {
        _updateProgressWindowForFile(
          file,
          (current) => current.copyWith(
            status: DownloadProgressStatus.paused,
            downloadedBytes: pausedBytes,
            speedBytesPerSecond: 0,
            connectionSegments: savedSegments.isNotEmpty
                ? savedSegments
                : current.connectionSegments,
            clearRemainingTime: true,
            clearErrorMessage: true,
          ),
        );
      } else if (cancelled) {
        _updateProgressWindowForFile(
          file,
          (current) => current.copyWith(
            status: DownloadProgressStatus.stopped,
            downloadedBytes: 0,
            speedBytesPerSecond: 0,
            connectionSegments: const [],
            clearRemainingTime: true,
            clearErrorMessage: true,
          ),
        );
      } else {
        final message = formatErrorMessage(error);
        _updateProgressWindowForFile(
          file,
          (current) => current.copyWith(
            status: DownloadProgressStatus.failed,
            downloadedBytes: 0,
            speedBytesPerSecond: 0,
            clearRemainingTime: true,
            errorMessage: message,
          ),
        );
      }

      if (!cancelled) {
        _emitMessage('Download failed: ${formatErrorMessage(error)}');
      }
    } finally {
      if (identical(_downloadCancelToken, cancelToken)) {
        _isDownloadRunning = false;
        _downloadCancelToken = null;
        _activeDownloadIndex = null;
      }
    }

    if (downloadCompleted && !_disposed) {
      final nextIndex = _getNextQueuedDownload();
      if (nextIndex != null) {
        selectedFileIndex = nextIndex;
        _notify();
        await _startDownloadAt(nextIndex);
      }
    }
  }

  int? _getNextQueuedDownload() {
    for (int i = 0; i < files.length; i++) {
      if (files[i][2] == 'Queued') {
        return i;
      }
    }
    return null;
  }

  void pauseSelectedDownload() {
    if (files.isEmpty) return;
    pauseDownloadForFile(files[selectedFileIndex]);
  }

  void pauseDownloadForFile(List<String> targetFile) {
    final index = files.indexOf(targetFile);
    if (index == -1) return;

    if (_isDownloadRunning &&
        _downloadCancelToken != null &&
        _activeDownloadIndex == index) {
      _isPauseRequested = true;
      _downloadCancelToken!.cancel('Paused by user');
      return;
    }

    if (targetFile[2] == 'Queued') {
      targetFile[2] = 'Paused';
      _notify();

      _updateProgressWindowForFile(
        targetFile,
        (current) => current.copyWith(
          status: DownloadProgressStatus.paused,
          speedBytesPerSecond: 0,
          clearRemainingTime: true,
        ),
      );
    }
  }

  void resumeDownloadForFile(List<String> targetFile) {
    final index = files.indexOf(targetFile);
    if (index == -1) return;

    selectedFileIndex = index;
    _notify();
    _startDownloadAt(index);
  }

  Future<void> stopSelectedDownload() async {
    if (files.isEmpty) return;
    await stopDownloadForFile(files[selectedFileIndex]);
  }

  Future<void> stopDownloadForFile(List<String> targetFile) async {
    final index = files.indexOf(targetFile);
    if (index == -1) return;

    if (targetFile[2] == 'Finished') return;

    if (_isDownloadRunning &&
        _downloadCancelToken != null &&
        _activeDownloadIndex == index) {
      _isPauseRequested = false;
      _downloadCancelToken!.cancel('Stopped by user');
      return;
    }

    final savePath = targetFile.length >= 8 && targetFile[7].isNotEmpty
        ? targetFile[7]
        : await downloadPathService.getFilePath(
            fileName: targetFile[0].replaceAll(RegExp(r'[<>:"/\\|?*]'), '_'),
            category: downloadPathService.getCategoryForFile(targetFile[0]),
          );
    await downloadService.cleanupPartialFiles(savePath);

    if (targetFile.length >= 7 && targetFile[6].isNotEmpty) {
      _downloadedBytesByUrl[targetFile[6]] = 0;
    }

    if (_disposed) return;

    targetFile[2] = 'Stopped';
    targetFile[3] = '—';
    targetFile[4] = '—';
    targetFile[5] = '0';
    _notify();

    _updateProgressWindowForFile(
      targetFile,
      (current) => current.copyWith(
        status: DownloadProgressStatus.stopped,
        downloadedBytes: 0,
        speedBytesPerSecond: 0,
        connectionSegments: const [],
        clearRemainingTime: true,
        clearErrorMessage: true,
      ),
    );
  }

  void retrySelectedDownload() {
    if (files.isEmpty) return;
    retryDownloadForFile(files[selectedFileIndex]);
  }

  void retryDownloadForFile(List<String> targetFile) {
    final index = files.indexOf(targetFile);
    if (index == -1) return;

    final status = targetFile[2];
    if (status != 'Failed' && status != 'Stopped') {
      _emitMessage('Only failed or stopped downloads can be retried.');
      return;
    }

    selectedFileIndex = index;
    _notify();
    _startDownloadAt(index);
  }

  void deleteSelectedDownload() {
    if (files.isEmpty) return;

    final removedIndex = selectedFileIndex;
    final removedFile = files[removedIndex];

    if (_isDownloadRunning && _activeDownloadIndex == removedIndex) {
      _isPauseRequested = false;
      _downloadCancelToken?.cancel('Deleted by user');
    }

    files.removeAt(removedIndex);

    if (_activeDownloadIndex != null) {
      if (_activeDownloadIndex == removedIndex) {
        _activeDownloadIndex = null;
      } else if (removedIndex < _activeDownloadIndex!) {
        _activeDownloadIndex = _activeDownloadIndex! - 1;
      }
    }

    if (identical(_progressWindowFile, removedFile)) {
      isProgressWindowVisible = false;
      _progressWindowFile = null;
      progressNotifier.value = null;
    }

    if (files.isEmpty) {
      selectedFileIndex = 0;
    } else if (selectedFileIndex >= files.length) {
      selectedFileIndex = files.length - 1;
    }

    _notify();
  }

  void moveQueuedFile(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= files.length) return;
    if (newIndex < 0 || newIndex >= files.length) return;
    if (oldIndex == newIndex) return;

    if (files[oldIndex][2] != 'Queued' || files[newIndex][2] != 'Queued') {
      return;
    }

    final movedFile = files.removeAt(oldIndex);
    files.insert(newIndex, movedFile);

    if (selectedFileIndex == oldIndex) {
      selectedFileIndex = newIndex;
    } else if (oldIndex < selectedFileIndex && newIndex >= selectedFileIndex) {
      selectedFileIndex--;
    } else if (oldIndex > selectedFileIndex && newIndex <= selectedFileIndex) {
      selectedFileIndex++;
    }

    if (_activeDownloadIndex != null) {
      if (_activeDownloadIndex == oldIndex) {
        _activeDownloadIndex = newIndex;
      } else if (oldIndex < _activeDownloadIndex! &&
          newIndex >= _activeDownloadIndex!) {
        _activeDownloadIndex = _activeDownloadIndex! - 1;
      } else if (oldIndex > _activeDownloadIndex! &&
          newIndex <= _activeDownloadIndex!) {
        _activeDownloadIndex = _activeDownloadIndex! + 1;
      }
    }

    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    _downloadCancelToken?.cancel('Controller disposed');
    progressNotifier.dispose();
    super.dispose();
  }
}
