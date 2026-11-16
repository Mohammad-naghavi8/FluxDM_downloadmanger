import 'dart:io';

import 'package:dio/dio.dart';
import 'package:download_manager/core/theme/app_colors.dart';
import 'package:download_manager/features/downloads/services/download_service.dart';
import 'package:material_ui/material_ui.dart';

class MainWindow extends StatefulWidget {
  const new({super.key});

  @override
  State<MainWindow> createState() => _MainWindowState();
}

class _MainWindowState extends State<MainWindow> {
  String selectedCategory = 'All Downloads';
  int selectedFileIndex = 0;
  int? _activeDownloadIndex;
  bool _isDownloadRunning = false;
  int _lastReceivedBytes = 0;
  DateTime? _lastProgressTime;
  final DownloadService _downloadService = DownloadService();

  CancelToken? _downloadCancelToken;

  final categories = [
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

  final files = [
    [
      'Stray.Goldberg.part1.rar',
      '4.19 GB',
      'Downloading',
      '2.4 MB/s',
      '03:25',
      '44',
    ],
    [
      'Rick.and.Morty.Season.5.zip',
      '1.13 GB',
      'Downloading',
      '5.1 MB/s',
      '00:18',
      '89',
    ],
    ['Stray.Goldberg.part2.rar', '2.66 GB', 'Paused', '—', '—', '21'],
    ['WinRAR7Z.exe', '3.4 MB', 'Finished', '—', '—', '100'],
    ['Structure.mp4', '850 MB', 'Finished', '—', '—', '100'],
    ['Advanced Compression.mp4', '1.2 GB', 'Finished', '—', '—', '100'],
    ['No Hard Feelings.mp3', '8.5 MB', 'Finished', '—', '—', '100'],
    ['Competition.pdf', '12 MB', 'Finished', '—', '—', '100'],
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          _toolbar(),
          _sidebar(),
          Expanded(child: _content()),
        ],
      ),
    );
  }

  Widget _toolbar() {
    return Container(
      width: 48,
      color: AppColors.accent,
      child: Column(
        children: [
          _tool(Icons.menu),
          _tool(Icons.add, onPressed: _showAddDownloadDialog),
          const SizedBox(height: 15),
          _tool(
            Icons.play_circle_outline_sharp,
            onPressed: _startSelectedDownload,
          ),
          _tool(
            Icons.pause_circle_outline_outlined,
            onPressed: _pauseSelectedDownload,
          ),
          _tool(Icons.stop_outlined, onPressed: _stopSelectedDownload),
          _tool(Icons.close),
          _tool(Icons.delete_outline, onPressed: _deleteSelectedDownload),
          const Spacer(),
          _tool(Icons.settings),
        ],
      ),
    );
  }

  Widget _tool(IconData icon, {VoidCallback? onPressed}) {
    return IconButton(
      onPressed: onPressed ?? () {},
      icon: Icon(icon, color: Colors.black87),
      tooltip: _toolTip(icon),
    );
  }

  String _toolTip(IconData icon) {
    if (icon == Icons.play_circle_outline_sharp) return 'Start';
    if (icon == Icons.pause_circle_outline_outlined) return 'Pause';
    if (icon == Icons.stop_outlined) return 'Stop';
    if (icon == Icons.delete_outline) return 'Delete';
    return '';
  }

  Future<void> _startSelectedDownload() async {
    if (files.isEmpty) return;

    if (_isDownloadRunning) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please wait until the previous download stops.'),
        ),
      );
      return;
    }

    final file = files[selectedFileIndex];

    if (file[2] == 'Finished') return;

    if (file.length < 7 || file[6].isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add a download URL first.')),
      );
      return;
    }

    final url = file[6];

    final fileName = file[0].replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');

    final userProfile =
        Platform.environment['USERPROFILE'] ?? Directory.current.path;

    final savePath =
        '$userProfile${Platform.pathSeparator}'
        'Downloads${Platform.pathSeparator}$fileName';

    final cancelToken = CancelToken();

    _isDownloadRunning = true;
    _downloadCancelToken = cancelToken;
    _activeDownloadIndex = selectedFileIndex;
    _lastReceivedBytes = 0;
    _lastProgressTime = null;

    setState(() {
      file[2] = 'Downloading';
      file[3] = 'Connecting...';
      file[4] = 'Calculating...';
      file[5] = '0';
    });

    try {
      await _downloadService.downloadFile(
        url: url,
        savePath: savePath,
        cancelToken: cancelToken,
        onProgress: (received, total) {
          if (!mounted) return;

          final now = DateTime.now();
          final previousTime = _lastProgressTime;

          if (previousTime != null) {
            final elapsed = now.difference(previousTime).inMilliseconds / 1000;

            if (elapsed >= 1) {
              final downloadedBytes = received - _lastReceivedBytes;
              final speed = downloadedBytes / elapsed;

              if (speed > 0) {
                final speedMB = speed / (1024 * 1024);

                file[3] = '${speedMB.toStringAsFixed(2)} MB/s';

                if (total > 0) {
                  final remainingBytes = total - received;
                  final remainingSeconds = remainingBytes / speed;

                  final minutes = remainingSeconds ~/ 60;
                  final seconds = remainingSeconds.toInt() % 60;

                  file[4] =
                      '${minutes.toString().padLeft(2, '0')}:'
                      '${seconds.toString().padLeft(2, '0')}';
                }
              }

              _lastReceivedBytes = received;
              _lastProgressTime = now;
            }
          } else {
            _lastReceivedBytes = received;
            _lastProgressTime = now;
          }

          setState(() {
            if (total > 0) {
              file[5] = ((received / total) * 100).toStringAsFixed(0);
              file[1] = '${(total / (1024 * 1024)).toStringAsFixed(2)} MB';
            }
          });
        },
      );

      if (!mounted) return;

      setState(() {
        file[2] = 'Finished';
        file[3] = '—';
        file[4] = '—';
        file[5] = '100';
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Download completed: $fileName')));
    } catch (error) {
      if (!mounted) return;

      final cancelled =
          error is DioException && error.type == DioExceptionType.cancel;

      setState(() {
        file[2] = cancelled ? 'Stopped' : 'Stopped';
        file[3] = '—';
        file[4] = '—';
      });

      if (!cancelled) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Download failed: $error')));
      }
    } finally {
      _isDownloadRunning = false;

      if (identical(_downloadCancelToken, cancelToken)) {
        _downloadCancelToken = null;
        _activeDownloadIndex = null;
      }
    }
  }

  void _pauseSelectedDownload() {
    if (files.isEmpty) return;

    setState(() {
      files[selectedFileIndex][2] = 'Paused';
      files[selectedFileIndex][3] = '—';
      files[selectedFileIndex][4] = '—';
    });
  }

  void _stopSelectedDownload() {
    if (files.isEmpty) return;

    if (_isDownloadRunning &&
        _downloadCancelToken != null &&
        _activeDownloadIndex == selectedFileIndex) {
      _downloadCancelToken!.cancel('Stopped by user');
      return;
    }

    setState(() {
      files[selectedFileIndex][2] = 'Stopped';
      files[selectedFileIndex][3] = '—';
      files[selectedFileIndex][4] = '—';
    });
  }

  void _deleteSelectedDownload() {
    if (files.isEmpty) return;

    setState(() {
      files.removeAt(selectedFileIndex);

      if (files.isEmpty) {
        selectedFileIndex = 0;
      } else if (selectedFileIndex >= files.length) {
        selectedFileIndex = files.length - 1;
      }
    });
  }

  Future<void> _showAddDownloadDialog() async {
    String enteredUrl = '';

    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text('Add New Download', style: TextStyle(fontSize: 16)),
          content: SizedBox(
            width: 400,
            child: TextField(
              autofocus: true,
              onChanged: (value) {
                enteredUrl = value.trim();
              },
              decoration: const InputDecoration(
                hintText: 'https://example.com/file.zip',
                labelText: 'Download URL',
                prefixIcon: Icon(Icons.link),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(dialogContext, enteredUrl);
              },
              child: const Text('Add to Queue'),
            ),
          ],
        );
      },
    );

    if (!mounted || result == null || result.isEmpty) {
      return;
    }

    final uri = Uri.tryParse(result);

    if (uri == null ||
        !uri.hasAuthority ||
        !uri.hasScheme ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid HTTP or HTTPS URL')),
      );
      return;
    }

    final fileName =
        uri.pathSegments.isNotEmpty && uri.pathSegments.last.isNotEmpty
        ? uri.pathSegments.last
        : 'download_${DateTime.now().millisecondsSinceEpoch}';

    setState(() {
      files.add([fileName, 'Unknown', 'Queued', '—', '—', '0', result]);

      selectedFileIndex = files.length - 1;
    });

    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Download added to queue')));
  }

  int get queuedCount {
    return files.where((file) => file[2] == 'Queued').length;
  }

  Widget _sidebar() {
    return Container(
      width: 224,
      color: AppColors.sidebar,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Text(
              'LIBRARY',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: categories.map((category) {
                final selected = selectedCategory == category;

                return Material(
                  color: Colors.transparent,
                  child: ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                    minLeadingWidth: 20,
                    horizontalTitleGap: 12,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                    selected: selected,
                    selectedTileColor: AppColors.accentDark,
                    leading: Icon(
                      _categoryIcon(category),
                      size: 17,
                      color: selected
                          ? AppColors.accent
                          : AppColors.textSecondary,
                    ),
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            category,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: selected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: selected
                                  ? AppColors.accent
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ),
                        if (category == 'Queues' && queuedCount > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.accentDark,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '$queuedCount',
                              style: const TextStyle(
                                color: AppColors.accent,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                    onTap: () {
                      setState(() {
                        selectedCategory = category;
                      });
                    },
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  IconData _categoryIcon(String category) {
    return switch (category) {
      'All Downloads' => Icons.download_rounded,
      'Compressed' => Icons.folder_zip_outlined,
      'Documents' => Icons.description_outlined,
      'Music' => Icons.music_note_outlined,
      'Program' => Icons.apps,
      'Video' => Icons.video_library_outlined,
      'Unfinished' => Icons.downloading_outlined,
      'Finished' => Icons.check_circle_outline,
      'Queues' => Icons.playlist_play,
      _ => Icons.folder_outlined,
    };
  }

  Widget _content() {
    return Row(
      children: [
        Expanded(
          child: Padding(
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
                __tableHeader(),
                const Divider(color: AppColors.border),
                Expanded(
                  child: ListView.builder(
                    itemCount: files.length,
                    itemBuilder: (context, index) {
                      final file = files[index];

                      if (file[2] == 'Queued') {
                        return _queueRow(file, index);
                      }

                      return _fileRow(file, index);
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
          ),
        ),

        SizedBox(width: 260, child: _detailsPanel()),
      ],
    );
  }

  Widget __tableHeader() {
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

  Widget _detailsPanel() {
    if (files.isEmpty) {
      return Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(left: BorderSide(color: AppColors.border)),
        ),
        padding: const EdgeInsets.all(18),
        child: const Center(
          child: Text(
            'No download selected',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
        ),
      );
    }

    final file = files[selectedFileIndex];
    final status = file[2];
    final progress = double.parse(file[5]) / 100;

    final statusColor = switch (status) {
      'Downloading' => AppColors.accent,
      'Paused' => AppColors.paused,
      'Queued' => Colors.cyanAccent,
      'Stopped' => Colors.redAccent,
      'Finished' => Colors.greenAccent,
      _ => AppColors.textSecondary,
    };

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(left: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'DOWNLOAD DETAILS',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
              color: AppColors.textSecondary,
            ),
          ),

          const SizedBox(height: 28),

          const Center(
            child: Icon(
              Icons.insert_drive_file_outlined,
              size: 48,
              color: AppColors.accent,
            ),
          ),

          const SizedBox(height: 16),

          Center(
            child: Text(
              file[0],
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
            ),
          ),

          const SizedBox(height: 12),

          Center(
            child: Text(
              status,
              style: TextStyle(color: statusColor, fontSize: 12),
            ),
          ),

          const SizedBox(height: 28),

          Text(
            '${file[5]}%',
            style: const TextStyle(
              fontSize: 25,
              fontWeight: FontWeight.bold,
              color: AppColors.accent,
            ),
          ),

          const SizedBox(height: 10),

          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 7,
              backgroundColor: AppColors.border,
              valueColor: AlwaysStoppedAnimation(statusColor),
            ),
          ),

          const SizedBox(height: 28),

          _detailItem(Icons.storage, 'File Size', file[1]),
          _detailItem(Icons.speed, 'Download Speed', file[3]),
          _detailItem(Icons.timer_outlined, 'Time Left', file[4]),

          const Spacer(),

          const Divider(color: AppColors.border),

          const SizedBox(height: 12),

          const Row(
            children: [
              Icon(
                Icons.info_outline,
                size: 15,
                color: AppColors.textSecondary,
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Download information',
                  style: TextStyle(
                    fontSize: 10,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _detailItem(IconData icon, String title, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Row(
        children: [
          Icon(icon, size: 17, color: AppColors.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(value, style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _fileRow(List<String> file, int index) {
    final status = file[2];
    final progress = double.parse(file[5]) / 100;

    final progressColor = switch (status) {
      'Downloading' => AppColors.accent,
      'Paused' => AppColors.paused,
      'Queued' => Colors.cyanAccent,
      'Stopped' => Colors.redAccent,
      'Finished' => Colors.greenAccent,
      _ => AppColors.textSecondary,
    };

    final selected = selectedFileIndex == index;

    return GestureDetector(
      onTap: () {
        setState(() {
          selectedFileIndex = index;
        });
      },
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

  void _moveQueuedFile(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= files.length) return;
    if (newIndex < 0 || newIndex >= files.length) return;
    if (oldIndex == newIndex) return;

    if (files[oldIndex][2] != 'Queued' || files[newIndex][2] != 'Queued') {
      return;
    }

    setState(() {
      final movedFile = files.removeAt(oldIndex);
      files.insert(newIndex, movedFile);

      if (selectedFileIndex == oldIndex) {
        selectedFileIndex = newIndex;
      } else if (oldIndex < selectedFileIndex &&
          newIndex >= selectedFileIndex) {
        selectedFileIndex--;
      } else if (oldIndex > selectedFileIndex &&
          newIndex <= selectedFileIndex) {
        selectedFileIndex++;
      }
    });
  }

  Widget _queueRow(List<String> file, int index) {
    return DragTarget<int>(
      onWillAcceptWithDetails: (details) {
        final fromIndex = details.data;

        return fromIndex != index &&
            fromIndex >= 0 &&
            fromIndex < files.length &&
            files[fromIndex][2] == 'Queued';
      },
      onAcceptWithDetails: (details) {
        _moveQueuedFile(details.data, index);
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
            child: _fileRow(file, index),
          ),
          child: Container(
            decoration: candidates.isNotEmpty
                ? BoxDecoration(border: Border.all(color: AppColors.accent))
                : null,
            child: _fileRow(file, index),
          ),
        );
      },
    );
  }
}
