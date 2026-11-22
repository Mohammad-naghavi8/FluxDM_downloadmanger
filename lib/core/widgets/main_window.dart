import 'dart:async';

import 'package:clipboard_watcher/clipboard_watcher.dart';
import 'package:download_manager/core/widgets/sidebar.dart';
import 'package:download_manager/core/widgets/toolbar.dart';
import 'package:download_manager/features/downloads/controllers/download_manager_controller.dart';
import 'package:download_manager/features/downloads/models/download_progress_state.dart';
import 'package:download_manager/features/downloads/services/browser_bridge_service.dart';
import 'package:download_manager/features/downloads/services/go_engine_process.dart';
import 'package:download_manager/features/downloads/utils/download_link_helper.dart';
import 'package:download_manager/features/downloads/widgets/add_download_dialog.dart';
import 'package:download_manager/features/downloads/widgets/browser_integration_dialog.dart';
import 'package:download_manager/features/downloads/widgets/download_list_view.dart';
import 'package:download_manager/features/downloads/widgets/download_progress_window.dart';
import 'package:download_manager/features/downloads/widgets/enter_address_dialog.dart';
import 'package:download_manager/features/downloads/widgets/scheduler_dialog.dart';
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
  bool _isAddDialogOpen = false;
  bool _isSidebarVisible = true;
  String? _lastClipboardUrl;

  @override
  void initState() {
    super.initState();

    _controller = DownloadManagerController(onMessage: _showSnackBar);
    clipboardWatcher.addListener(this);
    clipboardWatcher.start();
    _controller.initialize();
    _startBrowserBridge();
    unawaited(GoEngineProcess.instance.ensureStarted());
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

  @override
  Future<void> onClipboardChanged() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final rawText = data?.text;

    if (!mounted || rawText == null || rawText.trim().isEmpty) return;

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
        queuedCount: _controller.queuedCount,
        activeCount: _controller.activeDownloadCount,
        onStartQueueNow: _controller.startQueue,
        onPauseAll: _controller.pauseAllDownloads,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Row(
            children: [
              DownloadToolbar(
                isSidebarVisible: _isSidebarVisible,
                onToggleSidebar: () =>
                    setState(() => _isSidebarVisible = !_isSidebarVisible),
                onAdd: _showEnterAddressFlow,
                onStart: _controller.startSelectedDownload,
                onPause: _controller.pauseSelectedDownload,
                onStop: _controller.stopSelectedDownload,
                onRetry: _controller.retrySelectedDownload,
                onDelete: _controller.deleteSelectedDownload,
                onStartQueue: _controller.startQueue,
                onOpenScheduler: _showSchedulerDialog,
                onOpenBrowserBridge: _showBrowserIntegrationDialog,
              ),
              Expanded(
                child: ListenableBuilder(
                  listenable: _controller,
                  builder: (context, _) {
                    return Row(
                      children: [
                        if (_isSidebarVisible)
                          DownloadSidebar(
                            categories: DownloadManagerController.categories,
                            selectedCategory: _controller.selectedCategory,
                            queuedCount: _controller.queuedCount,
                            categoryCount: _controller.categoryCount,
                            onSelectCategory: _controller.selectCategory,
                            onClose: () =>
                                setState(() => _isSidebarVisible = false),
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
                              message: 'Show Categories',
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
                      ],
                    );
                  },
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
        ],
      ),
    );
  }
}
