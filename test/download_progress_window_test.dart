import 'package:download_manager/core/theme/app_theme.dart';
import 'package:download_manager/features/downloads/models/download_progress_state.dart';
import 'package:download_manager/features/downloads/widgets/download_progress_window.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  DownloadProgressState buildState({
    DownloadProgressStatus status = DownloadProgressStatus.downloading,
    int downloadedBytes = 44 * 1024 * 1024,
    int? totalBytes = 100 * 1024 * 1024,
    double speedBytesPerSecond = 2.5 * 1024 * 1024,
    Duration? remainingTime = const Duration(minutes: 2, seconds: 15),
    bool? supportsResume = true,
    String? errorMessage,
  }) {
    return DownloadProgressState(
      url: 'https://example.com/files/archive.zip',
      fileName: 'archive.zip',
      savePath: r'C:\Users\Test\Downloads\Download Manager\Compressed\archive.zip',
      category: 'Compressed',
      status: status,
      downloadedBytes: downloadedBytes,
      totalBytes: totalBytes,
      speedBytesPerSecond: speedBytesPerSecond,
      remainingTime: remainingTime,
      supportsResume: supportsResume,
      errorMessage: errorMessage,
      startedAt: DateTime(2026, 1, 1, 12, 0, 0),
    );
  }

  Widget wrap(Widget child, {Size size = const Size(900, 650)}) {
    return MaterialApp(
      theme: AppTheme.darkTheme,
      home: Scaffold(
        body: SizedBox(width: size.width, height: size.height, child: child),
      ),
    );
  }

  group('DownloadProgressState', () {
    test('formats sizes, speed, duration, and labels accurately', () {
      final state = buildState();

      expect(state.percentageInt, 44);
      expect(state.titleText, '44% archive.zip');
      expect(state.statusLabel, 'Receiving data...');
      expect(state.formattedFileSize, '100.00 MB');
      expect(state.formattedDownloaded, '44.00 MB');
      expect(state.formattedTransferRate, '2.500 MB/sec');
      expect(state.formattedTimeLeft, '2 Min 15 Sec');
      expect(state.resumeCapabilityLabel, 'Yes');
      expect(state.serverHost, 'example.com');
    });

    test('handles unknown total size and sub-MB speeds', () {
      final state = buildState(
        totalBytes: null,
        downloadedBytes: 512 * 1024,
        speedBytesPerSecond: 256 * 1024,
        remainingTime: null,
        supportsResume: false,
      );

      expect(state.progress, isNull);
      expect(state.percentageLabel, '—');
      expect(state.formattedFileSize, 'Unknown');
      expect(state.formattedDownloaded, '512.00 KB');
      expect(state.formattedTransferRate, '256.00 KB/sec');
      expect(state.formattedTimeLeft, 'Unknown');
      expect(state.resumeCapabilityLabel, 'No');
    });

    test('reports 100% progress when completed', () {
      final state = buildState(
        status: DownloadProgressStatus.completed,
        downloadedBytes: 100 * 1024 * 1024,
        speedBytesPerSecond: 0,
        remainingTime: null,
      );

      expect(state.progress, 1.0);
      expect(state.percentageInt, 100);
      expect(state.titleText, '100% archive.zip');
      expect(state.statusLabel, 'Completed');
    });
  });

  group('DownloadProgressWindow', () {
    testWidgets('displays all real-time download fields and toggles details', (
      tester,
    ) async {
      bool paused = false;
      bool cancelled = false;
      bool closed = false;

      await tester.pumpWidget(
        wrap(
          DownloadProgressWindow(
            state: buildState(),
            onClose: () => closed = true,
            onPause: () => paused = true,
            onResume: () {},
            onCancel: () => cancelled = true,
            onRetry: () {},
            onOpenFolder: () {},
          ),
        ),
      );

      expect(find.text('44% archive.zip'), findsOneWidget);
      expect(find.text('https://example.com/files/archive.zip'), findsOneWidget);
      expect(find.text('archive.zip'), findsOneWidget);
      expect(find.text('Receiving data...'), findsOneWidget);
      expect(find.text('100.00 MB'), findsOneWidget);
      expect(find.text('44.00 MB'), findsOneWidget);
      expect(find.text('2.500 MB/sec'), findsOneWidget);
      expect(find.text('2 Min 15 Sec'), findsOneWidget);
      expect(find.text('Yes'), findsOneWidget);

      // Details hidden by default
      expect(
        find.text('Start positions and download progress by connections'),
        findsNothing,
      );
      expect(find.text('Show Details'), findsOneWidget);

      // Expand IDM connection details
      await tester.tap(find.text('Show Details'));
      await tester.pumpAndSettle();

      expect(
        find.text('Start positions and download progress by connections'),
        findsOneWidget,
      );
      expect(find.text('Hide Details'), findsOneWidget);
      expect(find.text('N.'), findsOneWidget);
      expect(find.text('Downloaded'), findsOneWidget);
      expect(find.text('Info'), findsOneWidget);
      expect(find.text('Receiving data... (2.500 MB/sec)'), findsOneWidget);

      // Collapse details
      await tester.tap(find.text('Hide Details'));
      await tester.pumpAndSettle();
      expect(
        find.text('Start positions and download progress by connections'),
        findsNothing,
      );

      // Pause, Cancel, and Close actions
      await tester.tap(find.text('Pause'));
      expect(paused, isTrue);

      await tester.tap(find.text('Cancel'));
      expect(cancelled, isTrue);

      await tester.tap(find.byTooltip('Close'));
      expect(closed, isTrue);
    });

    testWidgets('shows Resume when paused and Retry when failed', (
      tester,
    ) async {
      bool resumed = false;
      bool retried = false;

      await tester.pumpWidget(
        wrap(
          DownloadProgressWindow(
            state: buildState(
              status: DownloadProgressStatus.paused,
              speedBytesPerSecond: 0,
              remainingTime: null,
            ),
            onClose: () {},
            onPause: () {},
            onResume: () => resumed = true,
            onCancel: () {},
            onRetry: () => retried = true,
          ),
        ),
      );

      expect(find.text('Paused'), findsOneWidget);
      expect(find.text('Resume'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);

      await tester.tap(find.text('Resume'));
      expect(resumed, isTrue);

      await tester.pumpWidget(
        wrap(
          DownloadProgressWindow(
            state: buildState(
              status: DownloadProgressStatus.failed,
              downloadedBytes: 0,
              speedBytesPerSecond: 0,
              remainingTime: null,
              errorMessage: 'Server returned HTTP 404',
            ),
            onClose: () {},
            onPause: () {},
            onResume: () {},
            onCancel: () {},
            onRetry: () => retried = true,
          ),
        ),
      );

      expect(find.text('Failed'), findsOneWidget);
      expect(find.text('Server returned HTTP 404'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      expect(retried, isTrue);
    });

    testWidgets('shows Completed state with Open Folder and Close', (
      tester,
    ) async {
      bool openedFolder = false;
      bool closed = false;

      await tester.pumpWidget(
        wrap(
          DownloadProgressWindow(
            state: buildState(
              status: DownloadProgressStatus.completed,
              downloadedBytes: 100 * 1024 * 1024,
              speedBytesPerSecond: 0,
              remainingTime: null,
            ),
            onClose: () => closed = true,
            onPause: () {},
            onResume: () {},
            onCancel: () {},
            onRetry: () {},
            onOpenFolder: () => openedFolder = true,
          ),
        ),
      );

      expect(find.text('Completed'), findsOneWidget);
      expect(find.text('100% archive.zip'), findsOneWidget);
      expect(find.text('Open Folder'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);

      await tester.tap(find.text('Open Folder'));
      expect(openedFolder, isTrue);

      await tester.tap(find.text('Close'));
      expect(closed, isTrue);
    });

    testWidgets('adapts cleanly to compact Windows desktop window sizes', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          DownloadProgressWindow(
            state: buildState(),
            onClose: () {},
            onPause: () {},
            onResume: () {},
            onCancel: () {},
            onRetry: () {},
            onOpenFolder: () {},
          ),
          size: const Size(420, 360),
        ),
      );

      await tester.ensureVisible(find.text('Show Details'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Show Details'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}
