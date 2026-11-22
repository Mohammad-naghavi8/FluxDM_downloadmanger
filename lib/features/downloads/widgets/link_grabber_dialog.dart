import 'package:download_manager/core/localization/app_strings.dart';
import 'package:download_manager/core/theme/app_colors.dart';
import 'package:download_manager/features/downloads/models/download_progress_state.dart';
import 'package:download_manager/features/downloads/services/go_engine_client.dart';
import 'package:download_manager/features/settings/widgets/config_ui_helpers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

class LinkGrabberResult {
  final List<String> urls;
  final String saveDirectory;
  final bool startNow;

  const LinkGrabberResult({
    required this.urls,
    required this.saveDirectory,
    required this.startNow,
  });
}

class LinkGrabberDialog extends StatefulWidget {
  final String initialSaveDirectory;
  final String? initialInput;

  const LinkGrabberDialog({
    super.key,
    required this.initialSaveDirectory,
    this.initialInput,
  });

  @override
  State<LinkGrabberDialog> createState() => _LinkGrabberDialogState();
}

class _LinkGrabberDialogState extends State<LinkGrabberDialog> {
  final TextEditingController _sourceCtrl = TextEditingController();
  final TextEditingController _pkgNameCtrl = TextEditingController();
  final TextEditingController _pkgPassCtrl = TextEditingController();
  late final TextEditingController _saveToCtrl;

  List<GoGrabbedLink> _links = [];
  bool _hideWebPages = true;
  bool _extractWhenDone = false;
  bool _deleteAfterExtract = false;
  bool _isGrabbing = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _saveToCtrl = TextEditingController(text: widget.initialSaveDirectory);
    if (widget.initialInput != null && widget.initialInput!.trim().isNotEmpty) {
      _sourceCtrl.text = widget.initialInput!.trim();
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _grabFromInput(widget.initialInput!),
      );
    }
  }

  @override
  void dispose() {
    _sourceCtrl.dispose();
    _pkgNameCtrl.dispose();
    _pkgPassCtrl.dispose();
    _saveToCtrl.dispose();
    super.dispose();
  }

  Future<void> _pasteAndGrab() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim();
      if (text != null && text.isNotEmpty) {
        _sourceCtrl.text = text.split('\n').first;
        await _grabFromInput(text);
      }
    } catch (_) {}
  }

  Future<void> _grabFromInput(String rawInput) async {
    if (rawInput.trim().isEmpty) return;
    setState(() {
      _isGrabbing = true;
      _errorText = null;
    });
    try {
      final res = await GoEngineClient().grabLinks(
        rawInput,
        probeOnline: true,
        hideWebPages: _hideWebPages,
      );
      if (!mounted) return;
      setState(() {
        _links = res.links;
        _isGrabbing = false;
        if (res.source.isNotEmpty && _sourceCtrl.text.isEmpty) {
          _sourceCtrl.text = res.source;
        }
      });
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _isGrabbing = false;
        _errorText = err.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  List<GoGrabbedLink> get _visibleLinks => _hideWebPages
      ? _links.where((l) => !l.isWebPage).toList(growable: false)
      : _links;

  int get _selectedCount => _visibleLinks.where((l) => l.selected).length;

  void _setAll(bool value) {
    setState(() {
      for (final l in _visibleLinks) {
        l.selected = value;
      }
    });
  }

  void _submit({required bool startNow}) {
    final urls = _visibleLinks
        .where((l) => l.selected)
        .map((l) => l.url)
        .toList();
    if (urls.isEmpty) return;
    Navigator.of(context).pop(
      LinkGrabberResult(
        urls: urls,
        saveDirectory: _saveToCtrl.text.trim(),
        startNow: startNow,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visibleLinks;
    final selectedCount = _selectedCount;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: Container(
        width: 680,
        height: 530,
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
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'Source:',
                          style: TextStyle(color: Colors.white, fontSize: 12),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ConfigUi.textField(
                            controller: _sourceCtrl,
                            hint: 'Page URL or paste links...',
                          ),
                        ),
                        const SizedBox(width: 6),
                        ConfigUi.button(
                          'Grab',
                          width: 64,
                          onPressed: _isGrabbing
                              ? null
                              : () => _grabFromInput(_sourceCtrl.text),
                        ),
                        const SizedBox(width: 6),
                        ConfigUi.button(
                          'Paste',
                          width: 64,
                          onPressed: _isGrabbing ? null : _pasteAndGrab,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF1C1C1C),
                          border: Border.all(color: const Color(0xFF3E3E3E)),
                        ),
                        child: Column(
                          children: [
                            Container(
                              height: 24,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                              ),
                              color: const Color(0xFF141414),
                              child: const Row(
                                children: [
                                  Expanded(
                                    flex: 6,
                                    child: Text(
                                      'Name',
                                      style: TextStyle(
                                        color: Color(0xFFD8D8D8),
                                        fontSize: 11.5,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: Text(
                                      'Size',
                                      textAlign: TextAlign.right,
                                      style: TextStyle(
                                        color: Color(0xFFD8D8D8),
                                        fontSize: 11.5,
                                      ),
                                    ),
                                  ),
                                  SizedBox(width: 12),
                                  Expanded(
                                    flex: 2,
                                    child: Text(
                                      'Status',
                                      style: TextStyle(
                                        color: Color(0xFFD8D8D8),
                                        fontSize: 11.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: _isGrabbing
                                  ? const Center(
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: AppColors.accent,
                                      ),
                                    )
                                  : _errorText != null
                                  ? Center(
                                      child: Text(
                                        _errorText!,
                                        style: const TextStyle(
                                          color: Color(0xFFFF7A7A),
                                          fontSize: 12,
                                        ),
                                      ),
                                    )
                                  : visible.isEmpty
                                  ? const Center(
                                      child: Text(
                                        "Paste links here (Ctrl+V), or send a page's links from the browser.",
                                        style: TextStyle(
                                          color: Color(0xFFA8A8A8),
                                          fontSize: 12,
                                        ),
                                      ),
                                    )
                                  : ListView.separated(
                                      itemCount: visible.length,
                                      separatorBuilder: (_, _) => const Divider(
                                        height: 1,
                                        color: Color(0xFF2B2B2B),
                                      ),
                                      itemBuilder: (_, idx) {
                                        final item = visible[idx];
                                        return InkWell(
                                          onTap: () => setState(
                                            () =>
                                                item.selected = !item.selected,
                                          ),
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
                                                    activeColor:
                                                        AppColors.accent,
                                                    checkColor: Colors.black,
                                                    onChanged: (v) => setState(
                                                      () => item.selected =
                                                          v ?? false,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  flex: 6,
                                                  child: Text(
                                                    item.name,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                ),
                                                Expanded(
                                                  flex: 2,
                                                  child: Text(
                                                    item.sizeBytes > 0
                                                        ? DownloadProgressState
                                                              .formatBytes(
                                                                item.sizeBytes,
                                                              )
                                                        : '—',
                                                    textAlign: TextAlign.right,
                                                    style: const TextStyle(
                                                      color: Color(0xFFA8A8A8),
                                                      fontSize: 11.5,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 12),
                                                Expanded(
                                                  flex: 2,
                                                  child: Text(
                                                    item.status,
                                                    style: TextStyle(
                                                      color:
                                                          item.status ==
                                                              'Online'
                                                          ? AppColors.accent
                                                          : const Color(
                                                              0xFFB0B0B0,
                                                            ),
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
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        SizedBox(
                          width: 130,
                          child: ConfigUi.checkRow(
                            value: _hideWebPages,
                            label: 'Hide web pages',
                            onChanged: (v) => setState(() => _hideWebPages = v),
                          ),
                        ),
                        Text(
                          '$selectedCount of ${visible.length} selected',
                          style: const TextStyle(
                            color: Color(0xFFD0D0D0),
                            fontSize: 12,
                          ),
                        ),
                        const Spacer(),
                        ConfigUi.button(
                          'Check all',
                          width: 84,
                          onPressed: visible.isNotEmpty
                              ? () => _setAll(true)
                              : null,
                        ),
                        const SizedBox(width: 6),
                        ConfigUi.button(
                          'Uncheck all',
                          width: 90,
                          onPressed: visible.isNotEmpty
                              ? () => _setAll(false)
                              : null,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ConfigUi.groupBox(
                      title: 'Package',
                      child: Column(
                        children: [
                          Row(
                            children: [
                              const SizedBox(
                                width: 56,
                                child: Text(
                                  'Name:',
                                  style: TextStyle(
                                    color: Color(0xFFB8B8B8),
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: ConfigUi.textField(
                                  controller: _pkgNameCtrl,
                                ),
                              ),
                              const SizedBox(width: 12),
                              const SizedBox(
                                width: 64,
                                child: Text(
                                  'Password:',
                                  style: TextStyle(
                                    color: Color(0xFFB8B8B8),
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: ConfigUi.textField(
                                  controller: _pkgPassCtrl,
                                  obscure: true,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const SizedBox(
                                width: 56,
                                child: Text(
                                  'Save to:',
                                  style: TextStyle(
                                    color: Color(0xFFB8B8B8),
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: ConfigUi.textField(
                                  controller: _saveToCtrl,
                                ),
                              ),
                              const SizedBox(width: 6),
                              ConfigUi.button(
                                'Browse',
                                width: 76,
                                onPressed: () async {
                                  final picked =
                                      await FilePicker.pickDirectory();
                                  if (picked != null &&
                                      picked.path.isNotEmpty &&
                                      mounted) {
                                    setState(
                                      () => _saveToCtrl.text = picked.path,
                                    );
                                  }
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Expanded(
                                child: ConfigUi.checkRow(
                                  value: _extractWhenDone,
                                  label: 'Extract when done',
                                  onChanged: (v) =>
                                      setState(() => _extractWhenDone = v),
                                ),
                              ),
                              Expanded(
                                child: ConfigUi.checkRow(
                                  value: _deleteAfterExtract,
                                  label: 'Delete archives after extracting',
                                  enabled: _extractWhenDone,
                                  onChanged: (v) =>
                                      setState(() => _deleteAfterExtract = v),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        ConfigUi.button(
                          'Add to queue',
                          width: 102,
                          onPressed: selectedCount > 0
                              ? () => _submit(startNow: false)
                              : null,
                        ),
                        const SizedBox(width: 6),
                        ConfigUi.button(
                          'Start',
                          primary: true,
                          width: 82,
                          onPressed: selectedCount > 0
                              ? () => _submit(startNow: true)
                              : null,
                        ),
                        const SizedBox(width: 6),
                        ConfigUi.button(
                          'Cancel',
                          width: 82,
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
          const Icon(Icons.link_rounded, size: 15, color: AppColors.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              AppStrings.instance.t('Link grabber'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          InkWell(
            onTap: () => Navigator.of(context).pop(),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.close, size: 15, color: Color(0xFFCCCCCC)),
            ),
          ),
        ],
      ),
    );
  }
}
