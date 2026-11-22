import 'package:download_manager/core/theme/app_colors.dart';
import 'package:download_manager/features/downloads/models/download_entry.dart';
import 'package:download_manager/features/downloads/models/download_schedule_config.dart';
import 'package:material_ui/material_ui.dart';

class DownloadListView extends StatelessWidget {
  final String selectedCategory;
  final List<DownloadEntry> files;
  final int totalCount;
  final int activeCount;
  final int maxConcurrent;
  final DownloadScheduleConfig scheduleConfig;
  final String? selectedFileId;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onSelectFile;
  final ValueChanged<String> onOpenProgress;
  final void Function(String fromId, String toId) onMoveQueuedEntry;

  const DownloadListView({
    super.key,
    required this.selectedCategory,
    required this.files,
    required this.totalCount,
    required this.activeCount,
    required this.maxConcurrent,
    required this.scheduleConfig,
    required this.selectedFileId,
    required this.onSearchChanged,
    required this.onSelectFile,
    required this.onOpenProgress,
    required this.onMoveQueuedEntry,
  });

  @override
  Widget build(BuildContext context) {
    final footerParts = <String>[
      '$totalCount ${totalCount == 1 ? 'file' : 'files'}',
      'Active: $activeCount/$maxConcurrent',
      'Segments: ${scheduleConfig.segmentsPerDownload}',
    ];
    if (scheduleConfig.speedLimitEnabled && scheduleConfig.speedLimitKBps > 0) {
      footerParts.add('Speed limit: ${scheduleConfig.speedLimitKBps} KB/s');
    }
    if (scheduleConfig.autoStartQueueEnabled &&
        scheduleConfig.queueStartTime != null) {
      footerParts.add(
        'Auto-start: ${DownloadScheduleConfig.formatScheduleDateTime(scheduleConfig.queueStartTime)}',
      );
    }
    if (scheduleConfig.autoStopEnabled && scheduleConfig.queueStopTime != null) {
      footerParts.add(
        'Auto-pause: ${DownloadScheduleConfig.formatScheduleDateTime(scheduleConfig.queueStopTime)}',
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  selectedCategory,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              SizedBox(
                width: 220,
                child: TextField(
                  onChanged: onSearchChanged,
                  decoration: InputDecoration(
                    hintText: 'Search files',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const _TableHeader(),
          const Divider(color: AppColors.border),
          Expanded(
            child: files.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.download_outlined,
                          size: 40,
                          color: AppColors.textSecondary,
                        ),
                        SizedBox(height: 12),
                        Text(
                          'No downloads yet',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        SizedBox(height: 6),
                        Text(
                          'Click + or copy a download URL to add a download',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: files.length,
                    itemBuilder: (context, index) {
                      final entry = files[index];
                      if (entry.isQueued) {
                        return _buildQueueRow(entry);
                      }
                      return _buildFileRow(entry);
                    },
                  ),
          ),
          const SizedBox(height: 6),
          Text(
            footerParts.join('  •  '),
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFileRow(DownloadEntry entry) {
    final status = entry.status;
    final progress = (entry.progressPercent / 100).clamp(0.0, 1.0);

    final progressColor = switch (status) {
      'Downloading' => AppColors.accent,
      'Paused' => AppColors.paused,
      'Queued' => Colors.cyanAccent,
      'Scheduled' => AppColors.video,
      'Stopped' => Colors.redAccent,
      'Failed' => Colors.redAccent,
      'Finished' => Colors.greenAccent,
      _ => AppColors.textSecondary,
    };

    final selected = selectedFileId == entry.id;

    return GestureDetector(
      onTap: () => onSelectFile(entry.id),
      onDoubleTap: () => onOpenProgress(entry.id),
      child: Container(
        height: 58,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.accentDark.withValues(alpha: 0.25)
              : Colors.transparent,
          border: const Border(bottom: BorderSide(color: AppColors.border)),
        ),
        child: Row(
          children: [
            Expanded(
              flex: 5,
              child: Row(
                children: [
                  Icon(
                    entry.isScheduled
                        ? Icons.schedule_rounded
                        : Icons.insert_drive_file_outlined,
                    color: entry.isScheduled
                        ? AppColors.video
                        : AppColors.accent,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      entry.fileName,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 1,
              child: Text(entry.sizeText, style: const TextStyle(fontSize: 11)),
            ),
            Expanded(
              flex: 2,
              child: Text(
                status,
                style: TextStyle(fontSize: 11, color: progressColor),
              ),
            ),
            Expanded(
              flex: 1,
              child: Text(
                entry.speedText,
                style: const TextStyle(fontSize: 11),
              ),
            ),
            Expanded(
              flex: 1,
              child: Text(
                entry.timeLeftText,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11),
              ),
            ),
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${entry.progressPercent}%',
                      style: TextStyle(fontSize: 10, color: progressColor),
                    ),
                    const SizedBox(height: 5),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(5),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 5,
                        backgroundColor: AppColors.border,
                        valueColor: AlwaysStoppedAnimation(progressColor),
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

  Widget _buildQueueRow(DownloadEntry entry) {
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) => details.data != entry.id,
      onAcceptWithDetails: (details) {
        onMoveQueuedEntry(details.data, entry.id);
      },
      builder: (context, candidates, rejected) {
        return LongPressDraggable<String>(
          data: entry.id,
          feedback: Material(
            color: AppColors.surface,
            elevation: 8,
            child: SizedBox(
              width: 420,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  entry.fileName,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ),
          childWhenDragging: Opacity(
            opacity: 0.3,
            child: _buildFileRow(entry),
          ),
          child: Container(
            decoration: candidates.isNotEmpty
                ? BoxDecoration(border: Border.all(color: AppColors.accent))
                : null,
            child: _buildFileRow(entry),
          ),
        );
      },
    );
  }
}

class _TableHeader extends StatelessWidget {
  const _TableHeader();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Expanded(flex: 5, child: Text('File Name')),
        Expanded(flex: 1, child: Text('Size')),
        Expanded(flex: 2, child: Text('Status')),
        Expanded(flex: 1, child: Text('Speed')),
        Expanded(flex: 1, child: Text('Time Left')),
        Expanded(flex: 2, child: Text('Progress')),
      ],
    );
  }
}
