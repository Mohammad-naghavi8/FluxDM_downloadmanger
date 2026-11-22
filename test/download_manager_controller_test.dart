import 'dart:io';

import 'package:download_manager/features/downloads/controllers/download_manager_controller.dart';
import 'package:download_manager/features/downloads/models/download_schedule_config.dart';
import 'package:download_manager/features/downloads/services/download_path_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _TestDownloadPathService extends DownloadPathService {
  final Directory rootDir;

  _TestDownloadPathService(this.rootDir);

  @override
  Future<String> getSavedPath() async => rootDir.path;

  @override
  Future<String> getFilePath({
    required String fileName,
    required String category,
  }) async {
    final dir = Directory('${rootDir.path}${Platform.pathSeparator}$category');
    await dir.create(recursive: true);
    return '${dir.path}${Platform.pathSeparator}$fileName';
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DownloadManagerController concurrent, queue & scheduler', () {
    late HttpServer server;
    late Directory tempDir;
    late List<int> payload;
    late DownloadManagerController controller;

    setUp(() async {
      HttpOverrides.global = null;
      SharedPreferences.setMockInitialValues({});
      tempDir = await Directory.systemTemp.createTemp('dm_controller_test_');
      payload = List<int>.generate(64 * 1024, (i) => i % 251);

      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((HttpRequest request) async {
        if (request.method == 'HEAD') {
          request.response.headers.set('accept-ranges', 'bytes');
          request.response.headers.set('content-length', payload.length);
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
          request.response.add(slice);
          await request.response.close();
          return;
        }

        request.response.statusCode = HttpStatus.ok;
        request.response.headers.set('accept-ranges', 'bytes');
        request.response.headers.set('content-length', payload.length);

        const chunkSize = 8 * 1024;
        for (int offset = 0; offset < payload.length; offset += chunkSize) {
          final end = (offset + chunkSize).clamp(0, payload.length);
          request.response.add(payload.sublist(offset, end));
          await request.response.flush();
          await Future<void>.delayed(const Duration(milliseconds: 12));
        }
        await request.response.close();
      });

      controller = DownloadManagerController(
        downloadPathService: _TestDownloadPathService(tempDir),
      );
    });

    tearDown(() async {
      controller.dispose();
      await server.close(force: true);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    Future<void> waitUntil(
      bool Function() condition, {
      Duration timeout = const Duration(seconds: 6),
    }) async {
      final deadline = DateTime.now().add(timeout);
      while (!condition()) {
        if (DateTime.now().isAfter(deadline)) {
          fail('Timed out waiting for condition');
        }
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
    }

    test(
      'downloads multiple files simultaneously up to maxConcurrent and pumps queue',
      () async {
        await controller.updateScheduleConfig(
          const DownloadScheduleConfig(maxConcurrentDownloads: 2),
        );

        final e1 = await controller.addDownload(
          url: 'http://127.0.0.1:${server.port}/file1.zip',
          startNow: true,
        );
        final e2 = await controller.addDownload(
          url: 'http://127.0.0.1:${server.port}/file2.zip',
          startNow: true,
        );
        final e3 = await controller.addDownload(
          url: 'http://127.0.0.1:${server.port}/file3.zip',
          startNow: true,
        );

        expect(e1, isNotNull);
        expect(e2, isNotNull);
        expect(e3, isNotNull);

        // Immediately, 2 downloads are active and the 3rd waits in queue
        expect(controller.activeDownloadCount, 2);
        expect(e3!.isQueued, isTrue);

        // Wait for all 3 downloads to complete automatically
        await waitUntil(
          () => e1!.isFinished && e2!.isFinished && e3.isFinished,
        );

        expect(controller.activeDownloadCount, 0);
        expect(await File(e1!.savePath).readAsBytes(), equals(payload));
        expect(await File(e2!.savePath).readAsBytes(), equals(payload));
        expect(await File(e3.savePath).readAsBytes(), equals(payload));
      },
    );

    test(
      'automatically starts scheduled downloads and global queue at specified time',
      () async {
        final futureTime = DateTime.now().add(const Duration(minutes: 10));

        // 1. Per-file scheduled download
        final scheduled = await controller.addDownload(
          url: 'http://127.0.0.1:${server.port}/auto_file.zip',
          startNow: false,
          scheduledAt: futureTime,
        );
        expect(scheduled, isNotNull);
        expect(scheduled!.isScheduled, isTrue);
        expect(controller.activeDownloadCount, 0);

        // 2. Queued download waiting for global queue schedule
        final queued = await controller.addDownload(
          url: 'http://127.0.0.1:${server.port}/queued_file.zip',
          startNow: false,
        );
        expect(queued, isNotNull);
        expect(queued!.isQueued, isTrue);

        final queueTime = DateTime.now().add(const Duration(minutes: 20));
        await controller.updateScheduleConfig(
          DownloadScheduleConfig(
            maxConcurrentDownloads: 3,
            autoStartQueueEnabled: true,
            queueStartTime: queueTime,
          ),
        );

        // Before scheduled time: nothing starts
        controller.checkSchedules(DateTime.now().add(const Duration(minutes: 5)));
        expect(scheduled.isScheduled, isTrue);
        expect(queued.isQueued, isTrue);

        // At individual scheduled time: scheduled file starts automatically
        controller.checkSchedules(futureTime);
        await waitUntil(() => scheduled.isFinished);
        expect(scheduled.isFinished, isTrue);
        expect(queued.isQueued, isTrue);

        // At queue auto-start time: queued file starts automatically
        controller.checkSchedules(queueTime);
        await waitUntil(() => queued.isFinished);
        expect(queued.isFinished, isTrue);
        expect(controller.scheduleConfig.autoStartQueueEnabled, isFalse);
      },
    );

    test('supports queue reordering, filtering, cancel and delete', () async {
      final a = await controller.addDownload(
        url: 'http://127.0.0.1:${server.port}/alpha.mp4',
        startNow: false,
      );
      final b = await controller.addDownload(
        url: 'http://127.0.0.1:${server.port}/beta.pdf',
        startNow: false,
      );

      expect(controller.files.map((e) => e.id).toList(), [a!.id, b!.id]);

      // Reorder queue
      controller.moveQueuedEntry(b.id, a.id);
      expect(controller.files.map((e) => e.id).toList(), [b.id, a.id]);

      // Category & search filtering
      controller.selectCategory('Video');
      expect(controller.visibleFiles.map((e) => e.id).toList(), [a.id]);

      controller.selectCategory('All Downloads');
      controller.updateSearchQuery('beta');
      expect(controller.visibleFiles.map((e) => e.id).toList(), [b.id]);

      // Cancel and delete
      await controller.stopDownloadById(b.id);
      expect(b.isStopped, isTrue);

      await controller.deleteDownloadById(b.id);
      expect(controller.findEntryById(b.id), isNull);
    });
  });
}
