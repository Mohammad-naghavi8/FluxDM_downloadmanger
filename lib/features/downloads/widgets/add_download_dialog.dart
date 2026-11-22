import 'dart:async';

import 'package:download_manager/core/theme/app_colors.dart';
import 'package:download_manager/features/downloads/models/download_file_info.dart';
import 'package:download_manager/features/downloads/services/download_path_service.dart';
import 'package:download_manager/features/downloads/services/download_service.dart';
import 'package:material_ui/material_ui.dart';

class AddDownloadResult {
  final String url;
  final DownloadFileInfo? fileInfo;

  const AddDownloadResult({required this.url, this.fileInfo});
}

class AddDownloadDialog extends StatefulWidget {
  final DownloadService downloadService;
  final DownloadPathService downloadPathService;
  final String initialDirectory;
  final String? initialUrl;
  final String Function(Object error) formatError;
  final ValueChanged<String> onDirectoryChanged;

  const AddDownloadDialog({
    super.key,
    required this.downloadService,
    required this.downloadPathService,
    required this.initialDirectory,
    required this.formatError,
    required this.onDirectoryChanged,
    this.initialUrl,
  });

  @override
  State<AddDownloadDialog> createState() => _AddDownloadDialogState();
}

class _AddDownloadDialogState extends State<AddDownloadDialog> {
  late String _enteredUrl;
  late String _dialogPath;
  DownloadFileInfo? _fileInfo;
  bool _isLoadingInfo = false;
  String? _infoError;
  int _infoRequestId = 0;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _enteredUrl = widget.initialUrl?.trim() ?? '';
    _dialogPath = widget.initialDirectory;

    if (_enteredUrl.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _fetchFileInfo(_enteredUrl);
        }
      });
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _scheduleFetch(String url) {
    _debounceTimer?.cancel();
    final trimmed = url.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _infoRequestId++;
        _fileInfo = null;
        _isLoadingInfo = false;
        _infoError = null;
      });
      return;
    }

    _debounceTimer = Timer(const Duration(milliseconds: 280), () {
      if (mounted) {
        _fetchFileInfo(trimmed);
      }
    });
  }

  Future<void> _fetchFileInfo(String url) async {
    final currentRequest = ++_infoRequestId;
    final uri = Uri.tryParse(url);

    if (uri == null ||
        !uri.hasAuthority ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      setState(() {
        _fileInfo = null;
        _isLoadingInfo = false;
        _infoError = null;
      });
      return;
    }

    setState(() {
      _isLoadingInfo = true;
      _fileInfo = null;
      _infoError = null;
    });

    try {
      final info = await widget.downloadService.getFileInfo(url);

      if (!mounted || currentRequest != _infoRequestId) {
        return;
      }

      setState(() {
        _fileInfo = info;
        _isLoadingInfo = false;
      });
    } catch (error) {
      if (!mounted || currentRequest != _infoRequestId) {
        return;
      }

      setState(() {
        _fileInfo = null;
        _isLoadingInfo = false;
        _infoError =
            'Could not retrieve file information (${widget.formatError(error)})';
      });
    }
  }

  Future<void> _browseDirectory() async {
    final changed = await widget.downloadPathService.chooseDirectory();
    if (!changed || !mounted) return;

    final newPath = await widget.downloadPathService.getSavedPath();
    if (!mounted) return;

    setState(() {
      _dialogPath = newPath;
    });
    widget.onDirectoryChanged(newPath);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: const Text('Add New Download', style: TextStyle(fontSize: 16)),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                autofocus: true,
                initialValue: widget.initialUrl ?? '',
                onChanged: (value) {
                  _enteredUrl = value.trim();
                  _scheduleFetch(_enteredUrl);
                },
                decoration: const InputDecoration(
                  hintText: 'https://example.com/file.zip',
                  labelText: 'Download URL',
                  prefixIcon: Icon(Icons.link),
                ),
              ),
              const SizedBox(height: 18),
              if (_isLoadingInfo)
                const Row(
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 10),
                    Text('Getting file information...'),
                  ],
                ),
              if (_fileInfo != null) ...[
                const Text(
                  'File Information',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                _detailRow('File name', _fileInfo!.fileName),
                _detailRow('File type', _fileInfo!.fileType),
                _detailRow('File size', _fileInfo!.formattedSize),
                _detailRow(
                  'Resume',
                  _fileInfo!.supportsResume ? 'Supported' : 'Not supported',
                ),
              ],
              if (_infoError != null) ...[
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        _infoError!,
                        style: const TextStyle(
                          color: Colors.redAccent,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _enteredUrl.isEmpty
                          ? null
                          : () => _fetchFileInfo(_enteredUrl),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 20),
              const Text(
                'Save location',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(_dialogPath, style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _browseDirectory,
                icon: const Icon(Icons.folder_open),
                label: const Text('Browse'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _enteredUrl.isEmpty || _isLoadingInfo
              ? null
              : () {
                  Navigator.pop(
                    context,
                    AddDownloadResult(url: _enteredUrl, fileInfo: _fileInfo),
                  );
                },
          child: const Text('Start Download'),
        ),
      ],
    );
  }

  Widget _detailRow(String title, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(title, style: const TextStyle(color: Colors.grey)),
          ),
          Expanded(child: Text(value, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }
}
