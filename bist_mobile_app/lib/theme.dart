import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Uygulamanın renk paleti — borsa/fintek temasına uygun.
class AppColors {
  // Marka rengi (yeşil — büyüme, kazanç)
  static const Color primary = Color(0xFF10B981); // zümrüt yeşili
  static const Color primaryDark = Color(0xFF059669);

  // Fiyat renkleri (her iki temada da ortak)
  static const Color up = Color(0xFF16C784); // yükseliş yeşili
  static const Color down = Color(0xFFEA3943); // düşüş kırmızısı

  // Açık tema
  static const Color lightBg = Color(0xFFF6F8FA);
  static const Color lightCard = Color(0xFFFFFFFF);
  static const Color lightText = Color(0xFF0F172A);
  static const Color lightSubtle = Color(0xFF64748B);

  // Koyu tema (lacivert-finans)
  static const Color darkBg = Color(0xFF0B1622);
  static const Color darkCard = Color(0xFF16202E);
  static const Color darkElevated = Color(0xFF1E2A3A);
  static const Color darkText = Color(0xFFE6EDF3);
  static const Color darkSubtle = Color(0xFF8B98A9);
}

/// Tema kontrolcüsü — açık/koyu geçiş + kalıcı kayıt.
class ThemeController extends ChangeNotifier {
  static const _prefKey = 'theme_mode';
  ThemeMode _mode = ThemeMode.light;

  ThemeMode get mode => _mode;
  bool get isDark => _mode == ThemeMode.dark;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefKey);
    if (saved == 'dark') {
      _mode = ThemeMode.dark;
    } else if (saved == 'light') {
      _mode = ThemeMode.light;
    } else {
      _mode = ThemeMode.system;
    }
    notifyListeners();
  }

  Future<void> toggle() async {
    _mode = _mode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, _mode == ThemeMode.dark ? 'dark' : 'light');
  }

  Future<void> setMode(ThemeMode mode) async {
    _mode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefKey,
      mode == ThemeMode.dark ? 'dark' : mode == ThemeMode.light ? 'light' : 'system',
    );
  }
}

/// Global tema kontrolcüsü.
final themeController = ThemeController();

class AppTheme {
  // ── AÇIK TEMA ──────────────────────────────────────────────
  static ThemeData get light {
    final base = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.light,
    ).copyWith(
      primary: AppColors.primary,
      surface: AppColors.lightCard,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: base,
      scaffoldBackgroundColor: AppColors.lightBg,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.lightBg,
        foregroundColor: AppColors.lightText,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: AppColors.lightText,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.lightCard,
        elevation: 0,
        shadowColor: Colors.black.withValues(alpha: 0.06),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: EdgeInsets.zero,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.lightCard,
        indicatorColor: AppColors.primary.withValues(alpha: 0.15),
        elevation: 0,
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        ),
      ),
      textTheme: _textTheme(AppColors.lightText, AppColors.lightSubtle),
      iconTheme: const IconThemeData(color: AppColors.lightText),
      dividerColor: Colors.grey.shade200,
    );
  }

  // ── KOYU TEMA ──────────────────────────────────────────────
  static ThemeData get dark {
    final base = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.dark,
    ).copyWith(
      primary: AppColors.primary,
      surface: AppColors.darkCard,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: base,
      scaffoldBackgroundColor: AppColors.darkBg,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.darkBg,
        foregroundColor: AppColors.darkText,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: AppColors.darkText,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.darkCard,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: EdgeInsets.zero,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.darkCard,
        indicatorColor: AppColors.primary.withValues(alpha: 0.22),
        elevation: 0,
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        ),
      ),
      textTheme: _textTheme(AppColors.darkText, AppColors.darkSubtle),
      iconTheme: const IconThemeData(color: AppColors.darkText),
      dividerColor: Colors.white.withValues(alpha: 0.08),
    );
  }

  static TextTheme _textTheme(Color main, Color subtle) {
    return TextTheme(
      titleLarge: TextStyle(color: main, fontWeight: FontWeight.bold),
      titleMedium: TextStyle(color: main, fontWeight: FontWeight.w600),
      bodyLarge: TextStyle(color: main),
      bodyMedium: TextStyle(color: main),
      bodySmall: TextStyle(color: subtle),
      labelMedium: TextStyle(color: subtle),
    );
  }
}
