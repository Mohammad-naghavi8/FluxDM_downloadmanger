import 'dart:math' as math;

import 'package:download_manager/core/theme/app_colors.dart';
import 'package:download_manager/features/downloads/models/download_progress_state.dart';
import 'package:material_ui/material_ui.dart';

class DownloadProgressWindow extends StatefulWidget {
  final DownloadProgressState state;
  final VoidCallback onClose;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onCancel;
  final VoidCallback onRetry;
  final VoidCallback? onOpenFolder;

  const DownloadProgressWindow({
    super.key,
    required this.state,
    required this.onClose,
    required this.onPause,
    required this.onResume,
    required this.onCancel,
    required this.onRetry,
    this.onOpenFolder,
  });

  @override
  State<DownloadProgressWindow> createState() => _DownloadProgressWindowState();
}

class _DownloadProgressWindowState extends State<DownloadProgressWindow> {
  static const double _leftStripWidth = 44;
  static const double _titleBarHeight = 44;
  static const Color _panelBg = Color(0xFF000000);
  static const Color _borderColor = Color(0xFF232825);
  static const Color _dividerColor = Color(0xFF1D221F);
  static const Color _labelColor = Color(0xFF8C928E);
  static const Color _valueColor = Color(0xFFF2F5F3);

  bool _showDetails = false;
  Offset? _position;
  final ScrollController _connectionsScrollController = ScrollController();

  @override
  void dispose() {
    _connectionsScrollController.dispose();
    super.dispose();
  }

  Color _statusColor(DownloadProgressStatus status) {
    return switch (status) {
      DownloadProgressStatus.connecting => AppColors.accent,
      DownloadProgressStatus.downloading => AppColors.accent,
      DownloadProgressStatus.rebuilding => AppColors.accent,
      DownloadProgressStatus.paused => AppColors.paused,
      DownloadProgressStatus.stopped => Colors.redAccent,
      DownloadProgressStatus.failed => Colors.redAccent,
      DownloadProgressStatus.completed => AppColors.accent,
    };
  }

  (IconData, Color) _fileIconForName(String fileName) {
    final ext = fileName.contains('.')
        ? fileName.split('.').last.toLowerCase()
        : '';

    const archives = {'rar', 'zip', '7z', 'tar', 'gz'};
    const videos = {'mp4', 'mkv', 'avi', 'mov', 'wmv', 'webm'};
    const audio = {'mp3', 'wav', 'flac', 'aac', 'ogg', 'm4a'};
    const docs = {'pdf', 'doc', 'docx', 'txt', 'xls', 'xlsx', 'ppt', 'pptx'};
    const programs = {'exe', 'msi', 'msix', 'appx', 'apk'};

    if (archives.contains(ext)) {
      return (Icons.folder_zip_outlined, const Color(0xFFFFC107));
    }
    if (videos.contains(ext)) {
      return (Icons.movie_outlined, AppColors.video);
    }
    if (audio.contains(ext)) {
      return (Icons.audio_file_outlined, AppColors.audio);
    }
    if (docs.contains(ext)) {
      return (Icons.description_outlined, AppColors.document);
    }
    if (programs.contains(ext)) {
      return (Icons.apps_outlined, AppColors.accent);
    }
    return (Icons.insert_drive_file_outlined, const Color(0xFFFFC107));
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final statusColor = _statusColor(state.status);

    return LayoutBuilder(
      builder: (context, constraints) {
        const margin = 12.0;
        final availableWidth = math.max(
          300.0,
          constraints.maxWidth - margin * 2,
        );
        final windowWidth = math.min(560.0, availableWidth);
        final maxWindowHeight = math.max(
          220.0,
          constraints.maxHeight - margin * 2,
        );

        final estimatedHeight = _showDetails
            ? 560.0
            : (state.isFailed ? 410.0 : 365.0);
        final clampedEstHeight = math.min(estimatedHeight, maxWindowHeight);

        final defaultLeft = math.max(
          margin,
          (constraints.maxWidth - windowWidth) / 2,
        );
        final defaultTop = math.max(
          margin,
          (constraints.maxHeight - clampedEstHeight) / 2,
        );

        final maxLeft = math.max(
          margin,
          constraints.maxWidth - windowWidth - margin,
        );
        final maxTop = math.max(
          margin,
          constraints.maxHeight - math.min(clampedEstHeight, 220.0) - margin,
        );

        final currentPos = _position ?? Offset(defaultLeft, defaultTop);
        final left = currentPos.dx.clamp(margin, maxLeft);
        final top = currentPos.dy.clamp(margin, maxTop);
        final effectiveMaxHeight = math.max(
          180.0,
          math.min(maxWindowHeight, constraints.maxHeight - top - margin),
        );

        void handleDrag(Offset delta) {
          setState(() {
            final base = Offset(left, top);
            _position = Offset(
              (base.dx + delta.dx).clamp(margin, maxLeft),
              (base.dy + delta.dy).clamp(margin, maxTop),
            );
          });
        }

        return Stack(
          children: [
            Positioned(
              left: left,
              top: top,
              child: RepaintBoundary(
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                  width: windowWidth,
                  constraints: BoxConstraints(maxHeight: effectiveMaxHeight),
                  decoration: BoxDecoration(
                    color: _panelBg,
                    borderRadius: BorderRadius.circular(2),
                    border: Border.all(color: _borderColor, width: 1),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.78),
                        blurRadius: 28,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(1),
                    child: Stack(
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(left: _leftStripWidth),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildTitleBar(
                                state: state,
                                onDragUpdate: handleDrag,
                              ),
                              const Divider(
                                height: 1,
                                thickness: 1,
                                color: _dividerColor,
                              ),
                              Flexible(
                                child: SingleChildScrollView(
                                  padding: const EdgeInsets.fromLTRB(
                                    14,
                                    14,
                                    14,
                                    14,
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      _buildInfoCard(state, statusColor),
                                      const SizedBox(height: 12),
                                      _buildProgressBar(state, statusColor),
                                      if (state.isFailed &&
                                          state.errorMessage != null &&
                                          state.errorMessage!.isNotEmpty) ...[
                                        const SizedBox(height: 10),
                                        _buildErrorLine(state.errorMessage!),
                                      ],
                                      const SizedBox(height: 12),
                                      _buildBottomButtons(state),
                                      if (_showDetails) ...[
                                        const SizedBox(height: 14),
                                        _buildIdmConnectionDetails(
                                          state,
                                          statusColor,
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Positioned(
                          left: 0,
                          top: 0,
                          bottom: 0,
                          width: _leftStripWidth,
                          child: _buildLeftAccentStrip(
                            state: state,
                            onDragUpdate: handleDrag,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildLeftAccentStrip({
    required DownloadProgressState state,
    required void Function(Offset delta) onDragUpdate,
  }) {
    return Container(
      color: AppColors.accent,
      child: Column(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanUpdate: (details) => onDragUpdate(details.delta),
            child: const MouseRegion(
              cursor: SystemMouseCursors.move,
              child: SizedBox(
                height: _titleBarHeight,
                width: double.infinity,
                child: Center(
                  child: Icon(
                    Icons.download_outlined,
                    color: Colors.black87,
                    size: 20,
                  ),
                ),
              ),
            ),
          ),
          Container(
            height: 1,
            color: Colors.black.withValues(alpha: 0.45),
          ),
          const SizedBox(height: 12),
          _stripIconButton(
            icon: Icons.apps_rounded,
            tooltip: 'Download Status',
            onPressed: () {
              if (_showDetails) {
                setState(() => _showDetails = false);
              }
            },
          ),
          const SizedBox(height: 6),
          _stripIconButton(
            icon: Icons.play_circle_outline_rounded,
            tooltip: state.isPaused ? 'Resume' : 'Pause / Resume',
            onPressed: state.isActive
                ? widget.onPause
                : state.isPaused
                ? widget.onResume
                : null,
          ),
          const SizedBox(height: 6),
          _stripIconButton(
            icon: Icons.access_time_rounded,
            tooltip: _showDetails ? 'Hide Details' : 'Show Details',
            onPressed: () {
              setState(() => _showDetails = !_showDetails);
            },
          ),
        ],
      ),
    );
  }

  Widget _stripIconButton({
    required IconData icon,
    required String tooltip,
    VoidCallback? onPressed,
  }) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed ?? () {},
      icon: Icon(icon, color: Colors.black87, size: 19),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 32, height: 32),
      style: IconButton.styleFrom(
        hoverColor: Colors.black.withValues(alpha: 0.12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
    );
  }

  Widget _buildTitleBar({
    required DownloadProgressState state,
    required void Function(Offset delta) onDragUpdate,
  }) {
    final (fileIcon, fileIconColor) = _fileIconForName(state.fileName);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanUpdate: (details) => onDragUpdate(details.delta),
      child: MouseRegion(
        cursor: SystemMouseCursors.move,
        child: Container(
          height: _titleBarHeight,
          color: _panelBg,
          padding: const EdgeInsets.only(left: 14, right: 8),
          child: Row(
            children: [
              Icon(fileIcon, size: 17, color: fileIconColor),
              const SizedBox(width: 10),
              Expanded(
                child: Tooltip(
                  message: state.titleText,
                  child: Text(
                    state.titleText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _valueColor,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: IconButton(
                  tooltip: 'Close',
                  onPressed: widget.onClose,
                  iconSize: 17,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 28,
                    height: 28,
                  ),
                  style: IconButton.styleFrom(
                    foregroundColor: const Color(0xFFB5BBB7),
                    hoverColor: const Color(0xFF1A201D),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  icon: const Icon(Icons.close_rounded),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard(DownloadProgressState state, Color statusColor) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: _panelBg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: _borderColor, width: 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _infoRow('Address:', state.url, tooltip: state.url),
          _infoRow('File Name:', state.fileName, tooltip: state.fileName),
          _infoRow('Status:', state.statusLabel, valueColor: statusColor),
          _infoRow('File size:', state.formattedFileSize),
          _infoRow('Downloaded:', state.formattedDownloaded),
          _infoRow('Transfer rate:', state.formattedTransferRate),
          _infoRow('Time left:', state.formattedTimeLeft),
          _infoRow(
            'Resume\nCapability:',
            state.resumeCapabilityLabel,
            isLast: true,
          ),
        ],
      ),
    );
  }

  Widget _infoRow(
    String label,
    String value, {
    Color valueColor = _valueColor,
    bool isLast = false,
    String? tooltip,
  }) {
    final textWidget = Text(
      value,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: valueColor,
        fontSize: 12.5,
        height: 1.3,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );

    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 102,
            child: Text(
              label,
              style: const TextStyle(
                color: _labelColor,
                fontSize: 12.5,
                height: 1.3,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: tooltip != null
                ? Tooltip(message: tooltip, child: textWidget)
                : textWidget,
          ),
        ],
      ),
    );
  }

  Widget _buildProgressBar(DownloadProgressState state, Color statusColor) {
    return Container(
      height: 8,
      decoration: BoxDecoration(
        color: _panelBg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFF2B312E), width: 1),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: LinearProgressIndicator(
          value: state.progress,
          backgroundColor: _panelBg,
          valueColor: AlwaysStoppedAnimation<Color>(statusColor),
        ),
      ),
    );
  }

  Widget _buildErrorLine(String message) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.redAccent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            size: 14,
            color: Colors.redAccent,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.redAccent, fontSize: 11.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIdmConnectionDetails(
    DownloadProgressState state,
    Color statusColor,
  ) {
    final connections = state.connections;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Start positions and download progress by connections',
          textAlign: TextAlign.center,
          style: TextStyle(color: _labelColor, fontSize: 11.5),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 16,
          child: CustomPaint(
            painter: _IdmConnectionsBarPainter(
              connections: connections,
              totalBytes: state.totalBytes,
              isCompleted: state.isCompleted,
              activeColor: statusColor,
              completedSegmentColor: const Color(0xFF0A8F5F),
              markerColor: const Color(0xFFE24A3B),
              trackColor: const Color(0xFF0A0D0B),
              borderColor: const Color(0xFF2B312E),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: _panelBg,
            borderRadius: BorderRadius.circular(2),
            border: Border.all(color: _borderColor, width: 1),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 28,
                decoration: const BoxDecoration(
                  color: Color(0xFF0C100E),
                  border: Border(
                    bottom: BorderSide(color: _borderColor, width: 1),
                  ),
                ),
                child: const Row(
                  children: [
                    SizedBox(
                      width: 36,
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          'N.',
                          style: TextStyle(
                            color: _valueColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    VerticalDivider(
                      width: 1,
                      thickness: 1,
                      color: _borderColor,
                    ),
                    SizedBox(
                      width: 100,
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          'Downloaded',
                          style: TextStyle(
                            color: _valueColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    VerticalDivider(
                      width: 1,
                      thickness: 1,
                      color: _borderColor,
                    ),
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          'Info',
                          style: TextStyle(
                            color: _valueColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 152),
                child: Scrollbar(
                  controller: _connectionsScrollController,
                  thumbVisibility: connections.length > 5,
                  child: ListView.builder(
                    controller: _connectionsScrollController,
                    shrinkWrap: true,
                    itemCount: connections.length,
                    itemBuilder: (context, index) {
                      return _buildConnectionRow(
                        connections[index],
                        statusColor: statusColor,
                        isLast: index == connections.length - 1,
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
        if (state.savePath.isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Tooltip(
                  message: state.savePath,
                  child: Text(
                    'Save to: ${state.savePath}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _labelColor, fontSize: 11),
                  ),
                ),
              ),
              if (widget.onOpenFolder != null) ...[
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: widget.onOpenFolder,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.accent,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: const Icon(Icons.folder_open_outlined, size: 13),
                  label: const Text(
                    'Open Folder',
                    style: TextStyle(fontSize: 11),
                  ),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildConnectionRow(
    DownloadConnectionProgress connection, {
    required Color statusColor,
    required bool isLast,
  }) {
    final Color infoColor;
    if (connection.hasError) {
      infoColor = Colors.redAccent;
    } else if (connection.isCompleted) {
      infoColor = AppColors.accent;
    } else if (connection.info.startsWith('Receiving')) {
      infoColor = statusColor;
    } else if (connection.info.startsWith('Paused')) {
      infoColor = AppColors.paused;
    } else {
      infoColor = _valueColor;
    }

    return Container(
      height: 25,
      decoration: BoxDecoration(
        border: isLast
            ? null
            : const Border(bottom: BorderSide(color: _dividerColor, width: 1)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                '${connection.number}',
                style: const TextStyle(
                  color: _valueColor,
                  fontSize: 11.5,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
          const SizedBox(width: 1),
          SizedBox(
            width: 100,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                connection.formattedDownloaded,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _valueColor,
                  fontSize: 11.5,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
          const SizedBox(width: 1),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Tooltip(
                message: connection.info,
                child: Text(
                  connection.info,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: infoColor,
                    fontSize: 11.5,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomButtons(DownloadProgressState state) {
    final String middleLabel;
    final VoidCallback? middleAction;

    if (state.isActive) {
      middleLabel = 'Pause';
      middleAction = widget.onPause;
    } else if (state.isPaused) {
      middleLabel = 'Resume';
      middleAction = widget.onResume;
    } else if (state.isFailed || state.isStopped) {
      middleLabel = 'Retry';
      middleAction = widget.onRetry;
    } else {
      middleLabel = 'Open Folder';
      middleAction = widget.onOpenFolder;
    }

    final String rightLabel = state.isCompleted ? 'Close' : 'Cancel';
    final VoidCallback? rightAction = state.isCompleted
        ? widget.onClose
        : (state.isStopped ? null : widget.onCancel);

    return Row(
      children: [
        Expanded(
          child: _flatActionButton(
            onPressed: () {
              setState(() {
                _showDetails = !_showDetails;
              });
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    _showDetails ? 'Hide Details' : 'Show Details',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  _showDetails
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 16,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _flatActionButton(
            onPressed: middleAction,
            child: Text(middleLabel, overflow: TextOverflow.ellipsis),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _flatActionButton(
            onPressed: rightAction,
            child: Text(rightLabel, overflow: TextOverflow.ellipsis),
          ),
        ),
      ],
    );
  }

  Widget _flatActionButton({
    required VoidCallback? onPressed,
    required Widget child,
  }) {
    return SizedBox(
      height: 36,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: _panelBg,
          foregroundColor: _valueColor,
          disabledForegroundColor: _labelColor.withValues(alpha: 0.45),
          side: const BorderSide(color: Color(0xFF262C28), width: 1),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          textStyle: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
          ),
        ),
        child: child,
      ),
    );
  }
}

class _IdmConnectionsBarPainter extends CustomPainter {
  final List<DownloadConnectionProgress> connections;
  final int? totalBytes;
  final bool isCompleted;
  final Color activeColor;
  final Color completedSegmentColor;
  final Color markerColor;
  final Color trackColor;
  final Color borderColor;

  const _IdmConnectionsBarPainter({
    required this.connections,
    required this.totalBytes,
    required this.isCompleted,
    required this.activeColor,
    required this.completedSegmentColor,
    required this.markerColor,
    required this.trackColor,
    required this.borderColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final barRect = Rect.fromLTWH(0, 0, size.width, size.height);
    final barRRect = RRect.fromRectAndRadius(barRect, const Radius.circular(1));

    canvas.drawRRect(barRRect, Paint()..color = trackColor);

    final total = totalBytes;
    final hasKnownTotal = total != null && total > 0;

    canvas.save();
    canvas.clipRRect(barRRect);

    if (isCompleted) {
      canvas.drawRect(barRect, Paint()..color = activeColor);
    } else if (hasKnownTotal) {
      for (final conn in connections) {
        final startRatio = (conn.startByte / total).clamp(0.0, 1.0);
        final endRatio =
            ((conn.startByte + conn.downloadedBytes) / total).clamp(0.0, 1.0);
        final leftX = startRatio * size.width;
        final width = (endRatio - startRatio) * size.width;

        if (width > 0) {
          final segmentColor = conn.isCompleted && !conn.isActive
              ? completedSegmentColor
              : activeColor;
          canvas.drawRect(
            Rect.fromLTWH(leftX, 0, math.max(1.5, width), size.height),
            Paint()..color = segmentColor,
          );
        }
      }

      // Draw crisp vertical IDM start-position markers for each connection
      final startLinePaint = Paint()
        ..color = markerColor
        ..strokeWidth = 1.5;

      for (final conn in connections) {
        final ratio = (conn.startByte / total).clamp(0.0, 1.0);
        final x = (ratio * size.width).clamp(1.0, size.width - 1.0);
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), startLinePaint);
      }
    } else {
      final anyDownloaded = connections.any((c) => c.downloadedBytes > 0);
      if (anyDownloaded) {
        canvas.drawRect(
          Rect.fromLTWH(0, 0, size.width * 0.25, size.height),
          Paint()..color = activeColor.withValues(alpha: 0.7),
        );
      }
    }

    canvas.restore();

    canvas.drawRRect(
      barRRect.deflate(0.5),
      Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _IdmConnectionsBarPainter oldDelegate) {
    return oldDelegate.connections != connections ||
        oldDelegate.totalBytes != totalBytes ||
        oldDelegate.isCompleted != isCompleted ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.markerColor != markerColor;
  }
}
