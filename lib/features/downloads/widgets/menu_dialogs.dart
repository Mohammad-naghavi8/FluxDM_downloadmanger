import 'package:download_manager/core/localization/app_strings.dart';
import 'package:download_manager/core/theme/app_colors.dart';
import 'package:download_manager/features/settings/widgets/config_ui_helpers.dart';
import 'package:material_ui/material_ui.dart';

class FindFileQuery {
  final String query;
  final bool inFileName;
  final bool inDescription;
  final bool inUrl;
  final bool matchCase;
  final bool matchWholeString;

  const FindFileQuery({
    required this.query,
    this.inFileName = true,
    this.inDescription = false,
    this.inUrl = false,
    this.matchCase = false,
    this.matchWholeString = false,
  });
}

class FindFileDialog extends StatefulWidget {
  final FindFileQuery? initialQuery;

  const FindFileDialog({super.key, this.initialQuery});

  @override
  State<FindFileDialog> createState() => _FindFileDialogState();
}

class _FindFileDialogState extends State<FindFileDialog> {
  late final TextEditingController _ctrl;
  late bool _inFileName;
  late bool _inDescription;
  late bool _inUrl;
  late bool _matchCase;
  late bool _matchWhole;

  @override
  void initState() {
    super.initState();
    final q = widget.initialQuery;
    _ctrl = TextEditingController(text: q?.query ?? '');
    _inFileName = q?.inFileName ?? true;
    _inDescription = q?.inDescription ?? false;
    _inUrl = q?.inUrl ?? false;
    _matchCase = q?.matchCase ?? false;
    _matchWhole = q?.matchWholeString ?? false;
    _ctrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    Navigator.of(context).pop(
      FindFileQuery(
        query: text,
        inFileName: _inFileName,
        inDescription: _inDescription,
        inUrl: _inUrl,
        matchCase: _matchCase,
        matchWholeString: _matchWhole,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canFind = _ctrl.text.trim().isNotEmpty;
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 390,
        decoration: BoxDecoration(
          color: const Color(0xFF232323),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: const Color(0xFF3A3A3A)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _titleBar(context, Icons.search_rounded, 'Find file'),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    AppStrings.instance.t('Find:'),
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                  const SizedBox(height: 6),
                  ConfigUi.textField(controller: _ctrl),
                  const SizedBox(height: 8),
                  ConfigUi.checkRow(
                    value: _inFileName,
                    label: 'File name or part of the name',
                    onChanged: (v) => setState(() => _inFileName = v),
                  ),
                  ConfigUi.checkRow(
                    value: _inDescription,
                    label: 'Description or part of the description',
                    onChanged: (v) => setState(() => _inDescription = v),
                  ),
                  ConfigUi.checkRow(
                    value: _inUrl,
                    label: 'Site name/Download link/Parent web page/Referer',
                    onChanged: (v) => setState(() => _inUrl = v),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Divider(height: 1, color: Color(0xFF3E3E3E)),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: Column(
                      children: [
                        ConfigUi.checkRow(
                          value: _matchCase,
                          label: 'Match case',
                          onChanged: (v) => setState(() => _matchCase = v),
                        ),
                        ConfigUi.checkRow(
                          value: _matchWhole,
                          label: 'Match whole string only',
                          onChanged: (v) => setState(() => _matchWhole = v),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ConfigUi.button(
                        'Find',
                        primary: true,
                        width: 86,
                        onPressed: canFind ? _submit : null,
                      ),
                      const SizedBox(width: 14),
                      ConfigUi.button(
                        'Cancel',
                        width: 86,
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SpeedLimiterSettingsResult {
  final int maxPerFileKBps;
  final bool alwaysOnStartup;
  final bool limitAllEnabled;
  final int limitAllKBps;
  final bool onlyWhileUsingComputer;

  const SpeedLimiterSettingsResult({
    required this.maxPerFileKBps,
    required this.alwaysOnStartup,
    required this.limitAllEnabled,
    required this.limitAllKBps,
    required this.onlyWhileUsingComputer,
  });
}

class SpeedLimiterSettingsDialog extends StatefulWidget {
  final int initialKBps;
  final bool initialAlwaysOnStartup;

  const SpeedLimiterSettingsDialog({
    super.key,
    required this.initialKBps,
    this.initialAlwaysOnStartup = false,
  });

  @override
  State<SpeedLimiterSettingsDialog> createState() =>
      _SpeedLimiterSettingsDialogState();
}

class _SpeedLimiterSettingsDialogState
    extends State<SpeedLimiterSettingsDialog> {
  late final TextEditingController _perFileCtrl;
  final TextEditingController _allFilesCtrl = TextEditingController(
    text: '500',
  );
  late bool _alwaysOnStartup;
  bool _limitAll = false;
  bool _onlyWhileUsing = false;

  @override
  void initState() {
    super.initState();
    _perFileCtrl = TextEditingController(text: '${widget.initialKBps}');
    _alwaysOnStartup = widget.initialAlwaysOnStartup;
  }

  @override
  void dispose() {
    _perFileCtrl.dispose();
    _allFilesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 470,
        decoration: BoxDecoration(
          color: const Color(0xFF232323),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: const Color(0xFF3A3A3A)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _titleBar(context, Icons.speed_rounded, 'Speed Limiter settings'),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        'Maximum download speed for one file',
                        style: TextStyle(color: Colors.white, fontSize: 12),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 68,
                        child: ConfigUi.textField(controller: _perFileCtrl),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'KBytes/sec',
                        style: TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Note: Internet servers may break connection when the speed is too limited! Thus it\'s not recommended to use Speed Limiter to download from servers that do not support "resume" feature.',
                    style: TextStyle(color: Color(0xFFD0D0D0), fontSize: 11.5),
                  ),
                  const SizedBox(height: 10),
                  ConfigUi.checkRow(
                    value: _alwaysOnStartup,
                    label: 'Always turn on Speed Limiter on FluxDM startup',
                    onChanged: (v) => setState(() => _alwaysOnStartup = v),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Divider(height: 1, color: Color(0xFF3E3E3E)),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: ConfigUi.checkRow(
                          value: _limitAll,
                          label: 'Limit all downloads together to',
                          onChanged: (v) => setState(() => _limitAll = v),
                        ),
                      ),
                      SizedBox(
                        width: 68,
                        child: ConfigUi.textField(
                          controller: _allFilesCtrl,
                          enabled: _limitAll,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'KBytes/sec',
                        style: TextStyle(
                          color: Color(0xFFB0B0B0),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 20),
                    child: ConfigUi.checkRow(
                      value: _onlyWhileUsing,
                      label: "Only while I'm using the computer",
                      enabled: _limitAll,
                      onChanged: (v) => setState(() => _onlyWhileUsing = v),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      ConfigUi.button(
                        'OK',
                        primary: true,
                        width: 82,
                        onPressed: () {
                          final perFile =
                              int.tryParse(_perFileCtrl.text.trim()) ??
                              widget.initialKBps;
                          final allVal =
                              int.tryParse(_allFilesCtrl.text.trim()) ?? 500;
                          Navigator.of(context).pop(
                            SpeedLimiterSettingsResult(
                              maxPerFileKBps: perFile.clamp(16, 1024 * 1024),
                              alwaysOnStartup: _alwaysOnStartup,
                              limitAllEnabled: _limitAll,
                              limitAllKBps: allVal.clamp(16, 1024 * 1024),
                              onlyWhileUsingComputer: _onlyWhileUsing,
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: 8),
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
          ],
        ),
      ),
    );
  }
}

class LanguageDialog extends StatefulWidget {
  final String currentLanguage;

  const LanguageDialog({super.key, required this.currentLanguage});

  @override
  State<LanguageDialog> createState() => _LanguageDialogState();
}

class _LanguageDialogState extends State<LanguageDialog> {
  final TextEditingController _searchCtrl = TextEditingController();
  late String _selectedCode;

  @override
  void initState() {
    super.initState();
    _selectedCode = widget.currentLanguage;
    _searchCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _searchCtrl.text.trim().toLowerCase();
    final filtered = AppStrings.allLanguages.where((item) {
      if (q.isEmpty) return true;
      return item.nativeName.toLowerCase().contains(q) ||
          item.englishName.toLowerCase().contains(q) ||
          item.code.toLowerCase().contains(q);
    }).toList();

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 420,
        height: 510,
        decoration: BoxDecoration(
          color: const Color(0xFF232323),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: const Color(0xFF3A3A3A)),
        ),
        child: Column(
          children: [
            _titleBar(context, Icons.translate_rounded, 'Language'),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      AppStrings.instance.t(
                        'Choose the language FluxDM shows its windows in:',
                      ),
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text(
                          AppStrings.instance.t('Search:'),
                          style: const TextStyle(
                            color: Color(0xFFD8D8D8),
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ConfigUi.textField(controller: _searchCtrl),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1A1A),
                          border: Border.all(color: const Color(0xFF3E3E3E)),
                        ),
                        child: ListView.builder(
                          itemCount: filtered.length,
                          itemBuilder: (_, idx) {
                            final lang = filtered[idx];
                            final selected = lang.code == _selectedCode;
                            return InkWell(
                              onTap: () =>
                                  setState(() => _selectedCode = lang.code),
                              child: Container(
                                color: selected
                                    ? const Color(0xFF0E63B8)
                                    : Colors.transparent,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 28,
                                      height: 18,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: selected
                                            ? Colors.white.withValues(alpha: 0.2)
                                            : const Color(0xFF2C2C2C),
                                        borderRadius: BorderRadius.circular(2),
                                        border: Border.all(
                                          color: selected
                                              ? Colors.white54
                                              : const Color(0xFF454545),
                                          width: 0.8,
                                        ),
                                      ),
                                      child: Text(
                                        lang.badge,
                                        style: TextStyle(
                                          color: selected
                                              ? Colors.white
                                              : AppColors.accent,
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        lang.nativeName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: selected
                                              ? Colors.white
                                              : const Color(0xFFE6E6E6),
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                    if (lang.englishName.isNotEmpty)
                                      Text(
                                        lang.englishName,
                                        style: TextStyle(
                                          color: selected
                                              ? Colors.white.withValues(alpha: 0.9)
                                              : const Color(0xFF9A9A9A),
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
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        ConfigUi.button(
                          'OK',
                          primary: true,
                          width: 80,
                          onPressed: () =>
                              Navigator.of(context).pop(_selectedCode),
                        ),
                        const SizedBox(width: 8),
                        ConfigUi.button(
                          'Cancel',
                          width: 80,
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
}

Widget _titleBar(BuildContext context, IconData icon, String title) {
  return Container(
    height: 30,
    padding: const EdgeInsets.only(left: 10, right: 6),
    decoration: const BoxDecoration(
      color: Color(0xFF141414),
      border: Border(bottom: BorderSide(color: Color(0xFF333333))),
    ),
    child: Row(
      children: [
        Icon(icon, size: 15, color: AppColors.accent),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            AppStrings.instance.t(title),
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
