import 'package:download_manager/core/localization/app_strings.dart';
import 'package:download_manager/core/theme/app_theme_controller.dart';
import 'package:download_manager/core/widgets/main_window.dart';
import 'package:material_ui/material_ui.dart';

class DownloadManagerApp extends StatefulWidget {
  const DownloadManagerApp({super.key});

  @override
  State<DownloadManagerApp> createState() => _DownloadManagerAppState();
}

class _DownloadManagerAppState extends State<DownloadManagerApp> {
  @override
  void initState() {
    super.initState();
    AppThemeController.instance.load();
    AppStrings.instance.load();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        AppThemeController.instance,
        AppStrings.instance,
      ]),
      builder: (context, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'FluxDM',
          theme: AppThemeController.instance.buildThemeData(),
          builder: (context, child) {
            return Directionality(
              textDirection: AppStrings.instance.textDirection,
              child: child ?? const SizedBox.shrink(),
            );
          },
          home: const MainWindow(),
        );
      },
    );
  }
}
