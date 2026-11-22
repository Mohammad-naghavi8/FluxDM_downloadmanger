import 'package:clipboard_watcher/clipboard_watcher.dart';
import 'package:download_manager/core/widgets/sidebar.dart';
import 'package:download_manager/core/widgets/toolbar.dart';
import 'package:download_manager/features/downloads/controllers/download_manager_controller.dart';
import 'package:download_manager/features/downloads/models/download_progress_state.dart';
import 'package:download_manager/features/downloads/widgets/add_download_dialog.dart';
import 'package:download_manager/features/downloads/widgets/download_list_view.dart';
import 'package:download_manager/features/downloads/widgets/download_progress_window.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

class MainWindow extends StatefulWidget {
  const new({super.key});

  @override
  State<MainWindow> createState() => _MainWindowState();
}

class _MainWindowState extends State<MainWindow> with ClipboardListener {
  late final DownloadManagerController _controller;
  bool _isAddDialogOpen = false;

  @override
  void initState() {
    super.initState();

    _controller = DownloadManagerController(onMessage: _showSnackBar);
    clipboardWatcher.addListener(this);
    clipboardWatcher.start();
    _controller.loadDownloadDirectory();
  }

  @override
  void dispose() {
    clipboardWatcher.removeListener(this);
    clipboardWatcher.stop();
    _controller.dispose();
    super.dispose();
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Future<void> onClipboardChanged() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();

    if (!mounted || text == null || text.isEmpty) return;

    final uri = Uri.tryParse(text);
    if (uri == null ||
        !uri.hasAuthority ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      return;
    }

    if (_isAddDialogOpen) return;

    _isAddDialogOpen = true;
    try {
      await _showAddDownloadDialog(initialUrl: text);
    } finally {
      _isAddDialogOpen = false;
    }
  }

  Future<void> _showAddDownloadDialog({String? initialUrl}) async {
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
        formatError: _controller.formatErrorMessage,
        onDirectoryChanged: _controller.updateDownloadDirectory,
      ),
    );

    if (!mounted || result == null || result.url.isEmpty) return;

    await _controller.addDownload(url: result.url, fileInfo: result.fileInfo);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Row(
            children: [
              DownloadToolbar(
                onAdd: _showAddDownloadDialog,
                onStart: _controller.startSelectedDownload,
                onPause: _controller.pauseSelectedDownload,
                onStop: _controller.stopSelectedDownload,
                onRetry: _controller.retrySelectedDownload,
                onDelete: _controller.deleteSelectedDownload,
              ),
              Expanded(
                child: ListenableBuilder(
                  listenable: _controller,
                  builder: (context, _) {
                    return Row(
                      children: [
                        DownloadSidebar(
                          categories: DownloadManagerController.categories,
                          selectedCategory: _controller.selectedCategory,
                          queuedCount: _controller.queuedCount,
                          onSelectCategory: _controller.selectCategory,
                        ),
                        Expanded(
                          child: DownloadListView(
                            selectedCategory: _controller.selectedCategory,
                            files: _controller.files,
                            selectedFileIndex: _controller.selectedFileIndex,
                            onSelectFile: _controller.selectFile,
                            onOpenProgress:
                                _controller.openExistingProgressWindow,
                            onMoveQueuedFile: _controller.moveQueuedFile,
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

                  final targetFile = _controller.progressWindowFile;

                  return DownloadProgressWindow(
                    state: progressState,
                    onClose: _controller.closeProgressWindow,
                    onPause: () {
                      if (targetFile != null) {
                        _controller.pauseDownloadForFile(targetFile);
                      }
                    },
                    onResume: () {
                      if (targetFile != null) {
                        _controller.resumeDownloadForFile(targetFile);
                      }
                    },
                    onCancel: () {
                      if (targetFile != null) {
                        _controller.stopDownloadForFile(targetFile);
                      }
                    },
                    onRetry: () {
                      if (targetFile != null) {
                        _controller.retryDownloadForFile(targetFile);
                      }
                    },
                    onOpenFolder: progressState.savePath.isNotEmpty
                        ? () => _controller.openFolderForPath(
                            progressState.savePath,
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
