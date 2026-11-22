class DownloadScheduleConfig {
  final int maxConcurrentDownloads;
  final int segmentsPerDownload;
  final bool speedLimitEnabled;
  final int speedLimitKBps;
  final bool autoStartQueueEnabled;
  final DateTime? queueStartTime;
  final bool autoStopEnabled;
  final DateTime? queueStopTime;

  const DownloadScheduleConfig({
    this.maxConcurrentDownloads = 3,
    this.segmentsPerDownload = 8,
    this.speedLimitEnabled = false,
    this.speedLimitKBps = 1024,
    this.autoStartQueueEnabled = false,
    this.queueStartTime,
    this.autoStopEnabled = false,
    this.queueStopTime,
  });

  int get effectiveSpeedLimitBytesPerSecond =>
      speedLimitEnabled && speedLimitKBps > 0 ? speedLimitKBps * 1024 : 0;

  DownloadScheduleConfig copyWith({
    int? maxConcurrentDownloads,
    int? segmentsPerDownload,
    bool? speedLimitEnabled,
    int? speedLimitKBps,
    bool? autoStartQueueEnabled,
    DateTime? queueStartTime,
    bool clearQueueStartTime = false,
    bool? autoStopEnabled,
    DateTime? queueStopTime,
    bool clearQueueStopTime = false,
  }) {
    return DownloadScheduleConfig(
      maxConcurrentDownloads:
          maxConcurrentDownloads ?? this.maxConcurrentDownloads,
      segmentsPerDownload: segmentsPerDownload ?? this.segmentsPerDownload,
      speedLimitEnabled: speedLimitEnabled ?? this.speedLimitEnabled,
      speedLimitKBps: speedLimitKBps ?? this.speedLimitKBps,
      autoStartQueueEnabled:
          autoStartQueueEnabled ?? this.autoStartQueueEnabled,
      queueStartTime: clearQueueStartTime
          ? null
          : (queueStartTime ?? this.queueStartTime),
      autoStopEnabled: autoStopEnabled ?? this.autoStopEnabled,
      queueStopTime: clearQueueStopTime
          ? null
          : (queueStopTime ?? this.queueStopTime),
    );
  }

  static String formatScheduleDateTime(DateTime? dt) {
    if (dt == null) return 'Not set';
    final now = DateTime.now();
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    final isToday =
        dt.year == now.year && dt.month == now.month && dt.day == now.day;
    if (isToday) return 'Today $hh:$mm';
    final tomorrow = now.add(const Duration(days: 1));
    final isTomorrow =
        dt.year == tomorrow.year &&
        dt.month == tomorrow.month &&
        dt.day == tomorrow.day;
    if (isTomorrow) return 'Tomorrow $hh:$mm';
    final month = dt.month.toString().padLeft(2, '0');
    final day = dt.day.toString().padLeft(2, '0');
    return '${dt.year}-$month-$day $hh:$mm';
  }
}
