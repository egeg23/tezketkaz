import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Modern delivery-app design system inspired by Yandex Eda / Wolt / Uber Eats.
class AppColors {
  // Brand — vibrant green with depth
  static const primary = Color(0xFF14A44D);       // Bolder, saturated green
  static const primaryDark = Color(0xFF0E8B40);
  static const primaryLight = Color(0xFFEAF8F0);
  static const primarySoft = Color(0xFFD3F1DD);

  // Courier accent — energetic orange-red
  static const courier = Color(0xFFFF5630);
  static const courierLight = Color(0xFFFFF1EC);

  // Shop accent — premium indigo
  static const shop = Color(0xFF4338CA);
  static const shopLight = Color(0xFFEEF0FF);

  // Backgrounds & surfaces
  static const bg = Color(0xFFF7F8FA);             // Subtle warm grey
  static const surface = Color(0xFFFFFFFF);
  static const surfaceElevated = Color(0xFFFFFFFF);
  static const surfaceMuted = Color(0xFFF1F3F5);
  static const border = Color(0xFFEAEEF2);
  static const borderLight = Color(0xFFF1F3F6);
  static const overlay = Color(0x66000000);

  // Text
  static const textPrimary = Color(0xFF0E1318);
  static const textSecondary = Color(0xFF5A6470);
  static const textHint = Color(0xFF96A0AD);

  // Status
  static const success = Color(0xFF14A44D);
  static const successLight = Color(0xFFEAF8F0);
  static const warning = Color(0xFFFF9F1C);
  static const warningLight = Color(0xFFFFF6E5);
  static const error = Color(0xFFE5484D);
  static const errorLight = Color(0xFFFEEEEF);
  static const info = Color(0xFF3B82F6);

  // Categories — pastel pairs (background, accent)
  static const catProduce = Color(0xFFEAF8F0);
  static const catProduceFg = Color(0xFF14A44D);
  static const catMeat = Color(0xFFFEEEEF);
  static const catMeatFg = Color(0xFFE5484D);
  static const catDairy = Color(0xFFE8F2FE);
  static const catDairyFg = Color(0xFF2570F0);
  static const catBakery = Color(0xFFFFF6E5);
  static const catBakeryFg = Color(0xFFFF9F1C);
  static const catDrinks = Color(0xFFF3EBFA);
  static const catDrinksFg = Color(0xFF7E57C2);
  static const catGrocery = Color(0xFFEFF1F4);
  static const catGroceryFg = Color(0xFF5A6470);
}

class AppShadows {
  // Layered shadows — soft, warm, never harsh black
  static const card = [
    BoxShadow(color: Color(0x08000000), blurRadius: 1, offset: Offset(0, 1)),
    BoxShadow(color: Color(0x0A0E1318), blurRadius: 16, offset: Offset(0, 6)),
  ];
  static const cardHover = [
    BoxShadow(color: Color(0x0A000000), blurRadius: 2, offset: Offset(0, 2)),
    BoxShadow(color: Color(0x14000000), blurRadius: 28, offset: Offset(0, 12)),
  ];
  static const elevated = [
    BoxShadow(color: Color(0x14000000), blurRadius: 32, offset: Offset(0, 8)),
  ];
  static const button = [
    BoxShadow(color: Color(0x2614A44D), blurRadius: 12, offset: Offset(0, 4)),
  ];
  static const courierButton = [
    BoxShadow(color: Color(0x33FF5630), blurRadius: 14, offset: Offset(0, 4)),
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
  static ThemeData get light {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        brightness: Brightness.light,
        primary: AppColors.primary,
        secondary: AppColors.courier,
        surface: AppColors.surface,
        error: AppColors.error,
      ),
      scaffoldBackgroundColor: AppColors.bg,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
    );

    final textTheme = GoogleFonts.interTextTheme(base.textTheme).copyWith(
      displayLarge: GoogleFonts.inter(
        fontSize: 34, fontWeight: FontWeight.w800,
        color: AppColors.textPrimary, letterSpacing: -1.0, height: 1.1,
      ),
      displayMedium: GoogleFonts.inter(
        fontSize: 26, fontWeight: FontWeight.w800,
        color: AppColors.textPrimary, letterSpacing: -0.6, height: 1.15,
      ),
      headlineLarge: GoogleFonts.inter(
        fontSize: 22, fontWeight: FontWeight.w700,
        color: AppColors.textPrimary, letterSpacing: -0.4,
      ),
      headlineMedium: GoogleFonts.inter(
        fontSize: 20, fontWeight: FontWeight.w700,
        color: AppColors.textPrimary, letterSpacing: -0.3,
      ),
      headlineSmall: GoogleFonts.inter(
        fontSize: 17, fontWeight: FontWeight.w700,
        color: AppColors.textPrimary, letterSpacing: -0.2,
      ),
      titleLarge: GoogleFonts.inter(
        fontSize: 16, fontWeight: FontWeight.w600,
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
        color: Colors.white, letterSpacing: 0.1,
      ),
      labelMedium: GoogleFonts.inter(
        fontSize: 13, fontWeight: FontWeight.w600,
        color: AppColors.textSecondary,
      ),
    );

    return base.copyWith(
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: textTheme.headlineSmall,
        toolbarHeight: 60,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((s) {
            if (s.contains(WidgetState.disabled)) return AppColors.surfaceMuted;
            return AppColors.primary;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((s) {
            if (s.contains(WidgetState.disabled)) return AppColors.textHint;
            return Colors.white;
          }),
          minimumSize: WidgetStateProperty.all(const Size(double.infinity, 56)),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
          ),
          elevation: WidgetStateProperty.all(0),
          textStyle: WidgetStateProperty.all(
            GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0.1),
          ),
          overlayColor: WidgetStateProperty.resolveWith((s) {
            if (s.contains(WidgetState.pressed)) return Colors.white.withValues(alpha: 0.1);
            return null;
          }),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          backgroundColor: AppColors.surface,
          side: const BorderSide(color: AppColors.border, width: 1.5),
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
          textStyle: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceMuted,
        hintStyle: GoogleFonts.inter(color: AppColors.textHint, fontWeight: FontWeight.w400),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
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
        backgroundColor: AppColors.textPrimary,
        contentTextStyle: GoogleFonts.inter(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.sm)),
        behavior: SnackBarBehavior.floating,
        actionTextColor: AppColors.primaryLight,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surfaceMuted,
        labelStyle: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.pill)),
      ),
    );
  }
}
