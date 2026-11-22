import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:download_manager/core/theme/app_theme.dart';
import 'package:download_manager/features/downloads/services/browser_bridge_service.dart';
import 'package:download_manager/features/downloads/services/download_service.dart';
import 'package:download_manager/features/downloads/utils/download_link_helper.dart';
import 'package:download_manager/features/downloads/widgets/enter_address_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('DownloadLinkHelper & direct download detection', () {
    test('validates and extracts HTTP, HTTPS, and FTP URLs', () {
      expect(
        DownloadLinkHelper.isSupportedUrl('https://example.com/file.zip'),
        isTrue,
      );
      expect(
        DownloadLinkHelper.isSupportedUrl('http://example.com/app.exe'),
        isTrue,
      );
      expect(
        DownloadLinkHelper.isSupportedUrl('ftp://ftp.example.com/pub/a.iso'),
        isTrue,
      );
      expect(DownloadLinkHelper.isSupportedUrl('file:///C:/test.txt'), isFalse);
      expect(DownloadLinkHelper.isSupportedUrl('not a url'), isFalse);

      expect(
        DownloadLinkHelper.extractSupportedUrl(
          'Download here: ftp://files.example.org/releases/app.tar.gz.',
        ),
        'ftp://files.example.org/releases/app.tar.gz',
      );
    });

    test('distinguishes direct file links from HTML web pages', () {
      expect(
        DownloadLinkHelper.isLikelyDirectDownloadUrl(
          Uri.parse('https://dl.example.com/Windows.part1.rar?12345'),
        ),
        isTrue,
      );
      expect(
        DownloadLinkHelper.isLikelyDirectDownloadUrl(
          Uri.parse('ftp://mirror.example.com/debian/netinst.iso'),
        ),
        isTrue,
      );
      expect(
        DownloadLinkHelper.isLikelyDirectDownloadUrl(
          Uri.parse('https://example.com/articles/news-today'),
        ),
        isFalse,
      );

      final htmlCheck = DownloadLinkHelper.evaluateDirectDownload(
        uri: Uri.parse('https://example.com/download-page'),
        contentType: 'text/html; charset=utf-8',
      );
      expect(htmlCheck.isDirect, isFalse);

      final attachmentCheck = DownloadLinkHelper.evaluateDirectDownload(
        uri: Uri.parse('https://example.com/get?id=42'),
        contentType: 'text/html',
        contentDisposition: 'attachment; filename="installer.exe"',
      );
      expect(attachmentCheck.isDirect, isTrue);

      final binaryCheck = DownloadLinkHelper.evaluateDirectDownload(
        uri: Uri.parse('https://cdn.example.com/stream/123'),
        contentType: 'application/octet-stream',
      );
      expect(binaryCheck.isDirect, isTrue);
    });
  });

  group('BrowserBridgeService', () {
    test('receives browser links via local HTTP bridge', () async {
      HttpOverrides.global = null;
      final bridge = BrowserBridgeService();
      BrowserCapturedLink? captured;

      final started = await bridge.start(
        port: 0,
        onLinkReceived: (link) => captured = link,
      );
      expect(started, isTrue);

      final dio = Dio();
      try {
        final health = await dio.get<Map<String, dynamic>>(
          'http://127.0.0.1:${bridge.port}/health',
        );
        expect(health.statusCode, 200);
        expect(health.data?['ok'], isTrue);

        final addRes = await dio.post<Map<String, dynamic>>(
          'http://127.0.0.1:${bridge.port}/add-download',
          data: {
            'url': 'ftp://ftp.example.com/pub/archive.zip',
            'fileName': 'archive.zip',
            'autoStart': false,
          },
        );
        expect(addRes.statusCode, 200);
        expect(captured?.url, 'ftp://ftp.example.com/pub/archive.zip');
        expect(captured?.fileName, 'archive.zip');
      } finally {
        dio.close(force: true);
        await bridge.stop();
      }
    });
  });

  group('FTP protocol support (RFC 959)', () {
    late ServerSocket controlServer;
    late Directory tempDir;
    late List<int> payload;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('dm_ftp_test_');
      payload = List<int>.generate(64 * 1024, (i) => (i * 7) % 256);

      controlServer = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      controlServer.listen((Socket controlSocket) {
        controlSocket.write('220 Local Test FTP Ready\r\n');
        int restartOffset = 0;
        ServerSocket? dataServer;

        controlSocket
            .cast<List<int>>()
            .transform(latin1.decoder)
            .transform(const LineSplitter())
            .listen((line) async {
              final cmd = line.trim();
              if (cmd.startsWith('USER ')) {
                controlSocket.write('331 Password required\r\n');
              } else if (cmd.startsWith('PASS ')) {
                controlSocket.write('230 Logged in\r\n');
              } else if (cmd.startsWith('TYPE ')) {
                controlSocket.write('200 Type set\r\n');
              } else if (cmd.startsWith('SIZE ')) {
                controlSocket.write('213 ${payload.length}\r\n');
              } else if (cmd.startsWith('REST ')) {
                restartOffset = int.tryParse(cmd.substring(5).trim()) ?? 0;
                controlSocket.write('350 Restarting at $restartOffset\r\n');
              } else if (cmd == 'PASV') {
                await dataServer?.close();
                dataServer = await ServerSocket.bind(
                  InternetAddress.loopbackIPv4,
                  0,
                );
                final port = dataServer!.port;
                final p1 = port ~/ 256;
                final p2 = port % 256;
                controlSocket.write(
                  '227 Entering Passive Mode (127,0,0,1,$p1,$p2)\r\n',
                );
              } else if (cmd.startsWith('RETR ')) {
                final server = dataServer;
                if (server == null) {
                  controlSocket.write('425 Use PASV first\r\n');
                  return;
                }
                controlSocket.write('150 Opening binary data connection\r\n');
                final dataClient = await server.first;
                dataClient.add(payload.sublist(restartOffset));
                await dataClient.flush();
                await dataClient.close();
                await server.close();
                dataServer = null;
                restartOffset = 0;
                controlSocket.write('226 Transfer complete\r\n');
              } else if (cmd == 'QUIT') {
                controlSocket.write('221 Goodbye\r\n');
                await controlSocket.close();
              } else {
                controlSocket.write('502 Not implemented\r\n');
              }
            });
      });
    });

    tearDown(() async {
      await controlServer.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('fetches FTP file info, downloads, and resumes via REST', () async {
      final service = DownloadService();
      final url = 'ftp://127.0.0.1:${controlServer.port}/pub/test_file.zip';

      final info = await service.getFileInfo(url);
      expect(info.fileName, 'test_file.zip');
      expect(info.fileSize, payload.length);
      expect(info.protocol, 'FTP');
      expect(info.isDirectDownload, isTrue);
      expect(info.supportsResume, isTrue);

      // Full FTP download
      final fullPath = '${tempDir.path}${Platform.pathSeparator}full.zip';
      int reportedTotal = 0;
      await service.downloadFile(
        url: url,
        savePath: fullPath,
        onProgress: (received, total) => reportedTotal = total,
      );
      expect(reportedTotal, payload.length);
      expect(await File(fullPath).readAsBytes(), equals(payload));

      // Resumed FTP download using REST
      final partialPath = '${tempDir.path}${Platform.pathSeparator}resumed.zip';
      const splitPoint = 20 * 1024;
      await File(partialPath).writeAsBytes(payload.sublist(0, splitPoint));

      await service.resumeDownload(
        url: url,
        savePath: partialPath,
        downloadedBytes: splitPoint,
        onProgress: (_, _) {},
      );
      expect(await File(partialPath).readAsBytes(), equals(payload));
    });
  });

  group('EnterAddressDialog', () {
    testWidgets('supports URL input and Use authorization credentials', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      EnterAddressResult? dialogResult;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  dialogResult = await showDialog<EnterAddressResult>(
                    context: context,
                    builder: (_) => const EnterAddressDialog(
                      initialUrl: 'https://example.com/archive.rar',
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Enter new address to download'), findsOneWidget);
      expect(find.text('Address'), findsOneWidget);
      expect(find.text('Use authorization'), findsOneWidget);
      expect(find.text('Login'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);
      expect(find.text('OK'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);

      await tester.tap(find.text('Use authorization'));
      await tester.pumpAndSettle();

      final textFields = find.byType(TextField);
      await tester.enterText(textFields.at(1), 'myuser');
      await tester.enterText(textFields.at(2), 'secret123');

      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(dialogResult, isNotNull);
      expect(dialogResult!.url, 'https://example.com/archive.rar');
      expect(dialogResult!.username, 'myuser');
      expect(dialogResult!.password, 'secret123');
    });
  });
}
