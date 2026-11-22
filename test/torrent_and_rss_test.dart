import 'dart:convert';
import 'dart:typed_data';

import 'package:download_manager/features/torrents/models/torrent_models.dart';
import 'package:download_manager/features/torrents/services/rss_feed_service.dart';
import 'package:download_manager/features/torrents/services/torrent_parser.dart';
import 'package:download_manager/features/torrents/widgets/add_torrent_dialog.dart';
import 'package:download_manager/features/torrents/widgets/rss_feeds_dialog.dart';
import 'package:download_manager/features/torrents/widgets/torrent_settings_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('TorrentParser parses magnet links and bencoded .torrent files', () {
    final magnet = TorrentParser.parseMagnet(
      'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567&dn=Ubuntu+24.04.iso&xl=1048576&tr=udp%3A%2F%2Ftracker.example.com%3A80',
    );
    expect(magnet.isMagnet, isTrue);
    expect(magnet.name, 'Ubuntu 24.04.iso');
    expect(magnet.infoHash, '0123456789abcdef0123456789abcdef01234567');
    expect(magnet.totalBytes, 1048576);
    expect(magnet.trackers, contains('udp://tracker.example.com:80'));

    // Minimal valid bencode single-file torrent:
    // d8:announce24:http://tracker.local/ann4:infod6:lengthi4096e4:name12:sample.bin12:piece lengthi16384eee
    final raw =
        'd8:announce24:http://tracker.local/ann4:infod6:lengthi4096e4:name10:sample.bin12:piece lengthi16384eee';
    final parsed = TorrentParser.parseTorrentBytes(
      Uint8List.fromList(utf8.encode(raw)),
      sourcePath: r'C:\Downloads\sample.torrent',
    );
    expect(parsed.isMagnet, isFalse);
    expect(parsed.name, 'sample.bin');
    expect(parsed.files.length, 1);
    expect(parsed.files.first.sizeBytes, 4096);
    expect(parsed.trackers, contains('http://tracker.local/ann'));
  });

  test('RssAndTorrentStorageService parses RSS XML and evaluates download rules', () {
    const xml = '''
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0">
  <channel>
    <title>Demo Torrents</title>
    <item>
      <title>Show.Name.S01E06.1080p.WEB</title>
      <link>magnet:?xt=urn:btih:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa&amp;dn=Show.S01E06</link>
      <pubDate>Sun, 22 Nov 2026 10:00:00 GMT</pubDate>
    </item>
    <item>
      <title>Show.Name.S01E09.CAM</title>
      <link>magnet:?xt=urn:btih:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb&amp;dn=Show.S01E09</link>
    </item>
  </channel>
</rss>
''';
    final parsed = RssAndTorrentStorageService.parseFeedXml(
      xml,
      feedId: 'f1',
      fallbackTitle: 'Fallback',
    );
    expect(parsed.title, 'Demo Torrents');
    expect(parsed.articles.length, 2);

    final rule = RssDownloadRule(
      id: 'r1',
      name: 'Show Rule',
      mustContain: 'Show* 1080p | 720p',
      mustNotContain: 'CAM',
      episodes: '1x2;1x5-8;2x1-',
    );

    expect(rule.matchesArticle(parsed.articles[0]), isTrue);
    expect(rule.matchesArticle(parsed.articles[1]), isFalse);
  });

  testWidgets('AddTorrentDialog looks up magnet link and enables Download Now', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AddTorrentDialog(
            initialSaveDirectory: r'C:\Users\Test\Downloads',
            initialSource:
                'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567&dn=ArchLinux.iso&xl=2097152',
            autoLookup: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Add torrent'), findsOneWidget);
    expect(find.text('ArchLinux.iso'), findsOneWidget);
    expect(find.text('Download Now'), findsOneWidget);
  });

  testWidgets('RssFeedsDialog switches to Download rules and creates a new rule', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final storage = RssAndTorrentStorageService();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: RssFeedsDialog(storage: storage)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('RSS feeds'), findsOneWidget);
    await tester.tap(find.text('Download rules'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'A rule adds the new articles whose titles it matches, as they come.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('New rule'));
    await tester.pumpAndSettle();

    expect(find.text('Use this rule'), findsOneWidget);
    expect(find.text('Must contain:'), findsOneWidget);
    expect(find.text('Episodes:'), findsOneWidget);
  });

  testWidgets('TorrentSettingsDialog displays all controls and saves settings', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: TorrentSettingsDialog(initialSettings: TorrentSettings()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Torrent settings'), findsOneWidget);
    expect(find.text('Keep sharing torrents after they finish'), findsOneWidget);
    expect(find.text('Accept incoming connections'), findsOneWidget);
    expect(find.text('Find peers through the DHT'), findsOneWidget);
    expect(find.text('Limit uploading for all torrents to'), findsOneWidget);
  });
}
