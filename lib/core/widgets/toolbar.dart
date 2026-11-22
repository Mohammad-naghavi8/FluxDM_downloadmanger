import 'package:download_manager/core/theme/app_colors.dart';
import 'package:material_ui/material_ui.dart';

class DownloadToolbar extends StatelessWidget {
  final bool isSidebarVisible;
  final VoidCallback onToggleSidebar;
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
    required this.isSidebarVisible,
    required this.onToggleSidebar,
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
      width: 50,
      decoration: const BoxDecoration(
        color: AppColors.accent,
        border: Border(
          right: BorderSide(color: Color(0xFF00B876), width: 1),
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 6),
          _ToolbarButton(
            icon: Icons.menu_rounded,
            tooltip: isSidebarVisible ? 'Hide Categories' : 'Show Categories',
            isActive: isSidebarVisible,
            onPressed: onToggleSidebar,
          ),
          const SizedBox(height: 4),
          _ToolbarButton(
            icon: Icons.add_rounded,
            tooltip: 'Add Download',
            iconSize: 23,
            onPressed: onAdd,
          ),
          _groupDivider(),
          Expanded(
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: Column(
                children: [
                  _ToolbarButton(
                    icon: Icons.play_arrow_rounded,
                    tooltip: 'Start / Resume',
                    iconSize: 22,
                    onPressed: onStart,
                  ),
                  _ToolbarButton(
                    icon: Icons.pause_rounded,
                    tooltip: 'Pause',
                    iconSize: 21,
                    onPressed: onPause,
                  ),
                  _ToolbarButton(
                    icon: Icons.stop_rounded,
                    tooltip: 'Stop / Cancel',
                    iconSize: 21,
                    onPressed: onStop,
                  ),
                  _ToolbarButton(
                    icon: Icons.refresh_rounded,
                    tooltip: 'Retry',
                    iconSize: 20,
                    onPressed: onRetry,
                  ),
                  _ToolbarButton(
                    icon: Icons.delete_outline_rounded,
                    tooltip: 'Delete',
                    iconSize: 20,
                    onPressed: onDelete,
                  ),
                  _groupDivider(),
                  _ToolbarButton(
                    icon: Icons.playlist_play_rounded,
                    tooltip: 'Start Queue',
                    iconSize: 22,
                    onPressed: onStartQueue,
                  ),
                  _ToolbarButton(
                    icon: Icons.schedule_rounded,
                    tooltip: 'Scheduler & Speed Limit',
                    iconSize: 20,
                    onPressed: onOpenScheduler,
                  ),
                  _ToolbarButton(
                    icon: Icons.language_rounded,
                    tooltip: 'Browser Integration',
                    iconSize: 20,
                    onPressed: onOpenBrowserBridge,
                  ),
                ],
              ),
            ),
          ),
          _groupDivider(),
          _ToolbarButton(
            icon: Icons.settings_outlined,
            tooltip: 'Settings',
            iconSize: 20,
            onPressed: onOpenScheduler,
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _groupDivider() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 11),
      height: 1,
      color: Colors.black.withValues(alpha: 0.16),
    );
  }
}

class _ToolbarButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final double iconSize;
  final bool isActive;

  const _ToolbarButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.iconSize = 20,
    this.isActive = false,
  });

  @override
  State<_ToolbarButton> createState() => _ToolbarButtonState();
}

class _ToolbarButtonState extends State<_ToolbarButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final bgColor = _hovered
        ? Colors.black.withValues(alpha: 0.14)
        : widget.isActive
        ? Colors.black.withValues(alpha: 0.09)
        : Colors.transparent;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Tooltip(
        message: widget.tooltip,
        waitDuration: const Duration(milliseconds: 350),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onPressed,
              borderRadius: BorderRadius.circular(8),
              splashColor: Colors.black.withValues(alpha: 0.16),
              highlightColor: Colors.black.withValues(alpha: 0.10),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  widget.icon,
                  size: widget.iconSize,
                  color: const Color(0xFF0A0A0A),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
