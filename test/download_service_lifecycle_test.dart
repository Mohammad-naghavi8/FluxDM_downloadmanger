import 'dart:io';

import 'package:dio/dio.dart';
import 'package:download_manager/features/downloads/services/download_service.dart';
import 'package:download_manager/features/downloads/services/speed_limiter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DownloadService real HTTP lifecycle', () {
    late HttpServer server;
    late Directory tempDir;
    late List<int> payload;
    late DownloadService service;

    setUp(() async {
      service = DownloadService();
      tempDir = await Directory.systemTemp.createTemp('dm_lifecycle_test_');
      // 256 KB deterministic payload
      payload = List<int>.generate(256 * 1024, (i) => i % 251);

      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      bool droppedOnce = false;
      server.listen((HttpRequest request) async {
        final path = request.uri.path;

        if (path == '/fail') {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
          return;
        }

        if (path == '/flaky.bin' &&
            request.method == 'GET' &&
            !droppedOnce) {
          droppedOnce = true;
          request.response.statusCode = HttpStatus.ok;
          request.response.headers.set('accept-ranges', 'bytes');
          request.response.headers.set('content-length', payload.length);
          // Detach raw socket after sending headers, write 32 KB, then drop TCP
          final socket = await request.response.detachSocket(writeHeaders: true);
          socket.add(payload.sublist(0, 32 * 1024));
          await socket.flush();
          socket.destroy();
          return;
        }

        if (request.method == 'HEAD') {
          request.response.headers.set('accept-ranges', 'bytes');
          request.response.headers.set('content-length', payload.length);
          request.response.headers.set(
            'content-disposition',
            'attachment; filename="sample.bin"',
          );
          request.response.statusCode = HttpStatus.ok;
          await request.response.close();
          return;
        }

        final rangeHeader = request.headers.value('range');
        if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
          final parts = rangeHeader.substring('bytes='.length).split('-');
          final start = int.parse(parts[0]);
          final end = (parts.length > 1 && parts[1].isNotEmpty)
              ? int.parse(parts[1])
              : payload.length - 1;
          final slice = payload.sublist(start, end + 1);
          request.response.statusCode = HttpStatus.partialContent;
          request.response.headers.set('accept-ranges', 'bytes');
          request.response.headers.set(
            'content-range',
            'bytes $start-$end/${payload.length}',
          );
          request.response.headers.set('content-length', slice.length);

          // Stream in 8 KB chunks so mid-download pause is deterministic
          const chunkSize = 8 * 1024;
          for (int offset = 0; offset < slice.length; offset += chunkSize) {
            final chunkEnd = (offset + chunkSize).clamp(0, slice.length);
            request.response.add(slice.sublist(offset, chunkEnd));
            await request.response.flush();
            await Future<void>.delayed(const Duration(milliseconds: 50));
          }
          await request.response.close();
          return;
        }

        request.response.statusCode = HttpStatus.ok;
        request.response.headers.set('accept-ranges', 'bytes');
        request.response.headers.set('content-length', payload.length);

        const chunkSize = 16 * 1024;
        for (int offset = 0; offset < payload.length; offset += chunkSize) {
          final end = (offset + chunkSize).clamp(0, payload.length);
          request.response.add(payload.sublist(offset, end));
          await request.response.flush();
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        await request.response.close();
      });
    });

    tearDown(() async {
      await server.close(force: true);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('fetches info, pauses mid-download, and resumes via HTTP Range', () async {
      final url = 'http://127.0.0.1:${server.port}/sample.bin';
      final savePath = '${tempDir.path}${Platform.pathSeparator}sample.bin';

      final info = await service.getFileInfo(url);
      expect(info.fileName, 'sample.bin');
      expect(info.fileSize, payload.length);
      expect(info.supportsResume, isTrue);

      final pauseToken = CancelToken();
      int lastReceived = 0;

      await expectLater(
        service.downloadFile(
          url: url,
          savePath: savePath,
          cancelToken: pauseToken,
          onProgress: (received, total) {
            lastReceived = received;
            if (received >= 32 * 1024 && !pauseToken.isCancelled) {
              pauseToken.cancel('Paused by test');
            }
          },
        ),
        throwsA(isA<DioException>()),
      );

      final partialBytes = await service.getDownloadedBytes(savePath);
      expect(partialBytes, greaterThan(0));
      expect(partialBytes, lessThan(payload.length));
      expect(lastReceived, greaterThanOrEqualTo(32 * 1024));

      final canResume = await service.supportsResume(url);
      expect(canResume, isTrue);

      int finalReceived = 0;
      int finalTotal = 0;
      await service.resumeDownload(
        url: url,
        savePath: savePath,
        downloadedBytes: partialBytes,
        onProgress: (received, total) {
          finalReceived = received;
          finalTotal = total;
        },
      );

      expect(finalReceived, payload.length);
      expect(finalTotal, payload.length);

      final savedBytes = await File(savePath).readAsBytes();
      expect(savedBytes, equals(payload));
    });

    test(
      'downloads with 8 parallel connections, pauses, resumes, and rebuilds exact file',
      () async {
        final url = 'http://127.0.0.1:${server.port}/sample.bin';
        final savePath = '${tempDir.path}${Platform.pathSeparator}segmented.bin';

        final pauseToken = CancelToken();
        int maxConnectionCount = 0;
        bool rebuiltCalled = false;

        await expectLater(
          service.downloadFileSegmented(
            url: url,
            savePath: savePath,
            totalBytes: payload.length,
            connectionCount: 8,
            cancelToken: pauseToken,
            onConnectionsChanged: (connections) {
              if (connections.length > maxConnectionCount) {
                maxConnectionCount = connections.length;
              }
            },
            onProgress: (received, total) {
              if (received >= 48 * 1024 && !pauseToken.isCancelled) {
                pauseToken.cancel('Paused segmented test');
              }
            },
          ),
          throwsA(isA<DioException>()),
        );

        expect(maxConnectionCount, 8);
        expect(await service.hasSegmentedState(savePath), isTrue);

        final pausedBytes = await service.getDownloadedBytes(savePath);
        expect(pausedBytes, greaterThan(0));
        expect(pausedBytes, lessThan(payload.length));

        final savedSegments = await service.getSavedConnectionProgress(savePath);
        expect(savedSegments.length, 8);

        int finalReceived = 0;
        await service.downloadFileSegmented(
          url: url,
          savePath: savePath,
          totalBytes: payload.length,
          connectionCount: 8,
          resumeExisting: true,
          onRebuilding: () => rebuiltCalled = true,
          onProgress: (received, total) {
            finalReceived = received;
          },
        );

        expect(rebuiltCalled, isTrue);
        expect(finalReceived, payload.length);
        expect(await service.hasSegmentedState(savePath), isFalse);

        final savedBytes = await File(savePath).readAsBytes();
        expect(savedBytes, equals(payload));
      },
    );

    test(
      'auto-reconnects and resumes seamlessly after unexpected network drop',
      () async {
        final url = 'http://127.0.0.1:${server.port}/flaky.bin';
        final savePath = '${tempDir.path}${Platform.pathSeparator}flaky.bin';

        int reconnectCalls = 0;

        await service.downloadFile(
          url: url,
          savePath: savePath,
          onReconnecting: (_) => reconnectCalls++,
          onProgress: (_, _) {},
        );

        expect(reconnectCalls, greaterThanOrEqualTo(1));
        final savedBytes = await File(savePath).readAsBytes();
        expect(savedBytes, equals(payload));
      },
    );

    test('enforces real-time speed limit without corrupting data', () async {
      final url = 'http://127.0.0.1:${server.port}/sample.bin';
      final savePath = '${tempDir.path}${Platform.pathSeparator}limited.bin';

      // Limit 256 KB payload to 256 KB/s -> should throttle smoothly (~500ms+)
      final limiter = SpeedLimiter(() => 256 * 1024);
      final sw = Stopwatch()..start();

      await service.downloadFileSegmented(
        url: url,
        savePath: savePath,
        totalBytes: payload.length,
        connectionCount: 4,
        speedLimiter: limiter,
        onProgress: (_, _) {},
      );
      sw.stop();

      expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(450));
      final savedBytes = await File(savePath).readAsBytes();
      expect(savedBytes, equals(payload));
    });
  });
}
