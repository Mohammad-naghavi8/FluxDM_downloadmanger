import 'package:download_manager/core/localization/app_strings.dart';
import 'package:download_manager/core/theme/app_colors.dart';
import 'package:download_manager/features/downloads/models/download_progress_state.dart';
import 'package:download_manager/features/torrents/models/torrent_models.dart';
import 'package:download_manager/features/torrents/services/torrent_parser.dart';
import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';

class AddTorrentResult {
  final TorrentMetadata metadata;
  final String saveDirectory;
  final bool downloadInOrder;
  final bool startNow;

  const AddTorrentResult({
    required this.metadata,
    required this.saveDirectory,
    required this.downloadInOrder,
    required this.startNow,
  });
}

class AddTorrentDialog extends StatefulWidget {
  final String initialSaveDirectory;
  final String? initialSource;
  final bool autoLookup;

  const AddTorrentDialog({
    super.key,
    required this.initialSaveDirectory,
    this.initialSource,
    this.autoLookup = false,
  });

  @override
  State<AddTorrentDialog> createState() => _AddTorrentDialogState();
}

class _AddTorrentDialogState extends State<AddTorrentDialog> {
  late final TextEditingController _sourceController;
  late final TextEditingController _saveToController;

  TorrentMetadata? _metadata;
  bool _isLookingUp = false;
  bool _downloadInOrder = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _sourceController = TextEditingController(text: widget.initialSource ?? '');
    _saveToController = TextEditingController(
      text: widget.initialSaveDirectory,
    );
    _sourceController.addListener(() {
      if (mounted) setState(() {});
    });

    if (widget.autoLookup && _sourceController.text.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _lookupSource());
    }
  }

  @override
  void dispose() {
    _sourceController.dispose();
    _saveToController.dispose();
    super.dispose();
  }

  Future<void> _pickTorrentFile() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['torrent'],
    );
    if (!mounted || picked.isEmpty) return;

    final path = picked.single.path;
    if (path != null && path.isNotEmpty) {
      _sourceController.text = path;
      await _lookupSource();
    }
  }

  Future<void> _pickSaveDirectory() async {
    final result = await FilePicker.pickDirectory();
    if (!mounted || result == null) return;
    if (result.path.isNotEmpty) {
      setState(() => _saveToController.text = result.path);
    }
  }

  Future<void> _lookupSource() async {
    final raw = _sourceController.text.trim();
    if (raw.isEmpty) return;

    setState(() {
      _isLookingUp = true;
      _errorText = null;
    });

    try {
      final meta = await TorrentParser.parse(raw);
      if (!mounted) return;
      setState(() {
        _metadata = meta;
        _isLookingUp = false;
      });
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _metadata = null;
        _isLookingUp = false;
        _errorText = err is FormatException ? err.message : err.toString();
      });
    }
  }

  void _selectAll(bool selected) {
    final meta = _metadata;
    if (meta == null) return;
    setState(() {
      for (final f in meta.files) {
        f.selected = selected;
      }
    });
  }

  bool get _canSubmit {
    final meta = _metadata;
    if (meta == null || meta.files.isEmpty) return false;
    return meta.files.any((f) => f.selected);
  }

  void _submit({required bool startNow}) {
    final meta = _metadata;
    if (meta == null) return;
    Navigator.of(context).pop(
      AddTorrentResult(
        metadata: meta,
        saveDirectory: _saveToController.text.trim().isNotEmpty
            ? _saveToController.text.trim()
            : widget.initialSaveDirectory,
        downloadInOrder: _downloadInOrder,
        startNow: startNow,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasSource = _sourceController.text.trim().isNotEmpty;
    final hasFiles = _metadata != null && _metadata!.files.isNotEmpty;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: Container(
        width: 610,
        height: 455,
        decoration: BoxDecoration(
          color: const Color(0xFF232323),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: const Color(0xFF3A3A3A)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x99000000),
              blurRadius: 24,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          children: [
            _buildTitleBar(),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildTorrentInputRow(hasSource),
                    const SizedBox(height: 12),
                    Expanded(child: _buildFilesTable(hasFiles)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _actionBtn(
                          'Select all',
                          onPressed: hasFiles ? () => _selectAll(true) : null,
                        ),
                        const SizedBox(width: 6),
                        _actionBtn(
                          'Select none',
                          onPressed: hasFiles ? () => _selectAll(false) : null,
                        ),
                        const Spacer(),
                        if (_metadata != null && _metadata!.selectedBytes > 0)
                          Text(
                            'Selected: ${DownloadProgressState.formatBytes(_metadata!.selectedBytes)}',
                            style: const TextStyle(
                              color: Color(0xFFA0A0A0),
                              fontSize: 11.5,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildSaveToRow(),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: Checkbox(
                            value: _downloadInOrder,
                            activeColor: AppColors.accent,
                            checkColor: Colors.black,
                            side: const BorderSide(color: Color(0xFF666666)),
                            onChanged: (v) =>
                                setState(() => _downloadInOrder = v ?? false),
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () => setState(
                            () => _downloadInOrder = !_downloadInOrder,
                          ),
                          child: const Text(
                            'Download in order',
                            style: TextStyle(
                              color: Color(0xFFD0D0D0),
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const Spacer(),
                        _actionBtn(
                          'Download Now',
                          primary: true,
                          width: 108,
                          onPressed: _canSubmit
                              ? () => _submit(startNow: true)
                              : null,
                        ),
                        const SizedBox(width: 6),
                        _actionBtn(
                          'Later',
                          width: 90,
                          onPressed: _canSubmit
                              ? () => _submit(startNow: false)
                              : null,
                        ),
                        const SizedBox(width: 6),
                        _actionBtn(
                          'Cancel',
                          width: 90,
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTitleBar() {
    return Container(
      height: 30,
      padding: const EdgeInsets.only(left: 10, right: 6),
      decoration: const BoxDecoration(
        color: Color(0xFF141414),
        border: Border(bottom: BorderSide(color: Color(0xFF333333))),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.hub_outlined,
            size: 15,
            color: AppColors.accent,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              AppStrings.instance.t('Add torrent'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          InkWell(
            onTap: () => Navigator.of(context).pop(),
            borderRadius: BorderRadius.circular(3),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.close, size: 15, color: Color(0xFFCCCCCC)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTorrentInputRow(bool hasSource) {
    return Row(
      children: [
        const SizedBox(
          width: 58,
          child: Text(
            'Torrent',
            style: TextStyle(color: Color(0xFFE0E0E0), fontSize: 12),
          ),
        ),
        Expanded(
          child: _desktopTextField(
            controller: _sourceController,
            hint: 'magnet:?xt=urn:btih:... or path to .torrent file',
            onSubmitted: (_) => _lookupSource(),
          ),
        ),
        const SizedBox(width: 6),
        _actionBtn('...', width: 28, onPressed: _pickTorrentFile),
        const SizedBox(width: 6),
        _actionBtn(
          _isLookingUp ? '...' : 'Look up',
          width: 78,
          onPressed: (hasSource && !_isLookingUp) ? _lookupSource : null,
        ),
      ],
    );
  }

  Widget _buildFilesTable(bool hasFiles) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        border: Border.all(color: const Color(0xFF3A3A3A)),
      ),
      child: Column(
        children: [
          Container(
            height: 24,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: const BoxDecoration(
              color: Color(0xFF171717),
              border: Border(bottom: BorderSide(color: Color(0xFF343434))),
            ),
            child: const Row(
              children: [
                Expanded(
                  child: Text(
                    'Name',
                    style: TextStyle(
                      color: Color(0xFFD8D8D8),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                SizedBox(
                  width: 90,
                  child: Text(
                    'Size',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: Color(0xFFD8D8D8),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLookingUp
                ? const Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.accent,
                      ),
                    ),
                  )
                : _errorText != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        _errorText!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFFFF7A7A),
                          fontSize: 12,
                        ),
                      ),
                    ),
                  )
                : !hasFiles
                ? const Center(
                    child: Text(
                      'Paste a magnet link or choose a .torrent file, then Look up.',
                      style: TextStyle(
                        color: Color(0xFFAEAEAE),
                        fontSize: 12,
                      ),
                    ),
                  )
                : ListView.separated(
                    itemCount: _metadata!.files.length,
                    separatorBuilder: (_, _) =>
                        const Divider(height: 1, color: Color(0xFF2B2B2B)),
                    itemBuilder: (context, index) {
                      final item = _metadata!.files[index];
                      return InkWell(
                        onTap: () =>
                            setState(() => item.selected = !item.selected),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 5,
                          ),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 18,
                                height: 18,
                                child: Checkbox(
                                  value: item.selected,
                                  activeColor: AppColors.accent,
                                  checkColor: Colors.black,
                                  side: const BorderSide(
                                    color: Color(0xFF666666),
                                  ),
                                  onChanged: (v) => setState(
                                    () => item.selected = v ?? false,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  item.relativePath,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xFFE6E6E6),
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 90,
                                child: Text(
                                  item.sizeBytes > 0
                                      ? DownloadProgressState.formatBytes(
                                          item.sizeBytes,
                                        )
                                      : 'Unknown',
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(
                                    color: Color(0xFFA8A8A8),
                                    fontSize: 11.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSaveToRow() {
    return Row(
      children: [
        const SizedBox(
          width: 58,
          child: Text(
            'Save to',
            style: TextStyle(color: Color(0xFFE0E0E0), fontSize: 12),
          ),
        ),
        Expanded(child: _desktopTextField(controller: _saveToController)),
        const SizedBox(width: 6),
        _actionBtn('...', width: 28, onPressed: _pickSaveDirectory),
      ],
    );
  }

  Widget _desktopTextField({
    required TextEditingController controller,
    String? hint,
    ValueChanged<String>? onSubmitted,
  }) {
    return SizedBox(
      height: 27,
      child: TextField(
        controller: controller,
        onSubmitted: onSubmitted,
        style: const TextStyle(color: Colors.white, fontSize: 12),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Color(0xFF707070), fontSize: 11.5),
          filled: true,
          fillColor: const Color(0xFF1A1A1A),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 6,
          ),
          enabledBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(2)),
            borderSide: BorderSide(color: Color(0xFF444444)),
          ),
          focusedBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(2)),
            borderSide: BorderSide(color: AppColors.accent, width: 1.2),
          ),
        ),
      ),
    );
  }

  Widget _actionBtn(
    String label, {
    VoidCallback? onPressed,
    bool primary = false,
    double? width,
  }) {
    final enabled = onPressed != null;
    return SizedBox(
      width: width,
      height: 26,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          backgroundColor: enabled
              ? (primary ? const Color(0xFF243B31) : const Color(0xFF303030))
              : const Color(0xFF262626),
          foregroundColor: enabled ? Colors.white : const Color(0xFF707070),
          side: BorderSide(
            color: enabled
                ? (primary ? AppColors.accent : const Color(0xFF4E4E4E))
                : const Color(0xFF3A3A3A),
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
          textStyle: const TextStyle(fontSize: 12),
        ),
        child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}
