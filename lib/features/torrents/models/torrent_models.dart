class TorrentFileItem {
  final String name;
  final String relativePath;
  final int sizeBytes;
  bool selected;

  TorrentFileItem({
    required this.name,
    required this.relativePath,
    required this.sizeBytes,
    this.selected = true,
  });
}

class TorrentMetadata {
  final String source;
  final String name;
  final String? infoHash;
  final List<String> trackers;
  final List<TorrentFileItem> files;
  final bool isMagnet;

  const TorrentMetadata({
    required this.source,
    required this.name,
    this.infoHash,
    this.trackers = const [],
    this.files = const [],
    this.isMagnet = false,
  });

  int get totalBytes =>
      files.fold<int>(0, (sum, item) => sum + (item.sizeBytes > 0 ? item.sizeBytes : 0));

  int get selectedBytes => files
      .where((f) => f.selected)
      .fold<int>(0, (sum, item) => sum + (item.sizeBytes > 0 ? item.sizeBytes : 0));
}

class TorrentSettings {
  final bool keepSharingAfterFinish;
  final bool stopAtShareRatio;
  final double shareRatio;
  final bool stopAfterMinutesEnabled;
  final int stopAfterMinutes;
  final bool registerFileAssociation;
  final bool acceptIncomingConnections;
  final int? listeningPort;
  final bool mapPortUpnp;
  final bool enableDht;
  final bool enableLocalPeerDiscovery;
  final bool useProxy;
  final bool stopEngineWhenIdle;
  final bool limitUploadEnabled;
  final int limitUploadKBps;
  final String blocklistUrl;

  const TorrentSettings({
    this.keepSharingAfterFinish = false,
    this.stopAtShareRatio = false,
    this.shareRatio = 2.0,
    this.stopAfterMinutesEnabled = false,
    this.stopAfterMinutes = 1440,
    this.registerFileAssociation = false,
    this.acceptIncomingConnections = true,
    this.listeningPort,
    this.mapPortUpnp = true,
    this.enableDht = true,
    this.enableLocalPeerDiscovery = true,
    this.useProxy = false,
    this.stopEngineWhenIdle = true,
    this.limitUploadEnabled = false,
    this.limitUploadKBps = 100,
    this.blocklistUrl = '',
  });

  TorrentSettings copyWith({
    bool? keepSharingAfterFinish,
    bool? stopAtShareRatio,
    double? shareRatio,
    bool? stopAfterMinutesEnabled,
    int? stopAfterMinutes,
    bool? registerFileAssociation,
    bool? acceptIncomingConnections,
    int? listeningPort,
    bool clearListeningPort = false,
    bool? mapPortUpnp,
    bool? enableDht,
    bool? enableLocalPeerDiscovery,
    bool? useProxy,
    bool? stopEngineWhenIdle,
    bool? limitUploadEnabled,
    int? limitUploadKBps,
    String? blocklistUrl,
  }) {
    return TorrentSettings(
      keepSharingAfterFinish:
          keepSharingAfterFinish ?? this.keepSharingAfterFinish,
      stopAtShareRatio: stopAtShareRatio ?? this.stopAtShareRatio,
      shareRatio: shareRatio ?? this.shareRatio,
      stopAfterMinutesEnabled:
          stopAfterMinutesEnabled ?? this.stopAfterMinutesEnabled,
      stopAfterMinutes: stopAfterMinutes ?? this.stopAfterMinutes,
      registerFileAssociation:
          registerFileAssociation ?? this.registerFileAssociation,
      acceptIncomingConnections:
          acceptIncomingConnections ?? this.acceptIncomingConnections,
      listeningPort: clearListeningPort
          ? null
          : (listeningPort ?? this.listeningPort),
      mapPortUpnp: mapPortUpnp ?? this.mapPortUpnp,
      enableDht: enableDht ?? this.enableDht,
      enableLocalPeerDiscovery:
          enableLocalPeerDiscovery ?? this.enableLocalPeerDiscovery,
      useProxy: useProxy ?? this.useProxy,
      stopEngineWhenIdle: stopEngineWhenIdle ?? this.stopEngineWhenIdle,
      limitUploadEnabled: limitUploadEnabled ?? this.limitUploadEnabled,
      limitUploadKBps: limitUploadKBps ?? this.limitUploadKBps,
      blocklistUrl: blocklistUrl ?? this.blocklistUrl,
    );
  }

  Map<String, dynamic> toJson() => {
    'keepSharingAfterFinish': keepSharingAfterFinish,
    'stopAtShareRatio': stopAtShareRatio,
    'shareRatio': shareRatio,
    'stopAfterMinutesEnabled': stopAfterMinutesEnabled,
    'stopAfterMinutes': stopAfterMinutes,
    'registerFileAssociation': registerFileAssociation,
    'acceptIncomingConnections': acceptIncomingConnections,
    'listeningPort': listeningPort,
    'mapPortUpnp': mapPortUpnp,
    'enableDht': enableDht,
    'enableLocalPeerDiscovery': enableLocalPeerDiscovery,
    'useProxy': useProxy,
    'stopEngineWhenIdle': stopEngineWhenIdle,
    'limitUploadEnabled': limitUploadEnabled,
    'limitUploadKBps': limitUploadKBps,
    'blocklistUrl': blocklistUrl,
  };

  factory TorrentSettings.fromJson(Map<String, dynamic> json) {
    return TorrentSettings(
      keepSharingAfterFinish: json['keepSharingAfterFinish'] == true,
      stopAtShareRatio: json['stopAtShareRatio'] == true,
      shareRatio: (json['shareRatio'] as num?)?.toDouble() ?? 2.0,
      stopAfterMinutesEnabled: json['stopAfterMinutesEnabled'] == true,
      stopAfterMinutes: (json['stopAfterMinutes'] as num?)?.toInt() ?? 1440,
      registerFileAssociation: json['registerFileAssociation'] == true,
      acceptIncomingConnections: json['acceptIncomingConnections'] != false,
      listeningPort: (json['listeningPort'] as num?)?.toInt(),
      mapPortUpnp: json['mapPortUpnp'] != false,
      enableDht: json['enableDht'] != false,
      enableLocalPeerDiscovery: json['enableLocalPeerDiscovery'] != false,
      useProxy: json['useProxy'] == true,
      stopEngineWhenIdle: json['stopEngineWhenIdle'] != false,
      limitUploadEnabled: json['limitUploadEnabled'] == true,
      limitUploadKBps: (json['limitUploadKBps'] as num?)?.toInt() ?? 100,
      blocklistUrl: json['blocklistUrl']?.toString() ?? '',
    );
  }
}

class RssArticle {
  final String title;
  final String link;
  final String pubDate;
  final String feedId;
  final String feedTitle;

  const RssArticle({
    required this.title,
    required this.link,
    this.pubDate = '',
    required this.feedId,
    required this.feedTitle,
  });
}

class RssFeedEntry {
  final String id;
  final String url;
  String title;
  List<RssArticle> articles;
  String? lastError;

  RssFeedEntry({
    required this.id,
    required this.url,
    required this.title,
    this.articles = const [],
    this.lastError,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'url': url,
    'title': title,
  };

  factory RssFeedEntry.fromJson(Map<String, dynamic> json) {
    return RssFeedEntry(
      id: json['id']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
      title: json['title']?.toString() ?? json['url']?.toString() ?? 'Feed',
    );
  }
}

class RssDownloadRule {
  final String id;
  bool enabled;
  String name;
  String mustContain;
  String mustNotContain;
  bool useRegex;
  String episodes;
  String saveTo;
  bool addWithoutStarting;
  List<String> feedIds;

  RssDownloadRule({
    required this.id,
    this.enabled = true,
    this.name = 'New rule',
    this.mustContain = '',
    this.mustNotContain = '',
    this.useRegex = false,
    this.episodes = '',
    this.saveTo = '',
    this.addWithoutStarting = false,
    List<String>? feedIds,
  }) : feedIds = feedIds ?? [];

  bool matchesArticle(RssArticle article) {
    if (feedIds.isNotEmpty && !feedIds.contains(article.feedId)) {
      return false;
    }
    return matchesTitle(article.title);
  }

  bool matchesTitle(String title) {
    final normalizedTitle = title.trim();
    if (normalizedTitle.isEmpty) return false;

    final must = mustContain.trim();
    final mustNot = mustNotContain.trim();
    final epFilter = episodes.trim();

    if (must.isEmpty && mustNot.isEmpty && epFilter.isEmpty) {
      return false;
    }

    if (must.isNotEmpty) {
      if (useRegex) {
        try {
          if (!RegExp(must, caseSensitive: false).hasMatch(normalizedTitle)) {
            return false;
          }
        } catch (_) {
          return false;
        }
      } else {
        if (!_matchesWildcardExpression(normalizedTitle, must)) {
          return false;
        }
      }
    }

    if (mustNot.isNotEmpty) {
      if (useRegex) {
        try {
          if (RegExp(mustNot, caseSensitive: false).hasMatch(normalizedTitle)) {
            return false;
          }
        } catch (_) {}
      } else {
        if (_matchesWildcardExpression(normalizedTitle, mustNot)) {
          return false;
        }
      }
    }

    if (epFilter.isNotEmpty && !_matchesEpisodes(normalizedTitle, epFilter)) {
      return false;
    }

    return true;
  }

  static bool _matchesWildcardExpression(String text, String expression) {
    final lower = text.toLowerCase();
    final alternatives = expression
        .split('|')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty);

    for (final alt in alternatives) {
      final words = alt.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
      bool allMatched = true;
      for (final word in words) {
        final escaped = RegExp.escape(
          word.toLowerCase(),
        ).replaceAll(r'\*', '.*').replaceAll(r'\?', '.');
        if (!RegExp(escaped).hasMatch(lower)) {
          allMatched = false;
          break;
        }
      }
      if (allMatched) return true;
    }
    return false;
  }

  static bool _matchesEpisodes(String title, String filter) {
    final match = RegExp(
      r'(?:S(\d{1,2})E(\d{1,3})|(\d{1,2})x(\d{1,3}))',
      caseSensitive: false,
    ).firstMatch(title);
    if (match == null) return false;

    final season = int.tryParse(match.group(1) ?? match.group(3) ?? '');
    final episode = int.tryParse(match.group(2) ?? match.group(4) ?? '');
    if (season == null || episode == null) return false;

    final parts = filter
        .split(';')
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty);

    for (final part in parts) {
      final epMatch = RegExp(
        r'^(\d+)x(\d+)(?:-(\d*))?$',
        caseSensitive: false,
      ).firstMatch(part);
      if (epMatch == null) continue;

      final s = int.tryParse(epMatch.group(1)!);
      final startE = int.tryParse(epMatch.group(2)!);
      if (s == null || startE == null || s != season) continue;

      if (!part.contains('-')) {
        if (episode == startE) return true;
      } else {
        final endRaw = epMatch.group(3);
        if (endRaw == null || endRaw.isEmpty) {
          if (episode >= startE) return true;
        } else {
          final endE = int.tryParse(endRaw);
          if (endE != null && episode >= startE && episode <= endE) {
            return true;
          }
        }
      }
    }
    return false;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'enabled': enabled,
    'name': name,
    'mustContain': mustContain,
    'mustNotContain': mustNotContain,
    'useRegex': useRegex,
    'episodes': episodes,
    'saveTo': saveTo,
    'addWithoutStarting': addWithoutStarting,
    'feedIds': feedIds,
  };

  factory RssDownloadRule.fromJson(Map<String, dynamic> json) {
    return RssDownloadRule(
      id: json['id']?.toString() ?? '',
      enabled: json['enabled'] != false,
      name: json['name']?.toString() ?? 'New rule',
      mustContain: json['mustContain']?.toString() ?? '',
      mustNotContain: json['mustNotContain']?.toString() ?? '',
      useRegex: json['useRegex'] == true,
      episodes: json['episodes']?.toString() ?? '',
      saveTo: json['saveTo']?.toString() ?? '',
      addWithoutStarting: json['addWithoutStarting'] == true,
      feedIds: (json['feedIds'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
    );
  }
}
