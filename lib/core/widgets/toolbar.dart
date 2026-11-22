import 'package:download_manager/core/theme/app_colors.dart';
import 'package:material_ui/material_ui.dart';

class DownloadToolbar extends StatelessWidget {
  final VoidCallback onAdd;
  final VoidCallback onStart;
  final VoidCallback onPause;
  final VoidCallback onStop;
  final VoidCallback onRetry;
  final VoidCallback onDelete;
  final VoidCallback onStartQueue;
  final VoidCallback onOpenScheduler;
  final VoidCallback onOpenBrowserBridge;

  const DownloadToolbar({
    super.key,
    required this.onAdd,
    required this.onStart,
    required this.onPause,
    required this.onStop,
    required this.onRetry,
    required this.onDelete,
    required this.onStartQueue,
    required this.onOpenScheduler,
    required this.onOpenBrowserBridge,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      color: AppColors.accent,
      child: Column(
        children: [
          _tool(Icons.menu),
          _tool(Icons.add, tooltip: 'Add Download', onPressed: onAdd),
          const SizedBox(height: 15),
          _tool(
            Icons.play_circle_outline_sharp,
            tooltip: 'Start / Resume',
            onPressed: onStart,
          ),
          _tool(
            Icons.pause_circle_outline_outlined,
            tooltip: 'Pause',
            onPressed: onPause,
          ),
          _tool(Icons.stop_outlined, tooltip: 'Cancel / Stop', onPressed: onStop),
          _tool(Icons.refresh, tooltip: 'Retry', onPressed: onRetry),
          _tool(Icons.delete_outline, tooltip: 'Delete', onPressed: onDelete),
          const SizedBox(height: 10),
          _tool(
            Icons.playlist_play_rounded,
            tooltip: 'Start Queue',
            onPressed: onStartQueue,
          ),
          _tool(
            Icons.schedule_rounded,
            tooltip: 'Scheduler & Concurrency',
            onPressed: onOpenScheduler,
          ),
          _tool(
            Icons.language_rounded,
            tooltip: 'Browser Integration',
            onPressed: onOpenBrowserBridge,
          ),
          const Spacer(),
          _tool(
            Icons.settings,
            tooltip: 'Queue & Scheduler Settings',
            onPressed: onOpenScheduler,
          ),
        ],
      ),
    );
  }

  Widget _tool(IconData icon, {String tooltip = '', VoidCallback? onPressed}) {
    return IconButton(
      onPressed: onPressed ?? () {},
      icon: Icon(icon, color: Colors.black87),
      tooltip: tooltip,
    );
  }
}
