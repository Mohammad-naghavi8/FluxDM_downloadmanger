import 'dart:convert';

import 'package:download_manager/core/localization/app_strings.dart';
import 'package:download_manager/core/theme/app_theme_controller.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum TorrentMenuAction {
  openTorrentFile,
  addMagnetLink,
  rssFeeds,
  torrentSettings,
}

class DownloadToolbar extends StatelessWidget {
  final bool isSidebarVisible;
  final VoidCallback onToggleSidebar;
  final VoidCallback onAdd;
  final ValueChanged<TorrentMenuAction> onTorrentMenuAction;
  final VoidCallback? onStart;
  final VoidCallback? onPause;
  final VoidCallback? onStop;
  final VoidCallback? onStopAll;
  final VoidCallback? onRetry;
  final VoidCallback? onDelete;
  final VoidCallback? onDeleteCompleted;
  final ValueChanged<String>? onStartQueue;
  final ValueChanged<String>? onStopQueue;
  final VoidCallback onOpenScheduler;
  final VoidCallback onOpenBrowserBridge;
  final VoidCallback onOpenSettings;

  const DownloadToolbar({
    super.key,
    required this.isSidebarVisible,
    required this.onToggleSidebar,
    required this.onAdd,
    required this.onTorrentMenuAction,
    required this.onStart,
    required this.onPause,
    required this.onStop,
    required this.onStopAll,
    required this.onRetry,
    required this.onDelete,
    required this.onDeleteCompleted,
    required this.onStartQueue,
    required this.onStopQueue,
    required this.onOpenScheduler,
    required this.onOpenBrowserBridge,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeController.instance.palette;
    return Container(
      width: 50,
      decoration: BoxDecoration(
        color: palette.accent,
        border: Border(
          right: BorderSide(color: palette.border, width: 1),
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
          _TorrentMenuButton(onSelected: onTorrentMenuAction),
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
                    tooltip: 'Stop',
                    iconSize: 21,
                    onPressed: onStop,
                  ),
                  _ToolbarButton(
                    icon: Icons.front_hand_outlined,
                    tooltip: 'Stop All',
                    iconSize: 19,
                    onPressed: onStopAll,
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
                  _ToolbarButton(
                    icon: Icons.delete_sweep_outlined,
                    tooltip: 'Delete Completed',
                    iconSize: 20,
                    onPressed: onDeleteCompleted,
                  ),
                  _groupDivider(),
                  _QueueMenuButton(
                    icon: Icons.playlist_play_rounded,
                    tooltip: 'Start Queue',
                    actionPrefix: 'Start',
                    onSelectedQueue: onStartQueue,
                  ),
                  _QueueMenuButton(
                    icon: Icons.stop_circle_outlined,
                    tooltip: 'Stop Queue',
                    actionPrefix: 'Stop',
                    onSelectedQueue: onStopQueue,
                  ),
                  _ToolbarButton(
                    icon: Icons.schedule_rounded,
                    tooltip: 'Scheduler & Queues',
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
            onPressed: onOpenSettings,
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

class _TorrentMenuButton extends StatefulWidget {
  final ValueChanged<TorrentMenuAction> onSelected;

  const _TorrentMenuButton({required this.onSelected});

  @override
  State<_TorrentMenuButton> createState() => _TorrentMenuButtonState();
}

class _TorrentMenuButtonState extends State<_TorrentMenuButton> {
  bool _hovered = false;

  Future<void> _showMenu() async {
    final renderBox = context.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (renderBox == null || overlay == null) return;

    final topRight = renderBox.localToGlobal(
      Offset(renderBox.size.width + 6, 0),
      ancestor: overlay,
    );

    final selected = await showMenu<TorrentMenuAction>(
      context: context,
      color: const Color(0xFF242424),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: const BorderSide(color: Color(0xFF3E3E3E)),
      ),
      position: RelativeRect.fromLTRB(
        topRight.dx,
        topRight.dy,
        overlay.size.width - topRight.dx,
        overlay.size.height - topRight.dy,
      ),
      items: [
        PopupMenuItem<TorrentMenuAction>(
          value: TorrentMenuAction.openTorrentFile,
          height: 32,
          child: Text(
            AppStrings.instance.t('Open torrent file...'),
            style: const TextStyle(color: Colors.white, fontSize: 12.5),
          ),
        ),
        PopupMenuItem<TorrentMenuAction>(
          value: TorrentMenuAction.addMagnetLink,
          height: 32,
          child: Text(
            AppStrings.instance.t('Add magnet link...'),
            style: const TextStyle(color: Colors.white, fontSize: 12.5),
          ),
        ),
        PopupMenuItem<TorrentMenuAction>(
          value: TorrentMenuAction.rssFeeds,
          height: 32,
          child: Text(
            AppStrings.instance.t('RSS feeds...'),
            style: const TextStyle(color: Colors.white, fontSize: 12.5),
          ),
        ),
        const PopupMenuDivider(height: 8),
        PopupMenuItem<TorrentMenuAction>(
          value: TorrentMenuAction.torrentSettings,
          height: 32,
          child: Text(
            AppStrings.instance.t('Torrent settings...'),
            style: const TextStyle(color: Colors.white, fontSize: 12.5),
          ),
        ),
      ],
    );

    if (selected != null) {
      widget.onSelected(selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Tooltip(
        message: AppStrings.instance.t('Add Torrent / RSS'),
        waitDuration: const Duration(milliseconds: 350),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _showMenu,
              borderRadius: BorderRadius.circular(8),
              splashColor: Colors.black.withValues(alpha: 0.16),
              highlightColor: Colors.black.withValues(alpha: 0.10),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _hovered
                      ? Colors.black.withValues(alpha: 0.14)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.hub_outlined,
                  size: 19,
                  color: Color(0xFF0A0A0A),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _QueueMenuButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final String actionPrefix;
  final ValueChanged<String>? onSelectedQueue;

  const _QueueMenuButton({
    required this.icon,
    required this.tooltip,
    required this.actionPrefix,
    required this.onSelectedQueue,
  });

  @override
  State<_QueueMenuButton> createState() => _QueueMenuButtonState();
}

class _QueueMenuButtonState extends State<_QueueMenuButton> {
  bool _hovered = false;

  Future<List<String>> _loadQueueNames() async {
    const defaults = ['Main download queue', 'Synchronization queue'];
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('scheduler_queues_v1');
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw) as List<dynamic>;
        final names = decoded
            .map((e) => (e as Map<String, dynamic>)['name']?.toString() ?? '')
            .where((n) => n.isNotEmpty)
            .toList();
        if (names.isNotEmpty) return names;
      }
    } catch (_) {}
    return defaults;
  }

  Future<void> _showQueueMenu() async {
    final renderBox = context.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (renderBox == null || overlay == null) return;

    final queues = await _loadQueueNames();
    if (!mounted) return;

    final topRight = renderBox.localToGlobal(
      Offset(renderBox.size.width + 6, 0),
      ancestor: overlay,
    );

    final selected = await showMenu<String>(
      context: context,
      color: const Color(0xFF242424),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: const BorderSide(color: Color(0xFF3E3E3E)),
      ),
      position: RelativeRect.fromLTRB(
        topRight.dx,
        topRight.dy,
        overlay.size.width - topRight.dx,
        overlay.size.height - topRight.dy,
      ),
      items: queues
          .map(
            (qName) => PopupMenuItem<String>(
              value: qName,
              height: 32,
              child: Text(
                AppStrings.instance.t('${widget.actionPrefix} $qName'),
                style: const TextStyle(color: Colors.white, fontSize: 12.5),
              ),
            ),
          )
          .toList(),
    );

    if (selected != null) {
      widget.onSelectedQueue?.call(selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onSelectedQueue != null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Tooltip(
        message: AppStrings.instance.t(widget.tooltip),
        waitDuration: const Duration(milliseconds: 350),
        child: MouseRegion(
          cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
          onEnter: (_) {
            if (enabled) setState(() => _hovered = true);
          },
          onExit: (_) => setState(() => _hovered = false),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: enabled ? _showQueueMenu : null,
              borderRadius: BorderRadius.circular(8),
              splashColor: Colors.black.withValues(alpha: 0.16),
              highlightColor: Colors.black.withValues(alpha: 0.10),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: (_hovered && enabled)
                      ? Colors.black.withValues(alpha: 0.14)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  widget.icon,
                  size: 21,
                  color: enabled
                      ? const Color(0xFF0A0A0A)
                      : const Color(0xFF0A0A0A).withValues(alpha: 0.28),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ToolbarButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
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
    final enabled = widget.onPressed != null;
    final bgColor = (_hovered && enabled)
        ? Colors.black.withValues(alpha: 0.14)
        : (widget.isActive && enabled)
        ? Colors.black.withValues(alpha: 0.09)
        : Colors.transparent;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Tooltip(
        message: AppStrings.instance.t(widget.tooltip),
        waitDuration: const Duration(milliseconds: 350),
        child: MouseRegion(
          cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
          onEnter: (_) {
            if (enabled) setState(() => _hovered = true);
          },
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
                  color: enabled
                      ? AppThemeController.instance.palette.toolbarFg
                      : AppThemeController.instance.palette.toolbarFg
                            .withValues(alpha: 0.28),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
