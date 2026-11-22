import 'package:download_manager/core/localization/app_strings.dart';
import 'package:download_manager/core/theme/app_colors.dart';
import 'package:download_manager/features/downloads/models/download_progress_state.dart';
import 'package:download_manager/features/downloads/services/go_engine_client.dart';
import 'package:download_manager/features/settings/widgets/config_ui_helpers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';

class VideoDownloadResult {
  final String url;
  final String fileName;
  final String saveDirectory;
  final bool startNow;

  const VideoDownloadResult({
    required this.url,
    required this.fileName,
    required this.saveDirectory,
    required this.startNow,
  });
}

class VideoDownloadDialog extends StatefulWidget {
  final String initialSaveDirectory;

  const VideoDownloadDialog({super.key, required this.initialSaveDirectory});

  @override
  State<VideoDownloadDialog> createState() => _VideoDownloadDialogState();
}

class _VideoDownloadDialogState extends State<VideoDownloadDialog> {
  final TextEditingController _pageCtrl = TextEditingController();
  late final TextEditingController _saveToCtrl;
  final TextEditingController _fileNameCtrl = TextEditingController();

  List<GoVideoStream> _streams = [];
  int? _selectedIdx;
  List<String> _subtitles = const ['None'];
  String _selectedSubtitle = 'None';
  bool _embedSubtitles = false;
  bool _isLookingUp = false;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    _saveToCtrl = TextEditingController(text: widget.initialSaveDirectory);
    _pageCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    _saveToCtrl.dispose();
    _fileNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _lookupVideo() async {
    final url = _pageCtrl.text.trim();
    if (url.isEmpty) return;

    setState(() {
      _isLookingUp = true;
      _statusMessage = null;
      _streams = [];
      _selectedIdx = null;
    });

    try {
      final res = await GoEngineClient().grabVideo(url);
      if (!mounted) return;
      setState(() {
        _streams = res.streams;
        _subtitles = res.subtitles;
        _selectedSubtitle = res.subtitles.first;
        _isLookingUp = false;
        if (_streams.isNotEmpty) {
          _selectedIdx = 0;
          final ext = _streams.first.format.toLowerCase();
          _fileNameCtrl.text =
              '${res.pageTitle.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')}.${ext.isNotEmpty ? ext : 'mp4'}';
        } else {
          _statusMessage =
              'No direct video streams found on this page. Install yt-dlp on PATH for YouTube/streaming sites.';
        }
      });
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _isLookingUp = false;
        _statusMessage = err.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  void _submit({required bool startNow}) {
    if (_selectedIdx == null || _selectedIdx! >= _streams.length) return;
    final stream = _streams[_selectedIdx!];
    Navigator.of(context).pop(
      VideoDownloadResult(
        url: stream.url,
        fileName: _fileNameCtrl.text.trim().isNotEmpty
            ? _fileNameCtrl.text.trim()
            : '${stream.title}.mp4',
        saveDirectory: _saveToCtrl.text.trim(),
        startNow: startNow,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasUrl = _pageCtrl.text.trim().isNotEmpty;
    final canDownload = _selectedIdx != null && _streams.isNotEmpty;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: Container(
        width: 550,
        height: 440,
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
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Page address',
                      style: TextStyle(color: Color(0xFFE0E0E0), fontSize: 12),
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Expanded(
                          child: ConfigUi.textField(
                            controller: _pageCtrl,
                            hint: 'https://...',
                          ),
                        ),
                        const SizedBox(width: 8),
                        ConfigUi.button(
                          _isLookingUp ? '...' : 'Look up',
                          width: 86,
                          onPressed: (hasUrl && !_isLookingUp)
                              ? _lookupVideo
                              : null,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF1C1C1C),
                          border: Border.all(color: const Color(0xFF3E3E3E)),
                        ),
                        child: _isLookingUp
                            ? const Center(
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.accent,
                                ),
                              )
                            : _streams.isEmpty
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Text(
                                    _statusMessage ??
                                        'Enter a page URL and click Look up (powered by Go engine).',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Color(0xFFA0A0A0),
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              )
                            : ListView.separated(
                                itemCount: _streams.length,
                                separatorBuilder: (_, _) => const Divider(
                                  height: 1,
                                  color: Color(0xFF2B2B2B),
                                ),
                                itemBuilder: (_, idx) {
                                  final s = _streams[idx];
                                  final sel = _selectedIdx == idx;
                                  return InkWell(
                                    onTap: () =>
                                        setState(() => _selectedIdx = idx),
                                    child: Container(
                                      color: sel
                                          ? const Color(0xFF234034)
                                          : Colors.transparent,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 7,
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(
                                            Icons.movie_outlined,
                                            size: 16,
                                            color: AppColors.accent,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              '${s.quality}  •  ${s.format}  •  ${s.title}',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                          if (s.sizeBytes > 0)
                                            Text(
                                              DownloadProgressState.formatBytes(
                                                s.sizeBytes,
                                              ),
                                              style: const TextStyle(
                                                color: Color(0xFFA8A8A8),
                                                fontSize: 11.5,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const SizedBox(
                          width: 66,
                          child: Text(
                            'Save to',
                            style: TextStyle(
                              color: Color(0xFFE0E0E0),
                              fontSize: 12,
                            ),
                          ),
                        ),
                        Expanded(
                          child: ConfigUi.textField(controller: _saveToCtrl),
                        ),
                        const SizedBox(width: 6),
                        ConfigUi.button(
                          '...',
                          width: 28,
                          onPressed: () async {
                            final picked = await FilePicker.pickDirectory();
                            if (picked != null &&
                                picked.path.isNotEmpty &&
                                mounted) {
                              setState(() => _saveToCtrl.text = picked.path);
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const SizedBox(
                          width: 66,
                          child: Text(
                            'File name',
                            style: TextStyle(
                              color: Color(0xFFE0E0E0),
                              fontSize: 12,
                            ),
                          ),
                        ),
                        Expanded(
                          child: ConfigUi.textField(controller: _fileNameCtrl),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const SizedBox(
                          width: 66,
                          child: Text(
                            'Subtitles',
                            style: TextStyle(
                              color: Color(0xFFA0A0A0),
                              fontSize: 12,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 175,
                          child: ConfigUi.dropdown(
                            value: _selectedSubtitle,
                            items: _subtitles,
                            enabled: _subtitles.length > 1,
                            onChanged: (v) =>
                                setState(() => _selectedSubtitle = v),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ConfigUi.checkRow(
                            value: _embedSubtitles,
                            label: 'Put them into the video',
                            enabled: _subtitles.length > 1,
                            onChanged: (v) =>
                                setState(() => _embedSubtitles = v),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        ConfigUi.button(
                          'Helpers...',
                          width: 90,
                          onPressed: () {
                            showDialog<void>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('FluxDM Video Helpers'),
                                content: const Text(
                                  'FluxDM Go engine automatically inspects direct HTML5 video streams and uses yt-dlp if available on your Windows PATH.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.of(ctx).pop(),
                                    child: const Text('OK'),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                        const Spacer(),
                        ConfigUi.button(
                          'Download Now',
                          primary: true,
                          width: 108,
                          onPressed: canDownload
                              ? () => _submit(startNow: true)
                              : null,
                        ),
                        const SizedBox(width: 6),
                        ConfigUi.button(
                          'Later',
                          width: 82,
                          onPressed: canDownload
                              ? () => _submit(startNow: false)
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
          const Icon(
            Icons.video_collection_outlined,
            size: 15,
            color: AppColors.accent,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              AppStrings.instance.t('Download video from a page'),
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
