import 'package:download_manager/features/downloads/models/download_schedule_config.dart';
import 'package:download_manager/features/downloads/services/download_path_service.dart';
import 'package:download_manager/features/downloads/widgets/scheduler_dialog.dart';
import 'package:download_manager/features/settings/models/app_settings.dart';
import 'package:download_manager/features/settings/services/app_settings_service.dart';
import 'package:download_manager/features/settings/widgets/configuration_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('AppSettingsService persists and reloads configuration', () async {
    final service = AppSettingsService();
    const custom = AppSettings(
      offerClipboardDownloads: false,
      defaultMaxConnections: 16,
      remoteControlEnabled: true,
      remotePort: 9000,
      proxyMode: 'manual',
      proxyServer: '127.0.0.1',
      proxyPort: '1080',
      extractArchivesOnComplete: true,
    );
    await service.save(custom);
    final loaded = await service.load();

    expect(loaded.offerClipboardDownloads, isFalse);
    expect(loaded.defaultMaxConnections, 16);
    expect(loaded.remoteControlEnabled, isTrue);
    expect(loaded.remotePort, 9000);
    expect(loaded.proxyMode, 'manual');
    expect(loaded.proxyServer, '127.0.0.1');
    expect(loaded.extractArchivesOnComplete, isTrue);
  });

  testWidgets('ConfigurationDialog renders all 12 tabs without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ConfigurationDialog(
            initialSettings: const AppSettings(),
            downloadPathService: DownloadPathService(),
            defaultDownloadDir: r'C:\Users\Test\Downloads',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    const tabs = [
      ('General', 'Browser/System Integration'),
      ('File types', 'Downloaded file types'),
      ('Save to', 'Categories, file types, folders'),
      ('Downloads', 'Default download settings'),
      ('Connection', 'Connections and Limits'),
      ('Remote', 'Remote control'),
      ('Proxy / Socks', 'Proxy / socks configuration'),
      ('Sites Logins', 'User names and passwords for servers/sites'),
      ('Accounts', 'Debrid service accounts'),
      ('Sounds', 'Sound settings'),
      ('Regional', 'Dates and times'),
      ('Archives', 'Archives and Link grabber'),
    ];

    for (final (tabName, headerTitle) in tabs) {
      await tester.tap(find.text(tabName));
      await tester.pumpAndSettle();
      expect(find.text(headerTitle), findsOneWidget);
    }
  });

  testWidgets(
    'SchedulerDialog supports Schedule, Files in queue, New queue, and Download limits',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SchedulerDialog(
              initialConfig: const DownloadScheduleConfig(),
              selectedEntry: null,
              queuedCount: 0,
              activeCount: 0,
              onStartQueueNow: () {},
              onPauseAll: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Scheduler'), findsOneWidget);
      expect(find.text('One-time downloading'), findsOneWidget);

      await tester.tap(find.text('Files in the queue'));
      await tester.pumpAndSettle();
      expect(find.text('files at the same time'), findsOneWidget);

      await tester.tap(find.text('New queue'));
      await tester.pumpAndSettle();
      expect(find.text('Enter queue name'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('Queue # 3'), findsWidgets);

      await tester.tap(find.text('Download limits'));
      await tester.pumpAndSettle();
      expect(find.text('Download no more than'), findsOneWidget);
    },
  );
}
