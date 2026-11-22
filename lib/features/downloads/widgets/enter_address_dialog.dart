import 'package:download_manager/core/localization/app_strings.dart';
import 'package:download_manager/core/theme/app_colors.dart';
import 'package:download_manager/features/downloads/utils/download_link_helper.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

class EnterAddressResult {
  final String url;
  final String? username;
  final String? password;

  const EnterAddressResult({
    required this.url,
    this.username,
    this.password,
  });
}

class EnterAddressDialog extends StatefulWidget {
  final String? initialUrl;

  const EnterAddressDialog({super.key, this.initialUrl});

  @override
  State<EnterAddressDialog> createState() => _EnterAddressDialogState();
}

class _EnterAddressDialogState extends State<EnterAddressDialog> {
  static const String _historyKey = 'recent_download_urls';

  late final TextEditingController _urlController;
  final TextEditingController _loginController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final FocusNode _urlFocusNode = FocusNode();

  bool _useAuthorization = false;
  bool _urlFocused = false;
  String? _validationError;
  List<String> _recentUrls = const [];

  @override
  void initState() {
    super.initState();
    final initial = widget.initialUrl?.trim() ?? '';
    _urlController = TextEditingController(text: initial);
    if (initial.isNotEmpty) {
      _urlController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: initial.length,
      );
    }

    _urlFocusNode.addListener(() {
      if (mounted) {
        setState(() => _urlFocused = _urlFocusNode.hasFocus);
      }
    });

    _loadHistory();
  }

  @override
  void dispose() {
    _urlController.dispose();
    _loginController.dispose();
    _passwordController.dispose();
    _urlFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList(_historyKey);
      if (!mounted || saved == null) return;
      setState(() {
        _recentUrls = saved;
      });
    } catch (_) {}
  }

  Future<void> _saveToHistory(String url) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = <String>[
        url,
        ..._recentUrls.where((item) => item != url),
      ].take(12).toList();
      await prefs.setStringList(_historyKey, list);
    } catch (_) {}
  }

  Future<void> _submit() async {
    final raw = _urlController.text.trim();
    final extracted = DownloadLinkHelper.extractSupportedUrl(raw);

    if (extracted == null) {
      setState(() {
        _validationError =
            'Please enter a valid HTTP, HTTPS, or FTP download address.';
      });
      return;
    }

    await _saveToHistory(extracted);
    if (!mounted) return;

    final login = _useAuthorization ? _loginController.text.trim() : null;
    final password = _useAuthorization ? _passwordController.text : null;

    Navigator.pop(
      context,
      EnterAddressResult(
        url: extracted,
        username: (login != null && login.isNotEmpty) ? login : null,
        password: (login != null && login.isNotEmpty) ? password : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final maxWidth = MediaQuery.sizeOf(context).width - 32;
    final dialogWidth = maxWidth.clamp(340.0, 580.0);

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
              color: Colors.black.withValues(alpha: 0.75),
              blurRadius: 24,
              offset: const Offset(0, 10),
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
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildAddressRow(),
                          const SizedBox(height: 10),
                          _buildAuthorizationGroupBox(),
                          if (_validationError != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              _validationError!,
                              style: const TextStyle(
                                color: Colors.redAccent,
                                fontSize: 11.5,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 88,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildActionButton(
                            label: 'OK',
                            isPrimary: true,
                            onPressed: _submit,
                          ),
                          const SizedBox(height: 8),
                          _buildActionButton(
                            label: 'Cancel',
                            isPrimary: false,
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                    ),
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
          Expanded(
            child: Text(
              AppStrings.instance.t('Enter new address to download'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          IconButton(
            tooltip: AppStrings.instance.t('Close'),
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

  Widget _buildAddressRow() {
    final s = AppStrings.instance;
    return Row(
      children: [
        SizedBox(
          width: 64,
          child: Text(
            s.t('Address'),
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 12.5),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: Container(
              height: 30,
              decoration: BoxDecoration(
                color: const Color(0xFF080B09),
                border: Border(
                  top: const BorderSide(color: Color(0xFF2B332E), width: 1),
                  left: const BorderSide(color: Color(0xFF2B332E), width: 1),
                  right: const BorderSide(color: Color(0xFF2B332E), width: 1),
                  bottom: BorderSide(
                    color: _urlFocused
                        ? AppColors.accent
                        : const Color(0xFF3A453E),
                    width: _urlFocused ? 2 : 1,
                  ),
                ),
              ),
              child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _urlController,
                    focusNode: _urlFocusNode,
                    autofocus: true,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 12.5,
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
                        fontSize: 12,
                      ),
                    ),
                    onChanged: (_) {
                      if (_validationError != null) {
                        setState(() => _validationError = null);
                      }
                    },
                    onSubmitted: (_) => _submit(),
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Recent addresses',
                  enabled: _recentUrls.isNotEmpty,
                  padding: EdgeInsets.zero,
                  color: AppColors.surface,
                  onSelected: (selectedUrl) {
                    _urlController.text = selectedUrl;
                    _urlController.selection = TextSelection.collapsed(
                      offset: selectedUrl.length,
                    );
                    if (_validationError != null) {
                      setState(() => _validationError = null);
                    }
                  },
                  itemBuilder: (context) => _recentUrls
                      .map(
                        (url) => PopupMenuItem<String>(
                          value: url,
                          height: 32,
                          child: SizedBox(
                            width: 340,
                            child: Text(
                              url,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                  child: SizedBox(
                    width: 26,
                    height: 28,
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 18,
                      color: _recentUrls.isNotEmpty
                          ? AppColors.textSecondary
                          : AppColors.textSecondary.withValues(alpha: 0.35),
                    ),
                  ),
                ),
              ],
            ),
          ),
          ),
        ),
      ],
    );
  }

  Widget _buildAuthorizationGroupBox() {
    final labelColor = _useAuthorization
        ? AppColors.textPrimary
        : AppColors.textSecondary.withValues(alpha: 0.6);

    return Stack(
      children: [
        Container(
          margin: const EdgeInsets.only(top: 9),
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 10),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFF2A322D), width: 1),
            borderRadius: BorderRadius.circular(2),
          ),
          child: Row(
            children: [
              Text(
                AppStrings.instance.t('Login'),
                style: TextStyle(color: labelColor, fontSize: 12),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildAuthInput(
                  controller: _loginController,
                  enabled: _useAuthorization,
                ),
              ),
              const SizedBox(width: 14),
              Text(
                AppStrings.instance.t('Password'),
                style: TextStyle(color: labelColor, fontSize: 12),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildAuthInput(
                  controller: _passwordController,
                  enabled: _useAuthorization,
                  obscureText: true,
                ),
              ),
            ],
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
                setState(() => _useAuthorization = !_useAuthorization);
              },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: Checkbox(
                      value: _useAuthorization,
                      activeColor: AppColors.accent,
                      checkColor: Colors.black,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                      side: const BorderSide(
                        color: AppColors.textSecondary,
                        width: 1.2,
                      ),
                      onChanged: (val) {
                        setState(() => _useAuthorization = val ?? false);
                      },
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    AppStrings.instance.t('Use authorization'),
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAuthInput({
    required TextEditingController controller,
    required bool enabled,
    bool obscureText = false,
  }) {
    return Container(
      height: 26,
      decoration: BoxDecoration(
        color: enabled ? const Color(0xFF080B09) : const Color(0xFF141916),
        borderRadius: BorderRadius.circular(2),
        border: Border.all(
          color: enabled ? const Color(0xFF2E3832) : const Color(0xFF232925),
        ),
      ),
      child: TextField(
        controller: controller,
        enabled: enabled,
        obscureText: obscureText,
        style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
        decoration: const InputDecoration(
          isDense: true,
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(horizontal: 7, vertical: 5),
        ),
        onSubmitted: (_) => _submit(),
      ),
    );
  }

  Widget _buildActionButton({
    required String label,
    required bool isPrimary,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      height: 30,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: const Color(0xFF171D1A),
          foregroundColor: AppColors.textPrimary,
          side: BorderSide(
            color: isPrimary ? AppColors.accent : const Color(0xFF2E3732),
            width: isPrimary ? 1.2 : 1,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
          padding: EdgeInsets.zero,
          textStyle: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
          ),
        ),
        child: Text(AppStrings.instance.t(label)),
      ),
    );
  }
}
