import 'package:download_manager/core/theme/app_colors.dart';
import 'package:material_ui/material_ui.dart';

class AppTheme {
  static ThemeData get darkTheme {
    return ThemeData(
      brightness: .dark,
      scaffoldBackgroundColor: AppColors.background,
      primaryColor: AppColors.accent,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.accent,
        surface: AppColors.surface,
      ),
      fontFamily: 'Segoe UI',
      dividerColor: AppColors.border,
      useMaterial3: true,
    );
  }
}
