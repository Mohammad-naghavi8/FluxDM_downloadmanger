import 'package:download_manager/core/theme/app_theme.dart';
import 'package:download_manager/core/widgets/main_window.dart';
import 'package:material_ui/material_ui.dart';

class DownloadManagerApp extends StatelessWidget {
  const DownloadManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: "Internet Download Manager",
      theme: AppTheme.darkTheme,
      home: const MainWindow(),
    );
  }
}
