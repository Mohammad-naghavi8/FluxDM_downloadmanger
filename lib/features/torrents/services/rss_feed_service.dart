import 'dart:convert';
import 'dart:io';

import 'package:download_manager/features/downloads/services/go_engine_client.dart';
import 'package:download_manager/features/downloads/services/go_engine_process.dart';
import 'package:download_manager/features/torrents/models/torrent_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RssAndTorrentStorageService {
  static const String _settingsKey = 'torrent_settings_v1';
  static const String _feedsKey = 'rss_feeds_v1';
  static const String _rulesKey = 'rss_rules_v1';
  static const String _intervalKey = 'rss_check_interval_minutes_v1';

  Future<TorrentSettings> loadTorrentSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_settingsKey);
      if (raw != null && raw.isNotEmpty) {
        return TorrentSettings.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
        );
      }
    } catch (_) {}
    return const TorrentSettings();
  }

  Future<void> saveTorrentSettings(TorrentSettings settings) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_settingsKey, jsonEncode(settings.toJson()));
    } catch (_) {}
  }

  Future<List<RssFeedEntry>> loadFeeds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_feedsKey);
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw) as List<dynamic>;
        return list
            .map((e) => RssFeedEntry.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  Future<void> saveFeeds(List<RssFeedEntry> feeds) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _feedsKey,
        jsonEncode(feeds.map((f) => f.toJson()).toList()),
      );
    } catch (_) {}
  }

  Future<List<RssDownloadRule>> loadRules() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_rulesKey);
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw) as List<dynamic>;
        return list
            .map((e) => RssDownloadRule.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  Future<void> saveRules(List<RssDownloadRule> rules) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _rulesKey,
        jsonEncode(rules.map((r) => r.toJson()).toList()),
      );
    } catch (_) {}
  }

  Future<int> loadCheckIntervalMinutes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final val = prefs.getInt(_intervalKey);
      if (val != null && val >= 1) return val;
    } catch (_) {}
    return 30;
  }

  Future<void> saveCheckIntervalMinutes(int minutes) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_intervalKey, minutes.clamp(1, 1440));
    } catch (_) {}
  }

  Future<({String title, List<RssArticle> articles})> fetchFeed(
    RssFeedEntry feed,
  ) async {
    final uri = Uri.tryParse(feed.url.trim());
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      throw const FormatException('Enter a valid HTTP/HTTPS RSS feed address.');
    }

    if (GoEngineProcess.instance.isRunning) {
      return GoEngineClient().fetchRssFeed(uri.toString(), feedId: feed.id);
    }

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
    try {
      final request = await client.getUrl(uri);
      request.headers.set('User-Agent', 'DownloadManager-RSS/1.0');
      request.headers.set('Accept', 'application/rss+xml, application/xml, text/xml, */*');
      final response = await request.close().timeout(const Duration(seconds: 15));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('Server returned HTTP ${response.statusCode}');
      }

      final xml = await utf8.decoder.bind(response).join();
      return parseFeedXml(xml, feedId: feed.id, fallbackTitle: uri.host);
    } finally {
      client.close(force: true);
    }
  }

  static ({String title, List<RssArticle> articles}) parseFeedXml(
    String xml, {
    required String feedId,
    required String fallbackTitle,
  }) {
    String feedTitle = fallbackTitle;
    final channelTitle = _extractTag(xml, 'title');
    if (channelTitle != null && channelTitle.isNotEmpty) {
      feedTitle = channelTitle;
    }

    final articles = <RssArticle>[];

    // Parse RSS 2.0 <item> blocks
    final itemMatches = RegExp(
      r'<item\b[^>]*>([\s\S]*?)</item>',
      caseSensitive: false,
    ).allMatches(xml);

    for (final m in itemMatches) {
      final block = m.group(1) ?? '';
      final title = _extractTag(block, 'title') ?? '';
      final enclosureUrl = _extractAttr(block, 'enclosure', 'url');
      final link = (enclosureUrl != null && enclosureUrl.isNotEmpty)
          ? enclosureUrl
          : (_extractTag(block, 'link') ?? '');
      final pubDate = _extractTag(block, 'pubDate') ?? '';
      if (title.isNotEmpty || link.isNotEmpty) {
        articles.add(
          RssArticle(
            title: title.isNotEmpty ? title : link,
            link: link,
            pubDate: pubDate,
            feedId: feedId,
            feedTitle: feedTitle,
          ),
        );
      }
    }

    // Fallback: Atom <entry> blocks
    if (articles.isEmpty) {
      final entryMatches = RegExp(
        r'<entry\b[^>]*>([\s\S]*?)</entry>',
        caseSensitive: false,
      ).allMatches(xml);
      for (final m in entryMatches) {
        final block = m.group(1) ?? '';
        final title = _extractTag(block, 'title') ?? '';
        final link =
            _extractAttr(block, 'link', 'href') ??
            _extractTag(block, 'link') ??
            '';
        final updated =
            _extractTag(block, 'updated') ??
            _extractTag(block, 'published') ??
            '';
        if (title.isNotEmpty || link.isNotEmpty) {
          articles.add(
            RssArticle(
              title: title.isNotEmpty ? title : link,
              link: link,
              pubDate: updated,
              feedId: feedId,
              feedTitle: feedTitle,
            ),
          );
        }
      }
    }

    return (title: feedTitle, articles: articles);
  }

  static String? _extractTag(String source, String tag) {
    final match = RegExp(
      '<$tag\\b[^>]*>([\\s\\S]*?)</$tag>',
      caseSensitive: false,
    ).firstMatch(source);
    if (match == null) return null;
    var value = match.group(1) ?? '';
    value = value.replaceAll(RegExp(r'<!\[CDATA\[([\s\S]*?)\]\]>'), r'$1');
    return _decodeXmlEntities(value).trim();
  }

  static String? _extractAttr(String source, String tag, String attr) {
    final match = RegExp(
      '<$tag\\b[^>]*$attr=["\']([^"\']+)["\']',
      caseSensitive: false,
    ).firstMatch(source);
    if (match == null) return null;
    return _decodeXmlEntities(match.group(1) ?? '').trim();
  }

  static String _decodeXmlEntities(String input) {
    return input
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&#39;', "'");
  }
}
