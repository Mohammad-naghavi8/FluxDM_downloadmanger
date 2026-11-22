import 'package:download_manager/core/theme/app_colors.dart';
import 'package:download_manager/features/downloads/models/download_entry.dart';
import 'package:download_manager/features/downloads/models/download_schedule_config.dart';
import 'package:material_ui/material_ui.dart';

class SchedulerDialogResult {
  final DownloadScheduleConfig config;
  final DateTime? selectedEntrySchedule;
  final bool updateSelectedEntrySchedule;

  const SchedulerDialogResult({
    required this.config,
    this.selectedEntrySchedule,
    this.updateSelectedEntrySchedule = false,
  });
}

class SchedulerDialog extends StatefulWidget {
  final DownloadScheduleConfig initialConfig;
  final DownloadEntry? selectedEntry;
  final int queuedCount;
  final int activeCount;
  final VoidCallback onStartQueueNow;
  final VoidCallback onPauseAll;

  const SchedulerDialog({
    super.key,
    required this.initialConfig,
    required this.queuedCount,
    required this.activeCount,
    required this.onStartQueueNow,
    required this.onPauseAll,
    this.selectedEntry,
  });

  @override
  State<SchedulerDialog> createState() => _SchedulerDialogState();
}

class _SchedulerDialogState extends State<SchedulerDialog> {
  late int _maxConcurrent;
  late int _segmentsPerDownload;
  late bool _speedLimitEnabled;
  late int _speedLimitKBps;
  late final TextEditingController _speedController;
  late bool _autoStartEnabled;
  DateTime? _queueStartTime;
  late bool _autoStopEnabled;
  DateTime? _queueStopTime;

  late bool _entryScheduleEnabled;
  DateTime? _entryScheduleTime;
  bool _entryScheduleTouched = false;

  bool get _canScheduleSelected {
    final entry = widget.selectedEntry;
    return entry != null && !entry.isFinished && !entry.isDownloading;
  }

  @override
  void initState() {
    super.initState();
    final cfg = widget.initialConfig;
    _maxConcurrent = cfg.maxConcurrentDownloads;
    _segmentsPerDownload = cfg.segmentsPerDownload;
    _speedLimitEnabled = cfg.speedLimitEnabled;
    _speedLimitKBps = cfg.speedLimitKBps;
    _speedController = TextEditingController(text: '$_speedLimitKBps');
    _autoStartEnabled = cfg.autoStartQueueEnabled;
    _queueStartTime =
        cfg.queueStartTime ?? DateTime.now().add(const Duration(minutes: 30));
    _autoStopEnabled = cfg.autoStopEnabled;
    _queueStopTime =
        cfg.queueStopTime ?? DateTime.now().add(const Duration(hours: 2));

    final entry = widget.selectedEntry;
    _entryScheduleEnabled = entry?.isScheduled ?? false;
    _entryScheduleTime =
        entry?.scheduledAt ?? DateTime.now().add(const Duration(minutes: 15));
  }

  @override
  void dispose() {
    _speedController.dispose();
    super.dispose();
  }

  Future<DateTime?> _pickDateTime(DateTime initial) async {
    final now = DateTime.now();
    final safeInitial = initial.isBefore(now) ? now : initial;

    final date = await showDatePicker(
      context: context,
      initialDate: safeInitial,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return null;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(safeInitial),
    );
    if (time == null || !mounted) return null;

    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  DateTime _nextOccurrenceOf(int hour, int minute) {
    final now = DateTime.now();
    var target = DateTime(now.year, now.month, now.day, hour, minute);
    if (!target.isAfter(now)) {
      target = target.add(const Duration(days: 1));
    }
    return target;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: const Row(
        children: [
          Icon(Icons.schedule_rounded, color: AppColors.accent, size: 20),
          SizedBox(width: 8),
          Text('Queue & Download Scheduler', style: TextStyle(fontSize: 16)),
        ],
      ),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _sectionCard(
                title: 'ACCELERATION & SPEED LIMIT',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Max simultaneous downloads',
                          style: TextStyle(fontSize: 12.5),
                        ),
                        Text(
                          '$_maxConcurrent files',
                          style: const TextStyle(
                            color: AppColors.accent,
                            fontWeight: FontWeight.bold,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                    Slider(
                      value: _maxConcurrent.toDouble(),
                      min: 1,
                      max: 8,
                      divisions: 7,
                      activeColor: AppColors.accent,
                      onChanged: (v) {
                        setState(() => _maxConcurrent = v.round());
                      },
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Segments per download (Connections)',
                          style: TextStyle(fontSize: 12.5),
                        ),
                        Text(
                          '$_segmentsPerDownload segments',
                          style: const TextStyle(
                            color: AppColors.accent,
                            fontWeight: FontWeight.bold,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                    Slider(
                      value: _segmentsPerDownload.toDouble(),
                      min: 1,
                      max: 16,
                      divisions: 15,
                      activeColor: AppColors.accent,
                      onChanged: (v) {
                        setState(() => _segmentsPerDownload = v.round());
                      },
                    ),
                    const Divider(color: AppColors.border, height: 18),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      activeThumbColor: AppColors.accent,
                      title: const Text(
                        'Limit download speed',
                        style: TextStyle(fontSize: 12.5),
                      ),
                      value: _speedLimitEnabled,
                      onChanged: (value) {
                        setState(() => _speedLimitEnabled = value);
                      },
                    ),
                    if (_speedLimitEnabled) ...[
                      Row(
                        children: [
                          SizedBox(
                            width: 115,
                            height: 34,
                            child: TextField(
                              controller: _speedController,
                              keyboardType: TextInputType.number,
                              style: const TextStyle(fontSize: 12.5),
                              decoration: const InputDecoration(
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                suffixText: 'KB/s',
                                border: OutlineInputBorder(),
                              ),
                              onChanged: (value) {
                                final parsed = int.tryParse(value.trim());
                                if (parsed != null && parsed > 0) {
                                  _speedLimitKBps = parsed;
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                for (final (label, kbps) in const [
                                  ('256 KB/s', 256),
                                  ('512 KB/s', 512),
                                  ('1 MB/s', 1024),
                                  ('2 MB/s', 2048),
                                  ('5 MB/s', 5120),
                                ])
                                  _presetChip(label, () {
                                    setState(() {
                                      _speedLimitKBps = kbps;
                                      _speedController.text = '$kbps';
                                    });
                                  }),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],
                    Text(
                      'Active now: ${widget.activeCount} • Waiting in queue: ${widget.queuedCount}',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _sectionCard(
                title: 'AUTOMATIC QUEUE SCHEDULE',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      activeThumbColor: AppColors.accent,
                      title: const Text(
                        'Auto-start queue at specific time',
                        style: TextStyle(fontSize: 12.5),
                      ),
                      value: _autoStartEnabled,
                      onChanged: (value) {
                        setState(() => _autoStartEnabled = value);
                      },
                    ),
                    if (_autoStartEnabled) ...[
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              DownloadScheduleConfig.formatScheduleDateTime(
                                _queueStartTime,
                              ),
                              style: const TextStyle(
                                color: AppColors.accent,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: () async {
                              final picked = await _pickDateTime(
                                _queueStartTime ?? DateTime.now(),
                              );
                              if (picked != null) {
                                setState(() => _queueStartTime = picked);
                              }
                            },
                            icon: const Icon(Icons.edit_calendar, size: 15),
                            label: const Text('Pick Time'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _presetChip('+5 min', () {
                            setState(() {
                              _queueStartTime = DateTime.now().add(
                                const Duration(minutes: 5),
                              );
                            });
                          }),
                          _presetChip('+30 min', () {
                            setState(() {
                              _queueStartTime = DateTime.now().add(
                                const Duration(minutes: 30),
                              );
                            });
                          }),
                          _presetChip('+1 hour', () {
                            setState(() {
                              _queueStartTime = DateTime.now().add(
                                const Duration(hours: 1),
                              );
                            });
                          }),
                          _presetChip('02:00 AM', () {
                            setState(() {
                              _queueStartTime = _nextOccurrenceOf(2, 0);
                            });
                          }),
                        ],
                      ),
                    ],
                    const Divider(color: AppColors.border, height: 20),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      activeThumbColor: AppColors.paused,
                      title: const Text(
                        'Auto-pause downloads at stop time',
                        style: TextStyle(fontSize: 12.5),
                      ),
                      value: _autoStopEnabled,
                      onChanged: (value) {
                        setState(() => _autoStopEnabled = value);
                      },
                    ),
                    if (_autoStopEnabled)
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              DownloadScheduleConfig.formatScheduleDateTime(
                                _queueStopTime,
                              ),
                              style: const TextStyle(
                                color: AppColors.paused,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: () async {
                              final picked = await _pickDateTime(
                                _queueStopTime ?? DateTime.now(),
                              );
                              if (picked != null) {
                                setState(() => _queueStopTime = picked);
                              }
                            },
                            icon: const Icon(Icons.edit_calendar, size: 15),
                            label: const Text('Pick Time'),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              if (_canScheduleSelected) ...[
                const SizedBox(height: 12),
                _sectionCard(
                  title: 'SELECTED DOWNLOAD SCHEDULE',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.selectedEntry!.fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        activeThumbColor: AppColors.accent,
                        title: const Text(
                          'Start this file automatically at time',
                          style: TextStyle(fontSize: 12.5),
                        ),
                        value: _entryScheduleEnabled,
                        onChanged: (value) {
                          setState(() {
                            _entryScheduleEnabled = value;
                            _entryScheduleTouched = true;
                          });
                        },
                      ),
                      if (_entryScheduleEnabled)
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                DownloadScheduleConfig.formatScheduleDateTime(
                                  _entryScheduleTime,
                                ),
                                style: const TextStyle(
                                  color: AppColors.accent,
                                  fontSize: 12.5,
                                ),
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: () async {
                                final picked = await _pickDateTime(
                                  _entryScheduleTime ?? DateTime.now(),
                                );
                                if (picked != null) {
                                  setState(() {
                                    _entryScheduleTime = picked;
                                    _entryScheduleTouched = true;
                                  });
                                }
                              },
                              icon: const Icon(Icons.edit_calendar, size: 15),
                              label: const Text('Pick Time'),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: widget.queuedCount == 0
              ? null
              : () {
                  Navigator.pop(context);
                  widget.onStartQueueNow();
                },
          icon: const Icon(Icons.playlist_play_rounded, size: 18),
          label: const Text('Start Queue'),
        ),
        TextButton.icon(
          onPressed: widget.activeCount == 0
              ? null
              : () {
                  Navigator.pop(context);
                  widget.onPauseAll();
                },
          icon: const Icon(Icons.pause_rounded, size: 16),
          label: const Text('Pause All'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            final parsedKbps =
                int.tryParse(_speedController.text.trim()) ?? _speedLimitKBps;
            final config = DownloadScheduleConfig(
              maxConcurrentDownloads: _maxConcurrent,
              segmentsPerDownload: _segmentsPerDownload,
              speedLimitEnabled: _speedLimitEnabled,
              speedLimitKBps: parsedKbps > 0 ? parsedKbps : 1024,
              autoStartQueueEnabled: _autoStartEnabled,
              queueStartTime: _autoStartEnabled ? _queueStartTime : null,
              autoStopEnabled: _autoStopEnabled,
              queueStopTime: _autoStopEnabled ? _queueStopTime : null,
            );

            Navigator.pop(
              context,
              SchedulerDialogResult(
                config: config,
                updateSelectedEntrySchedule:
                    _canScheduleSelected && _entryScheduleTouched,
                selectedEntrySchedule:
                    _entryScheduleEnabled ? _entryScheduleTime : null,
              ),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }

  Widget _sectionCard({required String title, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }

  Widget _presetChip(String label, VoidCallback onTap) {
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      backgroundColor: AppColors.surface,
      side: const BorderSide(color: AppColors.border),
      onPressed: onTap,
    );
  }
}
