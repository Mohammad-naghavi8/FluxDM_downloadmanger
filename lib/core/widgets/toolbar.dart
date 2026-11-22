import 'package:download_manager/core/theme/app_colors.dart';
import 'package:material_ui/material_ui.dart';

class DownloadToolbar extends StatelessWidget {
  final VoidCallback onAdd;
  final VoidCallback onStart;
  final VoidCallback onPause;
  final VoidCallback onStop;
  final VoidCallback onRetry;
  final VoidCallback onDelete;

  const DownloadToolbar({
    super.key,
    required this.onAdd,
    required this.onStart,
    required this.onPause,
    required this.onStop,
    required this.onRetry,
    required this.onDelete,
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
            tooltip: 'Start',
            onPressed: onStart,
          ),
          _tool(
            Icons.pause_circle_outline_outlined,
            tooltip: 'Pause',
            onPressed: onPause,
          ),
          _tool(Icons.stop_outlined, tooltip: 'Stop', onPressed: onStop),
          _tool(Icons.close),
          _tool(Icons.refresh, tooltip: 'Retry', onPressed: onRetry),
          _tool(Icons.delete_outline, tooltip: 'Delete', onPressed: onDelete),
          const Spacer(),
          _tool(Icons.settings),
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
