import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FluxThemePalette {
  final String name;
  final Color accent;
  final Color accentDark;
  final Color background;
  final Color surface;
  final Color sidebar;
  final Color menuBar;
  final Color border;
  final Color toolbarFg;
  final Brightness brightness;

  const FluxThemePalette({
    required this.name,
    required this.accent,
    required this.accentDark,
    required this.background,
    required this.surface,
    required this.sidebar,
    required this.menuBar,
    required this.border,
    this.toolbarFg = const Color(0xFF0A0A0A),
    this.brightness = Brightness.dark,
  });
}

class AppThemeController extends ChangeNotifier {
  static const String _themeKey = 'fluxdm_theme_v1';
  static const String _darkKey = 'fluxdm_always_dark_v1';
  static final AppThemeController instance = AppThemeController._();

  AppThemeController._();

  String _themeName = 'Classic';
  bool _alwaysDark = true;

  String get themeName => _themeName;
  bool get alwaysDark => _alwaysDark;

  static const Map<String, FluxThemePalette> _darkPalettes = {
    'Classic': FluxThemePalette(
      name: 'Classic',
      accent: Color(0xFF00D58A),
      accentDark: Color(0xFF0F3D2E),
      background: Color(0xFF0B0F0D),
      surface: Color(0xFF141A17),
      sidebar: Color(0xFF1A1A1A),
      menuBar: Color(0xFF181818),
      border: Color(0xFF29312D),
    ),
    'Native': FluxThemePalette(
      name: 'Native',
      accent: Color(0xFF60CDFF),
      accentDark: Color(0xFF173A4C),
      background: Color(0xFF1A1A1A),
      surface: Color(0xFF242424),
      sidebar: Color(0xFF1E1E1E),
      menuBar: Color(0xFF191919),
      border: Color(0xFF343434),
    ),
    'High contrast': FluxThemePalette(
      name: 'High contrast',
      accent: Color(0xFFFFEE00),
      accentDark: Color(0xFF3A3600),
      background: Color(0xFF000000),
      surface: Color(0xFF0A0A0A),
      sidebar: Color(0xFF000000),
      menuBar: Color(0xFF000000),
      border: Color(0xFFFFFFFF),
    ),
    'Metro': FluxThemePalette(
      name: 'Metro',
      accent: Color(0xFF00B4D8),
      accentDark: Color(0xFF0B3948),
      background: Color(0xFF0F172A),
      surface: Color(0xFF1E293B),
      sidebar: Color(0xFF162033),
      menuBar: Color(0xFF111827),
      border: Color(0xFF334155),
    ),
    'Adwaita': FluxThemePalette(
      name: 'Adwaita',
      accent: Color(0xFF3584E4),
      accentDark: Color(0xFF1A365D),
      background: Color(0xFF1E1E1E),
      surface: Color(0xFF2B2B2B),
      sidebar: Color(0xFF242424),
      menuBar: Color(0xFF202020),
      border: Color(0xFF3D3D3D),
      toolbarFg: Colors.white,
    ),
    'Breeze': FluxThemePalette(
      name: 'Breeze',
      accent: Color(0xFF3DAEE9),
      accentDark: Color(0xFF173A4E),
      background: Color(0xFF1B1E20),
      surface: Color(0xFF232629),
      sidebar: Color(0xFF1F2225),
      menuBar: Color(0xFF181B1D),
      border: Color(0xFF31363B),
    ),
    'Luna': FluxThemePalette(
      name: 'Luna',
      accent: Color(0xFF4C9AFF),
      accentDark: Color(0xFF172B4D),
      background: Color(0xFF0D1526),
      surface: Color(0xFF16223B),
      sidebar: Color(0xFF121C30),
      menuBar: Color(0xFF0F182A),
      border: Color(0xFF293B5F),
    ),
    'Aero': FluxThemePalette(
      name: 'Aero',
      accent: Color(0xFF56CCF2),
      accentDark: Color(0xFF163A47),
      background: Color(0xFF121921),
      surface: Color(0xFF1B2531),
      sidebar: Color(0xFF16202A),
      menuBar: Color(0xFF131B24),
      border: Color(0xFF2E3E50),
    ),
    'Aqua': FluxThemePalette(
      name: 'Aqua',
      accent: Color(0xFF0A84FF),
      accentDark: Color(0xFF123254),
      background: Color(0xFF18181D),
      surface: Color(0xFF23232A),
      sidebar: Color(0xFF1D1D23),
      menuBar: Color(0xFF19191F),
      border: Color(0xFF34343E),
      toolbarFg: Colors.white,
    ),
  };

  FluxThemePalette get palette {
    final base = _darkPalettes[_themeName] ?? _darkPalettes['Classic']!;
    if (_alwaysDark) return base;
    return FluxThemePalette(
      name: base.name,
      accent: base.accent,
      accentDark: base.accent.withValues(alpha: 0.16),
      background: const Color(0xFFF3F4F6),
      surface: const Color(0xFFFFFFFF),
      sidebar: const Color(0xFFE9ECEF),
      menuBar: const Color(0xFFE5E7EB),
      border: const Color(0xFFD1D5DB),
      toolbarFg: base.toolbarFg,
      brightness: Brightness.light,
    );
  }

  ThemeData buildThemeData() {
    final p = palette;
    final isDark = p.brightness == Brightness.dark;
    return ThemeData(
      brightness: p.brightness,
      scaffoldBackgroundColor: p.background,
      canvasColor: p.surface,
      dividerColor: p.border,
      colorScheme: (isDark ? const ColorScheme.dark() : const ColorScheme.light())
          .copyWith(
            primary: p.accent,
            secondary: p.accent,
            surface: p.surface,
          ),
      dialogTheme: DialogThemeData(backgroundColor: p.surface),
      textTheme: TextTheme(
        bodyLarge: TextStyle(color: isDark ? Colors.white : const Color(0xFF111827)),
        bodyMedium: TextStyle(color: isDark ? const Color(0xFFE5E7EB) : const Color(0xFF1F2937)),
        bodySmall: TextStyle(color: isDark ? const Color(0xFF9CA3AF) : const Color(0xFF4B5563)),
      ),
    );
  }

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedTheme = prefs.getString(_themeKey);
      final savedDark = prefs.getBool(_darkKey);
      if (savedTheme != null && _darkPalettes.containsKey(savedTheme)) {
        _themeName = savedTheme;
      }
      if (savedDark != null) {
        _alwaysDark = savedDark;
      }
      notifyListeners();
    } catch (_) {}
  }

  Future<void> setTheme(String name) async {
    if (!_darkPalettes.containsKey(name) || _themeName == name) return;
    _themeName = name;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_themeKey, name);
    } catch (_) {}
  }

  Future<void> setAlwaysDark(bool value) async {
    if (_alwaysDark == value) return;
    _alwaysDark = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_darkKey, value);
    } catch (_) {}
  }
}
