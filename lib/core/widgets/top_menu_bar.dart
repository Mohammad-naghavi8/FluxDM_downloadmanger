import 'package:download_manager/core/localization/app_strings.dart';
import 'package:download_manager/core/theme/app_theme_controller.dart';
import 'package:material_ui/material_ui.dart';

class TopMenuBar extends StatelessWidget {
  final bool isSidebarVisible;
  final bool isDropTargetVisible;
  final bool isSpeedLimiterOn;
  final String currentSortBy;
  final String currentTheme;
  final double currentScale;
  final String currentRenderer;
  final VoidCallback onAddNewDownload;
  final VoidCallback onOpenTorrentFile;
  final VoidCallback onAddMagnetLink;
  final VoidCallback onTorrentSettings;
  final VoidCallback onAddBatchDownload;
  final VoidCallback onAddBatchFromClipboard;
  final VoidCallback onDownloadVideoFromPage;
  final VoidCallback onLinkGrabber;
  final VoidCallback onRssFeeds;
  final VoidCallback onToggleDropTarget;
  final VoidCallback onExportFluxFile;
  final VoidCallback onExportTextFile;
  final VoidCallback onImportFluxFile;
  final VoidCallback onImportTextFile;
  final VoidCallback onExit;

  // File menu (nullable -> auto-disabled when no selection / inactive!)
  final VoidCallback? onStopDownload;
  final VoidCallback? onRemove;
  final VoidCallback? onRemoveWithFiles;
  final VoidCallback? onDownloadNow;
  final VoidCallback? onRedownload;

  // Downloads menu
  final VoidCallback? onPauseAll;
  final VoidCallback? onStopAll;
  final VoidCallback? onDeleteAllCompleted;
  final VoidCallback onFind;
  final VoidCallback? onFindNext;
  final VoidCallback? onSelectAll;
  final VoidCallback onOpenScheduler;
  final ValueChanged<String> onStartQueue;
  final ValueChanged<String>? onStopQueue;
  final VoidCallback onSpeedLimiterTurnOn;
  final VoidCallback onSpeedLimiterTurnOff;
  final VoidCallback onSpeedLimiterSettings;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenBrowserBridge;

  // View menu
  final VoidCallback onToggleSidebar;
  final ValueChanged<String> onArrangeFiles;
  final bool isAlwaysDark;
  final VoidCallback onToggleAlwaysDark;
  final ValueChanged<String> onSelectTheme;
  final ValueChanged<double> onSelectInterfaceSize;
  final ValueChanged<String> onSelectRenderer;
  final VoidCallback onOpenLanguage;
  final VoidCallback onAbout;

  const TopMenuBar({
    super.key,
    required this.isSidebarVisible,
    required this.isDropTargetVisible,
    required this.isSpeedLimiterOn,
    required this.currentSortBy,
    required this.currentTheme,
    required this.currentScale,
    required this.currentRenderer,
    required this.onAddNewDownload,
    required this.onOpenTorrentFile,
    required this.onAddMagnetLink,
    required this.onTorrentSettings,
    required this.onAddBatchDownload,
    required this.onAddBatchFromClipboard,
    required this.onDownloadVideoFromPage,
    required this.onLinkGrabber,
    required this.onRssFeeds,
    required this.onToggleDropTarget,
    required this.onExportFluxFile,
    required this.onExportTextFile,
    required this.onImportFluxFile,
    required this.onImportTextFile,
    required this.onExit,
    required this.onStopDownload,
    required this.onRemove,
    required this.onRemoveWithFiles,
    required this.onDownloadNow,
    required this.onRedownload,
    required this.onPauseAll,
    required this.onStopAll,
    required this.onDeleteAllCompleted,
    required this.onFind,
    required this.onFindNext,
    required this.onSelectAll,
    required this.onOpenScheduler,
    required this.onStartQueue,
    required this.onStopQueue,
    required this.onSpeedLimiterTurnOn,
    required this.onSpeedLimiterTurnOff,
    required this.onSpeedLimiterSettings,
    required this.onOpenSettings,
    required this.onOpenBrowserBridge,
    required this.onToggleSidebar,
    required this.onArrangeFiles,
    required this.isAlwaysDark,
    required this.onToggleAlwaysDark,
    required this.onSelectTheme,
    required this.onSelectInterfaceSize,
    required this.onSelectRenderer,
    required this.onOpenLanguage,
    required this.onAbout,
  });

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeController.instance.palette;
    final isDark = palette.brightness == Brightness.dark;
    final s = AppStrings.instance;
    final menuBg = isDark ? const Color(0xFF222222) : Colors.white;
    final menuFg = isDark ? const Color(0xFFE8E8E8) : const Color(0xFF111827);

    final menuStyle = MenuStyle(
      backgroundColor: WidgetStatePropertyAll(menuBg),
      surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      side: WidgetStatePropertyAll(BorderSide(color: palette.border)),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
      ),
      padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 4)),
    );

    final topBtnStyle = ButtonStyle(
      foregroundColor: WidgetStatePropertyAll(menuFg),
      overlayColor: WidgetStatePropertyAll(
        palette.accent.withValues(alpha: 0.14),
      ),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 10, vertical: 0),
      ),
      minimumSize: const WidgetStatePropertyAll(Size(0, 26)),
      textStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 12)),
    );

    final itemStyle = ButtonStyle(
      foregroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return isDark ? const Color(0xFF6B6B6B) : const Color(0xFF9CA3AF);
        }
        return menuFg;
      }),
      overlayColor: WidgetStatePropertyAll(
        palette.accent.withValues(alpha: 0.16),
      ),
      minimumSize: const WidgetStatePropertyAll(Size(220, 28)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 14, vertical: 0),
      ),
      textStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 12)),
    );

    MenuItemButton item(
      String label,
      VoidCallback? onPressed, {
      String? shortcut,
      bool checked = false,
      bool radioDot = false,
    }) {
      return MenuItemButton(
        style: itemStyle,
        onPressed: onPressed,
        leadingIcon: checked
            ? Icon(Icons.check_rounded, size: 14, color: palette.accent)
            : radioDot
            ? Icon(Icons.circle, size: 7, color: palette.accent)
            : const SizedBox(width: 14),
        trailingIcon: shortcut != null
            ? Text(
                shortcut,
                style: TextStyle(
                  color: onPressed == null
                      ? const Color(0xFF555555)
                      : const Color(0xFF8E8E8E),
                  fontSize: 11,
                ),
              )
            : null,
        child: Text(s.t(label)),
      );
    }

    Widget divider() => Divider(height: 8, color: palette.border);

    return Container(
      height: 27,
      decoration: BoxDecoration(
        color: palette.menuBar,
        border: Border(bottom: BorderSide(color: palette.border)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 6),
          Icon(Icons.bolt_rounded, size: 15, color: palette.accent),
          const SizedBox(width: 4),
          Text(
            'FluxDM',
            style: TextStyle(
              color: palette.accent,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(width: 10),
          MenuBar(
            style: const MenuStyle(
              backgroundColor: WidgetStatePropertyAll(Colors.transparent),
              elevation: WidgetStatePropertyAll(0),
              padding: WidgetStatePropertyAll(EdgeInsets.zero),
            ),
            children: [
              // ── TASKS ──
              SubmenuButton(
                style: topBtnStyle,
                menuStyle: menuStyle,
                menuChildren: [
                  item('Add new download', onAddNewDownload, shortcut: 'Ctrl+N'),
                  item('Open torrent file...', onOpenTorrentFile),
                  item('Add magnet link...', onAddMagnetLink),
                  item('Torrent settings...', onTorrentSettings),
                  item('Add batch download', onAddBatchDownload),
                  item(
                    'Add batch download from clipboard',
                    onAddBatchFromClipboard,
                  ),
                  item(
                    'Download video from a page...',
                    onDownloadVideoFromPage,
                  ),
                  item('Link grabber...', onLinkGrabber),
                  item('RSS feeds...', onRssFeeds),
                  divider(),
                  item(
                    isDropTargetVisible
                        ? 'Hide drop target'
                        : 'Show drop target',
                    onToggleDropTarget,
                  ),
                  divider(),
                  SubmenuButton(
                    style: itemStyle,
                    menuStyle: menuStyle,
                    menuChildren: [
                      item('To FluxDM export file...', onExportFluxFile),
                      item('To text file...', onExportTextFile),
                    ],
                    child: Text(s.t('Export')),
                  ),
                  SubmenuButton(
                    style: itemStyle,
                    menuStyle: menuStyle,
                    menuChildren: [
                      item('From FluxDM export file...', onImportFluxFile),
                      item('From text file...', onImportTextFile),
                    ],
                    child: Text(s.t('Import')),
                  ),
                  divider(),
                  item('Exit', onExit),
                ],
                child: Text(s.t('Tasks')),
              ),

              // ── FILE ──
              SubmenuButton(
                style: topBtnStyle,
                menuStyle: menuStyle,
                menuChildren: [
                  item('Stop Download', onStopDownload),
                  item('Remove', onRemove, shortcut: 'Delete'),
                  item(
                    'Remove with files',
                    onRemoveWithFiles,
                    shortcut: 'Shift+Delete',
                  ),
                  item('Download Now', onDownloadNow),
                  item('Redownload', onRedownload),
                ],
                child: Text(s.t('File')),
              ),

              // ── DOWNLOADS ──
              SubmenuButton(
                style: topBtnStyle,
                menuStyle: menuStyle,
                menuChildren: [
                  item('Pause All', onPauseAll),
                  item('Stop All', onStopAll),
                  divider(),
                  item('Delete All Completed', onDeleteAllCompleted),
                  divider(),
                  item('Find', onFind, shortcut: 'Ctrl+F'),
                  item('Find Next', onFindNext, shortcut: 'F3'),
                  item('Select all', onSelectAll, shortcut: 'Ctrl+A'),
                  divider(),
                  item('Scheduler', onOpenScheduler),
                  SubmenuButton(
                    style: itemStyle,
                    menuStyle: menuStyle,
                    menuChildren: [
                      item(
                        'Start Main download queue',
                        () => onStartQueue('Main download queue'),
                      ),
                      item(
                        'Start Synchronization queue',
                        () => onStartQueue('Synchronization queue'),
                      ),
                    ],
                    child: Text(s.t('Start queue')),
                  ),
                  SubmenuButton(
                    style: itemStyle,
                    menuStyle: menuStyle,
                    menuChildren: [
                      item(
                        'Stop Main download queue',
                        onStopQueue != null
                            ? () => onStopQueue!('Main download queue')
                            : null,
                      ),
                      item(
                        'Stop Synchronization queue',
                        onStopQueue != null
                            ? () => onStopQueue!('Synchronization queue')
                            : null,
                      ),
                    ],
                    child: Text(s.t('Stop queue')),
                  ),
                  divider(),
                  SubmenuButton(
                    style: itemStyle,
                    menuStyle: menuStyle,
                    menuChildren: [
                      item(
                        'Turn on',
                        onSpeedLimiterTurnOn,
                        checked: isSpeedLimiterOn,
                      ),
                      item(
                        'Turn off',
                        onSpeedLimiterTurnOff,
                        checked: !isSpeedLimiterOn,
                      ),
                      divider(),
                      item('Settings...', onSpeedLimiterSettings),
                    ],
                    child: Text(s.t('Speed Limiter')),
                  ),
                  divider(),
                  item('Browser Integration...', onOpenBrowserBridge),
                  item('Options', onOpenSettings),
                ],
                child: Text(s.t('Downloads')),
              ),

              // ── VIEW ──
              SubmenuButton(
                style: topBtnStyle,
                menuStyle: menuStyle,
                menuChildren: [
                  item(
                    isSidebarVisible ? 'Hide categories' : 'Show categories',
                    onToggleSidebar,
                  ),
                  SubmenuButton(
                    style: itemStyle,
                    menuStyle: menuStyle,
                    menuChildren: [
                      item(
                        'By Order Of Addition',
                        () => onArrangeFiles('order'),
                        radioDot: currentSortBy == 'order',
                      ),
                      item(
                        'By File Name',
                        () => onArrangeFiles('name'),
                        radioDot: currentSortBy == 'name',
                      ),
                      item(
                        'By Size',
                        () => onArrangeFiles('size'),
                        radioDot: currentSortBy == 'size',
                      ),
                      item(
                        'By Status',
                        () => onArrangeFiles('status'),
                        radioDot: currentSortBy == 'status',
                      ),
                      item(
                        'By Time Left',
                        () => onArrangeFiles('timeLeft'),
                        radioDot: currentSortBy == 'timeLeft',
                      ),
                      item(
                        'By Transfer Rate',
                        () => onArrangeFiles('speed'),
                        radioDot: currentSortBy == 'speed',
                      ),
                    ],
                    child: Text(s.t('Arrange files')),
                  ),
                  divider(),
                  item('Dark Mode support', onToggleAlwaysDark, checked: true),
                  item(
                    'Always dark',
                    onToggleAlwaysDark,
                    checked: isAlwaysDark,
                  ),
                  SubmenuButton(
                    style: itemStyle,
                    menuStyle: menuStyle,
                    menuChildren: [
                      for (final t in const [
                        'Classic',
                        'Native',
                        'High contrast',
                        'Metro',
                        'Adwaita',
                        'Breeze',
                        'Luna',
                        'Aero',
                        'Aqua',
                      ])
                        item(
                          t,
                          () => onSelectTheme(t),
                          radioDot: currentTheme == t,
                        ),
                    ],
                    child: Text(s.t('Theme')),
                  ),
                  SubmenuButton(
                    style: itemStyle,
                    menuStyle: menuStyle,
                    menuChildren: [
                      item(
                        '100%',
                        () => onSelectInterfaceSize(1.0),
                        shortcut: 'Ctrl+0',
                        radioDot: (currentScale - 1.0).abs() < 0.01,
                      ),
                      item(
                        '125%',
                        () => onSelectInterfaceSize(1.25),
                        radioDot: (currentScale - 1.25).abs() < 0.01,
                      ),
                      item(
                        '150%',
                        () => onSelectInterfaceSize(1.5),
                        radioDot: (currentScale - 1.5).abs() < 0.01,
                      ),
                      item(
                        '175%',
                        () => onSelectInterfaceSize(1.75),
                        radioDot: (currentScale - 1.75).abs() < 0.01,
                      ),
                      item(
                        '200%',
                        () => onSelectInterfaceSize(2.0),
                        radioDot: (currentScale - 2.0).abs() < 0.01,
                      ),
                    ],
                    child: Text(s.t('Interface size')),
                  ),
                  SubmenuButton(
                    style: itemStyle,
                    menuStyle: menuStyle,
                    menuChildren: [
                      item(
                        'OpenGL',
                        () => onSelectRenderer('OpenGL'),
                        radioDot: currentRenderer == 'OpenGL',
                      ),
                      item(
                        'Direct3D',
                        () => onSelectRenderer('Direct3D'),
                        radioDot: currentRenderer == 'Direct3D',
                      ),
                    ],
                    child: Text(s.t('Draw with')),
                  ),
                  divider(),
                  item('Language...', onOpenLanguage),
                ],
                child: Text(s.t('View')),
              ),

              // ── HELP ──
              SubmenuButton(
                style: topBtnStyle,
                menuStyle: menuStyle,
                menuChildren: [
                  item('About FluxDM...', onAbout),
                ],
                child: Text(s.t('Help')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
