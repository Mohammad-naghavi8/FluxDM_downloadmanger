class ConnectionException {
  final String server;
  final int connections;

  const ConnectionException({required this.server, required this.connections});

  Map<String, dynamic> toJson() => {
    'server': server,
    'connections': connections,
  };

  factory ConnectionException.fromJson(Map<String, dynamic> json) {
    return ConnectionException(
      server: json['server']?.toString() ?? '',
      connections: (json['connections'] as num?)?.toInt() ?? 1,
    );
  }
}

class SiteLoginEntry {
  final String sitePath;
  final String username;
  final String password;

  const SiteLoginEntry({
    required this.sitePath,
    required this.username,
    required this.password,
  });

  Map<String, dynamic> toJson() => {
    'sitePath': sitePath,
    'username': username,
    'password': password,
  };

  factory SiteLoginEntry.fromJson(Map<String, dynamic> json) {
    return SiteLoginEntry(
      sitePath: json['sitePath']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      password: json['password']?.toString() ?? '',
    );
  }
}

class DebridAccountEntry {
  final String service;
  final String account;
  final String state;

  const DebridAccountEntry({
    required this.service,
    required this.account,
    this.state = 'Active',
  });

  Map<String, dynamic> toJson() => {
    'service': service,
    'account': account,
    'state': state,
  };

  factory DebridAccountEntry.fromJson(Map<String, dynamic> json) {
    return DebridAccountEntry(
      service: json['service']?.toString() ?? '',
      account: json['account']?.toString() ?? '',
      state: json['state']?.toString() ?? 'Active',
    );
  }
}

class SoundEventSetting {
  final String event;
  final bool enabled;
  final String soundFile;

  const SoundEventSetting({
    required this.event,
    this.enabled = false,
    this.soundFile = '',
  });

  SoundEventSetting copyWith({bool? enabled, String? soundFile}) {
    return SoundEventSetting(
      event: event,
      enabled: enabled ?? this.enabled,
      soundFile: soundFile ?? this.soundFile,
    );
  }

  Map<String, dynamic> toJson() => {
    'event': event,
    'enabled': enabled,
    'soundFile': soundFile,
  };

  factory SoundEventSetting.fromJson(Map<String, dynamic> json) {
    return SoundEventSetting(
      event: json['event']?.toString() ?? '',
      enabled: json['enabled'] == true,
      soundFile: json['soundFile']?.toString() ?? '',
    );
  }
}

class AppSettings {
  static const String defaultFileTypes =
      '00* 3DM 3DS 3GP 3MF 7Z AAB AAC ABC ACE AFDESIGN AFPHOTO AI AIF AIFF APE APK APKM APKS APPIMAGE APPX APPXBUNDLE ARJ ARROW ARW ASF AU AVI AVRO AZW AZW3 BAK BAM BIN BLEND BZ BZ2 C4D CAB CAF CBR CBZ CCD CHD CKPT CPIO CR2 CR3 CRAM CSO DAE DAT DCM DDS DEB DFF DIVX DJVU DMG DNG DOC DOCX DSF DWG DXF EPS EPUB EXE EXR F3D F4V FASTA FASTQ FB2 FBX FEATHER FIG FITS FLAC FLATPAK FQ GCODE GCZ GEM GGML GGUF GLB GLTF GPKG GRIB GRIB2 GZ GZIP H5 HDF5 HDR IGES IGS IMG INDD IPA ISO ISZ JAR JOBLIB JSONL KERAS KRA LAS LAZ LLAMAFILE LWO LZ LZ4 LZH LZMA M2T M2TS M2V M4A M4B M4V MA MAT MAX MB MBTILES MDF MDS MID MIDI MKA MKV MLMODEL MOBI MOV MP3 MP4 MPA MPE MPEG MPG MSI MSIX MSIXBUNDLE MSP MSU MTS MXF NC NDJSON NEF NEMO NII NPY NPZ NRG NSP NSZ NUPKG OBJ ODP ODS ODT OGG OGM OGV ONNX OPUS ORC ORF OTF OVA OVF PAK PARQUET PB PBF PDF PICKLE PK3 PK4 PKG PKL PLJ PLY POTX PPS PPSX PPT PPTX PSB PSD PT PTH QCOW QCOW2 QT R0* R1* R2* R3* R4* R5* R6* R7* R8* R9* RA RAF RAR RDS RM RMVB RPM RTF RUN RVZ RW2 SAFETENSORS SEA SF2 SFZ SHP SIT SITX SKETCH SKP SLDASM SLDPRT SNAP SQLITE SQLITE3 STEP STL STP TAR TBZ TBZ2 TFLITE TGA TGZ TIF TIFF TLZ TORRENT TTA TTC TTF TXZ TZST UNITYPACKAGE USD USDA USDC USDZ VDB VDI VHD VHDX VMDK VOB VPK VSIX WAV WBFS WEBM WHL WIM WMA WMV WRL WTV WUA WV X3D XAPK XCF XCI XLS XLSB XLSM XLSX XZ Z Z0* ZIP ZIPX ZPR ZST ZTL';
  static const String defaultExcludedSites =
      '*.update.microsoft.com download.windowsupdate.com *.download.windowsupdate.com siteseal.thawte.com ecom.cimetz.com *.voice2page.com';
  static const List<String> defaultBrowsers = [
    'Apple Safari',
    'Brave Browser',
    'Floorp',
    'Google Chrome',
    'Microsoft Edge',
    'Mozilla Firefox',
    'Opera',
    'Vivaldi',
  ];

  // 1. General
  final bool launchOnStartup;
  final bool offerClipboardDownloads;
  final bool useAdvancedBrowserIntegration;
  final bool confirmBeforeDeleting;
  final bool minimizeToTray;
  final bool keepRunningOnClose;
  final List<String> enabledBrowsers;

  // 2. File types
  final String autoDownloadFileTypes;
  final String excludedSites;
  final List<String> excludedAddresses;
  final int minFileSizeKB;

  // 3. Save to
  final bool rememberCategoryFolder;
  final bool setServerFileCreationDate;

  // 4. Downloads
  final bool showStartDownloadDialog;
  final bool addOnlyToQueueWhenDialogHidden;
  final bool showDownloadCompleteDialog;
  final bool startImmediatelyWhileInfoShown;
  final bool showQueuePanelOnDownloadLater;
  final bool showQueuePanelOnBatchClose;
  final bool ignoreFileModTimeOnResume;
  final String duplicateLinkAction;
  final String manualUserAgent;

  // 5. Connection
  final int defaultMaxConnections;
  final bool allowMoreThan32Connections;
  final List<ConnectionException> connectionExceptions;
  final bool downloadLimitEnabled;
  final int downloadLimitMB;
  final int downloadLimitHours;
  final bool showWarningBeforeStopping;
  final String dnsMode;

  // 6. Remote
  final bool remoteControlEnabled;
  final String remoteListenOn;
  final int remotePort;

  // 7. Proxy / Socks
  final bool useBrowserProxyOnError;
  final String proxyMode; // none, system, pac, manual
  final String pacAddress;
  final String proxyServer;
  final String proxyPort;
  final String proxyUsername;
  final String proxyPassword;
  final bool proxyHttp;
  final bool proxyHttps;
  final bool proxyFtp;
  final String networkAdapter;
  final bool useFtpPasv;

  // 8. Sites Logins
  final List<SiteLoginEntry> siteLogins;
  final String videoCookiesMode; // off, browser
  final String videoCookiesBrowser;
  final String videoCookiesProfile;

  // 9. Accounts (Debrid)
  final List<DebridAccountEntry> debridAccounts;
  final bool useDebridForFileHosts;
  final bool sendTorrentsToDebrid;

  // 10. Sounds
  final List<SoundEventSetting> soundEvents;

  // 11. Regional
  final bool useSystemRegionFormat;
  final String dateOrder;
  final String clockFormat;
  final String firstDayOfWeek;

  // 12. Archives & Link grabber
  final bool extractArchivesOnComplete;
  final bool moveArchivesToRecycleBin;
  final String archiveExtractTarget;
  final bool linkGrabberLookupOnArrive;
  final bool linkGrabberHideWebPages;

  const AppSettings({
    this.launchOnStartup = true,
    this.offerClipboardDownloads = true,
    this.useAdvancedBrowserIntegration = true,
    this.confirmBeforeDeleting = true,
    this.minimizeToTray = true,
    this.keepRunningOnClose = true,
    this.enabledBrowsers = const [
      'Apple Safari',
      'Brave Browser',
      'Floorp',
      'Google Chrome',
      'Microsoft Edge',
      'Mozilla Firefox',
    ],
    this.autoDownloadFileTypes = defaultFileTypes,
    this.excludedSites = defaultExcludedSites,
    this.excludedAddresses = const [],
    this.minFileSizeKB = 0,
    this.rememberCategoryFolder = true,
    this.setServerFileCreationDate = false,
    this.showStartDownloadDialog = true,
    this.addOnlyToQueueWhenDialogHidden = false,
    this.showDownloadCompleteDialog = true,
    this.startImmediatelyWhileInfoShown = false,
    this.showQueuePanelOnDownloadLater = true,
    this.showQueuePanelOnBatchClose = true,
    this.ignoreFileModTimeOnResume = false,
    this.duplicateLinkAction = 'Show a dialog and ask what to do.',
    this.manualUserAgent =
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
    this.defaultMaxConnections = 8,
    this.allowMoreThan32Connections = false,
    this.connectionExceptions = const [],
    this.downloadLimitEnabled = false,
    this.downloadLimitMB = 200,
    this.downloadLimitHours = 5,
    this.showWarningBeforeStopping = true,
    this.dnsMode = "The system's DNS",
    this.remoteControlEnabled = false,
    this.remoteListenOn = 'Every local network address',
    this.remotePort = 8463,
    this.useBrowserProxyOnError = true,
    this.proxyMode = 'none',
    this.pacAddress = '',
    this.proxyServer = '',
    this.proxyPort = '',
    this.proxyUsername = '',
    this.proxyPassword = '',
    this.proxyHttp = false,
    this.proxyHttps = false,
    this.proxyFtp = false,
    this.networkAdapter = 'Any (the system chooses)',
    this.useFtpPasv = true,
    this.siteLogins = const [],
    this.videoCookiesMode = 'off',
    this.videoCookiesBrowser = 'Firefox',
    this.videoCookiesProfile = '',
    this.debridAccounts = const [],
    this.useDebridForFileHosts = true,
    this.sendTorrentsToDebrid = false,
    this.soundEvents = const [
      SoundEventSetting(event: 'Download complete'),
      SoundEventSetting(event: 'Download failed'),
      SoundEventSetting(event: 'Queue processing started'),
      SoundEventSetting(event: 'Queue processing stopped/finished'),
    ],
    this.useSystemRegionFormat = true,
    this.dateOrder = 'Day, month, year',
    this.clockFormat = '12-hour (9:41 PM)',
    this.firstDayOfWeek = 'Saturday',
    this.extractArchivesOnComplete = false,
    this.moveArchivesToRecycleBin = false,
    this.archiveExtractTarget =
        'Into a folder named after it, when it holds several things',
    this.linkGrabberLookupOnArrive = true,
    this.linkGrabberHideWebPages = true,
  });

  Map<String, dynamic> toJson() => {
    'launchOnStartup': launchOnStartup,
    'offerClipboardDownloads': offerClipboardDownloads,
    'useAdvancedBrowserIntegration': useAdvancedBrowserIntegration,
    'confirmBeforeDeleting': confirmBeforeDeleting,
    'minimizeToTray': minimizeToTray,
    'keepRunningOnClose': keepRunningOnClose,
    'enabledBrowsers': enabledBrowsers,
    'autoDownloadFileTypes': autoDownloadFileTypes,
    'excludedSites': excludedSites,
    'excludedAddresses': excludedAddresses,
    'minFileSizeKB': minFileSizeKB,
    'rememberCategoryFolder': rememberCategoryFolder,
    'setServerFileCreationDate': setServerFileCreationDate,
    'showStartDownloadDialog': showStartDownloadDialog,
    'addOnlyToQueueWhenDialogHidden': addOnlyToQueueWhenDialogHidden,
    'showDownloadCompleteDialog': showDownloadCompleteDialog,
    'startImmediatelyWhileInfoShown': startImmediatelyWhileInfoShown,
    'showQueuePanelOnDownloadLater': showQueuePanelOnDownloadLater,
    'showQueuePanelOnBatchClose': showQueuePanelOnBatchClose,
    'ignoreFileModTimeOnResume': ignoreFileModTimeOnResume,
    'duplicateLinkAction': duplicateLinkAction,
    'manualUserAgent': manualUserAgent,
    'defaultMaxConnections': defaultMaxConnections,
    'allowMoreThan32Connections': allowMoreThan32Connections,
    'connectionExceptions': connectionExceptions.map((e) => e.toJson()).toList(),
    'downloadLimitEnabled': downloadLimitEnabled,
    'downloadLimitMB': downloadLimitMB,
    'downloadLimitHours': downloadLimitHours,
    'showWarningBeforeStopping': showWarningBeforeStopping,
    'dnsMode': dnsMode,
    'remoteControlEnabled': remoteControlEnabled,
    'remoteListenOn': remoteListenOn,
    'remotePort': remotePort,
    'useBrowserProxyOnError': useBrowserProxyOnError,
    'proxyMode': proxyMode,
    'pacAddress': pacAddress,
    'proxyServer': proxyServer,
    'proxyPort': proxyPort,
    'proxyUsername': proxyUsername,
    'proxyPassword': proxyPassword,
    'proxyHttp': proxyHttp,
    'proxyHttps': proxyHttps,
    'proxyFtp': proxyFtp,
    'networkAdapter': networkAdapter,
    'useFtpPasv': useFtpPasv,
    'siteLogins': siteLogins.map((e) => e.toJson()).toList(),
    'videoCookiesMode': videoCookiesMode,
    'videoCookiesBrowser': videoCookiesBrowser,
    'videoCookiesProfile': videoCookiesProfile,
    'debridAccounts': debridAccounts.map((e) => e.toJson()).toList(),
    'useDebridForFileHosts': useDebridForFileHosts,
    'sendTorrentsToDebrid': sendTorrentsToDebrid,
    'soundEvents': soundEvents.map((e) => e.toJson()).toList(),
    'useSystemRegionFormat': useSystemRegionFormat,
    'dateOrder': dateOrder,
    'clockFormat': clockFormat,
    'firstDayOfWeek': firstDayOfWeek,
    'extractArchivesOnComplete': extractArchivesOnComplete,
    'moveArchivesToRecycleBin': moveArchivesToRecycleBin,
    'archiveExtractTarget': archiveExtractTarget,
    'linkGrabberLookupOnArrive': linkGrabberLookupOnArrive,
    'linkGrabberHideWebPages': linkGrabberHideWebPages,
  };

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    const d = AppSettings();
    final rawSounds = json['soundEvents'] as List<dynamic>?;
    return AppSettings(
      launchOnStartup: json['launchOnStartup'] as bool? ?? d.launchOnStartup,
      offerClipboardDownloads:
          json['offerClipboardDownloads'] as bool? ?? d.offerClipboardDownloads,
      useAdvancedBrowserIntegration:
          json['useAdvancedBrowserIntegration'] as bool? ??
          d.useAdvancedBrowserIntegration,
      confirmBeforeDeleting:
          json['confirmBeforeDeleting'] as bool? ?? d.confirmBeforeDeleting,
      minimizeToTray: json['minimizeToTray'] as bool? ?? d.minimizeToTray,
      keepRunningOnClose:
          json['keepRunningOnClose'] as bool? ?? d.keepRunningOnClose,
      enabledBrowsers: (json['enabledBrowsers'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          d.enabledBrowsers,
      autoDownloadFileTypes:
          json['autoDownloadFileTypes']?.toString() ?? d.autoDownloadFileTypes,
      excludedSites: json['excludedSites']?.toString() ?? d.excludedSites,
      excludedAddresses: (json['excludedAddresses'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          d.excludedAddresses,
      minFileSizeKB: (json['minFileSizeKB'] as num?)?.toInt() ?? d.minFileSizeKB,
      rememberCategoryFolder:
          json['rememberCategoryFolder'] as bool? ?? d.rememberCategoryFolder,
      setServerFileCreationDate:
          json['setServerFileCreationDate'] as bool? ??
          d.setServerFileCreationDate,
      showStartDownloadDialog:
          json['showStartDownloadDialog'] as bool? ?? d.showStartDownloadDialog,
      addOnlyToQueueWhenDialogHidden:
          json['addOnlyToQueueWhenDialogHidden'] as bool? ??
          d.addOnlyToQueueWhenDialogHidden,
      showDownloadCompleteDialog:
          json['showDownloadCompleteDialog'] as bool? ??
          d.showDownloadCompleteDialog,
      startImmediatelyWhileInfoShown:
          json['startImmediatelyWhileInfoShown'] as bool? ??
          d.startImmediatelyWhileInfoShown,
      showQueuePanelOnDownloadLater:
          json['showQueuePanelOnDownloadLater'] as bool? ??
          d.showQueuePanelOnDownloadLater,
      showQueuePanelOnBatchClose:
          json['showQueuePanelOnBatchClose'] as bool? ??
          d.showQueuePanelOnBatchClose,
      ignoreFileModTimeOnResume:
          json['ignoreFileModTimeOnResume'] as bool? ??
          d.ignoreFileModTimeOnResume,
      duplicateLinkAction:
          json['duplicateLinkAction']?.toString() ?? d.duplicateLinkAction,
      manualUserAgent: json['manualUserAgent']?.toString() ?? d.manualUserAgent,
      defaultMaxConnections:
          (json['defaultMaxConnections'] as num?)?.toInt() ??
          d.defaultMaxConnections,
      allowMoreThan32Connections:
          json['allowMoreThan32Connections'] as bool? ??
          d.allowMoreThan32Connections,
      connectionExceptions: (json['connectionExceptions'] as List<dynamic>?)
              ?.map(
                (e) => ConnectionException.fromJson(e as Map<String, dynamic>),
              )
              .toList() ??
          d.connectionExceptions,
      downloadLimitEnabled:
          json['downloadLimitEnabled'] as bool? ?? d.downloadLimitEnabled,
      downloadLimitMB:
          (json['downloadLimitMB'] as num?)?.toInt() ?? d.downloadLimitMB,
      downloadLimitHours:
          (json['downloadLimitHours'] as num?)?.toInt() ?? d.downloadLimitHours,
      showWarningBeforeStopping:
          json['showWarningBeforeStopping'] as bool? ??
          d.showWarningBeforeStopping,
      dnsMode: json['dnsMode']?.toString() ?? d.dnsMode,
      remoteControlEnabled:
          json['remoteControlEnabled'] as bool? ?? d.remoteControlEnabled,
      remoteListenOn: json['remoteListenOn']?.toString() ?? d.remoteListenOn,
      remotePort: (json['remotePort'] as num?)?.toInt() ?? d.remotePort,
      useBrowserProxyOnError:
          json['useBrowserProxyOnError'] as bool? ?? d.useBrowserProxyOnError,
      proxyMode: json['proxyMode']?.toString() ?? d.proxyMode,
      pacAddress: json['pacAddress']?.toString() ?? d.pacAddress,
      proxyServer: json['proxyServer']?.toString() ?? d.proxyServer,
      proxyPort: json['proxyPort']?.toString() ?? d.proxyPort,
      proxyUsername: json['proxyUsername']?.toString() ?? d.proxyUsername,
      proxyPassword: json['proxyPassword']?.toString() ?? d.proxyPassword,
      proxyHttp: json['proxyHttp'] as bool? ?? d.proxyHttp,
      proxyHttps: json['proxyHttps'] as bool? ?? d.proxyHttps,
      proxyFtp: json['proxyFtp'] as bool? ?? d.proxyFtp,
      networkAdapter: json['networkAdapter']?.toString() ?? d.networkAdapter,
      useFtpPasv: json['useFtpPasv'] as bool? ?? d.useFtpPasv,
      siteLogins: (json['siteLogins'] as List<dynamic>?)
              ?.map((e) => SiteLoginEntry.fromJson(e as Map<String, dynamic>))
              .toList() ??
          d.siteLogins,
      videoCookiesMode:
          json['videoCookiesMode']?.toString() ?? d.videoCookiesMode,
      videoCookiesBrowser:
          json['videoCookiesBrowser']?.toString() ?? d.videoCookiesBrowser,
      videoCookiesProfile:
          json['videoCookiesProfile']?.toString() ?? d.videoCookiesProfile,
      debridAccounts: (json['debridAccounts'] as List<dynamic>?)
              ?.map(
                (e) => DebridAccountEntry.fromJson(e as Map<String, dynamic>),
              )
              .toList() ??
          d.debridAccounts,
      useDebridForFileHosts:
          json['useDebridForFileHosts'] as bool? ?? d.useDebridForFileHosts,
      sendTorrentsToDebrid:
          json['sendTorrentsToDebrid'] as bool? ?? d.sendTorrentsToDebrid,
      soundEvents: rawSounds != null && rawSounds.isNotEmpty
          ? rawSounds
                .map(
                  (e) =>
                      SoundEventSetting.fromJson(e as Map<String, dynamic>),
                )
                .toList()
          : d.soundEvents,
      useSystemRegionFormat:
          json['useSystemRegionFormat'] as bool? ?? d.useSystemRegionFormat,
      dateOrder: json['dateOrder']?.toString() ?? d.dateOrder,
      clockFormat: json['clockFormat']?.toString() ?? d.clockFormat,
      firstDayOfWeek: json['firstDayOfWeek']?.toString() ?? d.firstDayOfWeek,
      extractArchivesOnComplete:
          json['extractArchivesOnComplete'] as bool? ??
          d.extractArchivesOnComplete,
      moveArchivesToRecycleBin:
          json['moveArchivesToRecycleBin'] as bool? ??
          d.moveArchivesToRecycleBin,
      archiveExtractTarget:
          json['archiveExtractTarget']?.toString() ?? d.archiveExtractTarget,
      linkGrabberLookupOnArrive:
          json['linkGrabberLookupOnArrive'] as bool? ??
          d.linkGrabberLookupOnArrive,
      linkGrabberHideWebPages:
          json['linkGrabberHideWebPages'] as bool? ?? d.linkGrabberHideWebPages,
    );
  }
}
