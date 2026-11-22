import 'package:download_manager/core/localization/translations_data.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LanguageOption {
  final String code;
  final String nativeName;
  final String englishName;
  final String badge;
  final bool isRtl;

  const LanguageOption({
    required this.code,
    required this.nativeName,
    required this.englishName,
    required this.badge,
    this.isRtl = false,
  });
}

class AppStrings extends ChangeNotifier {
  static const String _prefKey = 'fluxdm_language_v1';
  static final AppStrings instance = AppStrings._();

  AppStrings._();

  String _code = 'system';

  String get code => _code;

  String get effectiveCode => _code == 'system' ? 'en' : _code;

  bool get isRtl {
    final c = effectiveCode;
    return c == 'fa' || c == 'ar' || c == 'he' || c == 'ur';
  }

  TextDirection get textDirection =>
      isRtl ? TextDirection.rtl : TextDirection.ltr;

  /// Every language listed here has a real native translation dictionary in
  /// [kFluxTranslations] (or is English), so switching to any item translates
  /// the interface immediately.
  static const List<LanguageOption> allLanguages = [
    LanguageOption(code: 'system', nativeName: "Windows' language (English)", englishName: '', badge: 'SYS'),
    LanguageOption(code: 'en', nativeName: 'English', englishName: '', badge: 'GB'),
    LanguageOption(code: 'fa', nativeName: 'فارسی', englishName: 'Persian', badge: 'IR', isRtl: true),
    LanguageOption(code: 'ar', nativeName: 'العربية', englishName: 'Arabic', badge: 'SA', isRtl: true),
    LanguageOption(code: 'az', nativeName: 'Azərbaycan', englishName: 'Azerbaijani', badge: 'AZ'),
    LanguageOption(code: 'bn', nativeName: 'বাংলা', englishName: 'Bangla', badge: 'BD'),
    LanguageOption(code: 'bg', nativeName: 'Български', englishName: 'Bulgarian', badge: 'BG'),
    LanguageOption(code: 'zh_CN', nativeName: '简体中文', englishName: 'Chinese (Simplified)', badge: 'CN'),
    LanguageOption(code: 'zh_TW', nativeName: '繁體中文', englishName: 'Chinese (Traditional)', badge: 'TW'),
    LanguageOption(code: 'hr', nativeName: 'Hrvatski', englishName: 'Croatian', badge: 'HR'),
    LanguageOption(code: 'cs', nativeName: 'Čeština', englishName: 'Czech', badge: 'CZ'),
    LanguageOption(code: 'da', nativeName: 'Dansk', englishName: 'Danish', badge: 'DK'),
    LanguageOption(code: 'nl', nativeName: 'Nederlands', englishName: 'Dutch', badge: 'NL'),
    LanguageOption(code: 'fi', nativeName: 'Suomi', englishName: 'Finnish', badge: 'FI'),
    LanguageOption(code: 'fr_CA', nativeName: 'Français (Canada)', englishName: 'French (Canada)', badge: 'CA'),
    LanguageOption(code: 'fr', nativeName: 'Français (France)', englishName: 'French (France)', badge: 'FR'),
    LanguageOption(code: 'de', nativeName: 'Deutsch', englishName: 'German', badge: 'DE'),
    LanguageOption(code: 'el', nativeName: 'Ελληνικά', englishName: 'Greek', badge: 'GR'),
    LanguageOption(code: 'he', nativeName: 'עברית', englishName: 'Hebrew', badge: 'IL', isRtl: true),
    LanguageOption(code: 'hi', nativeName: 'हिन्दी', englishName: 'Hindi', badge: 'IN'),
    LanguageOption(code: 'hu', nativeName: 'Magyar', englishName: 'Hungarian', badge: 'HU'),
    LanguageOption(code: 'id', nativeName: 'Bahasa Indonesia', englishName: 'Indonesian', badge: 'ID'),
    LanguageOption(code: 'it', nativeName: 'Italiano', englishName: 'Italian', badge: 'IT'),
    LanguageOption(code: 'ja', nativeName: '日本語', englishName: 'Japanese', badge: 'JP'),
    LanguageOption(code: 'ko', nativeName: '한국어', englishName: 'Korean', badge: 'KR'),
    LanguageOption(code: 'ms', nativeName: 'Bahasa Melayu', englishName: 'Malay', badge: 'MY'),
    LanguageOption(code: 'nb', nativeName: 'Norsk bokmål', englishName: 'Norwegian', badge: 'NO'),
    LanguageOption(code: 'pl', nativeName: 'Polski', englishName: 'Polish', badge: 'PL'),
    LanguageOption(code: 'pt_BR', nativeName: 'Português (Brasil)', englishName: 'Portuguese (Brazil)', badge: 'BR'),
    LanguageOption(code: 'pt_PT', nativeName: 'Português (Portugal)', englishName: 'Portuguese (Portugal)', badge: 'PT'),
    LanguageOption(code: 'ro', nativeName: 'Română', englishName: 'Romanian', badge: 'RO'),
    LanguageOption(code: 'ru', nativeName: 'Русский', englishName: 'Russian', badge: 'RU'),
    LanguageOption(code: 'sr_Cyrl', nativeName: 'Српски (ћирилица)', englishName: 'Serbian', badge: 'RS'),
    LanguageOption(code: 'sk', nativeName: 'Slovenčina', englishName: 'Slovak', badge: 'SK'),
    LanguageOption(code: 'es_MX', nativeName: 'Español (México)', englishName: 'Spanish (Mexico)', badge: 'MX'),
    LanguageOption(code: 'es', nativeName: 'Español (España)', englishName: 'Spanish (Spain)', badge: 'ES'),
    LanguageOption(code: 'sv', nativeName: 'Svenska', englishName: 'Swedish', badge: 'SE'),
    LanguageOption(code: 'th', nativeName: 'ไทย', englishName: 'Thai', badge: 'TH'),
    LanguageOption(code: 'tr', nativeName: 'Türkçe', englishName: 'Turkish', badge: 'TR'),
    LanguageOption(code: 'uk', nativeName: 'Українська', englishName: 'Ukrainian', badge: 'UA'),
    LanguageOption(code: 'ur', nativeName: 'اردو', englishName: 'Urdu', badge: 'PK', isRtl: true),
    LanguageOption(code: 'vi', nativeName: 'Tiếng Việt', englishName: 'Vietnamese', badge: 'VN'),
  ];

  String t(String key) {
    final lang = effectiveCode;
    if (lang == 'en') return key;
    final exact = kFluxTranslations[lang]?[key];
    if (exact != null) return exact;
    if (lang.contains('_')) {
      final base = lang.split('_').first;
      final baseMatch = kFluxTranslations[base]?[key];
      if (baseMatch != null) return baseMatch;
    }
    return key;
  }

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefKey);
      if (saved != null && saved.isNotEmpty) {
        _code = saved;
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> setLanguage(String code) async {
    if (_code == code) return;
    _code = code;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, code);
    } catch (_) {}
  }
}
