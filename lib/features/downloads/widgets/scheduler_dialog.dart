import 'dart:convert';

import 'package:download_manager/core/localization/app_strings.dart';
import 'package:download_manager/core/theme/app_colors.dart';
import 'package:download_manager/features/downloads/models/download_entry.dart';
import 'package:download_manager/features/downloads/models/download_schedule_config.dart';
import 'package:download_manager/features/settings/widgets/config_ui_helpers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SchedulerDialogResult {
  final DownloadScheduleConfig config;
  final bool updateSelectedEntrySchedule;
  final DateTime? selectedEntrySchedule;

  const SchedulerDialogResult({
    required this.config,
    required this.updateSelectedEntrySchedule,
    required this.selectedEntrySchedule,
  });
}

class _QueueConfig {
  final String id;
  final String name;
  final bool builtIn;
  bool isPeriodicSync;
  bool startOnStartup;
  bool startAtEnabled;
  TimeOfDay startTime;
  bool isDaily;
  DateTime onceDate;
  List<bool> weekdays; // Sun..Sat
  bool wakeComputer;
  bool stopAtEnabled;
  TimeOfDay stopTime;
  bool retriesEnabled;
  int retriesCount;
  bool openFileWhenDone;
  String openFilePath;
  bool hangUpWhenDone;
  bool exitWhenDone;
  bool turnOffWhenDone;
  String powerAction;
  bool forceTerminate;
  int concurrentFiles;

  _QueueConfig({
    required this.id,
    required this.name,
    this.builtIn = false,
    this.isPeriodicSync = false,
    this.startOnStartup = false,
    this.startAtEnabled = false,
    this.startTime = const TimeOfDay(hour: 23, minute: 0),
    this.isDaily = true,
    DateTime? onceDate,
    List<bool>? weekdays,
    this.wakeComputer = false,
    this.stopAtEnabled = false,
    this.stopTime = const TimeOfDay(hour: 7, minute: 30),
    this.retriesEnabled = false,
    this.retriesCount = 10,
    this.openFileWhenDone = false,
    this.openFilePath = '',
    this.hangUpWhenDone = false,
    this.exitWhenDone = false,
    this.turnOffWhenDone = false,
    this.powerAction = 'Shut down',
    this.forceTerminate = false,
    this.concurrentFiles = 4,
  }) : onceDate = onceDate ?? DateTime.now(),
       weekdays = weekdays ?? List<bool>.filled(7, true);

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'builtIn': builtIn,
    'isPeriodicSync': isPeriodicSync,
    'startOnStartup': startOnStartup,
    'startAtEnabled': startAtEnabled,
    'startHour': startTime.hour,
    'startMinute': startTime.minute,
    'isDaily': isDaily,
    'onceDate': onceDate.toIso8601String(),
    'weekdays': weekdays,
    'wakeComputer': wakeComputer,
    'stopAtEnabled': stopAtEnabled,
    'stopHour': stopTime.hour,
    'stopMinute': stopTime.minute,
    'retriesEnabled': retriesEnabled,
    'retriesCount': retriesCount,
    'openFileWhenDone': openFileWhenDone,
    'openFilePath': openFilePath,
    'hangUpWhenDone': hangUpWhenDone,
    'exitWhenDone': exitWhenDone,
    'turnOffWhenDone': turnOffWhenDone,
    'powerAction': powerAction,
    'forceTerminate': forceTerminate,
    'concurrentFiles': concurrentFiles,
  };

  factory _QueueConfig.fromJson(Map<String, dynamic> json) {
    final rawDays = json['weekdays'] as List<dynamic>?;
    return _QueueConfig(
      id: json['id']?.toString() ?? 'q_custom',
      name: json['name']?.toString() ?? 'Queue',
      builtIn: json['builtIn'] == true,
      isPeriodicSync: json['isPeriodicSync'] == true,
      startOnStartup: json['startOnStartup'] == true,
      startAtEnabled: json['startAtEnabled'] == true,
      startTime: TimeOfDay(
        hour: (json['startHour'] as num?)?.toInt() ?? 23,
        minute: (json['startMinute'] as num?)?.toInt() ?? 0,
      ),
      isDaily: json['isDaily'] != false,
      onceDate:
          DateTime.tryParse(json['onceDate']?.toString() ?? '') ??
          DateTime.now(),
      weekdays: rawDays != null && rawDays.length == 7
          ? rawDays.map((e) => e == true).toList()
          : List<bool>.filled(7, true),
      wakeComputer: json['wakeComputer'] == true,
      stopAtEnabled: json['stopAtEnabled'] == true,
      stopTime: TimeOfDay(
        hour: (json['stopHour'] as num?)?.toInt() ?? 7,
        minute: (json['stopMinute'] as num?)?.toInt() ?? 30,
      ),
      retriesEnabled: json['retriesEnabled'] == true,
      retriesCount: (json['retriesCount'] as num?)?.toInt() ?? 10,
      openFileWhenDone: json['openFileWhenDone'] == true,
      openFilePath: json['openFilePath']?.toString() ?? '',
      hangUpWhenDone: json['hangUpWhenDone'] == true,
      exitWhenDone: json['exitWhenDone'] == true,
      turnOffWhenDone: json['turnOffWhenDone'] == true,
      powerAction: json['powerAction']?.toString() ?? 'Shut down',
      forceTerminate: json['forceTerminate'] == true,
      concurrentFiles: (json['concurrentFiles'] as num?)?.toInt() ?? 4,
    );
  }
}

class SchedulerDialog extends StatefulWidget {
  final DownloadScheduleConfig initialConfig;
  final DownloadEntry? selectedEntry;
  final List<DownloadEntry> queuedEntries;
  final int queuedCount;
  final int activeCount;
  final VoidCallback onStartQueueNow;
  final VoidCallback onPauseAll;
  final void Function(String fromId, String toId)? onMoveQueuedEntry;
  final void Function(String entryId)? onRemoveQueuedEntry;

  const SchedulerDialog({
    super.key,
    required this.initialConfig,
    required this.selectedEntry,
    this.queuedEntries = const [],
    required this.queuedCount,
    required this.activeCount,
    required this.onStartQueueNow,
    required this.onPauseAll,
    this.onMoveQueuedEntry,
    this.onRemoveQueuedEntry,
  });

  @override
  State<SchedulerDialog> createState() => _SchedulerDialogState();
}

class _SchedulerDialogState extends State<SchedulerDialog> {
  static const String _queuesStorageKey = 'scheduler_queues_v1';
  static const String _limitsStorageKey = 'scheduler_download_limits_v1';
  static const String _limitsItemId = '__download_limits__';

  static const List<String> _dayNames = [
    'Sunday',
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
  ];

  late List<_QueueConfig> _queues;
  String _selectedItemId = 'main_queue';
  int _activeTab = 0; // 0 = Schedule, 1 = Files in the queue
  String? _selectedQueueFileId;
  bool _hasChanges = false;

  // Download limits state
  bool _limitsEnabled = false;
  final TextEditingController _limitMbCtrl = TextEditingController(text: '200');
  final TextEditingController _limitHoursCtrl = TextEditingController(text: '5');
  bool _limitShowWarning = true;

  // Controllers synced to active queue
  final TextEditingController _retriesCtrl = TextEditingController(text: '10');
  final TextEditingController _openFileCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _queues = [
      _QueueConfig(
        id: 'main_queue',
        name: 'Main download queue',
        builtIn: true,
        startAtEnabled: widget.initialConfig.autoStartQueueEnabled,
        startTime: widget.initialConfig.queueStartTime != null
            ? TimeOfDay.fromDateTime(widget.initialConfig.queueStartTime!)
            : const TimeOfDay(hour: 23, minute: 0),
        stopAtEnabled: widget.initialConfig.autoStopEnabled,
        stopTime: widget.initialConfig.queueStopTime != null
            ? TimeOfDay.fromDateTime(widget.initialConfig.queueStopTime!)
            : const TimeOfDay(hour: 7, minute: 30),
        concurrentFiles: widget.initialConfig.maxConcurrentDownloads,
      ),
      _QueueConfig(
        id: 'sync_queue',
        name: 'Synchronization queue',
        builtIn: true,
        isPeriodicSync: true,
        concurrentFiles: 2,
      ),
    ];
    _syncControllersFromQueue(_queues.first);
    _loadPersistedState();
  }

  @override
  void dispose() {
    _limitMbCtrl.dispose();
    _limitHoursCtrl.dispose();
    _retriesCtrl.dispose();
    _openFileCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPersistedState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawQueues = prefs.getString(_queuesStorageKey);
      if (rawQueues != null && rawQueues.isNotEmpty) {
        final decoded = (jsonDecode(rawQueues) as List<dynamic>)
            .map((e) => _QueueConfig.fromJson(e as Map<String, dynamic>))
            .toList();
        if (decoded.isNotEmpty && mounted) {
          decoded.first.concurrentFiles =
              widget.initialConfig.maxConcurrentDownloads;
          setState(() {
            _queues = decoded;
            _syncControllersFromQueue(_activeQueue ?? _queues.first);
          });
        }
      }
      final rawLimits = prefs.getString(_limitsStorageKey);
      if (rawLimits != null && rawLimits.isNotEmpty && mounted) {
        final m = jsonDecode(rawLimits) as Map<String, dynamic>;
        setState(() {
          _limitsEnabled = m['enabled'] == true;
          _limitMbCtrl.text = '${(m['mb'] as num?)?.toInt() ?? 200}';
          _limitHoursCtrl.text = '${(m['hours'] as num?)?.toInt() ?? 5}';
          _limitShowWarning = m['showWarning'] != false;
        });
      }
    } catch (_) {}
  }

  Future<void> _savePersistedState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _queuesStorageKey,
        jsonEncode(_queues.map((q) => q.toJson()).toList()),
      );
      await prefs.setString(
        _limitsStorageKey,
        jsonEncode({
          'enabled': _limitsEnabled,
          'mb': int.tryParse(_limitMbCtrl.text.trim()) ?? 200,
          'hours': int.tryParse(_limitHoursCtrl.text.trim()) ?? 5,
          'showWarning': _limitShowWarning,
        }),
      );
    } catch (_) {}
  }

  _QueueConfig? get _activeQueue {
    if (_selectedItemId == _limitsItemId) return null;
    for (final q in _queues) {
      if (q.id == _selectedItemId) return q;
    }
    return _queues.first;
  }

  void _syncControllersFromQueue(_QueueConfig q) {
    _retriesCtrl.text = '${q.retriesCount}';
    _openFileCtrl.text = q.openFilePath;
  }

  void _markDirty() {
    if (!_hasChanges) {
      setState(() => _hasChanges = true);
    }
  }

  DateTime _nextDateTimeFor(TimeOfDay tod, DateTime? baseDate) {
    final now = DateTime.now();
    final d = baseDate ?? now;
    var candidate = DateTime(d.year, d.month, d.day, tod.hour, tod.minute);
    if (baseDate == null && !candidate.isAfter(now)) {
      candidate = candidate.add(const Duration(days: 1));
    }
    return candidate;
  }

  SchedulerDialogResult _buildResult() {
    final mainQueue = _queues.first;
    final nextStart = mainQueue.startAtEnabled
        ? _nextDateTimeFor(
            mainQueue.startTime,
            mainQueue.isDaily ? null : mainQueue.onceDate,
          )
        : null;
    final nextStop = mainQueue.stopAtEnabled
        ? _nextDateTimeFor(mainQueue.stopTime, null)
        : null;

    final config = widget.initialConfig.copyWith(
      maxConcurrentDownloads: mainQueue.concurrentFiles.clamp(1, 8),
      autoStartQueueEnabled: mainQueue.startAtEnabled,
      queueStartTime: nextStart,
      clearQueueStartTime: !mainQueue.startAtEnabled,
      autoStopEnabled: mainQueue.stopAtEnabled,
      queueStopTime: nextStop,
      clearQueueStopTime: !mainQueue.stopAtEnabled,
    );

    return SchedulerDialogResult(
      config: config,
      updateSelectedEntrySchedule: false,
      selectedEntrySchedule: null,
    );
  }

  Future<void> _createNewQueue() async {
    final defaultName = 'Queue # ${_queues.length + 1}';
    final ctrl = TextEditingController(text: defaultName);

    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 340,
          decoration: BoxDecoration(
            color: const Color(0xFF232323),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: const Color(0xFF3E3E3E)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x99000000),
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 28,
                padding: const EdgeInsets.only(left: 10, right: 6),
                decoration: const BoxDecoration(
                  color: Color(0xFF141414),
                  border: Border(bottom: BorderSide(color: Color(0xFF333333))),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.playlist_add_rounded,
                      size: 15,
                      color: AppColors.accent,
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Enter queue name',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: () => Navigator.of(ctx).pop(),
                      child: const Icon(
                        Icons.close,
                        size: 14,
                        color: Color(0xFFCCCCCC),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Enter a name for the new queue that will be displayed in the list of queues',
                      style: TextStyle(color: Color(0xFFD8D8D8), fontSize: 12),
                    ),
                    const SizedBox(height: 10),
                    ConfigUi.textField(controller: ctrl),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ConfigUi.button(
                          'OK',
                          primary: true,
                          width: 84,
                          onPressed: () {
                            final t = ctrl.text.trim();
                            if (t.isNotEmpty) Navigator.of(ctx).pop(t);
                          },
                        ),
                        const SizedBox(width: 10),
                        ConfigUi.button(
                          'Cancel',
                          width: 84,
                          onPressed: () => Navigator.of(ctx).pop(),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    ctrl.dispose();

    if (name != null && mounted) {
      final created = _QueueConfig(
        id: 'queue_${DateTime.now().microsecondsSinceEpoch}',
        name: name,
      );
      setState(() {
        _queues.add(created);
        _selectedItemId = created.id;
        _syncControllersFromQueue(created);
        _hasChanges = true;
      });
      await _savePersistedState();
    }
  }

  Future<void> _deleteSelectedQueue() async {
    final q = _activeQueue;
    if (q == null || q.builtIn) return;
    setState(() {
      _queues.removeWhere((item) => item.id == q.id);
      _selectedItemId = _queues.first.id;
      _syncControllersFromQueue(_queues.first);
      _hasChanges = true;
    });
    await _savePersistedState();
  }

  String _formatTime(TimeOfDay t) {
    final h12 = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final m = t.minute.toString().padLeft(2, '0');
    final ampm = t.hour >= 12 ? 'PM' : 'AM';
    return '$h12:$m:00 $ampm';
  }

  String _formatLongDate(DateTime d) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    final weekday = _dayNames[d.weekday % 7];
    return '$weekday, ${d.day} ${months[d.month - 1]} ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final activeQueue = _activeQueue;
    final canDeleteQueue = activeQueue != null && !activeQueue.builtIn;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: Container(
        width: 730,
        height: 560,
        decoration: BoxDecoration(
          color: const Color(0xFF232323),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: const Color(0xFF3A3A3A)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x99000000),
              blurRadius: 24,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          children: [
            _buildTitleBar(),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Left pane: Queues list
                    SizedBox(
                      width: 192,
                      child: Column(
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.alarm_on_outlined,
                                size: 26,
                                color: AppColors.accent,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                AppStrings.instance.t('Queues'),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFF1C1C1C),
                                border: Border.all(
                                  color: const Color(0xFF3E3E3E),
                                ),
                              ),
                              child: ListView(
                                children: [
                                  for (final q in _queues)
                                    _queueListRow(
                                      id: q.id,
                                      label: q.name,
                                      icon: q.id == 'sync_queue'
                                          ? Icons.sync_rounded
                                          : Icons.folder_rounded,
                                      iconColor: const Color(0xFFE8BE47),
                                    ),
                                  _queueListRow(
                                    id: _limitsItemId,
                                    label: 'Download limits',
                                    icon: Icons.speed_rounded,
                                    iconColor: const Color(0xFFFF9800),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: ConfigUi.button(
                                  'New queue',
                                  onPressed: _createNewQueue,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: ConfigUi.button(
                                  'Delete',
                                  onPressed: canDeleteQueue
                                      ? _deleteSelectedQueue
                                      : null,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 10),
                      child: VerticalDivider(width: 1, color: Color(0xFF3A3A3A)),
                    ),
                    // Right pane
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: activeQueue == null
                                ? _buildDownloadLimitsPane()
                                : _buildQueuePane(activeQueue),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              ConfigUi.button(
                                'Start now',
                                width: 84,
                                onPressed: activeQueue != null
                                    ? () {
                                        widget.onStartQueueNow();
                                      }
                                    : null,
                              ),
                              const SizedBox(width: 6),
                              ConfigUi.button(
                                'Stop',
                                width: 76,
                                onPressed:
                                    (activeQueue != null &&
                                        widget.activeCount > 0)
                                    ? () {
                                        widget.onPauseAll();
                                      }
                                    : null,
                              ),
                              const Spacer(),
                              ConfigUi.button(
                                'Apply',
                                primary: _hasChanges,
                                width: 78,
                                onPressed: _hasChanges
                                    ? () async {
                                        final nav = Navigator.of(context);
                                        await _savePersistedState();
                                        if (mounted) {
                                          nav.pop(_buildResult());
                                        }
                                      }
                                    : null,
                              ),
                              const SizedBox(width: 6),
                              ConfigUi.button(
                                'Close',
                                width: 78,
                                onPressed: () async {
                                  final nav = Navigator.of(context);
                                  if (_hasChanges) {
                                    await _savePersistedState();
                                    if (mounted) {
                                      nav.pop(_buildResult());
                                    }
                                  } else {
                                    nav.pop();
                                  }
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTitleBar() {
    return Container(
      height: 30,
      padding: const EdgeInsets.only(left: 10, right: 6),
      decoration: const BoxDecoration(
        color: Color(0xFF141414),
        border: Border(bottom: BorderSide(color: Color(0xFF333333))),
      ),
      child: Row(
        children: [
          const Icon(Icons.schedule_rounded, size: 15, color: AppColors.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              AppStrings.instance.t('Scheduler'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          InkWell(
            onTap: () => Navigator.of(context).pop(),
            borderRadius: BorderRadius.circular(3),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.close, size: 15, color: Color(0xFFCCCCCC)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _queueListRow({
    required String id,
    required String label,
    required IconData icon,
    required Color iconColor,
  }) {
    final selected = _selectedItemId == id;
    return InkWell(
      onTap: () {
        setState(() {
          _selectedItemId = id;
          final q = _activeQueue;
          if (q != null) _syncControllersFromQueue(q);
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        color: selected ? const Color(0xFF234034) : Colors.transparent,
        child: Row(
          children: [
            Icon(icon, size: 15, color: iconColor),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                AppStrings.instance.t(label),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? Colors.white : const Color(0xFFD8D8D8),
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w500 : FontWeight.normal,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQueuePane(_QueueConfig queue) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Text(
            AppStrings.instance.t(queue.name),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            _subTab('Schedule', 0),
            const SizedBox(width: 2),
            _subTab('Files in the queue', 1),
          ],
        ),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF282828),
              border: Border.all(color: const Color(0xFF3E3E3E)),
            ),
            child: _activeTab == 0
                ? _buildScheduleTab(queue)
                : _buildFilesInQueueTab(queue),
          ),
        ),
      ],
    );
  }

  Widget _subTab(String label, int index) {
    final active = _activeTab == index;
    return GestureDetector(
      onTap: () => setState(() => _activeTab = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF282828) : const Color(0xFF1D1D1D),
          border: Border(
            top: BorderSide(
              color: active ? AppColors.accent : const Color(0xFF3A3A3A),
              width: active ? 1.5 : 1,
            ),
            left: const BorderSide(color: Color(0xFF3A3A3A)),
            right: const BorderSide(color: Color(0xFF3A3A3A)),
          ),
        ),
        child: Text(
          AppStrings.instance.t(label),
          style: TextStyle(
            color: active ? Colors.white : const Color(0xFFB8B8B8),
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Widget _buildScheduleTab(_QueueConfig q) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: ConfigUi.radioRow<bool>(
                  value: false,
                  groupValue: q.isPeriodicSync,
                  label: 'One-time downloading',
                  onChanged: (v) {
                    setState(() => q.isPeriodicSync = v);
                    _markDirty();
                  },
                ),
              ),
              Expanded(
                child: ConfigUi.radioRow<bool>(
                  value: true,
                  groupValue: q.isPeriodicSync,
                  label: 'Periodic synchronization',
                  onChanged: (v) {
                    setState(() => q.isPeriodicSync = v);
                    _markDirty();
                  },
                ),
              ),
            ],
          ),
          const Divider(height: 12, color: Color(0xFF3E3E3E)),
          ConfigUi.checkRow(
            value: q.startOnStartup,
            label: 'Start download on FluxDM startup',
            onChanged: (v) {
              setState(() => q.startOnStartup = v);
              _markDirty();
            },
          ),
          const Divider(height: 12, color: Color(0xFF3E3E3E)),
          Row(
            children: [
              SizedBox(
                width: 155,
                child: ConfigUi.checkRow(
                  value: q.startAtEnabled,
                  label: 'Start download at',
                  onChanged: (v) {
                    setState(() => q.startAtEnabled = v);
                    _markDirty();
                  },
                ),
              ),
              ConfigUi.button(
                _formatTime(q.startTime),
                width: 112,
                onPressed: q.startAtEnabled
                    ? () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: q.startTime,
                        );
                        if (picked != null && mounted) {
                          setState(() => q.startTime = picked);
                          _markDirty();
                        }
                      }
                    : null,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Column(
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 96,
                      child: ConfigUi.radioRow<bool>(
                        value: false,
                        groupValue: q.isDaily,
                        label: 'Once at',
                        onChanged: (v) {
                          if (!q.startAtEnabled) return;
                          setState(() => q.isDaily = v);
                          _markDirty();
                        },
                      ),
                    ),
                    Expanded(
                      child: ConfigUi.button(
                        _formatLongDate(q.onceDate),
                        onPressed: (q.startAtEnabled && !q.isDaily)
                            ? () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: q.onceDate,
                                  firstDate: DateTime.now(),
                                  lastDate: DateTime.now().add(
                                    const Duration(days: 365),
                                  ),
                                );
                                if (picked != null && mounted) {
                                  setState(() => q.onceDate = picked);
                                  _markDirty();
                                }
                              }
                            : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 96,
                      child: ConfigUi.radioRow<bool>(
                        value: true,
                        groupValue: q.isDaily,
                        label: 'Daily',
                        onChanged: (v) {
                          if (!q.startAtEnabled) return;
                          setState(() => q.isDaily = v);
                          _markDirty();
                        },
                      ),
                    ),
                    Expanded(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 0,
                        children: List.generate(7, (idx) {
                          return SizedBox(
                            width: 102,
                            child: ConfigUi.checkRow(
                              value: q.weekdays[idx],
                              label: _dayNames[idx],
                              enabled: q.startAtEnabled && q.isDaily,
                              onChanged: (v) {
                                setState(() => q.weekdays[idx] = v);
                                _markDirty();
                              },
                            ),
                          );
                        }),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          ConfigUi.checkRow(
            value: q.wakeComputer,
            label: 'Wake the computer to run this queue',
            enabled: q.startAtEnabled,
            onChanged: (v) {
              setState(() => q.wakeComputer = v);
              _markDirty();
            },
          ),
          const Divider(height: 14, color: Color(0xFF3E3E3E)),
          Row(
            children: [
              SizedBox(
                width: 155,
                child: ConfigUi.checkRow(
                  value: q.stopAtEnabled,
                  label: 'Stop download at',
                  onChanged: (v) {
                    setState(() => q.stopAtEnabled = v);
                    _markDirty();
                  },
                ),
              ),
              ConfigUi.button(
                _formatTime(q.stopTime),
                width: 112,
                onPressed: q.stopAtEnabled
                    ? () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: q.stopTime,
                        );
                        if (picked != null && mounted) {
                          setState(() => q.stopTime = picked);
                          _markDirty();
                        }
                      }
                    : null,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: ConfigUi.checkRow(
                  value: q.retriesEnabled,
                  label: 'Number of retries for each file if downloading failed :',
                  onChanged: (v) {
                    setState(() => q.retriesEnabled = v);
                    _markDirty();
                  },
                ),
              ),
              SizedBox(
                width: 58,
                child: ConfigUi.textField(
                  controller: _retriesCtrl,
                  enabled: q.retriesEnabled,
                  onChanged: (val) {
                    q.retriesCount = int.tryParse(val.trim()) ?? 10;
                    _markDirty();
                  },
                ),
              ),
            ],
          ),
          const Divider(height: 14, color: Color(0xFF3E3E3E)),
          ConfigUi.checkRow(
            value: q.openFileWhenDone,
            label: 'Open the following file when done:',
            onChanged: (v) {
              setState(() => q.openFileWhenDone = v);
              _markDirty();
            },
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: ConfigUi.textField(
                  controller: _openFileCtrl,
                  enabled: q.openFileWhenDone,
                  onChanged: (val) {
                    q.openFilePath = val.trim();
                    _markDirty();
                  },
                ),
              ),
              const SizedBox(width: 6),
              ConfigUi.button(
                '...',
                width: 28,
                onPressed: q.openFileWhenDone
                    ? () async {
                        final picked = await FilePicker.pickFiles();
                        if (picked.isNotEmpty &&
                            picked.single.path != null &&
                            mounted) {
                          setState(() {
                            q.openFilePath = picked.single.path!;
                            _openFileCtrl.text = q.openFilePath;
                          });
                          _markDirty();
                        }
                      }
                    : null,
              ),
            ],
          ),
          const SizedBox(height: 6),
          ConfigUi.checkRow(
            value: q.hangUpWhenDone,
            label: 'Hang up modem when done',
            onChanged: (v) {
              setState(() => q.hangUpWhenDone = v);
              _markDirty();
            },
          ),
          ConfigUi.checkRow(
            value: q.exitWhenDone,
            label: 'Exit FluxDM when done',
            onChanged: (v) {
              setState(() => q.exitWhenDone = v);
              _markDirty();
            },
          ),
          Row(
            children: [
              Expanded(
                child: ConfigUi.checkRow(
                  value: q.turnOffWhenDone,
                  label: 'Turn off computer when done',
                  onChanged: (v) {
                    setState(() => q.turnOffWhenDone = v);
                    _markDirty();
                  },
                ),
              ),
              SizedBox(
                width: 120,
                child: ConfigUi.dropdown(
                  value: q.powerAction,
                  enabled: q.turnOffWhenDone,
                  items: const ['Shut down', 'Hibernate', 'Sleep', 'Log off'],
                  onChanged: (v) {
                    setState(() => q.powerAction = v);
                    _markDirty();
                  },
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 20),
            child: ConfigUi.checkRow(
              value: q.forceTerminate,
              label: 'Force processes to terminate',
              enabled: q.turnOffWhenDone,
              onChanged: (v) {
                setState(() => q.forceTerminate = v);
                _markDirty();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilesInQueueTab(_QueueConfig q) {
    final entries = widget.queuedEntries;
    final selectedIdx = entries.indexWhere((e) => e.id == _selectedQueueFileId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Text(
              'Download',
              style: TextStyle(color: Color(0xFFE0E0E0), fontSize: 12),
            ),
            const SizedBox(width: 8),
            ConfigUi.spinner(
              value: q.concurrentFiles.clamp(1, 8),
              min: 1,
              max: 8,
              width: 62,
              onChanged: (v) {
                setState(() => q.concurrentFiles = v);
                _markDirty();
              },
            ),
            const SizedBox(width: 8),
            const Text(
              'files at the same time',
              style: TextStyle(color: Color(0xFFE0E0E0), fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              border: Border.all(color: const Color(0xFF3E3E3E)),
            ),
            child: Column(
              children: [
                Container(
                  height: 24,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  color: const Color(0xFF141414),
                  child: const Row(
                    children: [
                      Expanded(
                        flex: 4,
                        child: Text(
                          'File Name',
                          style: TextStyle(
                            color: Color(0xFFD0D0D0),
                            fontSize: 11.5,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          'Size',
                          style: TextStyle(
                            color: Color(0xFFD0D0D0),
                            fontSize: 11.5,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          'Status',
                          style: TextStyle(
                            color: Color(0xFFD0D0D0),
                            fontSize: 11.5,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          'Time left',
                          style: TextStyle(
                            color: Color(0xFFD0D0D0),
                            fontSize: 11.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: entries.length,
                    itemBuilder: (_, idx) {
                      final e = entries[idx];
                      final sel = e.id == _selectedQueueFileId;
                      return InkWell(
                        onTap: () =>
                            setState(() => _selectedQueueFileId = e.id),
                        child: Container(
                          color: sel
                              ? const Color(0xFF234034)
                              : Colors.transparent,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 5,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 4,
                                child: Text(
                                  e.fileName,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11.5,
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Text(
                                  e.sizeText,
                                  style: const TextStyle(
                                    color: Color(0xFFC0C0C0),
                                    fontSize: 11.5,
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Text(
                                  e.status,
                                  style: const TextStyle(
                                    color: AppColors.accent,
                                    fontSize: 11.5,
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Text(
                                  e.timeLeftText,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xFFC0C0C0),
                                    fontSize: 11.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _queueIconBtn(
              icon: Icons.arrow_downward_rounded,
              tooltip: 'Move Down',
              color: AppColors.accent,
              onPressed: (selectedIdx >= 0 && selectedIdx < entries.length - 1)
                  ? () {
                      widget.onMoveQueuedEntry?.call(
                        entries[selectedIdx].id,
                        entries[selectedIdx + 1].id,
                      );
                      setState(() {});
                    }
                  : null,
            ),
            const SizedBox(width: 6),
            _queueIconBtn(
              icon: Icons.arrow_upward_rounded,
              tooltip: 'Move Up',
              color: AppColors.accent,
              onPressed: selectedIdx > 0
                  ? () {
                      widget.onMoveQueuedEntry?.call(
                        entries[selectedIdx].id,
                        entries[selectedIdx - 1].id,
                      );
                      setState(() {});
                    }
                  : null,
            ),
            const SizedBox(width: 6),
            _queueIconBtn(
              icon: Icons.close_rounded,
              tooltip: 'Remove from Queue',
              color: const Color(0xFFFF6B6B),
              onPressed: selectedIdx >= 0
                  ? () {
                      final id = entries[selectedIdx].id;
                      widget.onRemoveQueuedEntry?.call(id);
                      setState(() => _selectedQueueFileId = null);
                    }
                  : null,
            ),
          ],
        ),
      ],
    );
  }

  Widget _queueIconBtn({
    required IconData icon,
    required String tooltip,
    required Color color,
    VoidCallback? onPressed,
  }) {
    final enabled = onPressed != null;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(3),
        child: Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: const Color(0xFF2D2D2D),
            border: Border.all(color: const Color(0xFF444444)),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Icon(
            icon,
            size: 14,
            color: enabled ? color : const Color(0xFF555555),
          ),
        ),
      ),
    );
  }

  Widget _buildDownloadLimitsPane() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ConfigUi.checkRow(
            value: _limitsEnabled,
            label: 'Download limits',
            onChanged: (v) {
              setState(() => _limitsEnabled = v);
              _markDirty();
            },
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.only(left: 26),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 10,
                  runSpacing: 6,
                  children: [
                    Text(
                      'Download no more than',
                      style: TextStyle(
                        color: _limitsEnabled
                            ? const Color(0xFFE0E0E0)
                            : const Color(0xFF888888),
                        fontSize: 12,
                      ),
                    ),
                    SizedBox(
                      width: 64,
                      child: ConfigUi.textField(
                        controller: _limitMbCtrl,
                        enabled: _limitsEnabled,
                        onChanged: (_) => _markDirty(),
                      ),
                    ),
                    Text(
                      'MBytes',
                      style: TextStyle(
                        color: _limitsEnabled
                            ? const Color(0xFFE0E0E0)
                            : const Color(0xFF888888),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const SizedBox(width: 96),
                    Text(
                      'every',
                      style: TextStyle(
                        color: _limitsEnabled
                            ? const Color(0xFFE0E0E0)
                            : const Color(0xFF888888),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 64,
                      child: ConfigUi.textField(
                        controller: _limitHoursCtrl,
                        enabled: _limitsEnabled,
                        onChanged: (_) => _markDirty(),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'hours',
                      style: TextStyle(
                        color: _limitsEnabled
                            ? const Color(0xFFE0E0E0)
                            : const Color(0xFF888888),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          ConfigUi.checkRow(
            value: _limitShowWarning,
            label: 'Show warning before stopping downloads',
            enabled: _limitsEnabled,
            onChanged: (v) {
              setState(() => _limitShowWarning = v);
              _markDirty();
            },
          ),
        ],
      ),
    );
  }
}
