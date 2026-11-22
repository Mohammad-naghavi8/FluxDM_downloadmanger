import 'package:download_manager/core/localization/app_strings.dart';
import 'package:download_manager/core/localization/translations_data.dart';
import 'package:download_manager/core/widgets/sidebar.dart';
import 'package:download_manager/features/downloads/models/download_schedule_config.dart';
import 'package:download_manager/features/downloads/widgets/download_list_view.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppStrings.instance.setLanguage('en');
  });

  tearDown(() async {
    await AppStrings.instance.setLanguage('en');
  });

  test('every non-English language in allLanguages has 100% key coverage', () {
    final missing = <String>[];

    for (final lang in AppStrings.allLanguages) {
      if (lang.code == 'system' || lang.code == 'en') continue;
      final base = lang.code.contains('_')
          ? lang.code.split('_').first
          : lang.code;
      final dict = kFluxTranslations[lang.code] ?? kFluxTranslations[base];

      if (dict == null) {
        missing.add('${lang.code}: missing entire dictionary');
        continue;
      }

      for (final key in kRequiredLocalizationKeys) {
        final value = dict[key];
        if (value == null || value.trim().isEmpty) {
          missing.add('${lang.code}: missing "$key"');
        }
      }
    }

    expect(
      missing,
      isEmpty,
      reason: 'Missing translations:\n${missing.take(25).join('\n')}',
    );
  });

  test('RTL languages report TextDirection.rtl and LTR report ltr', () async {
    for (final rtlCode in ['fa', 'ar', 'he', 'ur']) {
      await AppStrings.instance.setLanguage(rtlCode);
      expect(AppStrings.instance.isRtl, isTrue);
      expect(AppStrings.instance.textDirection, TextDirection.rtl);
    }

    for (final ltrCode in ['en', 'de', 'fr', 'ja', 'ru', 'tr', 'zh_CN']) {
      await AppStrings.instance.setLanguage(ltrCode);
      expect(AppStrings.instance.isRtl, isFalse);
      expect(AppStrings.instance.textDirection, TextDirection.ltr);
    }
  });

  testWidgets(
    'DownloadListView & DownloadSidebar rebuild immediately when language switches',
    (tester) async {
      await tester.pumpWidget(
        ListenableBuilder(
          listenable: AppStrings.instance,
          builder: (context, _) => MaterialApp(
            home: Directionality(
              textDirection: AppStrings.instance.textDirection,
              child: Scaffold(
                body: Row(
                  children: [
                    DownloadSidebar(
                      categories: const ['All Downloads'],
                      selectedCategory: 'All Downloads',
                      queuedCount: 0,
                      onSelectCategory: (_) {},
                    ),
                    Expanded(
                      child: DownloadListView(
                        selectedCategory: 'All Downloads',
                        files: const [],
                        totalCount: 0,
                        activeCount: 0,
                        maxConcurrent: 3,
                        scheduleConfig: const DownloadScheduleConfig(),
                        selectedFileId: null,
                        onSearchChanged: (_) {},
                        onSelectFile: (_) {},
                        onOpenProgress: (_) {},
                        onMoveQueuedEntry: (_, _) {},
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      // Default English
      expect(find.text('File Name'), findsOneWidget);
      expect(find.text('No downloads yet'), findsOneWidget);
      expect(find.text('Categories'), findsOneWidget);

      // Switch to Persian (fa)
      await AppStrings.instance.setLanguage('fa');
      await tester.pump();
      expect(find.text('نام فایل'), findsOneWidget);
      expect(find.text('حجم'), findsOneWidget);
      expect(find.text('وضعیت'), findsOneWidget);
      expect(find.text('سرعت'), findsOneWidget);
      expect(find.text('زمان باقی‌مانده'), findsOneWidget);
      expect(find.text('پیشرفت'), findsOneWidget);
      expect(find.text('هنوز دانلودی وجود ندارد'), findsOneWidget);
      expect(find.text('دسته‌بندی‌ها'), findsOneWidget);
      expect(find.text('0 فایل'), findsOneWidget);

      // Switch to Arabic (ar)
      await AppStrings.instance.setLanguage('ar');
      await tester.pump();
      expect(find.text('اسم الملف'), findsOneWidget);
      expect(find.text('لا توجد تنزيلات بعد'), findsOneWidget);
      expect(find.text('الفئات'), findsOneWidget);
      expect(find.text('0 ملفات'), findsOneWidget);

      // Switch to Japanese (ja)
      await AppStrings.instance.setLanguage('ja');
      await tester.pump();
      expect(find.text('ファイル名'), findsOneWidget);
      expect(find.text('ダウンロードはまだありません'), findsOneWidget);
      expect(find.text('カテゴリ'), findsOneWidget);

      // Switch to German (de)
      await AppStrings.instance.setLanguage('de');
      await tester.pump();
      expect(find.text('Dateiname'), findsOneWidget);
      expect(find.text('Noch keine Downloads'), findsOneWidget);
      expect(find.text('Kategorien'), findsOneWidget);
    },
  );
}
