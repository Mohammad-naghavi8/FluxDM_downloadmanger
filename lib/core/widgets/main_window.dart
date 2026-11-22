import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:clipboard_watcher/clipboard_watcher.dart';
import 'package:download_manager/core/localization/app_strings.dart';
import 'package:download_manager/core/theme/app_colors.dart';
import 'package:download_manager/core/theme/app_theme_controller.dart';
import 'package:download_manager/core/widgets/sidebar.dart';
import 'package:download_manager/core/widgets/toolbar.dart';
import 'package:download_manager/core/widgets/top_menu_bar.dart';
import 'package:download_manager/features/downloads/controllers/download_manager_controller.dart';
import 'package:download_manager/features/downloads/models/download_progress_state.dart';
import 'package:download_manager/features/downloads/services/browser_bridge_service.dart';
import 'package:download_manager/features/downloads/services/go_engine_client.dart';
import 'package:download_manager/features/downloads/services/go_engine_process.dart';
import 'package:download_manager/features/downloads/utils/download_link_helper.dart';
import 'package:download_manager/features/downloads/widgets/add_download_dialog.dart';
import 'package:download_manager/features/downloads/widgets/batch_download_dialog.dart';
import 'package:download_manager/features/downloads/widgets/browser_integration_dialog.dart';
import 'package:download_manager/features/downloads/widgets/download_list_view.dart';
import 'package:download_manager/features/downloads/widgets/download_progress_window.dart';
import 'package:download_manager/features/downloads/widgets/enter_address_dialog.dart';
import 'package:download_manager/features/downloads/widgets/link_grabber_dialog.dart';
import 'package:download_manager/features/downloads/widgets/menu_dialogs.dart';
import 'package:download_manager/features/downloads/widgets/scheduler_dialog.dart';
import 'package:download_manager/features/downloads/widgets/video_download_dialog.dart';
import 'package:download_manager/features/settings/models/app_settings.dart';
import 'package:download_manager/features/settings/services/app_settings_service.dart';
import 'package:download_manager/features/settings/widgets/configuration_dialog.dart';
import 'package:download_manager/features/torrents/models/torrent_models.dart';
import 'package:download_manager/features/torrents/services/rss_feed_service.dart';
import 'package:download_manager/features/torrents/services/torrent_parser.dart';
import 'package:download_manager/features/torrents/widgets/add_torrent_dialog.dart';
import 'package:download_manager/features/torrents/widgets/rss_feeds_dialog.dart';
import 'package:download_manager/features/torrents/widgets/torrent_settings_dialog.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

class MainWindow extends StatefulWidget {
  const new({super.key});

  @override
  State<MainWindow> createState() => _MainWindowState();
}

class _MainWindowState extends State<MainWindow> with ClipboardListener {
  late final DownloadManagerController _controller;
  final BrowserBridgeService _browserBridge = BrowserBridgeService();
  final RssAndTorrentStorageService _torrentStorage =
      RssAndTorrentStorageService();
  final AppSettingsService _appSettingsService = AppSettingsService();
  AppSettings _appSettings = const AppSettings();
  bool _isAddDialogOpen = false;
  bool _isSidebarVisible = true;
  bool _isDropTargetVisible = false;
  Offset _dropTargetPosition = const Offset(24, 24);
  String? _lastClipboardUrl;
  FindFileQuery? _lastFindQuery;
  int _lastFindIndex = -1;
  double _interfaceScale = 1.0;
  String _selectedRenderer = 'Direct3D';

  @override
  void initState() {
    super.initState();

    _controller = DownloadManagerController(
      onMessage: _showSnackBar,
      onDownloadCompleted: _handleDownloadCompleted,
    );
    clipboardWatcher.addListener(this);
    clipboardWatcher.start();
    _controller.initialize();
    _startBrowserBridge();
    _initGoAndSettings();
  }

  Future<void> _initGoAndSettings() async {
    final loaded = await _appSettingsService.load();
    if (mounted) {
      setState(() => _appSettings = loaded);
    }
    final started = await GoEngineProcess.instance.ensureStarted();
    if (started) {
      unawaited(GoEngineClient().applyConfig(loaded).catchError((_) {}));
    }
  }

  void _handleDownloadCompleted(dynamic entry) {
    if (!_appSettings.extractArchivesOnComplete) return;
    if (!GoEngineProcess.instance.isRunning) return;
    final savePath = entry.savePath as String;
    final lower = savePath.toLowerCase();
    final isSupportedArchive =
        lower.endsWith('.zip') ||
        lower.endsWith('.tar') ||
        lower.endsWith('.tar.gz') ||
        lower.endsWith('.tgz');
    if (!isSupportedArchive) return;

    unawaited(
      GoEngineClient()
          .extractArchive(
            savePath,
            targetMode: _appSettings.archiveExtractTarget,
          )
          .then((res) {
            if (mounted) {
              _showSnackBar(
                'Extracted ${res.fileCount} file(s) via Go engine',
              );
            }
          })
          .catchError((_) {}),
    );
  }

  @override
  void dispose() {
    clipboardWatcher.removeListener(this);
    clipboardWatcher.stop();
    _browserBridge.stop();
    _controller.dispose();
    unawaited(GoEngineProcess.instance.stop());
    super.dispose();
  }

  Future<void> _startBrowserBridge() async {
    await _browserBridge.start(
      onLinkReceived: (link) {
        if (!mounted) return;
        _handleBrowserLink(link);
      },
    );
  }

  Future<void> _handleBrowserLink(BrowserCapturedLink link) async {
    if (link.autoStart) {
      await _controller.addDownload(url: link.url, startNow: true);
      return;
    }

    if (_isAddDialogOpen) {
      await _controller.addDownload(url: link.url, startNow: false);
      return;
    }

    _isAddDialogOpen = true;
    try {
      await _showAddDownloadDialog(initialUrl: link.url);
    } finally {
      _isAddDialogOpen = false;
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<String?> _readClipboardText() async {
    for (int attempt = 0; attempt < 3; attempt++) {
      try {
        final data = await Clipboard.getData(Clipboard.kTextPlain);
        return data?.text;
      } on PlatformException {
        // Windows briefly locks the clipboard when another app updates it.
        if (attempt < 2) {
          await Future<void>.delayed(const Duration(milliseconds: 60));
        }
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  @override
  Future<void> onClipboardChanged() async {
    if (!_appSettings.offerClipboardDownloads) return;

    final rawText = await _readClipboardText();

    if (!mounted || rawText == null || rawText.trim().isEmpty) return;

    final trimmedRaw = rawText.trim();
    if (TorrentParser.isMagnetLink(trimmedRaw) &&
        trimmedRaw != _lastClipboardUrl) {
      _lastClipboardUrl = trimmedRaw;
      if (_isAddDialogOpen) return;
      _isAddDialogOpen = true;
      try {
        await _showAddTorrentDialog(
          initialSource: trimmedRaw,
          autoLookup: true,
        );
      } finally {
        _isAddDialogOpen = false;
      }
      return;
    }

    final extractedUrl = DownloadLinkHelper.extractSupportedUrl(rawText);
    if (extractedUrl == null || extractedUrl == _lastClipboardUrl) return;

    final uri = Uri.tryParse(extractedUrl);
    if (uri == null || !DownloadLinkHelper.isLikelyDirectDownloadUrl(uri)) {
      return;
    }

    _lastClipboardUrl = extractedUrl;

    if (_isAddDialogOpen) return;

    _isAddDialogOpen = true;
    try {
      await _showAddDownloadDialog(initialUrl: extractedUrl);
    } finally {
      _isAddDialogOpen = false;
    }
  }

  Future<void> _showEnterAddressFlow() async {
    if (_isAddDialogOpen) return;

    _isAddDialogOpen = true;
    try {
      String? prefilledUrl;
      try {
        final clipData = await Clipboard.getData(Clipboard.kTextPlain);
        final raw = clipData?.text;
        if (raw != null && raw.trim().isNotEmpty) {
          prefilledUrl = DownloadLinkHelper.extractSupportedUrl(raw);
        }
      } catch (_) {}

      if (!mounted) return;

      final addressResult = await showDialog<EnterAddressResult>(
        context: context,
        builder: (_) => EnterAddressDialog(initialUrl: prefilledUrl),
      );

      if (!mounted || addressResult == null) return;

      await _showAddDownloadDialog(
        initialUrl: addressResult.url,
        initialUsername: addressResult.username,
        initialPassword: addressResult.password,
      );
    } finally {
      _isAddDialogOpen = false;
    }
  }

  Future<void> _showAddDownloadDialog({
    String? initialUrl,
    String? initialUsername,
    String? initialPassword,
  }) async {
    String dialogPath = _controller.downloadDirectory;
    if (dialogPath.isEmpty) {
      dialogPath = await _controller.downloadPathService.getSavedPath();
    }
    if (!mounted) return;

    final result = await showDialog<AddDownloadResult>(
      context: context,
      builder: (_) => AddDownloadDialog(
        downloadService: _controller.downloadService,
        downloadPathService: _controller.downloadPathService,
        initialDirectory: dialogPath,
        initialUrl: initialUrl,
        initialUsername: initialUsername,
        initialPassword: initialPassword,
        formatError: _controller.formatErrorMessage,
        onDirectoryChanged: _controller.updateDownloadDirectory,
      ),
    );

    if (!mounted || result == null || result.url.isEmpty) return;

    await _controller.addDownload(
      url: result.url,
      fileInfo: result.fileInfo,
      startNow: result.startNow,
      scheduledAt: result.scheduledAt,
      username: result.username,
      password: result.password,
      savePath: result.savePath,
      category: result.category,
    );
  }

  Future<void> _showSchedulerDialog() async {
    final selected = _controller.selectedEntry;

    final result = await showDialog<SchedulerDialogResult>(
      context: context,
      builder: (_) => SchedulerDialog(
        initialConfig: _controller.scheduleConfig,
        selectedEntry: selected,
        queuedEntries: _controller.files
            .where((e) => e.isQueued || e.isScheduled)
            .toList(),
        queuedCount: _controller.queuedCount,
        activeCount: _controller.activeDownloadCount,
        onStartQueueNow: _controller.startQueue,
        onPauseAll: _controller.pauseAllDownloads,
        onMoveQueuedEntry: _controller.moveQueuedEntry,
        onRemoveQueuedEntry: (id) => unawaited(_controller.deleteDownloadById(id)),
      ),
    );

    if (!mounted || result == null) return;

    await _controller.updateScheduleConfig(result.config);

    if (result.updateSelectedEntrySchedule && selected != null) {
      _controller.scheduleEntry(selected.id, result.selectedEntrySchedule);
    } else {
      _showSnackBar('Scheduler settings saved');
    }
  }

  Future<void> _showBrowserIntegrationDialog() async {
    await showDialog<void>(
      context: context,
      builder: (_) => BrowserIntegrationDialog(bridgeService: _browserBridge),
    );
  }

  Future<void> _handleTorrentMenuAction(TorrentMenuAction action) async {
    switch (action) {
      case TorrentMenuAction.openTorrentFile:
        final picked = await FilePicker.pickFiles(
          type: FileType.custom,
          allowedExtensions: const ['torrent'],
        );
        if (!mounted || picked.isEmpty) return;
        final path = picked.single.path;
        if (path != null && path.isNotEmpty) {
          await _showAddTorrentDialog(initialSource: path, autoLookup: true);
        }
      case TorrentMenuAction.addMagnetLink:
        String? clipboardMagnet;
        try {
          final clip = await Clipboard.getData(Clipboard.kTextPlain);
          final text = clip?.text?.trim();
          if (text != null && TorrentParser.isMagnetLink(text)) {
            clipboardMagnet = text;
          }
        } catch (_) {}
        if (!mounted) return;
        await _showAddTorrentDialog(
          initialSource: clipboardMagnet,
          autoLookup: clipboardMagnet != null,
        );
      case TorrentMenuAction.rssFeeds:
        await _showRssFeedsDialog();
      case TorrentMenuAction.torrentSettings:
        await _showTorrentSettingsDialog();
    }
  }

  Future<void> _showAddTorrentDialog({
    String? initialSource,
    bool autoLookup = false,
  }) async {
    String saveDir = _controller.downloadDirectory;
    if (saveDir.isEmpty) {
      saveDir = await _controller.downloadPathService.getSavedPath();
    }
    if (!mounted) return;

    final result = await showDialog<AddTorrentResult>(
      context: context,
      builder: (_) => AddTorrentDialog(
        initialSaveDirectory: saveDir,
        initialSource: initialSource,
        autoLookup: autoLookup,
      ),
    );

    if (!mounted || result == null) return;
    _controller.addTorrentDownload(
      metadata: result.metadata,
      saveDirectory: result.saveDirectory,
      downloadInOrder: result.downloadInOrder,
      startNow: result.startNow,
    );
  }

  Future<void> _showRssFeedsDialog() async {
    await showDialog<void>(
      context: context,
      builder: (_) => RssFeedsDialog(
        storage: _torrentStorage,
        onDownloadArticle: (RssArticle article) {
          Navigator.of(context).pop();
          final link = article.link.trim();
          if (link.isEmpty) return;
          if (TorrentParser.isMagnetLink(link) ||
              link.toLowerCase().endsWith('.torrent')) {
            unawaited(
              _showAddTorrentDialog(initialSource: link, autoLookup: true),
            );
          } else {
            unawaited(_showAddDownloadDialog(initialUrl: link));
          }
        },
      ),
    );
  }

  Future<void> _showTorrentSettingsDialog() async {
    final current = await _torrentStorage.loadTorrentSettings();
    if (!mounted) return;

    final updated = await showDialog<TorrentSettings>(
      context: context,
      builder: (_) => TorrentSettingsDialog(initialSettings: current),
    );

    if (!mounted || updated == null) return;
    await _torrentStorage.saveTorrentSettings(updated);
    _showSnackBar('Torrent settings saved');
  }

  Future<void> _showConfigurationDialog() async {
    String dir = _controller.downloadDirectory;
    if (dir.isEmpty) {
      dir = await _controller.downloadPathService.getSavedPath();
    }
    if (!mounted) return;

    final updated = await showDialog<AppSettings>(
      context: context,
      builder: (_) => ConfigurationDialog(
        initialSettings: _appSettings,
        downloadPathService: _controller.downloadPathService,
        defaultDownloadDir: dir,
        onOpenBrowserIntegration: () {
          Navigator.of(context).pop();
          unawaited(_showBrowserIntegrationDialog());
        },
      ),
    );

    if (!mounted || updated == null) return;
    setState(() => _appSettings = updated);
    await _appSettingsService.save(updated);
    if (GoEngineProcess.instance.isRunning) {
      unawaited(GoEngineClient().applyConfig(updated).catchError((_) {}));
    }

    final nextSegments = updated.defaultMaxConnections.clamp(1, 16);
    if (nextSegments != _controller.scheduleConfig.segmentsPerDownload) {
      await _controller.updateScheduleConfig(
        _controller.scheduleConfig.copyWith(segmentsPerDownload: nextSegments),
      );
    }
    _showSnackBar('Settings saved');
  }

  Future<void> _handleDeleteSelected() async {
    final selected = _controller.selectedEntry;
    if (selected == null) return;
    if (!_appSettings.confirmBeforeDeleting) {
      await _controller.deleteSelectedDownload();
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Delete'),
        content: Text('Delete "${selected.fileName}" from the download list?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _controller.deleteSelectedDownload();
    }
  }

  Future<void> _showBatchDownloadDialog() async {
    final result = await showDialog<BatchDownloadResult>(
      context: context,
      builder: (_) => const BatchDownloadDialog(),
    );
    if (!mounted || result == null || result.urls.isEmpty) return;

    int added = 0;
    for (final url in result.urls) {
      final entry = await _controller.addDownload(
        url: url,
        startNow: false,
        username: result.username,
        password: result.password,
      );
      if (entry != null) added++;
    }
    _showSnackBar('Added $added batch download(s) to queue');
  }

  Future<void> _addBatchFromClipboard() async {
    final text = await _readClipboardText();
    if (!mounted) return;
    await _showLinkGrabberDialog(initialInput: text);
  }

  Future<void> _showVideoDownloadDialog() async {
    String dir = _controller.downloadDirectory;
    if (dir.isEmpty) {
      dir = await _controller.downloadPathService.getSavedPath();
    }
    if (!mounted) return;

    final result = await showDialog<VideoDownloadResult>(
      context: context,
      builder: (_) => VideoDownloadDialog(
        initialSaveDirectory: '$dir${Platform.pathSeparator}Videos',
      ),
    );
    if (!mounted || result == null || result.url.isEmpty) return;

    final fullSavePath = result.saveDirectory.isNotEmpty
        ? '${result.saveDirectory}${Platform.pathSeparator}${result.fileName}'
        : null;
    await _controller.addDownload(
      url: result.url,
      startNow: result.startNow,
      savePath: fullSavePath,
      category: 'Videos',
    );
  }

  Future<void> _showLinkGrabberDialog({String? initialInput}) async {
    String dir = _controller.downloadDirectory;
    if (dir.isEmpty) {
      dir = await _controller.downloadPathService.getSavedPath();
    }
    if (!mounted) return;

    final result = await showDialog<LinkGrabberResult>(
      context: context,
      builder: (_) => LinkGrabberDialog(
        initialSaveDirectory: dir,
        initialInput: initialInput,
      ),
    );
    if (!mounted || result == null || result.urls.isEmpty) return;

    int added = 0;
    for (final url in result.urls) {
      final entry = await _controller.addDownload(
        url: url,
        startNow: result.startNow,
      );
      if (entry != null) added++;
    }
    _showSnackBar('Grabbed and added $added download(s)');
  }

  Future<void> _exportToFluxFile() async {
    if (_controller.files.isEmpty) {
      _showSnackBar('No downloads to export');
      return;
    }
    final payload = {
      'app': 'FluxDM',
      'version': 1,
      'downloads': _controller.files
          .map(
            (e) => {
              'url': e.url,
              'fileName': e.fileName,
              'category': e.category,
              'savePath': e.savePath,
            },
          )
          .toList(),
    };
    final jsonText = const JsonEncoder.withIndent('  ').convert(payload);
    final outUri = await FilePicker.saveFile(
      dialogTitle: 'Export to FluxDM file',
      fileName: 'fluxdm_downloads.fdm',
      bytes: Uint8List.fromList(utf8.encode(jsonText)),
    );
    if (outUri == null) return;
    final outPath = outUri.toFilePath();
    if (outPath.isNotEmpty) {
      await File(outPath).writeAsString(jsonText);
    }
    if (mounted) _showSnackBar('Exported to FluxDM file');
  }

  Future<void> _exportToTextFile() async {
    if (_controller.files.isEmpty) {
      _showSnackBar('No downloads to export');
      return;
    }
    final lines = _controller.files
        .map((e) => e.url)
        .where((u) => u.isNotEmpty)
        .join('\n');
    final outUri = await FilePicker.saveFile(
      dialogTitle: 'Export URLs to text file',
      fileName: 'fluxdm_links.txt',
      bytes: Uint8List.fromList(utf8.encode(lines)),
    );
    if (outUri == null) return;
    final outPath = outUri.toFilePath();
    if (outPath.isNotEmpty) {
      await File(outPath).writeAsString(lines);
    }
    if (mounted) _showSnackBar('Exported URLs to text file');
  }

  Future<void> _importFromFluxFile() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['fdm', 'json'],
    );
    if (!mounted || picked.isEmpty || picked.single.path == null) return;
    try {
      final raw = await File(picked.single.path!).readAsString();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final list = decoded['downloads'] as List<dynamic>? ?? const [];
      int added = 0;
      for (final item in list) {
        if (item is! Map<String, dynamic>) continue;
        final url = item['url']?.toString() ?? '';
        if (url.isEmpty) continue;
        final entry = await _controller.addDownload(
          url: url,
          startNow: false,
          savePath: item['savePath']?.toString(),
          category: item['category']?.toString(),
        );
        if (entry != null) added++;
      }
      _showSnackBar('Imported $added download(s) from FluxDM file');
    } catch (err) {
      _showSnackBar('Failed to import FluxDM file: $err');
    }
  }

  Future<void> _importFromTextFile() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['txt'],
    );
    if (!mounted || picked.isEmpty || picked.single.path == null) return;
    try {
      final raw = await File(picked.single.path!).readAsString();
      final lines = raw
          .split(RegExp(r'\r?\n'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty);
      int added = 0;
      for (final url in lines) {
        final entry = await _controller.addDownload(url: url, startNow: false);
        if (entry != null) added++;
      }
      _showSnackBar('Imported $added URL(s) from text file');
    } catch (err) {
      _showSnackBar('Failed to import text file: $err');
    }
  }

  Future<void> _exitApp() async {
    await GoEngineProcess.instance.stop();
    exit(0);
  }

  void _showAboutDialog() {
    final s = AppStrings.instance;
    final accent = AppThemeController.instance.palette.accent;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.bolt_rounded, color: accent),
            const SizedBox(width: 8),
            Text(s.t('About FluxDM')),
          ],
        ),
        content: Text(
          '${s.t('FluxDM — Fast & Modern Download Manager')}\n'
          '${s.t('Version 1.0.0')}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(s.t('OK')),
          ),
        ],
      ),
    );
  }

  Future<void> _showFindDialog() async {
    final result = await showDialog<FindFileQuery>(
      context: context,
      builder: (_) => FindFileDialog(initialQuery: _lastFindQuery),
    );
    if (!mounted || result == null) return;
    _lastFindQuery = result;
    _lastFindIndex = -1;
    _findNextMatch();
  }

  void _findNextMatch() {
    final q = _lastFindQuery;
    if (q == null) return;
    final list = _controller.visibleFiles;
    if (list.isEmpty) {
      _showSnackBar('No files in current view');
      return;
    }

    bool matches(String haystack) {
      final h = q.matchCase ? haystack : haystack.toLowerCase();
      final needle = q.matchCase ? q.query : q.query.toLowerCase();
      return q.matchWholeString ? h == needle : h.contains(needle);
    }

    for (int step = 1; step <= list.length; step++) {
      final idx = (_lastFindIndex + step) % list.length;
      final entry = list[idx];
      final hit =
          (q.inFileName && matches(entry.fileName)) ||
          (q.inUrl && matches(entry.url)) ||
          (q.inDescription && matches(entry.category));
      if (hit) {
        _lastFindIndex = idx;
        _controller.selectFileById(entry.id);
        return;
      }
    }
    _showSnackBar('No match found for "${q.query}"');
  }

  Future<void> _showSpeedLimiterSettingsDialog() async {
    final result = await showDialog<SpeedLimiterSettingsResult>(
      context: context,
      builder: (_) => SpeedLimiterSettingsDialog(
        initialKBps: _controller.scheduleConfig.speedLimitKBps,
        initialAlwaysOnStartup: _controller.scheduleConfig.speedLimitEnabled,
      ),
    );
    if (!mounted || result == null) return;
    await _controller.updateScheduleConfig(
      _controller.scheduleConfig.copyWith(
        speedLimitEnabled: result.alwaysOnStartup ||
            _controller.scheduleConfig.speedLimitEnabled,
        speedLimitKBps: result.maxPerFileKBps,
      ),
    );
    _showSnackBar('Speed Limiter set to ${result.maxPerFileKBps} KB/s');
  }

  Future<void> _showLanguageDialog() async {
    final picked = await showDialog<String>(
      context: context,
      builder: (_) => LanguageDialog(currentLanguage: AppStrings.instance.code),
    );
    if (!mounted || picked == null) return;
    await AppStrings.instance.setLanguage(picked);
    _showSnackBar('Language updated');
  }

  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(_interfaceScale),
      ),
      child: Scaffold(
        body: ListenableBuilder(
          listenable: Listenable.merge([
            _controller,
            AppThemeController.instance,
            AppStrings.instance,
          ]),
          builder: (context, _) {
            final selected = _controller.selectedEntry;
            final hasSelection = selected != null;
            final hasActive = _controller.activeDownloadCount > 0;
            final hasQueued = _controller.queuedCount > 0;
            final hasCompleted = _controller.hasCompletedDownloads;
            final canResume =
                selected != null &&
                !selected.isFinished &&
                !selected.isDownloading;
            final canPause = selected != null && selected.isDownloading;
            final canStop =
                selected != null &&
                !selected.isFinished &&
                (selected.isDownloading ||
                    selected.isQueued ||
                    selected.isScheduled ||
                    selected.isPaused);
            final canRetry =
                selected != null && (selected.isFailed || selected.isStopped);
            final canStopAll = hasActive || hasQueued;

            return Column(
              children: [
                TopMenuBar(
                  isSidebarVisible: _isSidebarVisible,
                  isDropTargetVisible: _isDropTargetVisible,
                  isSpeedLimiterOn:
                      _controller.scheduleConfig.speedLimitEnabled,
                  currentSortBy: _controller.sortBy,
                  currentTheme: AppThemeController.instance.themeName,
                  currentScale: _interfaceScale,
                  currentRenderer: _selectedRenderer,
                  onAddNewDownload: _showEnterAddressFlow,
                  onOpenTorrentFile: () => _handleTorrentMenuAction(
                    TorrentMenuAction.openTorrentFile,
                  ),
                  onAddMagnetLink: () => _handleTorrentMenuAction(
                    TorrentMenuAction.addMagnetLink,
                  ),
                  onTorrentSettings: () => _handleTorrentMenuAction(
                    TorrentMenuAction.torrentSettings,
                  ),
                  onAddBatchDownload: _showBatchDownloadDialog,
                  onAddBatchFromClipboard: _addBatchFromClipboard,
                  onDownloadVideoFromPage: _showVideoDownloadDialog,
                  onLinkGrabber: () => _showLinkGrabberDialog(),
                  onRssFeeds: _showRssFeedsDialog,
                  onToggleDropTarget: () => setState(
                    () => _isDropTargetVisible = !_isDropTargetVisible,
                  ),
                  onExportFluxFile: _exportToFluxFile,
                  onExportTextFile: _exportToTextFile,
                  onImportFluxFile: _importFromFluxFile,
                  onImportTextFile: _importFromTextFile,
                  onExit: _exitApp,
                  onStopDownload: canStop
                      ? _controller.stopSelectedDownload
                      : null,
                  onRemove: hasSelection ? _handleDeleteSelected : null,
                  onRemoveWithFiles: hasSelection
                      ? _controller.deleteSelectedWithFiles
                      : null,
                  onDownloadNow: canResume
                      ? _controller.startSelectedDownload
                      : null,
                  onRedownload: hasSelection
                      ? _controller.redownloadSelected
                      : null,
                  onPauseAll: hasActive ? _controller.pauseAllDownloads : null,
                  onStopAll: canStopAll ? _controller.stopAllDownloads : null,
                  onDeleteAllCompleted: hasCompleted
                      ? _controller.deleteCompletedDownloads
                      : null,
                  onFind: _showFindDialog,
                  onFindNext: _lastFindQuery != null ? _findNextMatch : null,
                  onSelectAll: _controller.visibleFiles.isNotEmpty
                      ? () => _controller.selectFileById(
                          _controller.visibleFiles.first.id,
                        )
                      : null,
                  onOpenScheduler: _showSchedulerDialog,
                  onStartQueue: (queueName) {
                    _controller.startQueue();
                    _showSnackBar('Started $queueName');
                  },
                  onStopQueue: hasActive
                      ? (queueName) {
                          _controller.pauseAllDownloads();
                          _showSnackBar('Stopped $queueName');
                        }
                      : null,
                  onSpeedLimiterTurnOn: () => _controller.updateScheduleConfig(
                    _controller.scheduleConfig.copyWith(
                      speedLimitEnabled: true,
                    ),
                  ),
                  onSpeedLimiterTurnOff: () => _controller.updateScheduleConfig(
                    _controller.scheduleConfig.copyWith(
                      speedLimitEnabled: false,
                    ),
                  ),
                  onSpeedLimiterSettings: _showSpeedLimiterSettingsDialog,
                  onOpenSettings: _showConfigurationDialog,
                  onOpenBrowserBridge: _showBrowserIntegrationDialog,
                  onToggleSidebar: () =>
                      setState(() => _isSidebarVisible = !_isSidebarVisible),
                  onArrangeFiles: _controller.setSortBy,
                  isAlwaysDark: AppThemeController.instance.alwaysDark,
                  onToggleAlwaysDark: () => AppThemeController.instance
                      .setAlwaysDark(!AppThemeController.instance.alwaysDark),
                  onSelectTheme: (t) => AppThemeController.instance.setTheme(t),
                  onSelectInterfaceSize: (s) =>
                      setState(() => _interfaceScale = s),
                  onSelectRenderer: (r) =>
                      setState(() => _selectedRenderer = r),
                  onOpenLanguage: _showLanguageDialog,
                  onAbout: _showAboutDialog,
                ),
                Expanded(
                  child: Stack(
                    children: [
                      Row(
                        children: [
                          DownloadToolbar(
                            isSidebarVisible: _isSidebarVisible,
                            onToggleSidebar: () => setState(
                              () => _isSidebarVisible = !_isSidebarVisible,
                            ),
                            onAdd: _showEnterAddressFlow,
                            onTorrentMenuAction: _handleTorrentMenuAction,
                            onStart: canResume
                                ? _controller.startSelectedDownload
                                : null,
                            onPause: canPause
                                ? _controller.pauseSelectedDownload
                                : null,
                            onStop: canStop
                                ? _controller.stopSelectedDownload
                                : null,
                            onStopAll: canStopAll
                                ? _controller.stopAllDownloads
                                : null,
                            onRetry: canRetry
                                ? _controller.retrySelectedDownload
                                : null,
                            onDelete: hasSelection
                                ? _handleDeleteSelected
                                : null,
                            onDeleteCompleted: hasCompleted
                                ? _controller.deleteCompletedDownloads
                                : null,
                            onStartQueue: hasQueued
                                ? (queueName) {
                                    _controller.startQueue();
                                    _showSnackBar('Started $queueName');
                                  }
                                : null,
                            onStopQueue: hasActive
                                ? (queueName) {
                                    _controller.pauseAllDownloads();
                                    _showSnackBar('Stopped $queueName');
                                  }
                                : null,
                            onOpenScheduler: _showSchedulerDialog,
                            onOpenBrowserBridge: _showBrowserIntegrationDialog,
                            onOpenSettings: _showConfigurationDialog,
                          ),
                          Expanded(
                            child: Row(
                              children: [
                        if (_isSidebarVisible)
                          RepaintBoundary(
                            child: DownloadSidebar(
                              categories: DownloadManagerController.categories,
                              selectedCategory: _controller.selectedCategory,
                              queuedCount: _controller.queuedCount,
                              categoryCount: _controller.categoryCount,
                              onSelectCategory: _controller.selectCategory,
                              onClose: () =>
                                  setState(() => _isSidebarVisible = false),
                            ),
                          )
                        else
                          Container(
                            width: 24,
                            decoration: const BoxDecoration(
                              color: Color(0xFF1A1A1A),
                              border: Border(
                                right: BorderSide(
                                  color: Color(0xFF333333),
                                  width: 1,
                                ),
                              ),
                            ),
                            child: Tooltip(
                              message: AppStrings.instance.t('Show Categories'),
                              child: InkWell(
                                onTap: () =>
                                    setState(() => _isSidebarVisible = true),
                                child: const Center(
                                  child: Icon(
                                    Icons.chevron_right_rounded,
                                    size: 16,
                                    color: Color(0xFFD0D0D0),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        Expanded(
                          child: RepaintBoundary(
                            child: DownloadListView(
                              selectedCategory: _controller.selectedCategory,
                              files: _controller.visibleFiles,
                              totalCount: _controller.files.length,
                              activeCount: _controller.activeDownloadCount,
                              maxConcurrent: _controller.maxConcurrentDownloads,
                              scheduleConfig: _controller.scheduleConfig,
                              selectedFileId: _controller.selectedFileId,
                              onSearchChanged: _controller.updateSearchQuery,
                              onSelectFile: _controller.selectFileById,
                              onOpenProgress:
                                  _controller.openExistingProgressWindow,
                              onMoveQueuedEntry: _controller.moveQueuedEntry,
                            ),
                          ),
                        ),
                              ],
                            ),
                          ),
                        ],
                      ),
          ListenableBuilder(
            listenable: _controller,
            builder: (context, _) {
              if (!_controller.isProgressWindowVisible) {
                return const SizedBox.shrink();
              }

              return ValueListenableBuilder<DownloadProgressState?>(
                valueListenable: _controller.progressNotifier,
                builder: (context, progressState, _) {
                  if (progressState == null) {
                    return const SizedBox.shrink();
                  }

                  final targetId = _controller.progressWindowEntryId;

                  return DownloadProgressWindow(
                    state: progressState,
                    onClose: _controller.closeProgressWindow,
                    onPause: () {
                      if (targetId != null) {
                        _controller.pauseDownloadById(targetId);
                      }
                    },
                    onResume: () {
                      if (targetId != null) {
                        _controller.resumeDownloadById(targetId);
                      }
                    },
                    onCancel: () {
                      if (targetId != null) {
                        _controller.stopDownloadById(targetId);
                      }
                    },
                    onRetry: () {
                      if (targetId != null) {
                        _controller.retryDownloadById(targetId);
                      }
                    },
                    onOpenFolder: progressState.savePath.isNotEmpty
                        ? () => _controller.openFolderForPath(
                            progressState.savePath,
                          )
                        : null,
                    onSpeedLimitChanged: targetId != null
                        ? (bytesPerSec) => _controller.setEntrySpeedLimit(
                            targetId,
                            bytesPerSec,
                          )
                        : null,
                  );
                },
              );
            },
          ),
          if (_isDropTargetVisible)
            Positioned(
              right: _dropTargetPosition.dx,
              bottom: _dropTargetPosition.dy,
              child: GestureDetector(
                onPanUpdate: (details) {
                  setState(() {
                    _dropTargetPosition = Offset(
                      (_dropTargetPosition.dx - details.delta.dx)
                          .clamp(8.0, 900.0),
                      (_dropTargetPosition.dy - details.delta.dy)
                          .clamp(8.0, 600.0),
                    );
                  });
                },
                onTap: _addBatchFromClipboard,
                onSecondaryTapDown: (details) async {
                  final pos = details.globalPosition;
                  final action = await showMenu<String>(
                    context: context,
                    color: const Color(0xFF222222),
                    surfaceTintColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(3),
                      side: const BorderSide(color: Color(0xFF3E3E3E)),
                    ),
                    position: RelativeRect.fromLTRB(
                      pos.dx,
                      pos.dy,
                      pos.dx + 1,
                      pos.dy + 1,
                    ),
                    items: [
                      PopupMenuItem<String>(
                        value: 'show',
                        height: 30,
                        child: Text(
                          AppStrings.instance.t('Show FluxDM'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                      PopupMenuItem<String>(
                        value: 'add',
                        height: 30,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              AppStrings.instance.t('Add new download'),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12.5,
                              ),
                            ),
                            const SizedBox(width: 24),
                            const Text(
                              'Ctrl+N',
                              style: TextStyle(
                                color: Color(0xFF8E8E8E),
                                fontSize: 11.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const PopupMenuDivider(height: 8),
                      PopupMenuItem<String>(
                        value: 'hide',
                        height: 30,
                        child: Text(
                          AppStrings.instance.t('Hide drop target'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                    ],
                  );
                  if (!mounted || action == null) return;
                  if (action == 'add') {
                    await _showEnterAddressFlow();
                  } else if (action == 'hide') {
                    setState(() => _isDropTargetVisible = false);
                  }
                },
                child: Tooltip(
                  message:
                      'FluxDM Drop Target\nLeft-click: Grab clipboard • Right-click: Menu • Drag to move',
                  child: Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: const Color(0xFF2A2A2A),
                      border: Border.all(
                        color: const Color(0xFF707070),
                        width: 1,
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x88000000),
                          blurRadius: 10,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF141414),
                          border: Border.all(
                            color: AppColors.accent,
                            width: 1.8,
                          ),
                        ),
                        child: const Icon(
                          Icons.bolt_rounded,
                          color: AppColors.accent,
                          size: 22,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
              ],
            ),
          ),
        ],
      );
          },
        ),
      ),
    );
  }
}
