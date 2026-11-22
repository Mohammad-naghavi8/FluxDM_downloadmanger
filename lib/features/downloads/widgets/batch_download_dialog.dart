import 'package:download_manager/core/localization/app_strings.dart';
import 'package:download_manager/core/theme/app_colors.dart';
import 'package:download_manager/features/settings/widgets/config_ui_helpers.dart';
import 'package:material_ui/material_ui.dart';

class BatchDownloadResult {
  final List<String> urls;
  final String? username;
  final String? password;

  const BatchDownloadResult({
    required this.urls,
    this.username,
    this.password,
  });
}

class BatchDownloadDialog extends StatefulWidget {
  const BatchDownloadDialog({super.key});

  @override
  State<BatchDownloadDialog> createState() => _BatchDownloadDialogState();
}

class _BatchDownloadDialogState extends State<BatchDownloadDialog> {
  final TextEditingController _addressCtrl = TextEditingController();
  final TextEditingController _loginCtrl = TextEditingController();
  final TextEditingController _passwordCtrl = TextEditingController();
  final TextEditingController _fromLetterCtrl = TextEditingController(text: 'a');
  final TextEditingController _toLetterCtrl = TextEditingController(text: 'z');

  bool _useNumbers = true;
  int _fromNum = 0;
  int _toNum = 10;
  int _wildcardSize = 1;
  bool _useAuth = false;

  @override
  void initState() {
    super.initState();
    _addressCtrl.addListener(() => setState(() {}));
    _fromLetterCtrl.addListener(() => setState(() {}));
    _toLetterCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _addressCtrl.dispose();
    _loginCtrl.dispose();
    _passwordCtrl.dispose();
    _fromLetterCtrl.dispose();
    _toLetterCtrl.dispose();
    super.dispose();
  }

  List<String> _generateUrls() {
    final template = _addressCtrl.text.trim();
    if (template.isEmpty || !template.contains('*')) return const [];

    final urls = <String>[];
    if (_useNumbers) {
      final start = _fromNum;
      final end = _toNum;
      final step = start <= end ? 1 : -1;
      int count = 0;
      for (int i = start; step > 0 ? i <= end : i >= end; i += step) {
        final token = i.toString().padLeft(_wildcardSize, '0');
        urls.add(template.replaceFirst('*', token));
        if (++count >= 500) break;
      }
    } else {
      final a = _fromLetterCtrl.text.trim().isNotEmpty
          ? _fromLetterCtrl.text.trim().codeUnitAt(0)
          : 'a'.codeUnitAt(0);
      final b = _toLetterCtrl.text.trim().isNotEmpty
          ? _toLetterCtrl.text.trim().codeUnitAt(0)
          : 'z'.codeUnitAt(0);
      final step = a <= b ? 1 : -1;
      int count = 0;
      for (int c = a; step > 0 ? c <= b : c >= b; c += step) {
        urls.add(template.replaceFirst('*', String.fromCharCode(c)));
        if (++count >= 200) break;
      }
    }
    return urls;
  }

  @override
  Widget build(BuildContext context) {
    final generated = _generateUrls();
    final firstUrl = generated.isNotEmpty ? generated.first : '';
    final secondUrl = generated.length > 1 ? generated[1] : '';
    final lastUrl = generated.length > 2 ? generated.last : '';

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: Container(
        width: 520,
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
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildTitleBar(),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    "It's possible to add a group of sequential file names like img001.jpg, img002.jpg, etc., img100.jpg to FluxDM download queue. Use the asterisk wildcard for the file name pattern.\nFor example:  http://www.example.com/pictures/img*.jpg",
                    style: TextStyle(color: Color(0xFFD8D8D8), fontSize: 11.8),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const SizedBox(
                        width: 64,
                        child: Text(
                          'Address',
                          style: TextStyle(color: Colors.white, fontSize: 12),
                        ),
                      ),
                      Expanded(
                        child: ConfigUi.textField(
                          controller: _addressCtrl,
                          hint: 'https://example.com/files/part*.rar',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ConfigUi.groupBox(
                    title: 'Replace asterisk to',
                    child: Column(
                      children: [
                        Row(
                          children: [
                            SizedBox(
                              width: 125,
                              child: ConfigUi.radioRow<bool>(
                                value: true,
                                groupValue: _useNumbers,
                                label: 'Numbers',
                                onChanged: (v) =>
                                    setState(() => _useNumbers = v),
                              ),
                            ),
                            SizedBox(
                              width: 125,
                              child: ConfigUi.radioRow<bool>(
                                value: false,
                                groupValue: _useNumbers,
                                label: 'Letters',
                                onChanged: (v) =>
                                    setState(() => _useNumbers = v),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Text(
                              'From:',
                              style: TextStyle(
                                color: Color(0xFFE0E0E0),
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (_useNumbers)
                              ConfigUi.spinner(
                                value: _fromNum,
                                min: 0,
                                max: 9999,
                                width: 72,
                                onChanged: (v) => setState(() => _fromNum = v),
                              )
                            else
                              SizedBox(
                                width: 52,
                                child: ConfigUi.textField(
                                  controller: _fromLetterCtrl,
                                ),
                              ),
                            const SizedBox(width: 16),
                            const Text(
                              'To:',
                              style: TextStyle(
                                color: Color(0xFFE0E0E0),
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (_useNumbers)
                              ConfigUi.spinner(
                                value: _toNum,
                                min: 0,
                                max: 9999,
                                width: 72,
                                onChanged: (v) => setState(() => _toNum = v),
                              )
                            else
                              SizedBox(
                                width: 52,
                                child: ConfigUi.textField(
                                  controller: _toLetterCtrl,
                                ),
                              ),
                            const Spacer(),
                            if (_useNumbers) ...[
                              const Text(
                                'Wildcard size',
                                style: TextStyle(
                                  color: Color(0xFFE0E0E0),
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(width: 8),
                              ConfigUi.spinner(
                                value: _wildcardSize,
                                min: 1,
                                max: 6,
                                width: 58,
                                onChanged: (v) =>
                                    setState(() => _wildcardSize = v),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  ConfigUi.groupBox(
                    title: 'Use authorization',
                    child: Column(
                      children: [
                        ConfigUi.checkRow(
                          value: _useAuth,
                          label: 'Use authorization',
                          onChanged: (v) => setState(() => _useAuth = v),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const SizedBox(
                              width: 48,
                              child: Text(
                                'Login',
                                style: TextStyle(
                                  color: Color(0xFFB8B8B8),
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            Expanded(
                              child: ConfigUi.textField(
                                controller: _loginCtrl,
                                enabled: _useAuth,
                              ),
                            ),
                            const SizedBox(width: 14),
                            const SizedBox(
                              width: 64,
                              child: Text(
                                'Password',
                                style: TextStyle(
                                  color: Color(0xFFB8B8B8),
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            Expanded(
                              child: ConfigUi.textField(
                                controller: _passwordCtrl,
                                enabled: _useAuth,
                                obscure: true,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _previewRow('First file:', firstUrl),
                  const SizedBox(height: 5),
                  _previewRow('Second file:', secondUrl),
                  const Padding(
                    padding: EdgeInsets.only(left: 16, top: 2, bottom: 2),
                    child: Text(
                      '...',
                      style: TextStyle(color: Color(0xFFA0A0A0), fontSize: 12),
                    ),
                  ),
                  _previewRow('Last file:', lastUrl),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (generated.isNotEmpty)
                        Expanded(
                          child: Text(
                            '${generated.length} links will be added',
                            style: const TextStyle(
                              color: AppColors.accent,
                              fontSize: 11.5,
                            ),
                          ),
                        ),
                      ConfigUi.button(
                        'OK',
                        primary: true,
                        width: 82,
                        onPressed: generated.isNotEmpty
                            ? () => Navigator.of(context).pop(
                                BatchDownloadResult(
                                  urls: generated,
                                  username: _useAuth
                                      ? _loginCtrl.text.trim()
                                      : null,
                                  password: _useAuth
                                      ? _passwordCtrl.text
                                      : null,
                                ),
                              )
                            : null,
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
          const Icon(Icons.layers_outlined, size: 15, color: AppColors.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              AppStrings.instance.t('Batch download'),
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

  Widget _previewRow(String label, String value) {
    return Row(
      children: [
        SizedBox(
          width: 82,
          child: Text(
            label,
            style: const TextStyle(color: Color(0xFFD8D8D8), fontSize: 12),
          ),
        ),
        Expanded(
          child: Container(
            height: 24,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF1D1D1D),
              border: Border.all(color: const Color(0xFF343434)),
              borderRadius: BorderRadius.circular(2),
            ),
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFFA8A8A8), fontSize: 11.5),
            ),
          ),
        ),
      ],
    );
  }
}
