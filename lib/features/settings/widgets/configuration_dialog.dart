import 'package:download_manager/core/localization/app_strings.dart';
import 'package:download_manager/core/theme/app_colors.dart';
import 'package:download_manager/features/downloads/services/download_path_service.dart';
import 'package:download_manager/features/settings/models/app_settings.dart';
import 'package:download_manager/features/settings/widgets/config_ui_helpers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';

class ConfigurationDialog extends StatefulWidget {
  final AppSettings initialSettings;
  final DownloadPathService downloadPathService;
  final String defaultDownloadDir;
  final VoidCallback? onOpenBrowserIntegration;

  const ConfigurationDialog({
    super.key,
    required this.initialSettings,
    required this.downloadPathService,
    required this.defaultDownloadDir,
    this.onOpenBrowserIntegration,
  });

  @override
  State<ConfigurationDialog> createState() => _ConfigurationDialogState();
}

class _ConfigurationDialogState extends State<ConfigurationDialog> {
  static const List<String> _row1Tabs = [
    'General',
    'File types',
    'Save to',
    'Downloads',
    'Connection',
    'Remote',
  ];
  static const List<String> _row2Tabs = [
    'Proxy / Socks',
    'Sites Logins',
    'Accounts',
    'Sounds',
    'Regional',
    'Archives',
  ];

  String _activeTab = 'General';

  // General
  late bool _launchOnStartup;
  late bool _offerClipboard;
  late bool _advancedBrowser;
  late bool _confirmDelete;
  late bool _minimizeTray;
  late bool _keepRunningClose;
  late Set<String> _enabledBrowsers;

  // File types
  late TextEditingController _fileTypesCtrl;
  late TextEditingController _excludedSitesCtrl;
  late List<String> _excludedAddresses;
  late TextEditingController _minFileSizeCtrl;

  // Save to
  String _selectedSaveCategory = 'General';
  late TextEditingController _categoryDirCtrl;
  late bool _rememberCategoryFolder;
  late bool _setServerDate;

  // Downloads
  late bool _showStartDialog;
  late bool _addOnlyQueue;
  late bool _showCompleteDialog;
  late bool _startImmediatelyInfo;
  late bool _showQueueOnLater;
  late bool _showQueueOnBatch;
  late bool _ignoreModTime;
  late String _duplicateAction;
  late TextEditingController _userAgentCtrl;

  // Connection
  late int _defaultMaxConn;
  late bool _allowMoreThan32;
  late List<ConnectionException> _connExceptions;
  int? _selectedExceptionIdx;
  late bool _downloadLimitEnabled;
  late TextEditingController _dlLimitMbCtrl;
  late TextEditingController _dlLimitHrsCtrl;
  late bool _warnBeforeStopping;
  late String _dnsMode;

  // Remote
  late bool _remoteEnabled;
  late String _remoteListenOn;
  late int _remotePort;

  // Proxy / Socks
  late bool _useBrowserProxyOnError;
  late String _proxyMode;
  late TextEditingController _pacCtrl;
  late TextEditingController _proxyHostCtrl;
  late TextEditingController _proxyPortCtrl;
  late TextEditingController _proxyUserCtrl;
  late TextEditingController _proxyPassCtrl;
  late bool _proxyHttp;
  late bool _proxyHttps;
  late bool _proxyFtp;
  late String _networkAdapter;
  late bool _useFtpPasv;

  // Sites Logins
  late List<SiteLoginEntry> _siteLogins;
  int? _selectedLoginIdx;
  late String _videoCookiesMode;
  late String _videoCookiesBrowser;
  late TextEditingController _videoProfileCtrl;

  // Accounts
  late List<DebridAccountEntry> _debridAccounts;
  int? _selectedAccountIdx;
  late bool _useDebridFileHosts;
  late bool _sendTorrentsDebrid;

  // Sounds
  late List<SoundEventSetting> _soundEvents;
  int? _selectedSoundIdx;

  // Regional
  late bool _useSystemRegion;
  late String _dateOrder;
  late String _clockFormat;
  late String _firstDayOfWeek;

  // Archives
  late bool _extractArchives;
  late bool _moveArchivesBin;
  late String _archiveTarget;
  late bool _linkGrabberLookup;
  late bool _linkGrabberHideWeb;

  @override
  void initState() {
    super.initState();
    final s = widget.initialSettings;
    _launchOnStartup = s.launchOnStartup;
    _offerClipboard = s.offerClipboardDownloads;
    _advancedBrowser = s.useAdvancedBrowserIntegration;
    _confirmDelete = s.confirmBeforeDeleting;
    _minimizeTray = s.minimizeToTray;
    _keepRunningClose = s.keepRunningOnClose;
    _enabledBrowsers = Set<String>.from(s.enabledBrowsers);

    _fileTypesCtrl = TextEditingController(text: s.autoDownloadFileTypes);
    _excludedSitesCtrl = TextEditingController(text: s.excludedSites);
    _excludedAddresses = List<String>.from(s.excludedAddresses);
    _minFileSizeCtrl = TextEditingController(text: '${s.minFileSizeKB}');

    _categoryDirCtrl = TextEditingController(text: widget.defaultDownloadDir);
    _rememberCategoryFolder = s.rememberCategoryFolder;
    _setServerDate = s.setServerFileCreationDate;

    _showStartDialog = s.showStartDownloadDialog;
    _addOnlyQueue = s.addOnlyToQueueWhenDialogHidden;
    _showCompleteDialog = s.showDownloadCompleteDialog;
    _startImmediatelyInfo = s.startImmediatelyWhileInfoShown;
    _showQueueOnLater = s.showQueuePanelOnDownloadLater;
    _showQueueOnBatch = s.showQueuePanelOnBatchClose;
    _ignoreModTime = s.ignoreFileModTimeOnResume;
    _duplicateAction = s.duplicateLinkAction;
    _userAgentCtrl = TextEditingController(text: s.manualUserAgent);

    _defaultMaxConn = s.defaultMaxConnections;
    _allowMoreThan32 = s.allowMoreThan32Connections;
    _connExceptions = List<ConnectionException>.from(s.connectionExceptions);
    _downloadLimitEnabled = s.downloadLimitEnabled;
    _dlLimitMbCtrl = TextEditingController(text: '${s.downloadLimitMB}');
    _dlLimitHrsCtrl = TextEditingController(text: '${s.downloadLimitHours}');
    _warnBeforeStopping = s.showWarningBeforeStopping;
    _dnsMode = s.dnsMode;

    _remoteEnabled = s.remoteControlEnabled;
    _remoteListenOn = s.remoteListenOn;
    _remotePort = s.remotePort;

    _useBrowserProxyOnError = s.useBrowserProxyOnError;
    _proxyMode = s.proxyMode;
    _pacCtrl = TextEditingController(text: s.pacAddress);
    _proxyHostCtrl = TextEditingController(text: s.proxyServer);
    _proxyPortCtrl = TextEditingController(text: s.proxyPort);
    _proxyUserCtrl = TextEditingController(text: s.proxyUsername);
    _proxyPassCtrl = TextEditingController(text: s.proxyPassword);
    _proxyHttp = s.proxyHttp;
    _proxyHttps = s.proxyHttps;
    _proxyFtp = s.proxyFtp;
    _networkAdapter = s.networkAdapter;
    _useFtpPasv = s.useFtpPasv;

    _siteLogins = List<SiteLoginEntry>.from(s.siteLogins);
    _videoCookiesMode = s.videoCookiesMode;
    _videoCookiesBrowser = s.videoCookiesBrowser;
    _videoProfileCtrl = TextEditingController(text: s.videoCookiesProfile);

    _debridAccounts = List<DebridAccountEntry>.from(s.debridAccounts);
    _useDebridFileHosts = s.useDebridForFileHosts;
    _sendTorrentsDebrid = s.sendTorrentsToDebrid;

    _soundEvents = List<SoundEventSetting>.from(s.soundEvents);

    _useSystemRegion = s.useSystemRegionFormat;
    _dateOrder = s.dateOrder;
    _clockFormat = s.clockFormat;
    _firstDayOfWeek = s.firstDayOfWeek;

    _extractArchives = s.extractArchivesOnComplete;
    _moveArchivesBin = s.moveArchivesToRecycleBin;
    _archiveTarget = s.archiveExtractTarget;
    _linkGrabberLookup = s.linkGrabberLookupOnArrive;
    _linkGrabberHideWeb = s.linkGrabberHideWebPages;
  }

  @override
  void dispose() {
    _fileTypesCtrl.dispose();
    _excludedSitesCtrl.dispose();
    _minFileSizeCtrl.dispose();
    _categoryDirCtrl.dispose();
    _userAgentCtrl.dispose();
    _dlLimitMbCtrl.dispose();
    _dlLimitHrsCtrl.dispose();
    _pacCtrl.dispose();
    _proxyHostCtrl.dispose();
    _proxyPortCtrl.dispose();
    _proxyUserCtrl.dispose();
    _proxyPassCtrl.dispose();
    _videoProfileCtrl.dispose();
    super.dispose();
  }

  AppSettings _collectSettings() {
    return AppSettings(
      launchOnStartup: _launchOnStartup,
      offerClipboardDownloads: _offerClipboard,
      useAdvancedBrowserIntegration: _advancedBrowser,
      confirmBeforeDeleting: _confirmDelete,
      minimizeToTray: _minimizeTray,
      keepRunningOnClose: _keepRunningClose,
      enabledBrowsers: _enabledBrowsers.toList(),
      autoDownloadFileTypes: _fileTypesCtrl.text.trim(),
      excludedSites: _excludedSitesCtrl.text.trim(),
      excludedAddresses: _excludedAddresses,
      minFileSizeKB: int.tryParse(_minFileSizeCtrl.text.trim()) ?? 0,
      rememberCategoryFolder: _rememberCategoryFolder,
      setServerFileCreationDate: _setServerDate,
      showStartDownloadDialog: _showStartDialog,
      addOnlyToQueueWhenDialogHidden: _addOnlyQueue,
      showDownloadCompleteDialog: _showCompleteDialog,
      startImmediatelyWhileInfoShown: _startImmediatelyInfo,
      showQueuePanelOnDownloadLater: _showQueueOnLater,
      showQueuePanelOnBatchClose: _showQueueOnBatch,
      ignoreFileModTimeOnResume: _ignoreModTime,
      duplicateLinkAction: _duplicateAction,
      manualUserAgent: _userAgentCtrl.text.trim(),
      defaultMaxConnections: _defaultMaxConn,
      allowMoreThan32Connections: _allowMoreThan32,
      connectionExceptions: _connExceptions,
      downloadLimitEnabled: _downloadLimitEnabled,
      downloadLimitMB: int.tryParse(_dlLimitMbCtrl.text.trim()) ?? 200,
      downloadLimitHours: int.tryParse(_dlLimitHrsCtrl.text.trim()) ?? 5,
      showWarningBeforeStopping: _warnBeforeStopping,
      dnsMode: _dnsMode,
      remoteControlEnabled: _remoteEnabled,
      remoteListenOn: _remoteListenOn,
      remotePort: _remotePort,
      useBrowserProxyOnError: _useBrowserProxyOnError,
      proxyMode: _proxyMode,
      pacAddress: _pacCtrl.text.trim(),
      proxyServer: _proxyHostCtrl.text.trim(),
      proxyPort: _proxyPortCtrl.text.trim(),
      proxyUsername: _proxyUserCtrl.text.trim(),
      proxyPassword: _proxyPassCtrl.text,
      proxyHttp: _proxyHttp,
      proxyHttps: _proxyHttps,
      proxyFtp: _proxyFtp,
      networkAdapter: _networkAdapter,
      useFtpPasv: _useFtpPasv,
      siteLogins: _siteLogins,
      videoCookiesMode: _videoCookiesMode,
      videoCookiesBrowser: _videoCookiesBrowser,
      videoCookiesProfile: _videoProfileCtrl.text.trim(),
      debridAccounts: _debridAccounts,
      useDebridForFileHosts: _useDebridFileHosts,
      sendTorrentsToDebrid: _sendTorrentsDebrid,
      soundEvents: _soundEvents,
      useSystemRegionFormat: _useSystemRegion,
      dateOrder: _dateOrder,
      clockFormat: _clockFormat,
      firstDayOfWeek: _firstDayOfWeek,
      extractArchivesOnComplete: _extractArchives,
      moveArchivesToRecycleBin: _moveArchivesBin,
      archiveExtractTarget: _archiveTarget,
      linkGrabberLookupOnArrive: _linkGrabberLookup,
      linkGrabberHideWebPages: _linkGrabberHideWeb,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isRow2Active = _row2Tabs.contains(_activeTab);
    final topRow = isRow2Active ? _row1Tabs : _row2Tabs;
    final bottomRow = isRow2Active ? _row2Tabs : _row1Tabs;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: Container(
        width: 565,
        height: 610,
        decoration: BoxDecoration(
          color: const Color(0xFF202020),
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
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
              child: Column(
                children: [
                  _buildTabStrip(topRow),
                  _buildTabStrip(bottomRow),
                ],
              ),
            ),
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF282828),
                  border: Border.all(color: const Color(0xFF3E3E3E)),
                ),
                child: SingleChildScrollView(
                  child: _buildActiveTabBody(),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
              child: Row(
                children: [
                  if (_activeTab == 'Save to')
                    Flexible(
                      child: ConfigUi.button(
                        'Restore built-in categories',
                        onPressed: () {
                          setState(() {
                            _selectedSaveCategory = 'General';
                            _categoryDirCtrl.text = widget.defaultDownloadDir;
                          });
                        },
                      ),
                    ),
                  const Spacer(),
                  ConfigUi.button(
                    'OK',
                    primary: true,
                    width: 82,
                    onPressed: () =>
                        Navigator.of(context).pop(_collectSettings()),
                  ),
                  const SizedBox(width: 8),
                  ConfigUi.button(
                    'Cancel',
                    width: 82,
                    onPressed: () => Navigator.of(context).pop(),
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
          const Icon(Icons.settings_outlined, size: 15, color: AppColors.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              AppStrings.instance.t('FluxDM Configuration'),
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

  Widget _buildTabStrip(List<String> tabs) {
    return Row(
      children: tabs.map((tab) {
        final active = _activeTab == tab;
        return Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _activeTab = tab),
            child: Container(
              height: 25,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: active
                    ? const Color(0xFF282828)
                    : const Color(0xFF1D1D1D),
                border: Border(
                  top: BorderSide(
                    color: active ? AppColors.accent : const Color(0xFF3A3A3A),
                    width: active ? 1.5 : 1,
                  ),
                  left: const BorderSide(color: Color(0xFF3A3A3A), width: 0.7),
                  right: const BorderSide(color: Color(0xFF3A3A3A), width: 0.7),
                ),
              ),
              child: Text(
                AppStrings.instance.t(tab),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: active ? Colors.white : const Color(0xFFC0C0C0),
                  fontSize: 11.5,
                  fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildActiveTabBody() {
    return switch (_activeTab) {
      'General' => _buildGeneralTab(),
      'File types' => _buildFileTypesTab(),
      'Save to' => _buildSaveToTab(),
      'Downloads' => _buildDownloadsTab(),
      'Connection' => _buildConnectionTab(),
      'Remote' => _buildRemoteTab(),
      'Proxy / Socks' => _buildProxyTab(),
      'Sites Logins' => _buildSitesLoginsTab(),
      'Accounts' => _buildAccountsTab(),
      'Sounds' => _buildSoundsTab(),
      'Regional' => _buildRegionalTab(),
      'Archives' => _buildArchivesTab(),
      _ => _buildGeneralTab(),
    };
  }

  // ── 1. GENERAL ─────────────────────────────────────────────────────────────
  Widget _buildGeneralTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ConfigUi.tabHeader(Icons.language_rounded, 'Browser/System Integration'),
        ConfigUi.checkRow(
          value: _launchOnStartup,
          label: 'Launch FluxDM on startup',
          onChanged: (v) => setState(() => _launchOnStartup = v),
        ),
        ConfigUi.checkRow(
          value: _offerClipboard,
          label: 'Offer to download links copied to the clipboard',
          onChanged: (v) => setState(() => _offerClipboard = v),
        ),
        ConfigUi.checkRow(
          value: _advancedBrowser,
          label: 'Use advanced browser integration',
          onChanged: (v) => setState(() => _advancedBrowser = v),
        ),
        ConfigUi.checkRow(
          value: _confirmDelete,
          label: 'Confirm before deleting downloads',
          onChanged: (v) => setState(() => _confirmDelete = v),
        ),
        ConfigUi.checkRow(
          value: _minimizeTray,
          label: 'Minimize to the notification area',
          onChanged: (v) => setState(() => _minimizeTray = v),
        ),
        ConfigUi.checkRow(
          value: _keepRunningClose,
          label: 'Keep running when closing the window',
          onChanged: (v) => setState(() => _keepRunningClose = v),
        ),
        const SizedBox(height: 8),
        ConfigUi.groupBox(
          title: 'Capture downloads from the following browsers:',
          child: Column(
            children: [
              Container(
                height: 112,
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  border: Border.all(color: const Color(0xFF3E3E3E)),
                ),
                child: ListView(
                  children: AppSettings.defaultBrowsers.map((browser) {
                    final checked = _enabledBrowsers.contains(browser);
                    return InkWell(
                      onTap: () => setState(() {
                        if (checked) {
                          _enabledBrowsers.remove(browser);
                        } else {
                          _enabledBrowsers.add(browser);
                        }
                      }),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              checked
                                  ? Icons.check_box
                                  : Icons.check_box_outline_blank,
                              size: 16,
                              color: checked
                                  ? AppColors.accent
                                  : const Color(0xFF666666),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              browser,
                              style: const TextStyle(
                                color: Color(0xFFE2E2E2),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ConfigUi.button(
                      'Test browser integration...',
                      onPressed: widget.onOpenBrowserIntegration,
                    ),
                  ),
                  const SizedBox(width: 8),
                  ConfigUi.button('Add browser...', onPressed: null, width: 120),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── 2. FILE TYPES ──────────────────────────────────────────────────────────
  Widget _buildFileTypesTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ConfigUi.tabHeader(Icons.description_outlined, 'Downloaded file types'),
        const Text(
          'Automatically start downloading the following file types:',
          style: TextStyle(color: Color(0xFFE0E0E0), fontSize: 12),
        ),
        const SizedBox(height: 6),
        ConfigUi.textField(controller: _fileTypesCtrl, maxLines: 4),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerRight,
          child: ConfigUi.button(
            'Default',
            width: 88,
            onPressed: () =>
                setState(() => _fileTypesCtrl.text = AppSettings.defaultFileTypes),
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          "Don't start downloading automatically from the following sites:",
          style: TextStyle(color: Color(0xFFE0E0E0), fontSize: 12),
        ),
        const SizedBox(height: 6),
        ConfigUi.textField(controller: _excludedSitesCtrl, maxLines: 3),
        const SizedBox(height: 6),
        Row(
          children: [
            const Text(
              '(separate names by spaces)',
              style: TextStyle(color: Color(0xFF9E9E9E), fontSize: 11.5),
            ),
            const Spacer(),
            ConfigUi.button(
              'Default',
              width: 88,
              onPressed: () => setState(
                () => _excludedSitesCtrl.text = AppSettings.defaultExcludedSites,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const Text(
          "Don't start downloading automatically from the following addresses:",
          style: TextStyle(color: Color(0xFFE0E0E0), fontSize: 12),
        ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerLeft,
          child: ConfigUi.button(
            'Edit list ... (${_excludedAddresses.length})',
            width: 155,
            onPressed: _editExcludedAddresses,
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            const Expanded(
              child: Text(
                "Don't take files smaller than (KB, 0 = any size):",
                style: TextStyle(color: Color(0xFFE0E0E0), fontSize: 12),
              ),
            ),
            SizedBox(
              width: 86,
              child: ConfigUi.textField(controller: _minFileSizeCtrl),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _editExcludedAddresses() async {
    final ctrl = TextEditingController(text: _excludedAddresses.join('\n'));
    final result = await showDialog<List<String>>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF232323),
        child: Container(
          width: 440,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFF3E3E3E)),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Addresses left to the browser',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'One address per line; * stands for any text: example.com/private/*',
                style: TextStyle(color: Color(0xFFB8B8B8), fontSize: 11.5),
              ),
              const SizedBox(height: 8),
              ConfigUi.textField(controller: ctrl, maxLines: 8),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  ConfigUi.button(
                    'OK',
                    primary: true,
                    width: 80,
                    onPressed: () {
                      final lines = ctrl.text
                          .split('\n')
                          .map((e) => e.trim())
                          .where((e) => e.isNotEmpty)
                          .toList();
                      Navigator.of(ctx).pop(lines);
                    },
                  ),
                  const SizedBox(width: 8),
                  ConfigUi.button(
                    'Cancel',
                    width: 80,
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    ctrl.dispose();
    if (result != null && mounted) {
      setState(() => _excludedAddresses = result);
    }
  }

  // ── 3. SAVE TO ─────────────────────────────────────────────────────────────
  Widget _buildSaveToTab() {
    final categories = [
      'General',
      'Compressed',
      'Documents',
      'Music',
      'Programs',
      'Videos',
      'Torrents',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ConfigUi.tabHeader(Icons.folder_outlined, 'Categories, file types, folders'),
        ConfigUi.groupBox(
          title: 'Save To...',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Category',
                style: TextStyle(color: Color(0xFFD8D8D8), fontSize: 12),
              ),
              const SizedBox(height: 5),
              ConfigUi.dropdown(
                value: _selectedSaveCategory,
                items: categories,
                onChanged: (cat) async {
                  setState(() => _selectedSaveCategory = cat);
                  final path = cat == 'General'
                      ? widget.defaultDownloadDir
                      : await widget.downloadPathService.getCategoryPath(cat);
                  if (mounted) {
                    setState(() => _categoryDirCtrl.text = path);
                  }
                },
              ),
              const SizedBox(height: 10),
              Text(
                'Default download directory for "$_selectedSaveCategory" category',
                style: const TextStyle(color: Color(0xFFD8D8D8), fontSize: 12),
              ),
              const SizedBox(height: 5),
              Row(
                children: [
                  Expanded(child: ConfigUi.textField(controller: _categoryDirCtrl)),
                  const SizedBox(width: 8),
                  ConfigUi.button(
                    'Browse',
                    width: 80,
                    onPressed: () async {
                      final picked = await FilePicker.pickDirectory();
                      if (picked != null && picked.path.isNotEmpty && mounted) {
                        setState(() => _categoryDirCtrl.text = picked.path);
                        if (_selectedSaveCategory != 'General') {
                          await widget.downloadPathService.saveCategoryPath(
                            _selectedSaveCategory,
                            picked.path,
                          );
                        }
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ConfigUi.checkRow(
                value: _rememberCategoryFolder,
                label: 'Change folder for "$_selectedSaveCategory" category on last selected',
                onChanged: (v) => setState(() => _rememberCategoryFolder = v),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        ConfigUi.checkRow(
          value: _setServerDate,
          label: 'Set file creation date as provided by the server',
          onChanged: (v) => setState(() => _setServerDate = v),
        ),
        const SizedBox(height: 8),
        ConfigUi.groupBox(
          title: 'Temporary directory',
          child: const Text(
            'Go download engine writes segment parts directly beside the target file and merges cleanly without duplicating temporary folders.',
            style: TextStyle(color: Color(0xFFA8A8A8), fontSize: 11.5),
          ),
        ),
      ],
    );
  }

  // ── 4. DOWNLOADS ───────────────────────────────────────────────────────────
  Widget _buildDownloadsTab() {
    const dupOptions = [
      'Show a dialog and ask what to do.',
      'Add numbered copy automatically',
      'Overwrite existing file',
      'Skip duplicate link',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ConfigUi.tabHeader(Icons.download_for_offline_outlined, 'Default download settings'),
        ConfigUi.checkRow(
          value: _showStartDialog,
          label: 'Show start download dialog',
          onChanged: (v) => setState(() => _showStartDialog = v),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 22),
          child: ConfigUi.checkRow(
            value: _addOnlyQueue,
            label: 'Do not start downloading, only add files to the queue',
            enabled: !_showStartDialog,
            onChanged: (v) => setState(() => _addOnlyQueue = v),
          ),
        ),
        ConfigUi.checkRow(
          value: _showCompleteDialog,
          label: 'Show download complete dialog',
          onChanged: (v) => setState(() => _showCompleteDialog = v),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Divider(height: 1, color: Color(0xFF3E3E3E)),
        ),
        ConfigUi.checkRow(
          value: _startImmediatelyInfo,
          label: 'Start downloading immediately while displaying "Download File Info" dialog',
          onChanged: (v) => setState(() => _startImmediatelyInfo = v),
        ),
        ConfigUi.checkRow(
          value: _showQueueOnLater,
          label: 'Show queue selection panel on pressing "Download Later" button',
          onChanged: (v) => setState(() => _showQueueOnLater = v),
        ),
        ConfigUi.checkRow(
          value: _showQueueOnBatch,
          label: 'Show queue selection panel on closing batch download dialogs',
          onChanged: (v) => setState(() => _showQueueOnBatch = v),
        ),
        ConfigUi.checkRow(
          value: _ignoreModTime,
          label: 'Ignore file modification time changes when resuming a download',
          onChanged: (v) => setState(() => _ignoreModTime = v),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Divider(height: 1, color: Color(0xFF3E3E3E)),
        ),
        const Text(
          'If a duplicate download link is added:',
          style: TextStyle(color: Color(0xFFE0E0E0), fontSize: 12),
        ),
        const SizedBox(height: 5),
        ConfigUi.dropdown(
          value: _duplicateAction,
          items: dupOptions,
          onChanged: (v) => setState(() => _duplicateAction = v),
        ),
        const SizedBox(height: 10),
        const Text(
          'User-Agent for manually added downloads:',
          style: TextStyle(color: Color(0xFFE0E0E0), fontSize: 12),
        ),
        const SizedBox(height: 5),
        ConfigUi.textField(controller: _userAgentCtrl),
      ],
    );
  }

  // ── 5. CONNECTION ──────────────────────────────────────────────────────────
  Widget _buildConnectionTab() {
    final maxAllowed = _allowMoreThan32 ? 64 : 32;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ConfigUi.tabHeader(Icons.lan_outlined, 'Connections and Limits'),
        ConfigUi.groupBox(
          title: 'Max. connections number',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  const Text(
                    'Default max. conn. number',
                    style: TextStyle(color: Color(0xFFE0E0E0), fontSize: 12),
                  ),
                  const SizedBox(width: 10),
                  ConfigUi.spinner(
                    value: _defaultMaxConn.clamp(1, maxAllowed),
                    min: 1,
                    max: maxAllowed,
                    onChanged: (v) => setState(() => _defaultMaxConn = v),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ConfigUi.checkRow(
                value: _allowMoreThan32,
                label: 'Allow more than 32 connections',
                onChanged: (v) => setState(() {
                  _allowMoreThan32 = v;
                  if (!v && _defaultMaxConn > 32) _defaultMaxConn = 32;
                }),
              ),
              const SizedBox(height: 6),
              const Text(
                'Exceptions:',
                style: TextStyle(color: Color(0xFFD8D8D8), fontSize: 12),
              ),
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Container(
                      height: 100,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1A1A),
                        border: Border.all(color: const Color(0xFF3E3E3E)),
                      ),
                      child: Column(
                        children: [
                          Container(
                            height: 22,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            color: const Color(0xFF141414),
                            child: const Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Server',
                                    style: TextStyle(
                                      color: Color(0xFFD0D0D0),
                                      fontSize: 11.5,
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  width: 60,
                                  child: Text(
                                    'Number',
                                    textAlign: TextAlign.right,
                                    style: TextStyle(
                                      color: Color(0xFFD0D0D0),
                                      fontSize: 11.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: ListView.builder(
                              itemCount: _connExceptions.length,
                              itemBuilder: (_, idx) {
                                final item = _connExceptions[idx];
                                final sel = _selectedExceptionIdx == idx;
                                return InkWell(
                                  onTap: () =>
                                      setState(() => _selectedExceptionIdx = idx),
                                  child: Container(
                                    color: sel
                                        ? const Color(0xFF363636)
                                        : Colors.transparent,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            item.server,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 11.5,
                                            ),
                                          ),
                                        ),
                                        SizedBox(
                                          width: 60,
                                          child: Text(
                                            '${item.connections}',
                                            textAlign: TextAlign.right,
                                            style: const TextStyle(
                                              color: AppColors.accent,
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
                  const SizedBox(width: 8),
                  Column(
                    children: [
                      ConfigUi.button(
                        'New',
                        width: 74,
                        onPressed: () => _openExceptionDialog(),
                      ),
                      const SizedBox(height: 6),
                      ConfigUi.button(
                        'Delete',
                        width: 74,
                        onPressed: _selectedExceptionIdx != null
                            ? () => setState(() {
                                _connExceptions.removeAt(_selectedExceptionIdx!);
                                _selectedExceptionIdx = null;
                              })
                            : null,
                      ),
                      const SizedBox(height: 6),
                      ConfigUi.button(
                        'Edit',
                        width: 74,
                        onPressed: _selectedExceptionIdx != null
                            ? () => _openExceptionDialog(
                                editIndex: _selectedExceptionIdx,
                              )
                            : null,
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        ConfigUi.groupBox(
          title: 'Download limits',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ConfigUi.checkRow(
                value: _downloadLimitEnabled,
                label: 'Enable periodic download quota limit',
                onChanged: (v) => setState(() => _downloadLimitEnabled = v),
              ),
              const SizedBox(height: 4),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 6,
                children: [
                  const Text(
                    'Download no more than',
                    style: TextStyle(color: Color(0xFFD0D0D0), fontSize: 12),
                  ),
                  SizedBox(
                    width: 64,
                    child: ConfigUi.textField(
                      controller: _dlLimitMbCtrl,
                      enabled: _downloadLimitEnabled,
                    ),
                  ),
                  const Text(
                    'MBytes every',
                    style: TextStyle(color: Color(0xFFD0D0D0), fontSize: 12),
                  ),
                  SizedBox(
                    width: 48,
                    child: ConfigUi.textField(
                      controller: _dlLimitHrsCtrl,
                      enabled: _downloadLimitEnabled,
                    ),
                  ),
                  const Text(
                    'hours',
                    style: TextStyle(color: Color(0xFFD0D0D0), fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              ConfigUi.checkRow(
                value: _warnBeforeStopping,
                label: 'Show warning before stopping downloads',
                enabled: _downloadLimitEnabled,
                onChanged: (v) => setState(() => _warnBeforeStopping = v),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            const Text(
              'DNS:',
              style: TextStyle(color: Color(0xFFE0E0E0), fontSize: 12),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ConfigUi.dropdown(
                value: _dnsMode,
                items: const [
                  "The system's DNS",
                  'Cloudflare DNS (1.1.1.1)',
                  'Google DNS (8.8.8.8)',
                ],
                onChanged: (v) => setState(() => _dnsMode = v),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _openExceptionDialog({int? editIndex}) async {
    final existing = editIndex != null ? _connExceptions[editIndex] : null;
    final serverCtrl = TextEditingController(text: existing?.server ?? '');
    int connCount = existing?.connections ?? 1;

    final result = await showDialog<ConnectionException>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => Dialog(
          backgroundColor: const Color(0xFF232323),
          child: Container(
            width: 340,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFF3E3E3E)),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  existing == null ? 'New exception' : 'Edit exception',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const SizedBox(
                      width: 82,
                      child: Text(
                        'Server:',
                        style: TextStyle(color: Color(0xFFE0E0E0), fontSize: 12),
                      ),
                    ),
                    Expanded(child: ConfigUi.textField(controller: serverCtrl)),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const SizedBox(
                      width: 82,
                      child: Text(
                        'Connections:',
                        style: TextStyle(color: Color(0xFFE0E0E0), fontSize: 12),
                      ),
                    ),
                    ConfigUi.spinner(
                      value: connCount,
                      min: 1,
                      max: 32,
                      width: 78,
                      onChanged: (v) => setLocal(() => connCount = v),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    ConfigUi.button(
                      'OK',
                      primary: true,
                      width: 74,
                      onPressed: () {
                        final host = serverCtrl.text.trim();
                        if (host.isEmpty) return;
                        Navigator.of(ctx).pop(
                          ConnectionException(server: host, connections: connCount),
                        );
                      },
                    ),
                    const SizedBox(width: 8),
                    ConfigUi.button(
                      'Cancel',
                      width: 74,
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    serverCtrl.dispose();
    if (result != null && mounted) {
      setState(() {
        if (editIndex != null) {
          _connExceptions[editIndex] = result;
        } else {
          _connExceptions.add(result);
        }
      });
    }
  }

  // ── 6. REMOTE ──────────────────────────────────────────────────────────────
  Widget _buildRemoteTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ConfigUi.tabHeader(Icons.smartphone_outlined, 'Remote control'),
        ConfigUi.checkRow(
          value: _remoteEnabled,
          label: 'Let phones and computers on the local network control Download Manager',
          onChanged: (v) => setState(() => _remoteEnabled = v),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const SizedBox(
              width: 90,
              child: Text(
                'Listen on:',
                style: TextStyle(color: Color(0xFFD0D0D0), fontSize: 12),
              ),
            ),
            Expanded(
              child: ConfigUi.dropdown(
                value: _remoteListenOn,
                enabled: _remoteEnabled,
                items: const [
                  'Every local network address',
                  'Loopback only (127.0.0.1)',
                ],
                onChanged: (v) => setState(() => _remoteListenOn = v),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const SizedBox(
              width: 90,
              child: Text(
                'Port:',
                style: TextStyle(color: Color(0xFFD0D0D0), fontSize: 12),
              ),
            ),
            ConfigUi.spinner(
              value: _remotePort,
              min: 1024,
              max: 65535,
              enabled: _remoteEnabled,
              onChanged: (v) => setState(() => _remotePort = v),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ConfigUi.groupBox(
          title: 'Status',
          child: Text(
            _remoteEnabled
                ? 'Ready on port $_remotePort ($_remoteListenOn).'
                : 'Off: nothing on the network can reach Download Manager.',
            style: const TextStyle(color: Color(0xFFD0D0D0), fontSize: 12),
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Paired devices:',
          style: TextStyle(color: Color(0xFFE0E0E0), fontSize: 12),
        ),
        const SizedBox(height: 6),
        Container(
          height: 88,
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            border: Border.all(color: const Color(0xFF3E3E3E)),
          ),
          child: Column(
            children: [
              Container(
                height: 22,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                color: const Color(0xFF141414),
                child: const Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Device',
                        style: TextStyle(color: Color(0xFFD0D0D0), fontSize: 11.5),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        'Paired',
                        style: TextStyle(color: Color(0xFFD0D0D0), fontSize: 11.5),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        'Last seen',
                        style: TextStyle(color: Color(0xFFD0D0D0), fontSize: 11.5),
                      ),
                    ),
                  ],
                ),
              ),
              const Expanded(
                child: Center(
                  child: Text(
                    'No paired devices',
                    style: TextStyle(color: Color(0xFF7A7A7A), fontSize: 11.5),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── 7. PROXY / SOCKS ───────────────────────────────────────────────────────
  Widget _buildProxyTab() {
    final isManual = _proxyMode == 'manual';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ConfigUi.tabHeader(Icons.shield_outlined, 'Proxy / socks configuration'),
        ConfigUi.checkRow(
          value: _useBrowserProxyOnError,
          label:
              "Use proxy/socks from a browser's request if there are download errors",
          onChanged: (v) => setState(() => _useBrowserProxyOnError = v),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 6),
          child: Divider(height: 1, color: Color(0xFF3E3E3E)),
        ),
        ConfigUi.radioRow<String>(
          value: 'none',
          groupValue: _proxyMode,
          label: 'No proxy/socks',
          onChanged: (v) => setState(() => _proxyMode = v),
        ),
        ConfigUi.radioRow<String>(
          value: 'system',
          groupValue: _proxyMode,
          label: 'Use system settings',
          onChanged: (v) => setState(() => _proxyMode = v),
        ),
        ConfigUi.radioRow<String>(
          value: 'pac',
          groupValue: _proxyMode,
          label: 'Use automatic configuration script',
          onChanged: (v) => setState(() => _proxyMode = v),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 22, top: 4, bottom: 6),
          child: Row(
            children: [
              const SizedBox(
                width: 60,
                child: Text(
                  'Address',
                  style: TextStyle(color: Color(0xFFB8B8B8), fontSize: 12),
                ),
              ),
              Expanded(
                child: ConfigUi.textField(
                  controller: _pacCtrl,
                  enabled: _proxyMode == 'pac',
                ),
              ),
            ],
          ),
        ),
        ConfigUi.radioRow<String>(
          value: 'manual',
          groupValue: _proxyMode,
          label: 'Manual proxy/socks configuration',
          onChanged: (v) => setState(() => _proxyMode = v),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 22, top: 6),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Proxy server address',
                          style: TextStyle(color: Color(0xFFB0B0B0), fontSize: 11),
                        ),
                        const SizedBox(height: 3),
                        ConfigUi.textField(
                          controller: _proxyHostCtrl,
                          enabled: isManual,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    flex: 1,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Port',
                          style: TextStyle(color: Color(0xFFB0B0B0), fontSize: 11),
                        ),
                        const SizedBox(height: 3),
                        ConfigUi.textField(
                          controller: _proxyPortCtrl,
                          enabled: isManual,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'UserName',
                          style: TextStyle(color: Color(0xFFB0B0B0), fontSize: 11),
                        ),
                        const SizedBox(height: 3),
                        ConfigUi.textField(
                          controller: _proxyUserCtrl,
                          enabled: isManual,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Password',
                          style: TextStyle(color: Color(0xFFB0B0B0), fontSize: 11),
                        ),
                        const SizedBox(height: 3),
                        ConfigUi.textField(
                          controller: _proxyPassCtrl,
                          enabled: isManual,
                          obscure: true,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: ConfigUi.checkRow(
                      value: _proxyHttp,
                      label: 'http',
                      enabled: isManual,
                      onChanged: (v) => setState(() => _proxyHttp = v),
                    ),
                  ),
                  Expanded(
                    child: ConfigUi.checkRow(
                      value: _proxyHttps,
                      label: 'https',
                      enabled: isManual,
                      onChanged: (v) => setState(() => _proxyHttps = v),
                    ),
                  ),
                  Expanded(
                    child: ConfigUi.checkRow(
                      value: _proxyFtp,
                      label: 'ftp',
                      enabled: isManual,
                      onChanged: (v) => setState(() => _proxyFtp = v),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Divider(height: 1, color: Color(0xFF3E3E3E)),
        ),
        Row(
          children: [
            const Text(
              'Network adapter:',
              style: TextStyle(color: Color(0xFFE0E0E0), fontSize: 12),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ConfigUi.dropdown(
                value: _networkAdapter,
                items: const ['Any (the system chooses)'],
                onChanged: (v) => setState(() => _networkAdapter = v),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ConfigUi.checkRow(
          value: _useFtpPasv,
          label: 'Use FTP in PASV mode',
          onChanged: (v) => setState(() => _useFtpPasv = v),
        ),
      ],
    );
  }

  // ── 8. SITES LOGINS ────────────────────────────────────────────────────────
  Widget _buildSitesLoginsTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ConfigUi.tabHeader(Icons.key_outlined, 'User names and passwords for servers/sites'),
        Container(
          height: 145,
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            border: Border.all(color: const Color(0xFF3E3E3E)),
          ),
          child: Column(
            children: [
              Container(
                height: 24,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                color: const Color(0xFF141414),
                child: const Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Text(
                        'Site/path',
                        style: TextStyle(color: Color(0xFFD0D0D0), fontSize: 11.5),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        'User',
                        style: TextStyle(color: Color(0xFFD0D0D0), fontSize: 11.5),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        'Password',
                        style: TextStyle(color: Color(0xFFD0D0D0), fontSize: 11.5),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: _siteLogins.length,
                  itemBuilder: (_, idx) {
                    final item = _siteLogins[idx];
                    final sel = _selectedLoginIdx == idx;
                    return InkWell(
                      onTap: () => setState(() => _selectedLoginIdx = idx),
                      child: Container(
                        color: sel ? const Color(0xFF363636) : Colors.transparent,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 5,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: Text(
                                item.sitePath,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11.5,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                item.username,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFFD0D0D0),
                                  fontSize: 11.5,
                                ),
                              ),
                            ),
                            const Expanded(
                              flex: 2,
                              child: Text(
                                '••••••••',
                                style: TextStyle(
                                  color: Color(0xFF909090),
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
        const SizedBox(height: 8),
        Row(
          children: [
            ConfigUi.button('New', width: 88, onPressed: _addSiteLogin),
            const SizedBox(width: 8),
            ConfigUi.button(
              'Remove',
              width: 88,
              onPressed: _selectedLoginIdx != null
                  ? () => setState(() {
                      _siteLogins.removeAt(_selectedLoginIdx!);
                      _selectedLoginIdx = null;
                    })
                  : null,
            ),
          ],
        ),
        const SizedBox(height: 12),
        ConfigUi.groupBox(
          title: 'Cookies for video sites',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ConfigUi.radioRow<String>(
                value: 'off',
                groupValue: _videoCookiesMode,
                label: 'Off',
                onChanged: (v) => setState(() => _videoCookiesMode = v),
              ),
              Row(
                children: [
                  SizedBox(
                    width: 130,
                    child: ConfigUi.radioRow<String>(
                      value: 'browser',
                      groupValue: _videoCookiesMode,
                      label: 'From browser:',
                      onChanged: (v) => setState(() => _videoCookiesMode = v),
                    ),
                  ),
                  Expanded(
                    child: ConfigUi.dropdown(
                      value: _videoCookiesBrowser,
                      enabled: _videoCookiesMode == 'browser',
                      items: const ['Firefox', 'Google Chrome', 'Microsoft Edge', 'Brave'],
                      onChanged: (v) => setState(() => _videoCookiesBrowser = v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  const SizedBox(
                    width: 130,
                    child: Text(
                      'Profile (optional):',
                      style: TextStyle(color: Color(0xFFB8B8B8), fontSize: 12),
                    ),
                  ),
                  Expanded(
                    child: ConfigUi.textField(
                      controller: _videoProfileCtrl,
                      enabled: _videoCookiesMode == 'browser',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _addSiteLogin() async {
    final siteCtrl = TextEditingController();
    final userCtrl = TextEditingController();
    final passCtrl = TextEditingController();

    final entry = await showDialog<SiteLoginEntry>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF232323),
        child: Container(
          width: 360,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFF3E3E3E)),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Add Site Login',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              ConfigUi.textField(controller: siteCtrl, hint: 'https://example.com'),
              const SizedBox(height: 8),
              ConfigUi.textField(controller: userCtrl, hint: 'Username'),
              const SizedBox(height: 8),
              ConfigUi.textField(
                controller: passCtrl,
                hint: 'Password',
                obscure: true,
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  ConfigUi.button(
                    'OK',
                    primary: true,
                    width: 74,
                    onPressed: () {
                      if (siteCtrl.text.trim().isEmpty) return;
                      Navigator.of(ctx).pop(
                        SiteLoginEntry(
                          sitePath: siteCtrl.text.trim(),
                          username: userCtrl.text.trim(),
                          password: passCtrl.text,
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 8),
                  ConfigUi.button(
                    'Cancel',
                    width: 74,
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    siteCtrl.dispose();
    userCtrl.dispose();
    passCtrl.dispose();
    if (entry != null && mounted) {
      setState(() => _siteLogins.add(entry));
    }
  }

  // ── 9. ACCOUNTS (DEBRID) ───────────────────────────────────────────────────
  Widget _buildAccountsTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ConfigUi.tabHeader(Icons.vpn_key_outlined, 'Debrid service accounts'),
        Container(
          height: 135,
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            border: Border.all(color: const Color(0xFF3E3E3E)),
          ),
          child: Column(
            children: [
              Container(
                height: 24,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                color: const Color(0xFF141414),
                child: const Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Service',
                        style: TextStyle(color: Color(0xFFD0D0D0), fontSize: 11.5),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        'Account',
                        style: TextStyle(color: Color(0xFFD0D0D0), fontSize: 11.5),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        'State',
                        style: TextStyle(color: Color(0xFFD0D0D0), fontSize: 11.5),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: _debridAccounts.length,
                  itemBuilder: (_, idx) {
                    final item = _debridAccounts[idx];
                    final sel = _selectedAccountIdx == idx;
                    return InkWell(
                      onTap: () => setState(() => _selectedAccountIdx = idx),
                      child: Container(
                        color: sel ? const Color(0xFF363636) : Colors.transparent,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 5,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                item.service,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11.5,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                item.account,
                                style: const TextStyle(
                                  color: Color(0xFFD0D0D0),
                                  fontSize: 11.5,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                item.state,
                                style: const TextStyle(
                                  color: AppColors.accent,
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
        const SizedBox(height: 8),
        Row(
          children: [
            ConfigUi.button('Add...', width: 82, onPressed: _addDebridAccount),
            const SizedBox(width: 6),
            ConfigUi.button(
              'Remove',
              width: 82,
              onPressed: _selectedAccountIdx != null
                  ? () => setState(() {
                      _debridAccounts.removeAt(_selectedAccountIdx!);
                      _selectedAccountIdx = null;
                    })
                  : null,
            ),
          ],
        ),
        const SizedBox(height: 12),
        ConfigUi.checkRow(
          value: _useDebridFileHosts,
          label: 'Download supported file-host links through these accounts',
          onChanged: (v) => setState(() => _useDebridFileHosts = v),
        ),
        ConfigUi.checkRow(
          value: _sendTorrentsDebrid,
          label: 'Send torrents and magnet links to the first account instead of to peers',
          onChanged: (v) => setState(() => _sendTorrentsDebrid = v),
        ),
      ],
    );
  }

  Future<void> _addDebridAccount() async {
    String service = 'Real-Debrid';
    final acctCtrl = TextEditingController();
    final entry = await showDialog<DebridAccountEntry>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => Dialog(
          backgroundColor: const Color(0xFF232323),
          child: Container(
            width: 340,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFF3E3E3E)),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Add Debrid Account',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                ConfigUi.dropdown(
                  value: service,
                  items: const ['Real-Debrid', 'AllDebrid', 'Premiumize'],
                  onChanged: (v) => setLocal(() => service = v),
                ),
                const SizedBox(height: 8),
                ConfigUi.textField(
                  controller: acctCtrl,
                  hint: 'Account email or API label',
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    ConfigUi.button(
                      'OK',
                      primary: true,
                      width: 74,
                      onPressed: () {
                        if (acctCtrl.text.trim().isEmpty) return;
                        Navigator.of(ctx).pop(
                          DebridAccountEntry(
                            service: service,
                            account: acctCtrl.text.trim(),
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 8),
                    ConfigUi.button(
                      'Cancel',
                      width: 74,
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    acctCtrl.dispose();
    if (entry != null && mounted) {
      setState(() => _debridAccounts.add(entry));
    }
  }

  // ── 10. SOUNDS ─────────────────────────────────────────────────────────────
  Widget _buildSoundsTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ConfigUi.tabHeader(Icons.volume_up_outlined, 'Sound settings'),
        ConfigUi.groupBox(
          title: 'Select sounds for Download Manager events',
          child: Column(
            children: [
              Container(
                height: 220,
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  border: Border.all(color: const Color(0xFF3E3E3E)),
                ),
                child: Column(
                  children: [
                    Container(
                      height: 24,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      color: const Color(0xFF141414),
                      child: const Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: Text(
                              'Event',
                              style: TextStyle(
                                color: Color(0xFFD0D0D0),
                                fontSize: 11.5,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: Text(
                              'Sound file',
                              style: TextStyle(
                                color: Color(0xFFD0D0D0),
                                fontSize: 11.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _soundEvents.length,
                        itemBuilder: (_, idx) {
                          final item = _soundEvents[idx];
                          final sel = _selectedSoundIdx == idx;
                          return InkWell(
                            onTap: () =>
                                setState(() => _selectedSoundIdx = idx),
                            child: Container(
                              color: sel
                                  ? const Color(0xFF363636)
                                  : Colors.transparent,
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
                                      value: item.enabled,
                                      activeColor: AppColors.accent,
                                      checkColor: Colors.black,
                                      onChanged: (v) => setState(() {
                                        _soundEvents[idx] = item.copyWith(
                                          enabled: v ?? false,
                                        );
                                      }),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    flex: 3,
                                    child: Text(
                                      item.event,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11.5,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 3,
                                    child: Text(
                                      item.soundFile,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Color(0xFFA0A0A0),
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
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ConfigUi.button(
                    'Browse...',
                    width: 96,
                    onPressed: _selectedSoundIdx != null
                        ? () async {
                            final picked = await FilePicker.pickFiles(
                              type: FileType.custom,
                              allowedExtensions: const ['wav', 'mp3', 'ogg'],
                            );
                            if (picked.isNotEmpty &&
                                picked.single.path != null &&
                                mounted) {
                              final idx = _selectedSoundIdx!;
                              setState(() {
                                _soundEvents[idx] = _soundEvents[idx].copyWith(
                                  enabled: true,
                                  soundFile: picked.single.path,
                                );
                              });
                            }
                          }
                        : null,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── 11. REGIONAL ───────────────────────────────────────────────────────────
  Widget _buildRegionalTab() {
    final custom = !_useSystemRegion;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ConfigUi.tabHeader(Icons.calendar_month_outlined, 'Dates and times'),
        ConfigUi.groupBox(
          title: 'Write dates and times',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ConfigUi.radioRow<bool>(
                value: true,
                groupValue: _useSystemRegion,
                label: "As the system's region writes them",
                onChanged: (v) => setState(() => _useSystemRegion = v),
              ),
              ConfigUi.radioRow<bool>(
                value: false,
                groupValue: _useSystemRegion,
                label: 'My own way:',
                onChanged: (v) => setState(() => _useSystemRegion = v),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(left: 24),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const SizedBox(
                          width: 118,
                          child: Text(
                            'Date order:',
                            style: TextStyle(color: Color(0xFFB8B8B8), fontSize: 12),
                          ),
                        ),
                        Expanded(
                          child: ConfigUi.dropdown(
                            value: _dateOrder,
                            enabled: custom,
                            items: const [
                              'Day, month, year',
                              'Month, day, year',
                              'Year, month, day',
                            ],
                            onChanged: (v) => setState(() => _dateOrder = v),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const SizedBox(
                          width: 118,
                          child: Text(
                            'Clock:',
                            style: TextStyle(color: Color(0xFFB8B8B8), fontSize: 12),
                          ),
                        ),
                        Expanded(
                          child: ConfigUi.dropdown(
                            value: _clockFormat,
                            enabled: custom,
                            items: const ['12-hour (9:41 PM)', '24-hour (21:41)'],
                            onChanged: (v) => setState(() => _clockFormat = v),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const SizedBox(
                          width: 118,
                          child: Text(
                            'First day of the week:',
                            style: TextStyle(color: Color(0xFFB8B8B8), fontSize: 12),
                          ),
                        ),
                        Expanded(
                          child: ConfigUi.dropdown(
                            value: _firstDayOfWeek,
                            enabled: custom,
                            items: const ['Saturday', 'Sunday', 'Monday'],
                            onChanged: (v) => setState(() => _firstDayOfWeek = v),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Example:  ${_formatExampleDate()}',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
              const SizedBox(height: 6),
              const Text(
                'Used by the list of downloads and the Scheduler.',
                style: TextStyle(color: Color(0xFF9E9E9E), fontSize: 11.5),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatExampleDate() {
    final now = DateTime.now();
    final d = now.day.toString().padLeft(2, '0');
    final m = now.month.toString().padLeft(2, '0');
    final y = now.year.toString();
    final datePart = switch (_dateOrder) {
      'Month, day, year' => '$m/$d/$y',
      'Year, month, day' => '$y-$m-$d',
      _ => '$d/$m/$y',
    };
    final min = now.minute.toString().padLeft(2, '0');
    final sec = now.second.toString().padLeft(2, '0');
    if (_clockFormat.startsWith('24')) {
      final h = now.hour.toString().padLeft(2, '0');
      return '$datePart $h:$min:$sec';
    }
    final h12 = now.hour % 12 == 0 ? 12 : now.hour % 12;
    final ampm = now.hour >= 12 ? 'PM' : 'AM';
    return '$datePart $h12:$min:$sec $ampm';
  }

  // ── 12. ARCHIVES & LINK GRABBER ────────────────────────────────────────────
  Widget _buildArchivesTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ConfigUi.tabHeader(Icons.inventory_2_outlined, 'Archives and Link grabber'),
        ConfigUi.groupBox(
          title: 'Archives',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ConfigUi.checkRow(
                value: _extractArchives,
                label: 'Extract archives when their download completes',
                onChanged: (v) => setState(() => _extractArchives = v),
              ),
              ConfigUi.checkRow(
                value: _moveArchivesBin,
                label: 'Then move the archives to the Recycle Bin',
                enabled: _extractArchives,
                onChanged: (v) => setState(() => _moveArchivesBin = v),
              ),
              const SizedBox(height: 8),
              const Text(
                'What an archive holds goes:',
                style: TextStyle(color: Color(0xFFE0E0E0), fontSize: 12),
              ),
              const SizedBox(height: 5),
              ConfigUi.dropdown(
                value: _archiveTarget,
                enabled: _extractArchives,
                items: const [
                  'Into a folder named after it, when it holds several things',
                  'Always into a folder named after the archive',
                  'Directly next to the archive',
                ],
                onChanged: (v) => setState(() => _archiveTarget = v),
              ),
              const SizedBox(height: 8),
              const Text(
                'ZIP, 7Z, RAR, TAR, GZ and XZ; a split archive (.part1.rar, .7z.001) once every volume is in.',
                style: TextStyle(color: Color(0xFFA0A0A0), fontSize: 11.5),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        ConfigUi.groupBox(
          title: 'Link grabber',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ConfigUi.checkRow(
                value: _linkGrabberLookup,
                label: 'Look links up when they arrive (name, size, online)',
                onChanged: (v) => setState(() => _linkGrabberLookup = v),
              ),
              ConfigUi.checkRow(
                value: _linkGrabberHideWeb,
                label: 'Hide web pages',
                onChanged: (v) => setState(() => _linkGrabberHideWeb = v),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
