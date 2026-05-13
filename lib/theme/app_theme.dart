import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// TezKetKaz dark-first design system (Master Design v1).
///
/// The whole app now lives on a near-black canvas with a lime accent, glass
/// surfaces (translucent white over the ink background) and a strict white
/// text hierarchy (1.0 / 0.55 / 0.35). Drop shadows are replaced by lime
/// glows where appropriate. Both [AppTheme.light] and [AppTheme.dark] return
/// the same dark palette — there is no longer a separate light skin, so
/// hardcoded references to AppColors continue to render correctly.
class AppColors {
  // ── Brand ────────────────────────────────────────────────────────────────
  static const primary = Color(0xFF06C167);          // --lime
  static const primaryDark = Color(0xFF04A357);
  static const primaryLight = Color(0x2606C167);     // 15% lime-soft
  static const primarySoft = Color(0x6606C167);      // 40% lime-glow

  // ── Surfaces (ink-deep base + glass cards) ──────────────────────────────
  static const bg = Color(0xFF050507);               // --ink-deep
  static const surface = Color(0xFF08080C);          // --ink
  static const surfaceElevated = Color(0xFF0D0D14);  // hover/elevated glass
  static const surfaceMuted = Color(0x12FFFFFF);     // ~7% white (glass-strong)
  static const border = Color(0x14FFFFFF);           // ~8% white
  static const borderLight = Color(0x0AFFFFFF);      // ~4% white
  static const overlay = Color(0xB3000000);

  // ── Text (1.0 / 0.55 / 0.35 opacity tiers) ──────────────────────────────
  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color(0x8CFFFFFF);    // ~55%
  static const textHint = Color(0x59FFFFFF);         // ~35%

  // ── Semantic ────────────────────────────────────────────────────────────
  static const success = Color(0xFF06C167);
  static const successLight = Color(0x2606C167);
  static const warning = Color(0xFFF5B95C);
  static const warningLight = Color(0x26F5B95C);
  static const error = Color(0xFFFF6464);
  static const errorLight = Color(0x26FF6464);
  static const info = Color(0xFF66B8F0);
  static const gold = Color(0xFFD4A85C);

  // ── Role accents (kept warm so role separation still reads) ─────────────
  static const courier = Color(0xFFFF7E33);
  static const courierLight = Color(0x33FF7E33);
  static const shop = Color(0xFF66B8F0);
  static const shopLight = Color(0x2666B8F0);

  // ── Categories (frosted glass pastels on dark) ──────────────────────────
  static const catProduce = Color(0x2606C167);
  static const catProduceFg = Color(0xFF06C167);
  static const catMeat = Color(0x26FF6464);
  static const catMeatFg = Color(0xFFFF6464);
  static const catDairy = Color(0x2666B8F0);
  static const catDairyFg = Color(0xFF66B8F0);
  static const catBakery = Color(0x26F5B95C);
  static const catBakeryFg = Color(0xFFF5B95C);
  static const catDrinks = Color(0x269581FF);
  static const catDrinksFg = Color(0xFFB9A8FF);
  static const catGrocery = Color(0x14FFFFFF);
  static const catGroceryFg = Color(0xFFFFFFFF);

  // ── Ink helpers retained for legacy callers (bottom nav, splash, …) ─────
  static const neutralInk = Color(0xFF08080C);
  static const neutralInkSoft = Color(0xFF0D0D14);
}

/// Dark counterpart. Now an alias of [AppColors] — the dark-first palette is
/// the canonical surface across the whole app.
class AppDarkColors {
  static const primary = AppColors.primary;
  static const primaryDark = AppColors.primaryDark;
  static const primaryLight = AppColors.primaryLight;
  static const primarySoft = AppColors.primarySoft;

  static const courier = AppColors.courier;
  static const courierLight = AppColors.courierLight;
  static const shop = AppColors.shop;
  static const shopLight = AppColors.shopLight;

  static const bg = AppColors.bg;
  static const surface = AppColors.surface;
  static const surfaceElevated = AppColors.surfaceElevated;
  static const surfaceMuted = AppColors.surfaceMuted;
  static const border = AppColors.border;
  static const borderLight = AppColors.borderLight;
  static const overlay = AppColors.overlay;

  static const textPrimary = AppColors.textPrimary;
  static const textSecondary = AppColors.textSecondary;
  static const textHint = AppColors.textHint;

  static const success = AppColors.success;
  static const successLight = AppColors.successLight;
  static const warning = AppColors.warning;
  static const warningLight = AppColors.warningLight;
  static const error = AppColors.error;
  static const errorLight = AppColors.errorLight;
  static const info = AppColors.info;
}

class AppShadows {
  // Lime-tinted glows replace neutral drop shadows on the dark canvas.
  static const card = [
    BoxShadow(color: Color(0x33000000), blurRadius: 18, offset: Offset(0, 8)),
  ];
  static const cardHover = [
    BoxShadow(color: Color(0x4D000000), blurRadius: 28, offset: Offset(0, 14)),
    BoxShadow(color: Color(0x2606C167), blurRadius: 28, offset: Offset(0, 0)),
  ];
  static const elevated = [
    BoxShadow(color: Color(0x66000000), blurRadius: 40, offset: Offset(0, 18)),
  ];
  // Primary lime CTA — the glow is the shadow.
  static const button = [
    BoxShadow(color: Color(0x6606C167), blurRadius: 28, offset: Offset(0, 12)),
    BoxShadow(color: Color(0x80000000), blurRadius: 16, offset: Offset(0, 8)),
  ];
  static const courierButton = [
    BoxShadow(color: Color(0x66FF7E33), blurRadius: 24, offset: Offset(0, 10)),
  ];
}

class AppRadii {
  static const xs = 8.0;
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 20.0;
  static const xl = 24.0;
  static const pill = 999.0;
}

class AppTheme {
  /// Both light and dark return the same dark-first palette — keeping two
  /// builders preserves call-sites in main.dart and ThemeProvider without
  /// forking the design.
  static ThemeData get light => _build();
  static ThemeData get dark => _build();

  static ThemeData _build() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: const ColorScheme.dark(
        brightness: Brightness.dark,
        primary: AppColors.primary,
        onPrimary: AppColors.bg,
        secondary: AppColors.gold,
        onSecondary: AppColors.bg,
        surface: AppColors.surface,
        onSurface: AppColors.textPrimary,
        surfaceContainerLowest: AppColors.bg,
        surfaceContainerLow: AppColors.surface,
        surfaceContainer: AppColors.surfaceElevated,
        surfaceContainerHigh: AppColors.surfaceMuted,
        surfaceContainerHighest: AppColors.surfaceMuted,
        onSurfaceVariant: AppColors.textSecondary,
        outline: AppColors.border,
        outlineVariant: AppColors.borderLight,
        error: AppColors.error,
        onError: AppColors.bg,
      ),
      scaffoldBackgroundColor: AppColors.bg,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      canvasColor: AppColors.bg,
    );

    final textTheme = GoogleFonts.interTextTheme(base.textTheme).copyWith(
      displayLarge: GoogleFonts.inter(
        fontSize: 34, fontWeight: FontWeight.w900,
        color: AppColors.textPrimary, letterSpacing: -1.1, height: 1.1,
      ),
      displayMedium: GoogleFonts.inter(
        fontSize: 26, fontWeight: FontWeight.w800,
        color: AppColors.textPrimary, letterSpacing: -0.7, height: 1.15,
      ),
      headlineLarge: GoogleFonts.inter(
        fontSize: 22, fontWeight: FontWeight.w800,
        color: AppColors.textPrimary, letterSpacing: -0.5,
      ),
      headlineMedium: GoogleFonts.inter(
        fontSize: 20, fontWeight: FontWeight.w800,
        color: AppColors.textPrimary, letterSpacing: -0.4,
      ),
      headlineSmall: GoogleFonts.inter(
        fontSize: 17, fontWeight: FontWeight.w700,
        color: AppColors.textPrimary, letterSpacing: -0.3,
      ),
      titleLarge: GoogleFonts.inter(
        fontSize: 16, fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      ),
      titleMedium: GoogleFonts.inter(
        fontSize: 15, fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ),
      titleSmall: GoogleFonts.inter(
        fontSize: 13, fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ),
      bodyLarge: GoogleFonts.inter(
        fontSize: 15, fontWeight: FontWeight.w400,
        color: AppColors.textPrimary, height: 1.4,
      ),
      bodyMedium: GoogleFonts.inter(
        fontSize: 14, fontWeight: FontWeight.w400,
        color: AppColors.textSecondary, height: 1.4,
      ),
      bodySmall: GoogleFonts.inter(
        fontSize: 12, fontWeight: FontWeight.w400,
        color: AppColors.textSecondary,
      ),
      labelLarge: GoogleFonts.inter(
        fontSize: 15, fontWeight: FontWeight.w700,
        color: AppColors.bg, letterSpacing: 0.1,
      ),
      labelMedium: GoogleFonts.inter(
        fontSize: 13, fontWeight: FontWeight.w600,
        color: AppColors.textSecondary,
      ),
    );

    return base.copyWith(
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.bg,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: textTheme.headlineSmall,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        actionsIconTheme: const IconThemeData(color: AppColors.textPrimary),
        toolbarHeight: 60,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          // Lime CTA on the dark canvas — high contrast, with a lime glow.
          backgroundColor: WidgetStateProperty.resolveWith((s) {
            if (s.contains(WidgetState.disabled)) return AppColors.surfaceMuted;
            return AppColors.primary;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((s) {
            if (s.contains(WidgetState.disabled)) return AppColors.textHint;
            return AppColors.bg;
          }),
          minimumSize: WidgetStateProperty.all(const Size(double.infinity, 56)),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.pill)),
          ),
          elevation: WidgetStateProperty.all(0),
          textStyle: WidgetStateProperty.all(
            GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 0.1),
          ),
          overlayColor: WidgetStateProperty.resolveWith((s) {
            if (s.contains(WidgetState.pressed)) return Colors.black.withValues(alpha: 0.18);
            return null;
          }),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          backgroundColor: AppColors.surfaceMuted,
          side: BorderSide(color: AppColors.border, width: 1),
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.pill)),
          textStyle: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceMuted,
        hintStyle: GoogleFonts.inter(color: AppColors.textHint, fontWeight: FontWeight.w400),
        labelStyle: GoogleFonts.inter(color: AppColors.textSecondary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
          borderSide: const BorderSide(color: AppColors.error, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.lg),
          side: const BorderSide(color: AppColors.border),
        ),
        margin: EdgeInsets.zero,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.surface,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.textHint,
        showUnselectedLabels: true,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.borderLight,
        thickness: 1,
        space: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.surfaceElevated,
        contentTextStyle: GoogleFonts.inter(
            color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
        behavior: SnackBarBehavior.floating,
        actionTextColor: AppColors.primary,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surfaceMuted,
        labelStyle: GoogleFonts.inter(
            fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.pill)),
        side: const BorderSide(color: AppColors.border),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surfaceElevated,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.xl)),
        titleTextStyle: textTheme.headlineSmall,
        contentTextStyle: textTheme.bodyMedium,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.xl)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.surfaceElevated,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
          side: const BorderSide(color: AppColors.border),
        ),
        textStyle: GoogleFonts.inter(color: AppColors.textPrimary, fontSize: 14),
      ),
    );
  }
}
