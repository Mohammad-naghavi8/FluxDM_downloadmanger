import 'dart:async';
import 'dart:io';

import 'package:download_manager/core/theme/app_colors.dart';
import 'package:download_manager/features/downloads/models/download_file_info.dart';
import 'package:download_manager/features/downloads/models/download_schedule_config.dart';
import 'package:download_manager/features/downloads/services/download_path_service.dart';
import 'package:download_manager/features/downloads/services/download_service.dart';
import 'package:download_manager/features/downloads/utils/download_link_helper.dart';
import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';

class AddDownloadResult {
  final String url;
  final DownloadFileInfo? fileInfo;
  final bool startNow;
  final DateTime? scheduledAt;
  final String? username;
  final String? password;
  final String? savePath;
  final String? category;

  const AddDownloadResult({
    required this.url,
    this.fileInfo,
    this.startNow = true,
    this.scheduledAt,
    this.username,
    this.password,
    this.savePath,
    this.category,
  });
}

class AddDownloadDialog extends StatefulWidget {
  final DownloadService downloadService;
  final DownloadPathService downloadPathService;
  final String initialDirectory;
  final String? initialUrl;
  final String? initialUsername;
  final String? initialPassword;
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
    this.initialUsername,
    this.initialPassword,
  });

  @override
  State<AddDownloadDialog> createState() => _AddDownloadDialogState();
}

class _AddDownloadDialogState extends State<AddDownloadDialog> {
  static const List<String> _categories = [
    'Compressed',
    'Documents',
    'Music',
    'Programs',
    'Videos',
    'Images',
    'Others',
  ];

  late final TextEditingController _urlController;
  late final TextEditingController _saveAsController;
  final TextEditingController _descriptionController = TextEditingController();

  late String _selectedCategory;
  late String _categoryFolderPath;
  bool _rememberCategoryPath = true;

  DownloadFileInfo? _fileInfo;
  bool _isLoadingInfo = false;
  String? _infoError;
  int? _serverLatencyMs;
  int _infoRequestId = 0;
  Timer? _debounceTimer;

  DateTime? _scheduledAt;

  @override
  void initState() {
    super.initState();
    final initialUrl = widget.initialUrl?.trim() ?? '';
    _urlController = TextEditingController(text: initialUrl);

    final initialFileName = _guessFileNameFromUrl(initialUrl);
    _selectedCategory = widget.downloadPathService.getCategoryForFile(
      initialFileName,
    );
    _categoryFolderPath =
        '${widget.initialDirectory}${Platform.pathSeparator}$_selectedCategory';
    _saveAsController = TextEditingController(
      text: '$_categoryFolderPath${Platform.pathSeparator}$initialFileName',
    );

    _loadCategoryPath(_selectedCategory, initialFileName);

    if (initialUrl.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _fetchFileInfo(initialUrl);
        }
      });
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _urlController.dispose();
    _saveAsController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  String _guessFileNameFromUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri != null &&
        uri.pathSegments.isNotEmpty &&
        uri.pathSegments.last.isNotEmpty) {
      return Uri.decodeComponent(
        uri.pathSegments.last,
      ).replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
    }
    return 'download_${DateTime.now().millisecondsSinceEpoch}';
  }

  String _currentFileName() {
    final full = _saveAsController.text.trim();
    if (full.isEmpty) {
      return _fileInfo?.fileName ?? _guessFileNameFromUrl(_urlController.text);
    }
    final sep = Platform.pathSeparator;
    final idx = full.lastIndexOf(sep);
    if (idx != -1 && idx < full.length - 1) {
      return full.substring(idx + 1);
    }
    return full;
  }

  Future<void> _loadCategoryPath(String category, String fileName) async {
    try {
      final dirPath = await widget.downloadPathService.getCategoryPath(
        category,
      );
      if (!mounted) return;
      final safeName = fileName.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
      setState(() {
        _categoryFolderPath = dirPath;
        _saveAsController.text = '$dirPath${Platform.pathSeparator}$safeName';
      });
    } catch (_) {}
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
        _serverLatencyMs = null;
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

    if (!DownloadLinkHelper.isSupportedUri(uri)) {
      setState(() {
        _fileInfo = null;
        _isLoadingInfo = false;
        _infoError = null;
        _serverLatencyMs = null;
      });
      return;
    }

    setState(() {
      _isLoadingInfo = true;
      _fileInfo = null;
      _infoError = null;
      _serverLatencyMs = null;
    });

    final stopwatch = Stopwatch()..start();

    try {
      final info = await widget.downloadService.getFileInfo(
        url,
        username: widget.initialUsername,
        password: widget.initialPassword,
      );
      stopwatch.stop();

      if (!mounted || currentRequest != _infoRequestId) {
        return;
      }

      final detectedCategory = widget.downloadPathService.getCategoryForFile(
        info.fileName,
      );

      setState(() {
        _fileInfo = info;
        _isLoadingInfo = false;
        _serverLatencyMs = stopwatch.elapsedMilliseconds;
        _selectedCategory = detectedCategory;
      });

      await _loadCategoryPath(detectedCategory, info.fileName);
    } catch (error) {
      stopwatch.stop();
      if (!mounted || currentRequest != _infoRequestId) {
        return;
      }

      setState(() {
        _fileInfo = null;
        _isLoadingInfo = false;
        _infoError = widget.formatError(error);
      });
    }
  }

  Future<void> _browseSavePath() async {
    final result = await FilePicker.pickDirectory();
    if (result == null || !mounted) return;

    final pickedDir = result.path;
    if (pickedDir.isEmpty) return;

    final fileName = _currentFileName();
    setState(() {
      _categoryFolderPath = pickedDir;
      _saveAsController.text = '$pickedDir${Platform.pathSeparator}$fileName';
    });

    if (_rememberCategoryPath) {
      await widget.downloadPathService.saveCategoryPath(
        _selectedCategory,
        pickedDir,
      );
    }
    widget.onDirectoryChanged(pickedDir);
  }

  Future<void> _pickScheduleTime() async {
    final now = DateTime.now();
    final initial = (_scheduledAt != null && _scheduledAt!.isAfter(now))
        ? _scheduledAt!
        : now.add(const Duration(minutes: 15));

    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null || !mounted) return;

    setState(() {
      _scheduledAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> _finish({required bool startNow}) async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;

    final savePath = _saveAsController.text.trim();
    if (_rememberCategoryPath && _categoryFolderPath.isNotEmpty) {
      await widget.downloadPathService.saveCategoryPath(
        _selectedCategory,
        _categoryFolderPath,
      );
    }
    if (!mounted) return;

    Navigator.pop(
      context,
      AddDownloadResult(
        url: url,
        fileInfo: _fileInfo,
        startNow: startNow && _scheduledAt == null,
        scheduledAt: startNow ? null : _scheduledAt,
        username: widget.initialUsername,
        password: widget.initialPassword,
        savePath: savePath.isNotEmpty ? savePath : null,
        category: _selectedCategory,
      ),
    );
  }

  (IconData, Color) _filePreviewIcon() {
    return switch (_selectedCategory) {
      'Compressed' => (Icons.folder_zip_outlined, const Color(0xFFFFC107)),
      'Videos' => (Icons.movie_outlined, AppColors.video),
      'Music' => (Icons.audio_file_outlined, AppColors.audio),
      'Documents' => (Icons.description_outlined, AppColors.document),
      'Programs' => (Icons.apps_outlined, AppColors.accent),
      'Images' => (Icons.image_outlined, Colors.cyanAccent),
      _ => (Icons.insert_drive_file_outlined, AppColors.accent),
    };
  }

  String _shortCategoryFolderLabel() {
    final path = _categoryFolderPath;
    final parts = path.split(Platform.pathSeparator);
    if (parts.length >= 2) {
      return '${parts[parts.length - 2]}${Platform.pathSeparator}${parts.last}${Platform.pathSeparator}';
    }
    return path;
  }

  @override
  Widget build(BuildContext context) {
    final maxWidth = MediaQuery.sizeOf(context).width - 32;
    final dialogWidth = maxWidth.clamp(380.0, 620.0);
    final urlText = _urlController.text.trim();
    final canSubmit = urlText.isNotEmpty && !_isLoadingInfo;
    final (previewIcon, previewColor) = _filePreviewIcon();

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        width: dialogWidth,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: const Color(0xFF2B332E), width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.78),
              blurRadius: 28,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildTitleBar(),
              const Divider(height: 1, thickness: 1, color: Color(0xFF1F2522)),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildUrlRow(),
                              const SizedBox(height: 9),
                              _buildCategoryRow(),
                              const SizedBox(height: 9),
                              _buildSaveAsRow(),
                              const SizedBox(height: 10),
                              _buildRememberPathBox(),
                              const SizedBox(height: 10),
                              _buildDescriptionRow(),
                              const SizedBox(height: 10),
                              _buildServerRow(),
                            ],
                          ),
                        ),
                        const SizedBox(width: 14),
                        SizedBox(
                          width: 110,
                          child: _buildRightPreviewColumn(
                            previewIcon,
                            previewColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _buildBottomActions(canSubmit),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTitleBar() {
    return Container(
      height: 36,
      color: const Color(0xFF000000),
      padding: const EdgeInsets.only(left: 10, right: 4),
      child: Row(
        children: [
          const Icon(
            Icons.download_for_offline_outlined,
            color: AppColors.accent,
            size: 17,
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Download File Info',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Close',
            onPressed: () => Navigator.pop(context),
            iconSize: 16,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 28, height: 28),
            style: IconButton.styleFrom(
              foregroundColor: const Color(0xFFB5BBB7),
              hoverColor: const Color(0xFF1A201D),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }

  Widget _fieldLabel(String text) {
    return SizedBox(
      width: 82,
      child: Padding(
        padding: const EdgeInsets.only(right: 10),
        child: Text(
          text,
          maxLines: 1,
          softWrap: false,
          textAlign: TextAlign.right,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
        ),
      ),
    );
  }

  Widget _buildUrlRow() {
    return Row(
      children: [
        _fieldLabel('URL'),
        Expanded(
          child: Container(
            height: 28,
            decoration: BoxDecoration(
              color: const Color(0xFF080B09),
              borderRadius: BorderRadius.circular(2),
              border: Border.all(color: const Color(0xFF2B332E)),
            ),
            child: TextField(
              controller: _urlController,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 12,
              ),
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 6,
                ),
                hintText: 'https://... or ftp://...',
                hintStyle: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11.5,
                ),
              ),
              onChanged: (value) {
                setState(() {});
                _scheduleFetch(value);
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryRow() {
    return Row(
      children: [
        _fieldLabel('Category'),
        Expanded(
          child: Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF080B09),
              borderRadius: BorderRadius.circular(2),
              border: Border.all(color: const Color(0xFF2B332E)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _categories.contains(_selectedCategory)
                    ? _selectedCategory
                    : 'Others',
                isExpanded: true,
                dropdownColor: AppColors.surface,
                icon: const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 18,
                  color: AppColors.textSecondary,
                ),
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 12,
                ),
                items: _categories
                    .map(
                      (cat) => DropdownMenuItem<String>(
                        value: cat,
                        child: Text(cat),
                      ),
                    )
                    .toList(),
                onChanged: (next) {
                  if (next == null) return;
                  setState(() => _selectedCategory = next);
                  _loadCategoryPath(next, _currentFileName());
                },
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: 28,
          height: 28,
          child: OutlinedButton(
            onPressed: _browseSavePath,
            style: OutlinedButton.styleFrom(
              backgroundColor: const Color(0xFF171D1A),
              foregroundColor: AppColors.textPrimary,
              side: const BorderSide(color: Color(0xFF2E3732)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(2),
              ),
              padding: EdgeInsets.zero,
            ),
            child: const Icon(Icons.add, size: 15),
          ),
        ),
      ],
    );
  }

  Widget _buildSaveAsRow() {
    return Row(
      children: [
        _fieldLabel('Save As'),
        Expanded(
          child: Container(
            height: 28,
            decoration: BoxDecoration(
              color: const Color(0xFF080B09),
              borderRadius: BorderRadius.circular(2),
              border: Border.all(color: const Color(0xFF2B332E)),
            ),
            child: TextField(
              controller: _saveAsController,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 12,
              ),
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 6,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: 30,
          height: 28,
          child: OutlinedButton(
            onPressed: _browseSavePath,
            style: OutlinedButton.styleFrom(
              backgroundColor: const Color(0xFF171D1A),
              foregroundColor: AppColors.textPrimary,
              side: const BorderSide(color: Color(0xFF2E3732)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(2),
              ),
              padding: EdgeInsets.zero,
            ),
            child: const Text('...', style: TextStyle(fontSize: 12)),
          ),
        ),
      ],
    );
  }

  Widget _buildRememberPathBox() {
    return Padding(
      padding: const EdgeInsets.only(left: 82),
      child: Stack(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 9),
            padding: const EdgeInsets.fromLTRB(10, 14, 10, 8),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFF2A322D), width: 1),
              borderRadius: BorderRadius.circular(2),
            ),
            child: Container(
              height: 26,
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF141916),
                borderRadius: BorderRadius.circular(2),
                border: Border.all(color: const Color(0xFF232925)),
              ),
              child: Tooltip(
                message: _categoryFolderPath,
                child: Text(
                  _shortCategoryFolderLabel(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11.5,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 8,
            top: 0,
            child: Container(
              color: AppColors.surface,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: InkWell(
                onTap: () {
                  setState(() => _rememberCategoryPath = !_rememberCategoryPath);
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: Checkbox(
                        value: _rememberCategoryPath,
                        activeColor: AppColors.accent,
                        checkColor: Colors.black,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                        side: const BorderSide(
                          color: AppColors.textSecondary,
                          width: 1.2,
                        ),
                        onChanged: (v) {
                          setState(() => _rememberCategoryPath = v ?? false);
                        },
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Remember this path for "$_selectedCategory" category',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDescriptionRow() {
    return Row(
      children: [
        _fieldLabel('Description'),
        Expanded(
          child: Container(
            height: 28,
            decoration: BoxDecoration(
              color: const Color(0xFF080B09),
              borderRadius: BorderRadius.circular(2),
              border: Border.all(color: const Color(0xFF2B332E)),
            ),
            child: TextField(
              controller: _descriptionController,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 12,
              ),
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 6,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildServerRow() {
    final uri = Uri.tryParse(_urlController.text.trim());
    final host = (uri != null && uri.host.isNotEmpty) ? uri.host : '—';

    Widget statusWidget;
    if (_isLoadingInfo) {
      statusWidget = const Row(
        children: [
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 1.8,
              color: AppColors.accent,
            ),
          ),
          SizedBox(width: 8),
          Text(
            'Connecting to server...',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 11.5),
          ),
        ],
      );
    } else if (_infoError != null) {
      statusWidget = Row(
        children: [
          Expanded(
            child: Text(
              _infoError!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.redAccent, fontSize: 11.5),
            ),
          ),
          const SizedBox(width: 6),
          InkWell(
            onTap: () => _fetchFileInfo(_urlController.text.trim()),
            child: const Text(
              'Retry',
              style: TextStyle(
                color: AppColors.accent,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      );
    } else if (_fileInfo != null) {
      final info = _fileInfo!;
      final pingText =
          _serverLatencyMs != null ? ' • $_serverLatencyMs ms' : '';
      final isDirect = info.isDirectDownload;
      statusWidget = Row(
        children: [
          Icon(
            isDirect ? Icons.verified_outlined : Icons.warning_amber_rounded,
            size: 14,
            color: isDirect ? AppColors.accent : AppColors.paused,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '$host$pingText • ${info.protocol} • ${isDirect ? 'Direct' : 'HTML page'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isDirect ? AppColors.textSecondary : AppColors.paused,
                fontSize: 11.5,
              ),
            ),
          ),
        ],
      );
    } else {
      statusWidget = Text(
        host,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5),
      );
    }

    return Row(
      children: [
        _fieldLabel('Server'),
        Expanded(child: statusWidget),
      ],
    );
  }

  Widget _buildRightPreviewColumn(IconData icon, Color iconColor) {
    final sizeLabel = _isLoadingInfo
        ? '...'
        : (_fileInfo?.formattedSize ?? 'Unknown');
    final resumeText = _fileInfo == null
        ? ''
        : (_fileInfo!.supportsResume ? 'Resume: Yes' : 'Resume: No');

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 22),
        Icon(icon, size: 50, color: iconColor),
        const SizedBox(height: 14),
        Text(
          sizeLabel,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (resumeText.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            resumeText,
            style: TextStyle(
              color: _fileInfo!.supportsResume
                  ? AppColors.accent
                  : AppColors.paused,
              fontSize: 10.5,
            ),
          ),
        ],
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          height: 28,
          child: OutlinedButton(
            onPressed: _pickScheduleTime,
            style: OutlinedButton.styleFrom(
              backgroundColor: const Color(0xFF171D1A),
              foregroundColor: _scheduledAt != null
                  ? AppColors.accent
                  : AppColors.textSecondary,
              side: BorderSide(
                color: _scheduledAt != null
                    ? AppColors.accent
                    : const Color(0xFF2B332E),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(3),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 6),
              textStyle: const TextStyle(fontSize: 11),
            ),
            child: Text(
              _scheduledAt != null ? 'Scheduled' : 'Schedule',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        if (_scheduledAt != null) ...[
          const SizedBox(height: 4),
          Text(
            DownloadScheduleConfig.formatScheduleDateTime(_scheduledAt),
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.accent, fontSize: 10),
          ),
        ],
      ],
    );
  }

  Widget _buildBottomActions(bool canSubmit) {
    final laterLabel = _scheduledAt != null ? 'Schedule' : 'Download Later';

    return Padding(
      padding: const EdgeInsets.only(left: 82),
      child: Row(
        children: [
          Expanded(
            child: _dialogButton(
              label: laterLabel,
              isPrimary: false,
              onPressed: canSubmit ? () => _finish(startNow: false) : null,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _dialogButton(
              label: 'Start Download',
              isPrimary: true,
              onPressed: canSubmit ? () => _finish(startNow: true) : null,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _dialogButton(
              label: 'Cancel',
              isPrimary: false,
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dialogButton({
    required String label,
    required bool isPrimary,
    required VoidCallback? onPressed,
  }) {
    return SizedBox(
      height: 32,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: const Color(0xFF171D1A),
          foregroundColor: AppColors.textPrimary,
          disabledForegroundColor: AppColors.textSecondary.withValues(
            alpha: 0.45,
          ),
          side: BorderSide(
            color: (isPrimary && onPressed != null)
                ? AppColors.accent
                : const Color(0xFF2E3732),
            width: isPrimary ? 1.2 : 1,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          textStyle: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
          ),
        ),
        child: Text(label, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}
