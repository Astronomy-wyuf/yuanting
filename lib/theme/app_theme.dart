import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// 皮肤 ID — 对齐原型 data-skin
enum AppSkin {
  day,
  night,
  paper,
  ink;

  static AppSkin parse(String? raw) {
    switch (raw) {
      case 'night':
        return AppSkin.night;
      case 'paper':
        return AppSkin.paper;
      case 'ink':
        return AppSkin.ink;
      default:
        return AppSkin.day;
    }
  }

  bool get isDark => this == night || this == ink;

  String get label => switch (this) {
        day => '日间',
        night => '夜间',
        paper => '纸感',
        ink => '墨青',
      };
}

/// 品牌色扩展：accent / accentSoft 随皮肤变化
@immutable
class BrandColors extends ThemeExtension<BrandColors> {
  final Color accent;
  final Color accentSoft;
  final Color cover1;
  final Color cover2;
  final Color cover3;
  final Color cover4;

  const BrandColors({
    required this.accent,
    required this.accentSoft,
    required this.cover1,
    required this.cover2,
    required this.cover3,
    required this.cover4,
  });

  List<Color> get covers => [cover1, cover2, cover3, cover4];

  static BrandColors of(BuildContext context) {
    return Theme.of(context).extension<BrandColors>() ??
        const BrandColors(
          accent: AppColors.accent,
          accentSoft: AppColors.accentSoft,
          cover1: Color(0xFFD8E4F8),
          cover2: Color(0xFFC9DDD2),
          cover3: Color(0xFFF0DCC8),
          cover4: Color(0xFFE2D4EA),
        );
  }

  @override
  BrandColors copyWith({
    Color? accent,
    Color? accentSoft,
    Color? cover1,
    Color? cover2,
    Color? cover3,
    Color? cover4,
  }) {
    return BrandColors(
      accent: accent ?? this.accent,
      accentSoft: accentSoft ?? this.accentSoft,
      cover1: cover1 ?? this.cover1,
      cover2: cover2 ?? this.cover2,
      cover3: cover3 ?? this.cover3,
      cover4: cover4 ?? this.cover4,
    );
  }

  @override
  BrandColors lerp(ThemeExtension<BrandColors>? other, double t) {
    if (other is! BrandColors) return this;
    return BrandColors(
      accent: Color.lerp(accent, other.accent, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      cover1: Color.lerp(cover1, other.cover1, t)!,
      cover2: Color.lerp(cover2, other.cover2, t)!,
      cover3: Color.lerp(cover3, other.cover3, t)!,
      cover4: Color.lerp(cover4, other.cover4, t)!,
    );
  }
}

/// 默认日间色板（兼容旧硬编码引用）
class AppColors {
  AppColors._();

  static const ink = Color(0xFF1A1A1A);
  static const paper = Color(0xFFFAFAF8);
  static const paperDeep = Color(0xFFF4F4F2);
  static const mist = Color(0xFFEBEBE8);
  static const accent = Color(0xFF2F6FED);
  static const accentSoft = Color(0xFFEAF1FF);
  static const forest = Color(0xFF1A7F4B);
  static const night = Color(0xFF111113);
  static const nightLift = Color(0xFF1C1C1E);
  static const nightLine = Color(0xFF2C2C2E);
  static const moon = Color(0xFFF2F2F0);
}

class AppTheme {
  AppTheme._();

  static const brandName = '源听';
  static const brandNameEn = 'YuanTing';
  static const brandTag = '自定义书源 · 聚合听书';

  static ThemeData forSkin(AppSkin skin) {
    switch (skin) {
      case AppSkin.day:
        return _build(
          brightness: Brightness.light,
          ink: const Color(0xFF1A1A1A),
          mute: const Color(0xFF8A8A8A),
          soft: const Color(0xFFF4F4F2),
          line: const Color(0xFFEBEBE8),
          card: const Color(0xFFFFFFFF),
          surface: const Color(0xFFFAFAF8),
          brand: const BrandColors(
            accent: Color(0xFF2F6FED),
            accentSoft: Color(0xFFEAF1FF),
            cover1: Color(0xFFD8E4F8),
            cover2: Color(0xFFC9DDD2),
            cover3: Color(0xFFF0DCC8),
            cover4: Color(0xFFE2D4EA),
          ),
        );
      case AppSkin.night:
        return _build(
          brightness: Brightness.dark,
          ink: const Color(0xFFF2F2F0),
          mute: const Color(0xFF8E8E8E),
          soft: const Color(0xFF1C1C1E),
          line: const Color(0xFF2C2C2E),
          card: const Color(0xFF242426),
          surface: const Color(0xFF111113),
          brand: const BrandColors(
            accent: Color(0xFF6B9BFF),
            accentSoft: Color(0xFF1A2740),
            cover1: Color(0xFF2A3550),
            cover2: Color(0xFF243830),
            cover3: Color(0xFF3A2E24),
            cover4: Color(0xFF322840),
          ),
        );
      case AppSkin.paper:
        return _build(
          brightness: Brightness.light,
          ink: const Color(0xFF2C2418),
          mute: const Color(0xFF9A8B74),
          soft: const Color(0xFFF3EBDD),
          line: const Color(0xFFE6DCCB),
          card: const Color(0xFFFFFAF1),
          surface: const Color(0xFFF7F0E4),
          brand: const BrandColors(
            accent: Color(0xFFB86A2C),
            accentSoft: Color(0xFFF5E6D4),
            cover1: Color(0xFFE8D5B8),
            cover2: Color(0xFFD6C4A8),
            cover3: Color(0xFFC9B89A),
            cover4: Color(0xFFDECEB4),
          ),
        );
      case AppSkin.ink:
        return _build(
          brightness: Brightness.dark,
          ink: const Color(0xFFE8EEF5),
          mute: const Color(0xFF7A8FA8),
          soft: const Color(0xFF152033),
          line: const Color(0xFF24324A),
          card: const Color(0xFF1A2740),
          surface: const Color(0xFF0D1524),
          brand: const BrandColors(
            accent: Color(0xFF3DD6C6),
            accentSoft: Color(0xFF16363A),
            cover1: Color(0xFF1E3A5F),
            cover2: Color(0xFF1A4A45),
            cover3: Color(0xFF2A3558),
            cover4: Color(0xFF243A50),
          ),
        );
    }
  }

  /// 兼容旧调用
  static ThemeData light() => forSkin(AppSkin.day);
  static ThemeData dark() => forSkin(AppSkin.night);

  static ThemeData _build({
    required Brightness brightness,
    required Color ink,
    required Color mute,
    required Color soft,
    required Color line,
    required Color card,
    required Color surface,
    required BrandColors brand,
  }) {
    final isDark = brightness == Brightness.dark;
    final display = GoogleFonts.notoSansSc(
      fontWeight: FontWeight.w700,
      height: 1.2,
      letterSpacing: -0.3,
    );
    final body = GoogleFonts.notoSansSc(height: 1.45, letterSpacing: 0);

    final scheme = ColorScheme(
      brightness: brightness,
      primary: ink,
      onPrimary: surface,
      secondary: brand.accent,
      onSecondary: Colors.white,
      tertiary: AppColors.forest,
      error: isDark ? const Color(0xFFFF6B6B) : const Color(0xFFE24B4B),
      onError: Colors.white,
      surface: surface,
      onSurface: ink,
      onSurfaceVariant: mute,
      outline: mute.withValues(alpha: 0.55),
      outlineVariant: line,
      surfaceContainerLowest: card,
      surfaceContainerLow: soft,
      surfaceContainer: line,
      surfaceContainerHigh: soft,
      surfaceContainerHighest: line,
      secondaryContainer: brand.accentSoft,
      onSecondaryContainer: brand.accent,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: surface,
      splashFactory: InkSparkle.splashFactory,
      extensions: [brand],
      textTheme: TextTheme(
        displayLarge: display.copyWith(fontSize: 40, color: ink),
        displayMedium: display.copyWith(fontSize: 32, color: ink),
        displaySmall: display.copyWith(fontSize: 26, color: ink),
        headlineLarge: display.copyWith(fontSize: 28, color: ink),
        headlineMedium: display.copyWith(fontSize: 22, color: ink),
        headlineSmall: display.copyWith(fontSize: 18, color: ink),
        titleLarge: body.copyWith(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: ink,
        ),
        titleMedium: body.copyWith(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: ink,
        ),
        titleSmall: body.copyWith(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: ink,
        ),
        bodyLarge: body.copyWith(fontSize: 16, color: ink),
        bodyMedium: body.copyWith(fontSize: 14, color: ink),
        bodySmall: body.copyWith(fontSize: 12, color: mute),
        labelLarge: body.copyWith(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
          color: ink,
        ),
        labelMedium: body.copyWith(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
          color: mute,
        ),
      ),
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: ink,
        systemOverlayStyle:
            isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        titleTextStyle: display.copyWith(fontSize: 20, color: ink),
      ),
      dividerTheme: DividerThemeData(
        color: line.withValues(alpha: 0.9),
        thickness: 1,
        space: 1,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: brand.accent,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          minimumSize: const Size(44, 44),
          textStyle: body.copyWith(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          side: BorderSide(color: line),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          minimumSize: const Size(44, 44),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: brand.accent,
          textStyle: body.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: soft,
        hintStyle: body.copyWith(color: mute),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: brand.accent, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: card,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: ink,
        contentTextStyle: body.copyWith(color: surface),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: brand.accent,
        linearTrackColor: line,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: brand.accent,
        inactiveTrackColor: line,
        thumbColor: brand.accent,
        overlayColor: brand.accentSoft.withValues(alpha: 0.6),
        trackHeight: 3,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.selected)) return Colors.white;
          return mute;
        }),
        trackColor: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.selected)) return brand.accent;
          return line;
        }),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: soft,
        selectedColor: brand.accentSoft,
        labelStyle: body.copyWith(fontSize: 13, fontWeight: FontWeight.w500),
        side: BorderSide(color: line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
      cardTheme: CardThemeData(
        color: card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: line),
        ),
      ),
    );
  }
}
