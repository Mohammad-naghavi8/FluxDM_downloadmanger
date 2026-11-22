enum DownloadProgressStatus {
  connecting,
  downloading,
  rebuilding,
  paused,
  stopped,
  failed,
  completed,
}

class DownloadConnectionProgress {
  final int number;
  final int startByte;
  final int downloadedBytes;
  final int? endByte;
  final String info;
  final bool isActive;
  final bool isCompleted;
  final bool hasError;

  const DownloadConnectionProgress({
    required this.number,
    required this.startByte,
    required this.downloadedBytes,
    this.endByte,
    required this.info,
    this.isActive = false,
    this.isCompleted = false,
    this.hasError = false,
  });

  String get formattedDownloaded =>
      DownloadProgressState.formatBytes(downloadedBytes);

  DownloadConnectionProgress copyWith({
    int? number,
    int? startByte,
    int? downloadedBytes,
    int? endByte,
    String? info,
    bool? isActive,
    bool? isCompleted,
    bool? hasError,
  }) {
    return DownloadConnectionProgress(
      number: number ?? this.number,
      startByte: startByte ?? this.startByte,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      endByte: endByte ?? this.endByte,
      info: info ?? this.info,
      isActive: isActive ?? this.isActive,
      isCompleted: isCompleted ?? this.isCompleted,
      hasError: hasError ?? this.hasError,
    );
  }
}

class DownloadProgressState {
  final String url;
  final String fileName;
  final String savePath;
  final String category;
  final DownloadProgressStatus status;
  final int downloadedBytes;
  final int? totalBytes;
  final double speedBytesPerSecond;
  final Duration? remainingTime;
  final bool? supportsResume;
  final bool isResumedTransfer;
  final int resumeStartBytes;
  final List<DownloadConnectionProgress> connectionSegments;
  final String? errorMessage;
  final DateTime startedAt;

  const DownloadProgressState({
    required this.url,
    required this.fileName,
    required this.savePath,
    required this.category,
    required this.status,
    this.downloadedBytes = 0,
    this.totalBytes,
    this.speedBytesPerSecond = 0,
    this.remainingTime,
    this.supportsResume,
    this.isResumedTransfer = false,
    this.resumeStartBytes = 0,
    this.connectionSegments = const [],
    this.errorMessage,
    required this.startedAt,
  });

  bool get isActive =>
      status == DownloadProgressStatus.connecting ||
      status == DownloadProgressStatus.downloading ||
      status == DownloadProgressStatus.rebuilding;

  bool get isPaused => status == DownloadProgressStatus.paused;

  bool get isStopped => status == DownloadProgressStatus.stopped;

  bool get isFailed => status == DownloadProgressStatus.failed;

  bool get isCompleted => status == DownloadProgressStatus.completed;

  double? get progress {
    if (status == DownloadProgressStatus.completed) return 1.0;
    if (status == DownloadProgressStatus.stopped) return 0.0;

    if (totalBytes != null && totalBytes! > 0) {
      return (downloadedBytes / totalBytes!).clamp(0.0, 1.0);
    }

    if (status == DownloadProgressStatus.failed) return 0.0;
    return null;
  }

  int? get percentageInt {
    final value = progress;
    if (value == null) return null;
    return (value * 100).round().clamp(0, 100);
  }

  String get percentageLabel {
    final pct = percentageInt;
    if (pct == null) return '—';
    return '$pct%';
  }

  String get titleText {
    final pct = percentageInt;
    if (pct == null) return fileName;
    return '$pct% $fileName';
  }

  String get statusLabel {
    return switch (status) {
      DownloadProgressStatus.connecting => 'Connecting...',
      DownloadProgressStatus.downloading => 'Receiving data...',
      DownloadProgressStatus.rebuilding => 'Rebuilding file...',
      DownloadProgressStatus.paused => 'Paused',
      DownloadProgressStatus.stopped => 'Stopped',
      DownloadProgressStatus.failed => 'Failed',
      DownloadProgressStatus.completed => 'Completed',
    };
  }

  String get formattedFileSize {
    if (totalBytes == null || totalBytes! <= 0) return 'Unknown';
    return formatBytes(totalBytes!);
  }

  String get formattedDownloaded {
    return formatBytes(downloadedBytes);
  }

  String get formattedTransferRate {
    if (status == DownloadProgressStatus.connecting) return 'Connecting...';
    if (status != DownloadProgressStatus.downloading) return '—';
    if (speedBytesPerSecond <= 0) return 'Calculating...';
    return formatSpeed(speedBytesPerSecond);
  }

  String get formattedTimeLeft {
    if (status == DownloadProgressStatus.connecting) return 'Calculating...';
    if (status != DownloadProgressStatus.downloading) return '—';
    if (speedBytesPerSecond <= 0) return 'Calculating...';
    if (remainingTime == null) return 'Unknown';
    return formatDuration(remainingTime!);
  }

  String get resumeCapabilityLabel {
    if (supportsResume == true) return 'Yes';
    if (supportsResume == false) return 'No';
    return isActive ? 'Checking...' : 'Unknown';
  }

  String get serverHost {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return 'Unknown';
    return uri.host;
  }

  String get exactBytesSummary {
    final downloaded = formatExactNumber(downloadedBytes);
    if (totalBytes != null && totalBytes! > 0) {
      return '$downloaded / ${formatExactNumber(totalBytes!)} bytes';
    }
    return '$downloaded bytes';
  }

  List<DownloadConnectionProgress> get connections {
    if (connectionSegments.isNotEmpty) {
      return connectionSegments;
    }

    final activeInfo = switch (status) {
      DownloadProgressStatus.connecting =>
        isResumedTransfer && resumeStartBytes > 0
            ? 'Sending GET (Range: bytes=$resumeStartBytes-)...'
            : 'Connecting to $serverHost...',
      DownloadProgressStatus.downloading =>
        speedBytesPerSecond > 0
            ? 'Receiving data... (${formatSpeed(speedBytesPerSecond)})'
            : 'Receiving data...',
      DownloadProgressStatus.rebuilding => 'Rebuilding file...',
      DownloadProgressStatus.paused =>
        'Disconnected (Paused at ${formatBytes(downloadedBytes)})',
      DownloadProgressStatus.stopped => 'Disconnected (Stopped)',
      DownloadProgressStatus.failed =>
        'Error: ${(errorMessage != null && errorMessage!.isNotEmpty) ? errorMessage : 'Connection failed'}',
      DownloadProgressStatus.completed => 'Completed',
    };

    if (isResumedTransfer && resumeStartBytes > 0) {
      final resumedSessionBytes =
          (downloadedBytes - resumeStartBytes).clamp(0, downloadedBytes);

      return [
        DownloadConnectionProgress(
          number: 1,
          startByte: 0,
          downloadedBytes: resumeStartBytes,
          endByte: resumeStartBytes,
          info: 'Saved on disk (0 B – ${formatBytes(resumeStartBytes)})',
          isActive: false,
          isCompleted: true,
        ),
        DownloadConnectionProgress(
          number: 2,
          startByte: resumeStartBytes,
          downloadedBytes: resumedSessionBytes,
          endByte: totalBytes,
          info: activeInfo,
          isActive: isActive,
          isCompleted: isCompleted,
        ),
      ];
    }

    return [
      DownloadConnectionProgress(
        number: 1,
        startByte: 0,
        downloadedBytes: downloadedBytes,
        endByte: totalBytes,
        info: activeInfo,
        isActive: isActive,
        isCompleted: isCompleted,
      ),
    ];
  }

  DownloadProgressState copyWith({
    String? url,
    String? fileName,
    String? savePath,
    String? category,
    DownloadProgressStatus? status,
    int? downloadedBytes,
    int? totalBytes,
    bool clearTotalBytes = false,
    double? speedBytesPerSecond,
    Duration? remainingTime,
    bool clearRemainingTime = false,
    bool? supportsResume,
    bool? isResumedTransfer,
    int? resumeStartBytes,
    List<DownloadConnectionProgress>? connectionSegments,
    String? errorMessage,
    bool clearErrorMessage = false,
    DateTime? startedAt,
  }) {
    return DownloadProgressState(
      url: url ?? this.url,
      fileName: fileName ?? this.fileName,
      savePath: savePath ?? this.savePath,
      category: category ?? this.category,
      status: status ?? this.status,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      totalBytes: clearTotalBytes ? null : (totalBytes ?? this.totalBytes),
      speedBytesPerSecond: speedBytesPerSecond ?? this.speedBytesPerSecond,
      remainingTime: clearRemainingTime
          ? null
          : (remainingTime ?? this.remainingTime),
      supportsResume: supportsResume ?? this.supportsResume,
      isResumedTransfer: isResumedTransfer ?? this.isResumedTransfer,
      resumeStartBytes: resumeStartBytes ?? this.resumeStartBytes,
      connectionSegments: connectionSegments ?? this.connectionSegments,
      errorMessage: clearErrorMessage
          ? null
          : (errorMessage ?? this.errorMessage),
      startedAt: startedAt ?? this.startedAt,
    );
  }

  static String formatBytes(int bytes) {
    if (bytes < 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(2)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  static String formatSpeed(double bytesPerSecond) {
    if (bytesPerSecond <= 0) return '0 B/sec';
    if (bytesPerSecond < 1024) {
      return '${bytesPerSecond.toStringAsFixed(0)} B/sec';
    }
    if (bytesPerSecond < 1024 * 1024) {
      return '${(bytesPerSecond / 1024).toStringAsFixed(2)} KB/sec';
    }
    return '${(bytesPerSecond / (1024 * 1024)).toStringAsFixed(3)} MB/sec';
  }

  static String formatDuration(Duration duration) {
    final totalSeconds = duration.inSeconds.clamp(0, 359999);
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;

    if (hours > 0) {
      return '$hours Hour(s) $minutes Min';
    }

    if (minutes > 0) {
      return '$minutes Min $seconds Sec';
    }

    return '$seconds Sec';
  }

  static String formatExactNumber(int number) {
    final digits = number.toString();
    final buffer = StringBuffer();
    for (int i = 0; i < digits.length; i++) {
      final remaining = digits.length - i;
      buffer.write(digits[i]);
      if (remaining > 1 && remaining % 3 == 1) {
        buffer.write(',');
      }
    }
    return buffer.toString();
  }
}
