class DownloadEntry {
  final String id;
  String fileName;
  String url;
  String savePath;
  String category;
  String sizeText;
  String status;
  String speedText;
  String timeLeftText;
  int progressPercent;
  int downloadedBytes;
  int? totalBytes;
  bool? supportsResume;
  DateTime? scheduledAt;
  String? username;
  String? password;

  DownloadEntry({
    required this.id,
    required this.fileName,
    required this.url,
    this.savePath = '',
    this.category = 'Others',
    this.sizeText = 'Unknown',
    this.status = 'Queued',
    this.speedText = '—',
    this.timeLeftText = '—',
    this.progressPercent = 0,
    this.downloadedBytes = 0,
    this.totalBytes,
    this.supportsResume,
    this.scheduledAt,
    this.username,
    this.password,
  });

  bool get isDownloading => status == 'Downloading';
  bool get isPaused => status == 'Paused';
  bool get isQueued => status == 'Queued';
  bool get isScheduled => status == 'Scheduled';
  bool get isFinished => status == 'Finished';
  bool get isStopped => status == 'Stopped';
  bool get isFailed => status == 'Failed';
  bool get isUnfinished => !isFinished;

  String get formattedScheduleTime {
    final dt = scheduledAt;
    if (dt == null) return '—';
    final now = DateTime.now();
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    final isToday =
        dt.year == now.year && dt.month == now.month && dt.day == now.day;
    if (isToday) {
      return '$hh:$mm';
    }
    final month = dt.month.toString().padLeft(2, '0');
    final day = dt.day.toString().padLeft(2, '0');
    return '$month/$day $hh:$mm';
  }
}
