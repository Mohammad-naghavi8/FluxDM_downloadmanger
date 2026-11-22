import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:download_manager/features/downloads/services/download_service.dart';
import 'package:download_manager/features/downloads/services/go_engine_client.dart';
import 'package:download_manager/features/downloads/services/go_engine_process.dart';
import 'package:flutter_test/flutter_test.dart';

Future<int> _findFreePort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

void main() {
  setUpAll(() {
    HttpOverrides.global = null;
  });

  test(
    'Go engine end-to-end: probe, 8-segment download, pause, resume, live limit, verify bytes',
    () async {
      final exePath =
          '${Directory.current.path}${Platform.pathSeparator}go_backend${Platform.pathSeparator}${Platform.isWindows ? 'dm_engine.exe' : 'dm_engine'}';
      expect(
        await File(exePath).exists(),
        isTrue,
        reason: 'dm_engine binary must exist at $exePath',
      );

      final enginePort = await _findFreePort();
      final engineProcess = GoEngineProcess(
        port: enginePort,
        executablePathOverride: exePath,
      );

      final started = await engineProcess.ensureStarted(
        timeout: const Duration(seconds: 5),
      );
      expect(started, isTrue, reason: 'Go engine should start and pass /health');
      expect(engineProcess.isRunning, isTrue);

      final goClient = GoEngineClient(baseUrl: engineProcess.baseUrl);
      final service = DownloadService(goClient: goClient);

      // Build deterministic 1.2 MB test payload.
      const totalSize = 1200 * 1024;
      final payload = Uint8List(totalSize);
      for (int i = 0; i < totalSize; i++) {
        payload[i] = (i * 31 + 7) & 0xFF;
      }

      // Local Range-capable HTTP server.
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      bool throttleChunks = true;
      server.listen((HttpRequest req) async {
        req.response.headers.set('Accept-Ranges', 'bytes');
        req.response.headers.set('Content-Type', 'application/octet-stream');

        if (req.method == 'HEAD') {
          req.response.headers.set('Content-Length', totalSize.toString());
          await req.response.close();
          return;
        }

        int start = 0;
        int end = totalSize - 1;
        final rangeHeader = req.headers.value('range');
        if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
          final parts = rangeHeader.substring('bytes='.length).split('-');
          start = int.parse(parts[0]);
          if (parts.length > 1 && parts[1].isNotEmpty) {
            end = int.parse(parts[1]);
          }
          req.response.statusCode = HttpStatus.partialContent;
          req.response.headers.set(
            'Content-Range',
            'bytes $start-$end/$totalSize',
          );
        }

        final length = end - start + 1;
        req.response.headers.set('Content-Length', length.toString());

        const chunkSize = 16 * 1024;
        int offset = start;
        try {
          while (offset <= end) {
            final nextEnd = (offset + chunkSize - 1) > end
                ? end
                : (offset + chunkSize - 1);
            req.response.add(payload.sublist(offset, nextEnd + 1));
            await req.response.flush();
            offset = nextEnd + 1;
            if (throttleChunks) {
              await Future<void>.delayed(const Duration(milliseconds: 25));
            }
          }
          await req.response.close();
        } catch (_) {}
      });

      final tempDir = await Directory.systemTemp.createTemp('go_dm_test_');
      final savePath =
          '${tempDir.path}${Platform.pathSeparator}windows_test.rar';
      final testUrl = 'http://127.0.0.1:${server.port}/windows_test.rar';

      try {
        // 1. Probe via Go backend.
        final info = await service.getFileInfo(testUrl);
        expect(info.fileName, 'windows_test.rar');
        expect(info.fileSize, totalSize);
        expect(info.supportsResume, isTrue);
        expect(info.isDirectDownload, isTrue);
        expect(info.protocol, 'HTTP');

        // 2. Start 8-segment download and pause mid-flight.
        final pauseToken = CancelToken();
        bool pauseRequested = false;
        int maxConnSeen = 0;
        bool limitUpdated = false;

        Object? caughtError;
        try {
          await service.downloadFileSegmented(
            taskId: 'task_go_e2e',
            url: testUrl,
            savePath: savePath,
            totalBytes: totalSize,
            connectionCount: 8,
            cancelToken: pauseToken,
            isPauseRequested: () => pauseRequested,
            onProgress: (r, t) {},
            onSegmentedProgress: (received, total, connections) {
              if (connections.length > maxConnSeen) {
                maxConnSeen = connections.length;
              }
              if (!limitUpdated && received > 0) {
                limitUpdated = true;
                unawaited(service.setLiveSpeedLimit('task_go_e2e', 512 * 1024));
              }
              if (!pauseRequested && received >= 128 * 1024) {
                pauseRequested = true;
                pauseToken.cancel('Paused by user');
              }
            },
          );
        } catch (err) {
          caughtError = err;
        }

        expect(caughtError, isA<DioException>());
        expect((caughtError as DioException).type, DioExceptionType.cancel);
        expect(maxConnSeen, 8);

        final savedBytes = await service.getDownloadedBytes(savePath);
        expect(savedBytes, greaterThan(0));
        expect(savedBytes, lessThan(totalSize));

        final savedConns = await service.getSavedConnectionProgress(savePath);
        expect(savedConns.length, 8);

        // 3. Resume 8-segment download to completion.
        throttleChunks = false;
        bool rebuilt = false;
        await service.downloadFileSegmented(
          taskId: 'task_go_e2e',
          url: testUrl,
          savePath: savePath,
          totalBytes: totalSize,
          connectionCount: 8,
          resumeExisting: true,
          onProgress: (r, t) {},
          onRebuilding: () => rebuilt = true,
        );

        expect(rebuilt, isTrue);
        final outFile = File(savePath);
        expect(await outFile.exists(), isTrue);
        final written = await outFile.readAsBytes();
        expect(written.length, totalSize);
        expect(written, orderedEquals(payload));

        // State and part files should be cleaned up after rebuild.
        expect(await File('$savePath.dmstate').exists(), isFalse);
        expect(await File('$savePath.part0').exists(), isFalse);
      } finally {
        await server.close(force: true);
        await engineProcess.stop();
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      }

      expect(engineProcess.isRunning, isFalse);
    },
  );
}
