import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:download_manager/features/downloads/models/download_entry.dart';
import 'package:download_manager/features/downloads/models/download_file_info.dart';
import 'package:download_manager/features/downloads/models/download_progress_state.dart';
import 'package:download_manager/features/downloads/models/download_schedule_config.dart';
import 'package:download_manager/features/downloads/services/download_path_service.dart';
import 'package:download_manager/features/downloads/services/download_service.dart';
import 'package:download_manager/features/downloads/services/speed_limiter.dart';
import 'package:download_manager/features/downloads/utils/download_link_helper.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ActiveDownloadSession {
  final DownloadService service;
  final CancelToken cancelToken;
  final SpeedLimiter speedLimiter;
  bool isPauseRequested = false;
  int lastReceivedBytes = 0;
  DateTime? lastProgressTime;

  _ActiveDownloadSession({
    required this.service,
    required this.cancelToken,
    required this.speedLimiter,
    this.lastReceivedBytes = 0,
  });
}

class DownloadManagerController extends ChangeNotifier {
  static const String _maxConcurrentKey = 'max_concurrent_downloads';
  static const String _segmentsPerDownloadKey = 'segments_per_download';
  static const String _speedLimitEnabledKey = 'speed_limit_enabled';
  static const String _speedLimitKbpsKey = 'speed_limit_kbps';

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
  final DownloadService Function() _serviceFactory;
  final DownloadPathService downloadPathService;
  final void Function(String message)? onMessage;

  DownloadManagerController({
    DownloadService? downloadService,
    DownloadService Function()? serviceFactory,
    DownloadPathService? downloadPathService,
    this.onMessage,
  }) : downloadService = downloadService ?? DownloadService(),
       _serviceFactory = serviceFactory ?? (() => DownloadService()),
       downloadPathService = downloadPathService ?? DownloadPathService() {
    _schedulerTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => checkSchedules(),
    );
  }

  String selectedCategory = 'All Downloads';
  String searchQuery = '';
  String? selectedFileId;
  String downloadDirectory = '';
  DownloadScheduleConfig scheduleConfig = const DownloadScheduleConfig();

  int _idCounter = 0;
  bool _disposed = false;
  Timer? _schedulerTimer;

  final List<DownloadEntry> files = [];
  final Map<String, _ActiveDownloadSession> _activeSessions = {};
  final Map<String, DownloadProgressState> _progressById = {};
  final Map<String, int> _entrySpeedLimitBytesById = {};

  final ValueNotifier<DownloadProgressState?> progressNotifier =
      ValueNotifier<DownloadProgressState?>(null);
  String? _progressWindowEntryId;
  bool isProgressWindowVisible = false;

  int get activeDownloadCount => _activeSessions.length;

  int get queuedCount =>
      files.where((entry) => entry.isQueued || entry.isScheduled).length;

  int get scheduledCount => files.where((entry) => entry.isScheduled).length;

  int get maxConcurrentDownloads => scheduleConfig.maxConcurrentDownloads;

  String? get progressWindowEntryId => _progressWindowEntryId;

  DownloadEntry? get selectedEntry {
    if (selectedFileId == null) return files.isEmpty ? null : files.first;
    return findEntryById(selectedFileId!);
  }

  List<DownloadEntry> get visibleFiles {
    final query = searchQuery.trim().toLowerCase();
    return files.where((entry) {
      if (!_matchesCategory(entry, selectedCategory)) {
        return false;
      }
      if (query.isEmpty) return true;
      return entry.fileName.toLowerCase().contains(query) ||
          entry.url.toLowerCase().contains(query);
    }).toList(growable: false);
  }

  bool _matchesCategory(DownloadEntry entry, String category) {
    return switch (category) {
      'All Downloads' => true,
      'Compressed' => entry.category == 'Compressed',
      'Documents' => entry.category == 'Documents',
      'Music' => entry.category == 'Music',
      'Program' => entry.category == 'Programs',
      'Video' => entry.category == 'Videos',
      'Unfinished' => entry.isUnfinished,
      'Finished' => entry.isFinished,
      'Queues' => entry.isQueued || entry.isScheduled,
      _ => true,
    };
  }

  DownloadEntry? findEntryById(String id) {
    for (final entry in files) {
      if (entry.id == id) return entry;
    }
    return null;
  }

  String _nextId() => 'dl_${DateTime.now().microsecondsSinceEpoch}_${++_idCounter}';

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

  Future<void> initialize() async {
    await Future.wait([loadDownloadDirectory(), _loadSettings()]);
  }

  Future<void> loadDownloadDirectory() async {
    final path = await downloadPathService.getSavedPath();
    if (_disposed) return;

    downloadDirectory = path;
    _notify();
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_disposed) return;

      final savedMax = prefs.getInt(_maxConcurrentKey);
      final savedSegments = prefs.getInt(_segmentsPerDownloadKey);
      final savedSpeedEnabled = prefs.getBool(_speedLimitEnabledKey);
      final savedSpeedKbps = prefs.getInt(_speedLimitKbpsKey);

      scheduleConfig = scheduleConfig.copyWith(
        maxConcurrentDownloads:
            (savedMax != null && savedMax >= 1 && savedMax <= 8)
            ? savedMax
            : null,
        segmentsPerDownload:
            (savedSegments != null && savedSegments >= 1 && savedSegments <= 16)
            ? savedSegments
            : null,
        speedLimitEnabled: savedSpeedEnabled,
        speedLimitKBps: (savedSpeedKbps != null && savedSpeedKbps > 0)
            ? savedSpeedKbps
            : null,
      );
      _notify();
    } catch (_) {}
  }

  Future<void> updateScheduleConfig(DownloadScheduleConfig nextConfig) async {
    final clampedMax = nextConfig.maxConcurrentDownloads.clamp(1, 8);
    final clampedSegments = nextConfig.segmentsPerDownload.clamp(1, 16);
    final clampedKbps = nextConfig.speedLimitKBps.clamp(16, 1024 * 1024);

    scheduleConfig = nextConfig.copyWith(
      maxConcurrentDownloads: clampedMax,
      segmentsPerDownload: clampedSegments,
      speedLimitKBps: clampedKbps,
    );

    // Sync active progress states with updated effective speed limit.
    for (final entry in files) {
      final limitBps = effectiveSpeedLimitForEntry(entry.id);
      final activeSession = _activeSessions[entry.id];
      if (activeSession != null) {
        unawaited(activeSession.service.setLiveSpeedLimit(entry.id, limitBps));
      }
      _updateProgressForEntry(
        entry,
        (current) => current.copyWith(
          speedLimitBytesPerSecond: limitBps > 0 ? limitBps : null,
          clearSpeedLimit: limitBps <= 0,
        ),
      );
    }

    _notify();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_maxConcurrentKey, clampedMax);
      await prefs.setInt(_segmentsPerDownloadKey, clampedSegments);
      await prefs.setBool(
        _speedLimitEnabledKey,
        scheduleConfig.speedLimitEnabled,
      );
      await prefs.setInt(_speedLimitKbpsKey, clampedKbps);
    } catch (_) {}

    if (_activeSessions.isNotEmpty) {
      _pumpQueue();
    }
  }

  int effectiveSpeedLimitForEntry(String entryId) {
    final overrideBps = _entrySpeedLimitBytesById[entryId];
    if (overrideBps != null) {
      return overrideBps;
    }
    return scheduleConfig.effectiveSpeedLimitBytesPerSecond;
  }

  void setEntrySpeedLimit(String entryId, int bytesPerSecond) {
    if (bytesPerSecond <= 0) {
      _entrySpeedLimitBytesById[entryId] = 0;
    } else {
      _entrySpeedLimitBytesById[entryId] = bytesPerSecond;
    }

    final entry = findEntryById(entryId);
    if (entry != null) {
      final activeLimit = effectiveSpeedLimitForEntry(entryId);
      final activeSession = _activeSessions[entryId];
      if (activeSession != null) {
        unawaited(
          activeSession.service.setLiveSpeedLimit(entryId, activeLimit),
        );
      }
      _updateProgressForEntry(
        entry,
        (current) => current.copyWith(
          speedLimitBytesPerSecond: activeLimit > 0 ? activeLimit : null,
          clearSpeedLimit: activeLimit <= 0,
        ),
      );
    }
    _notify();
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

  void updateSearchQuery(String query) {
    if (searchQuery == query) return;
    searchQuery = query;
    _notify();
  }

  void selectFileById(String id) {
    if (selectedFileId == id) return;
    selectedFileId = id;
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
      if (error.error is HandshakeException) {
        return 'SSL certificate error';
      }
      if (error.error is SocketException) {
        return 'Connection failed (check internet)';
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

  void _openProgressWindowForEntry(
    DownloadEntry entry,
    DownloadProgressState state,
  ) {
    if (_disposed) return;

    _progressById[entry.id] = state;
    _progressWindowEntryId = entry.id;
    progressNotifier.value = state;

    if (!isProgressWindowVisible) {
      isProgressWindowVisible = true;
      _notify();
    }
  }

  void _updateProgressForEntry(
    DownloadEntry entry,
    DownloadProgressState Function(DownloadProgressState current) updater,
  ) {
    if (_disposed) return;

    final current = _progressById[entry.id];
    if (current == null) return;

    final next = updater(current);
    _progressById[entry.id] = next;

    if (_progressWindowEntryId == entry.id) {
      progressNotifier.value = next;
    }
  }

  Future<void> _probeResumeCapability(
    DownloadEntry entry,
    _ActiveDownloadSession session,
  ) async {
    final supported = await session.service.supportsResume(
      entry.url,
      username: entry.username,
      password: entry.password,
      cancelToken: session.cancelToken,
    );

    if (_disposed || session.cancelToken.isCancelled) return;

    entry.supportsResume = supported;
    _updateProgressForEntry(
      entry,
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

  void openExistingProgressWindow(String entryId) {
    final entry = findEntryById(entryId);
    if (entry == null) return;

    selectedFileId = entry.id;
    _notify();

    if (entry.url.isEmpty) return;

    final cached = _progressById[entry.id];
    if (cached != null) {
      _progressWindowEntryId = entry.id;
      progressNotifier.value = cached;
      if (!isProgressWindowVisible) {
        isProgressWindowVisible = true;
        _notify();
      }
      return;
    }

    final status = switch (entry.status) {
      'Downloading' => DownloadProgressStatus.downloading,
      'Paused' => DownloadProgressStatus.paused,
      'Stopped' => DownloadProgressStatus.stopped,
      'Failed' => DownloadProgressStatus.failed,
      'Finished' => DownloadProgressStatus.completed,
      _ => DownloadProgressStatus.connecting,
    };

    final downloadedBytes = status == DownloadProgressStatus.completed
        ? (entry.totalBytes ?? entry.downloadedBytes)
        : entry.downloadedBytes;

    _openProgressWindowForEntry(
      entry,
      DownloadProgressState(
        url: entry.url,
        fileName: entry.fileName,
        savePath: entry.savePath,
        category: entry.category,
        status: status,
        downloadedBytes: downloadedBytes,
        totalBytes: entry.totalBytes,
        supportsResume: entry.supportsResume,
        startedAt: DateTime.now(),
      ),
    );

    if (entry.savePath.isNotEmpty && status == DownloadProgressStatus.paused) {
      downloadService.getSavedConnectionProgress(entry.savePath).then((
        segments,
      ) {
        if (_disposed || segments.isEmpty) return;
        _updateProgressForEntry(
          entry,
          (current) => current.copyWith(connectionSegments: segments),
        );
      });
    }
  }

  Future<DownloadEntry?> addDownload({
    required String url,
    DownloadFileInfo? fileInfo,
    bool startNow = true,
    DateTime? scheduledAt,
    String? username,
    String? password,
    String? savePath,
    String? category,
  }) async {
    final uri = Uri.tryParse(url);

    if (!DownloadLinkHelper.isSupportedUri(uri)) {
      _emitMessage('Please enter a valid HTTP, HTTPS, or FTP URL');
      return null;
    }

    final isDuplicate = files.any((entry) => entry.url == url);
    if (isDuplicate) {
      _emitMessage('This download already exists in the list');
      return null;
    }

    String fileName =
        fileInfo?.fileName ??
        (uri!.pathSegments.isNotEmpty && uri.pathSegments.last.isNotEmpty
            ? Uri.decodeComponent(uri.pathSegments.last)
            : 'download_${DateTime.now().millisecondsSinceEpoch}');

    final customSavePath = savePath?.trim() ?? '';
    if (customSavePath.isNotEmpty) {
      final sep = Platform.pathSeparator;
      final lastSep = customSavePath.lastIndexOf(sep);
      if (lastSep != -1 && lastSep < customSavePath.length - 1) {
        fileName = customSavePath.substring(lastSep + 1);
      }
    }

    final resolvedCategory =
        (category != null && category.isNotEmpty)
        ? category
        : downloadPathService.getCategoryForFile(fileName);
    final isScheduled =
        scheduledAt != null && scheduledAt.isAfter(DateTime.now());

    final entry = DownloadEntry(
      id: _nextId(),
      fileName: fileName,
      url: url,
      savePath: customSavePath,
      category: resolvedCategory,
      sizeText: fileInfo?.formattedSize ?? 'Unknown',
      status: isScheduled ? 'Scheduled' : 'Queued',
      totalBytes: fileInfo?.fileSize,
      supportsResume: fileInfo?.supportsResume,
      scheduledAt: isScheduled ? scheduledAt : null,
      username: username,
      password: password,
    );

    if (isScheduled) {
      entry.timeLeftText = 'At ${entry.formattedScheduleTime}';
    }

    files.add(entry);
    selectedFileId = entry.id;
    _notify();

    if (isScheduled) {
      _emitMessage(
        'Scheduled "${entry.fileName}" for ${DownloadScheduleConfig.formatScheduleDateTime(scheduledAt)}',
      );
      return entry;
    }

    if (startNow) {
      if (_activeSessions.length < maxConcurrentDownloads) {
        unawaited(_startDownloadEntry(entry));
      } else {
        _emitMessage(
          'Added to queue ($activeDownloadCount/$maxConcurrentDownloads active)',
        );
      }
    } else {
      _emitMessage('Download added to queue');
    }

    return entry;
  }

  void scheduleEntry(String entryId, DateTime? scheduledAt) {
    final entry = findEntryById(entryId);
    if (entry == null || entry.isFinished || entry.isDownloading) return;

    if (scheduledAt == null) {
      entry.scheduledAt = null;
      if (entry.isScheduled) {
        entry.status = 'Queued';
        entry.timeLeftText = '—';
      }
      _notify();
      _emitMessage('Schedule cleared for ${entry.fileName}');
      return;
    }

    entry.scheduledAt = scheduledAt;
    entry.status = 'Scheduled';
    entry.speedText = '—';
    entry.timeLeftText = 'At ${entry.formattedScheduleTime}';
    _notify();

    _emitMessage(
      'Scheduled "${entry.fileName}" for ${DownloadScheduleConfig.formatScheduleDateTime(scheduledAt)}',
    );
  }

  @visibleForTesting
  void checkSchedules([DateTime? nowOverride]) {
    if (_disposed) return;
    final now = nowOverride ?? DateTime.now();

    // 1. Trigger individual scheduled downloads whose time has arrived.
    final triggeredEntries = <DownloadEntry>[];
    for (final entry in files) {
      if (entry.isScheduled &&
          entry.scheduledAt != null &&
          !now.isBefore(entry.scheduledAt!)) {
        entry.scheduledAt = null;
        entry.status = 'Queued';
        entry.timeLeftText = '—';
        triggeredEntries.add(entry);
        _emitMessage('Scheduled download starting: ${entry.fileName}');
      }
    }
    if (triggeredEntries.isNotEmpty) {
      _notify();
      for (final entry in triggeredEntries) {
        if (_activeSessions.length >= maxConcurrentDownloads) break;
        if (!_activeSessions.containsKey(entry.id)) {
          unawaited(_startDownloadEntry(entry));
        }
      }
    }

    // 2. Trigger global queue auto-start schedule.
    if (scheduleConfig.autoStartQueueEnabled &&
        scheduleConfig.queueStartTime != null &&
        !now.isBefore(scheduleConfig.queueStartTime!)) {
      scheduleConfig = scheduleConfig.copyWith(autoStartQueueEnabled: false);
      _notify();
      _emitMessage('Scheduled queue started automatically');
      startQueue();
    }

    // 3. Trigger global auto-stop (pause all active downloads).
    if (scheduleConfig.autoStopEnabled &&
        scheduleConfig.queueStopTime != null &&
        !now.isBefore(scheduleConfig.queueStopTime!)) {
      scheduleConfig = scheduleConfig.copyWith(autoStopEnabled: false);
      _notify();
      if (_activeSessions.isNotEmpty) {
        pauseAllDownloads();
        _emitMessage('Active downloads paused by schedule');
      }
    }
  }

  void startQueue() {
    if (_disposed) return;
    final queued = files.where((e) => e.isQueued).toList();
    if (queued.isEmpty) {
      _emitMessage('No queued downloads to start.');
      return;
    }
    _pumpQueue();
  }

  void _pumpQueue() {
    if (_disposed) return;

    for (final entry in files) {
      if (_activeSessions.length >= maxConcurrentDownloads) {
        break;
      }
      if (entry.isQueued && !_activeSessions.containsKey(entry.id)) {
        unawaited(_startDownloadEntry(entry));
      }
    }
  }

  void pauseAllDownloads() {
    final activeIds = _activeSessions.keys.toList();
    for (final id in activeIds) {
      pauseDownloadById(id);
    }
  }

  Future<void> startSelectedDownload() async {
    final entry = selectedEntry;
    if (entry == null) return;
    await startDownloadById(entry.id);
  }

  Future<void> startDownloadById(String entryId) async {
    final entry = findEntryById(entryId);
    if (entry == null) return;

    if (entry.isFinished) return;

    if (_activeSessions.containsKey(entry.id)) {
      openExistingProgressWindow(entry.id);
      return;
    }

    if (_activeSessions.length >= maxConcurrentDownloads) {
      entry.scheduledAt = null;
      entry.status = 'Queued';
      entry.timeLeftText = '—';
      _notify();
      _emitMessage(
        'Maximum simultaneous downloads ($maxConcurrentDownloads) active — queued.',
      );
      return;
    }

    await _startDownloadEntry(entry);
  }

  Future<void> _startDownloadEntry(DownloadEntry entry) async {
    if (_disposed || entry.isFinished) return;
    if (_activeSessions.containsKey(entry.id)) return;

    if (entry.url.isEmpty) {
      _emitMessage('Please add a download URL first.');
      return;
    }

    final url = entry.url;
    final displayFileName = entry.fileName;
    final safeFileName = displayFileName.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
    final category = downloadPathService.getCategoryForFile(safeFileName);
    entry.category = category;

    // Reserve active slot immediately before async path lookup to prevent double starts.
    final cancelToken = CancelToken();
    final sessionService = _serviceFactory();
    final speedLimiter = SpeedLimiter(
      () => effectiveSpeedLimitForEntry(entry.id),
    );
    final shouldResume = entry.isPaused;
    final initialDownloadedBytes = shouldResume ? entry.downloadedBytes : 0;

    final session = _ActiveDownloadSession(
      service: sessionService,
      cancelToken: cancelToken,
      speedLimiter: speedLimiter,
      lastReceivedBytes: initialDownloadedBytes,
    );
    _activeSessions[entry.id] = session;

    final savePath = entry.savePath.isNotEmpty
        ? entry.savePath
        : await downloadPathService.getFilePath(
            fileName: safeFileName,
            category: category,
          );

    if (_disposed || !files.contains(entry) || cancelToken.isCancelled) {
      _activeSessions.remove(entry.id);
      return;
    }

    entry.savePath = savePath;
    entry.scheduledAt = null;
    entry.status = 'Downloading';
    entry.speedText = 'Connecting...';
    entry.timeLeftText = 'Calculating...';
    if (!shouldResume) {
      entry.progressPercent = 0;
      entry.downloadedBytes = 0;
    }
    _notify();

    final initialLimit = effectiveSpeedLimitForEntry(entry.id);
    _openProgressWindowForEntry(
      entry,
      DownloadProgressState(
        url: url,
        fileName: displayFileName,
        savePath: savePath,
        category: category,
        status: DownloadProgressStatus.connecting,
        downloadedBytes: initialDownloadedBytes,
        totalBytes: entry.totalBytes,
        supportsResume: entry.supportsResume,
        isResumedTransfer: shouldResume && initialDownloadedBytes > 0,
        resumeStartBytes: shouldResume ? initialDownloadedBytes : 0,
        speedLimitBytesPerSecond: initialLimit > 0 ? initialLimit : null,
        startedAt: DateTime.now(),
      ),
    );

    bool downloadCompleted = false;
    double currentSpeed = 0;
    Duration? currentRemaining;
    int latestReceived = initialDownloadedBytes;
    int latestTotal = entry.totalBytes ?? -1;

    try {
      int downloadedBytes = 0;

      if (shouldResume) {
        downloadedBytes = await sessionService.getDownloadedBytes(savePath);
        if (_disposed) return;

        latestReceived = downloadedBytes;
        entry.downloadedBytes = downloadedBytes;

        final savedSegments = await sessionService.getSavedConnectionProgress(
          savePath,
          pausedLabel: 'Connecting...',
        );
        if (_disposed) return;

        _updateProgressForEntry(
          entry,
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

      if (entry.supportsResume == null || entry.totalBytes == null) {
        try {
          final info = await sessionService.getFileInfo(
            url,
            username: entry.username,
            password: entry.password,
          );
          if (_disposed || cancelToken.isCancelled) return;

          entry.supportsResume = info.supportsResume;
          if (info.fileSize != null && info.fileSize! > 0) {
            entry.totalBytes = info.fileSize!;
            latestTotal = info.fileSize!;
            entry.sizeText = info.formattedSize;
            _notify();
          }

          _updateProgressForEntry(
            entry,
            (current) => current.copyWith(
              supportsResume: info.supportsResume,
              totalBytes: info.fileSize ?? current.totalBytes,
            ),
          );
        } catch (_) {
          if (!shouldResume && entry.supportsResume == null) {
            unawaited(_probeResumeCapability(entry, session));
          }
        }
      }

      void handleProgress(
        int received,
        int total, {
        List<DownloadConnectionProgress>? connections,
      }) {
        if (_disposed || !identical(_activeSessions[entry.id], session)) return;

        latestReceived = received;
        entry.downloadedBytes = received;

        if (total > 0) {
          latestTotal = total;
          entry.totalBytes = total;
        }

        bool listRowChanged = false;
        final now = DateTime.now();
        final previousTime = session.lastProgressTime;

        if (previousTime != null) {
          final elapsed = now.difference(previousTime).inMilliseconds / 1000;

          if (elapsed >= 0.75) {
            final deltaBytes = received - session.lastReceivedBytes;
            final speed = deltaBytes / elapsed;

            if (speed > 0) {
              currentSpeed = speed;
              final formattedSpeed = DownloadProgressState.formatSpeed(speed);
              if (entry.speedText != formattedSpeed) {
                entry.speedText = formattedSpeed;
                listRowChanged = true;
              }

              if (total > 0 && received <= total) {
                final remainingSeconds = ((total - received) / speed).ceil();
                currentRemaining = Duration(seconds: remainingSeconds);
                final formattedRemaining = DownloadProgressState.formatDuration(
                  currentRemaining!,
                );
                if (entry.timeLeftText != formattedRemaining) {
                  entry.timeLeftText = formattedRemaining;
                  listRowChanged = true;
                }
              } else {
                currentRemaining = null;
                if (entry.timeLeftText != 'Unknown') {
                  entry.timeLeftText = 'Unknown';
                  listRowChanged = true;
                }
              }
            }

            session.lastReceivedBytes = received;
            session.lastProgressTime = now;
          }
        } else {
          session.lastReceivedBytes = received;
          session.lastProgressTime = now;
        }

        if (total > 0) {
          final nextPct = ((received / total) * 100).round().clamp(0, 100);
          final nextSize = DownloadProgressState.formatBytes(total);
          if (entry.progressPercent != nextPct) {
            entry.progressPercent = nextPct;
            listRowChanged = true;
          }
          if (entry.sizeText != nextSize) {
            entry.sizeText = nextSize;
            listRowChanged = true;
          }
        }

        if (listRowChanged) {
          _notify();
        }

        _updateProgressForEntry(
          entry,
          (current) => current.copyWith(
            status: current.status == DownloadProgressStatus.rebuilding
                ? DownloadProgressStatus.rebuilding
                : DownloadProgressStatus.downloading,
            downloadedBytes: received,
            totalBytes: total > 0 ? total : current.totalBytes,
            speedBytesPerSecond: currentSpeed,
            remainingTime: currentRemaining,
            clearRemainingTime: currentRemaining == null,
            supportsResume: entry.supportsResume ?? current.supportsResume,
            connectionSegments: connections ?? current.connectionSegments,
          ),
        );
      }

      void reconnectingCallback(int attempt) {
        if (_disposed || !identical(_activeSessions[entry.id], session)) return;

        entry.speedText = 'Reconnecting...';
        entry.timeLeftText = 'Attempt $attempt';
        _notify();

        _updateProgressForEntry(
          entry,
          (current) => current.copyWith(
            status: DownloadProgressStatus.reconnecting,
            speedBytesPerSecond: 0,
            clearRemainingTime: true,
          ),
        );
      }

      void rebuildingCallback() {
        if (_disposed || !identical(_activeSessions[entry.id], session)) return;

        entry.speedText = 'Rebuilding...';
        entry.timeLeftText = '—';
        _notify();

        _updateProgressForEntry(
          entry,
          (current) => current.copyWith(
            status: DownloadProgressStatus.rebuilding,
            speedBytesPerSecond: 0,
            clearRemainingTime: true,
          ),
        );
      }

      final hasSegmented = await sessionService.hasSegmentedState(savePath);
      if (_disposed) return;

      final resolvedTotal = entry.totalBytes;
      final isHttpProtocol =
          url.toLowerCase().startsWith('http://') ||
          url.toLowerCase().startsWith('https://');
      final canUseSegmented =
          isHttpProtocol &&
          scheduleConfig.segmentsPerDownload > 1 &&
          entry.supportsResume == true &&
          resolvedTotal != null &&
          resolvedTotal >= DownloadService.minSegmentedSizeBytes;

      if (shouldResume && hasSegmented && resolvedTotal != null) {
        final canResume = await sessionService.supportsResume(
          url,
          username: entry.username,
          password: entry.password,
          cancelToken: cancelToken,
        );
        if (_disposed) return;

        entry.supportsResume = canResume;
        _updateProgressForEntry(
          entry,
          (current) => current.copyWith(supportsResume: canResume),
        );

        if (!canResume) {
          throw Exception('Server does not support download resume.');
        }

        session.lastReceivedBytes = downloadedBytes;

        await sessionService.downloadFileSegmented(
          taskId: entry.id,
          url: url,
          savePath: savePath,
          totalBytes: resolvedTotal,
          username: entry.username,
          password: entry.password,
          connectionCount: scheduleConfig.segmentsPerDownload,
          speedLimiter: session.speedLimiter,
          isPauseRequested: () => session.isPauseRequested,
          cancelToken: cancelToken,
          resumeExisting: true,
          onProgress: (r, t) => handleProgress(r, t),
          onSegmentedProgress: (r, t, conns) =>
              handleProgress(r, t, connections: conns),
          onReconnecting: reconnectingCallback,
          onRebuilding: rebuildingCallback,
        );
      } else if (shouldResume && downloadedBytes > 0) {
        final canResume = await sessionService.supportsResume(
          url,
          username: entry.username,
          password: entry.password,
          cancelToken: cancelToken,
        );
        if (_disposed) return;

        entry.supportsResume = canResume;
        _updateProgressForEntry(
          entry,
          (current) => current.copyWith(supportsResume: canResume),
        );

        if (!canResume) {
          throw Exception('Server does not support download resume.');
        }

        session.lastReceivedBytes = downloadedBytes;

        await sessionService.resumeDownload(
          taskId: entry.id,
          url: url,
          savePath: savePath,
          downloadedBytes: downloadedBytes,
          username: entry.username,
          password: entry.password,
          speedLimiter: session.speedLimiter,
          isPauseRequested: () => session.isPauseRequested,
          onReconnecting: reconnectingCallback,
          cancelToken: cancelToken,
          onProgress: (r, t) => handleProgress(r, t),
        );
      } else if (canUseSegmented) {
        await sessionService.downloadFileSegmented(
          taskId: entry.id,
          url: url,
          savePath: savePath,
          totalBytes: resolvedTotal,
          username: entry.username,
          password: entry.password,
          connectionCount: scheduleConfig.segmentsPerDownload,
          speedLimiter: session.speedLimiter,
          isPauseRequested: () => session.isPauseRequested,
          cancelToken: cancelToken,
          resumeExisting: false,
          onProgress: (r, t) => handleProgress(r, t),
          onSegmentedProgress: (r, t, conns) =>
              handleProgress(r, t, connections: conns),
          onReconnecting: reconnectingCallback,
          onRebuilding: rebuildingCallback,
        );
      } else {
        await sessionService.downloadFile(
          taskId: entry.id,
          url: url,
          savePath: savePath,
          username: entry.username,
          password: entry.password,
          speedLimiter: session.speedLimiter,
          isPauseRequested: () => session.isPauseRequested,
          onReconnecting: reconnectingCallback,
          cancelToken: cancelToken,
          onProgress: (r, t) => handleProgress(r, t),
        );
      }

      if (_disposed) return;

      int finalTotalBytes = latestTotal > 0
          ? latestTotal
          : await sessionService.getDownloadedBytes(savePath);
      if (_disposed) return;

      if (finalTotalBytes <= 0 && latestReceived > 0) {
        finalTotalBytes = latestReceived;
      }

      if (finalTotalBytes > 0) {
        entry.totalBytes = finalTotalBytes;
        entry.downloadedBytes = finalTotalBytes;
        entry.sizeText = DownloadProgressState.formatBytes(finalTotalBytes);
      }

      entry.status = 'Finished';
      entry.speedText = '—';
      entry.timeLeftText = '—';
      entry.progressPercent = 100;
      _notify();

      _updateProgressForEntry(
        entry,
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

      final paused = cancelled && session.isPauseRequested;
      int pausedBytes = latestReceived;
      List<DownloadConnectionProgress> savedSegments = const [];

      if (cancelled && !paused) {
        await sessionService.cleanupPartialFiles(savePath);
        entry.downloadedBytes = 0;
      } else if (paused) {
        pausedBytes = await sessionService.getDownloadedBytes(savePath);
        savedSegments = await sessionService.getSavedConnectionProgress(
          savePath,
          pausedLabel: 'Paused',
        );
        entry.downloadedBytes = pausedBytes;
      }

      if (_disposed) return;

      entry.status = paused
          ? 'Paused'
          : cancelled
          ? 'Stopped'
          : 'Failed';
      entry.speedText = '—';
      entry.timeLeftText = '—';
      if (!paused) {
        entry.progressPercent = 0;
      }
      _notify();

      if (paused) {
        _updateProgressForEntry(
          entry,
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
        _updateProgressForEntry(
          entry,
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
        _updateProgressForEntry(
          entry,
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
      if (identical(_activeSessions[entry.id], session)) {
        _activeSessions.remove(entry.id);
      }
    }

    if (downloadCompleted &&
        !_disposed &&
        !scheduleConfig.autoStartQueueEnabled) {
      _pumpQueue();
    }
  }

  void pauseSelectedDownload() {
    final entry = selectedEntry;
    if (entry == null) return;
    pauseDownloadById(entry.id);
  }

  void pauseDownloadById(String entryId) {
    final entry = findEntryById(entryId);
    if (entry == null) return;

    final session = _activeSessions[entry.id];
    if (session != null) {
      session.isPauseRequested = true;
      session.cancelToken.cancel('Paused by user');
      return;
    }

    if (entry.isQueued || entry.isScheduled) {
      entry.scheduledAt = null;
      entry.status = 'Paused';
      entry.timeLeftText = '—';
      _notify();

      _updateProgressForEntry(
        entry,
        (current) => current.copyWith(
          status: DownloadProgressStatus.paused,
          speedBytesPerSecond: 0,
          clearRemainingTime: true,
        ),
      );
    }
  }

  void resumeDownloadById(String entryId) {
    final entry = findEntryById(entryId);
    if (entry == null) return;

    selectedFileId = entry.id;
    _notify();
    startDownloadById(entry.id);
  }

  Future<void> stopSelectedDownload() async {
    final entry = selectedEntry;
    if (entry == null) return;
    await stopDownloadById(entry.id);
  }

  Future<void> stopDownloadById(String entryId) async {
    final entry = findEntryById(entryId);
    if (entry == null || entry.isFinished) return;

    final session = _activeSessions[entry.id];
    if (session != null) {
      session.isPauseRequested = false;
      session.cancelToken.cancel('Stopped by user');
      return;
    }

    final savePath = entry.savePath.isNotEmpty
        ? entry.savePath
        : await downloadPathService.getFilePath(
            fileName: entry.fileName.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_'),
            category: downloadPathService.getCategoryForFile(entry.fileName),
          );
    await downloadService.cleanupPartialFiles(savePath);

    if (_disposed) return;

    entry.scheduledAt = null;
    entry.status = 'Stopped';
    entry.speedText = '—';
    entry.timeLeftText = '—';
    entry.progressPercent = 0;
    entry.downloadedBytes = 0;
    _notify();

    _updateProgressForEntry(
      entry,
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
    final entry = selectedEntry;
    if (entry == null) return;
    retryDownloadById(entry.id);
  }

  void retryDownloadById(String entryId) {
    final entry = findEntryById(entryId);
    if (entry == null) return;

    if (!entry.isFailed && !entry.isStopped) {
      _emitMessage('Only failed or stopped downloads can be retried.');
      return;
    }

    selectedFileId = entry.id;
    _notify();
    startDownloadById(entry.id);
  }

  Future<void> deleteSelectedDownload() async {
    final entry = selectedEntry;
    if (entry == null) return;
    await deleteDownloadById(entry.id);
  }

  Future<void> deleteDownloadById(String entryId) async {
    final index = files.indexWhere((e) => e.id == entryId);
    if (index == -1) return;

    final removed = files[index];
    final session = _activeSessions.remove(removed.id);
    if (session != null) {
      session.isPauseRequested = false;
      session.cancelToken.cancel('Deleted by user');
    }

    files.removeAt(index);
    _progressById.remove(removed.id);

    if (_progressWindowEntryId == removed.id) {
      isProgressWindowVisible = false;
      _progressWindowEntryId = null;
      progressNotifier.value = null;
    }

    if (selectedFileId == removed.id) {
      if (files.isEmpty) {
        selectedFileId = null;
      } else {
        final nextIdx = index >= files.length ? files.length - 1 : index;
        selectedFileId = files[nextIdx].id;
      }
    }

    _notify();

    if (!removed.isFinished && removed.savePath.isNotEmpty) {
      await downloadService.cleanupPartialFiles(removed.savePath);
    }

    if (!_disposed &&
        !scheduleConfig.autoStartQueueEnabled &&
        _activeSessions.length < maxConcurrentDownloads) {
      _pumpQueue();
    }
  }

  void moveQueuedEntry(String fromId, String toId) {
    if (fromId == toId) return;
    final oldIndex = files.indexWhere((e) => e.id == fromId);
    final newIndex = files.indexWhere((e) => e.id == toId);
    if (oldIndex == -1 || newIndex == -1) return;

    if (!files[oldIndex].isQueued || !files[newIndex].isQueued) {
      return;
    }

    final moved = files.removeAt(oldIndex);
    files.insert(newIndex, moved);
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    _schedulerTimer?.cancel();
    for (final session in _activeSessions.values) {
      session.cancelToken.cancel('Controller disposed');
    }
    _activeSessions.clear();
    progressNotifier.dispose();
    super.dispose();
  }
}
