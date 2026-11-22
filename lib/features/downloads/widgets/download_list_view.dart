import 'package:download_manager/core/theme/app_colors.dart';
import 'package:material_ui/material_ui.dart';

class DownloadListView extends StatelessWidget {
  final String selectedCategory;
  final List<List<String>> files;
  final int selectedFileIndex;
  final ValueChanged<int> onSelectFile;
  final ValueChanged<int> onOpenProgress;
  final void Function(int oldIndex, int newIndex) onMoveQueuedFile;

  const DownloadListView({
    super.key,
    required this.selectedCategory,
    required this.files,
    required this.selectedFileIndex,
    required this.onSelectFile,
    required this.onOpenProgress,
    required this.onMoveQueuedFile,
  });

  @override
  Widget build(BuildContext context) {
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
                      final file = files[index];
                      if (file[2] == 'Queued') {
                        return _buildQueueRow(file, index);
                      }
                      return _buildFileRow(file, index);
                    },
                  ),
          ),
          Text(
            '${files.length} files',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFileRow(List<String> file, int index) {
    final status = file[2];
    final progress = (double.tryParse(file[5]) ?? 0) / 100;

    final progressColor = switch (status) {
      'Downloading' => AppColors.accent,
      'Paused' => AppColors.paused,
      'Queued' => Colors.cyanAccent,
      'Stopped' => Colors.redAccent,
      'Failed' => Colors.redAccent,
      'Finished' => Colors.greenAccent,
      _ => AppColors.textSecondary,
    };

    final selected = selectedFileIndex == index;

    return GestureDetector(
      onTap: () => onSelectFile(index),
      onDoubleTap: () => onOpenProgress(index),
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
                  const Icon(
                    Icons.insert_drive_file_outlined,
                    color: AppColors.accent,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      file[0],
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 1,
              child: Text(file[1], style: const TextStyle(fontSize: 11)),
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
              child: Text(file[3], style: const TextStyle(fontSize: 11)),
            ),
            Expanded(
              flex: 1,
              child: Text(file[4], style: const TextStyle(fontSize: 11)),
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
                      '${file[5]}%',
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

  Widget _buildQueueRow(List<String> file, int index) {
    return DragTarget<int>(
      onWillAcceptWithDetails: (details) {
        final fromIndex = details.data;

        return fromIndex != index &&
            fromIndex >= 0 &&
            fromIndex < files.length &&
            files[fromIndex][2] == 'Queued';
      },
      onAcceptWithDetails: (details) {
        onMoveQueuedFile(details.data, index);
      },
      builder: (context, candidates, rejected) {
        return LongPressDraggable<int>(
          data: index,
          feedback: Material(
            color: AppColors.surface,
            elevation: 8,
            child: SizedBox(
              width: 420,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  file[0],
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
            child: _buildFileRow(file, index),
          ),
          child: Container(
            decoration: candidates.isNotEmpty
                ? BoxDecoration(border: Border.all(color: AppColors.accent))
                : null,
            child: _buildFileRow(file, index),
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
