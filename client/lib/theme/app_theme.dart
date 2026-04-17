import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ── Color tokens ─────────────────────────────────────────────────────────────

abstract final class AppColors {
  // Surfaces (darkest → lightest)
  static const surface0 = Color(0xFF0E0F12); // scaffold background
  static const surface1 = Color(0xFF151720); // cards, top bar, sections
  static const surface2 = Color(0xFF1C1E2A); // menus, sheets, dropdowns
  static const surface3 = Color(0xFF252836); // hover states, subtle emphasis

  // Borders
  static const border = Color(0x18FFFFFF);
  static const borderSubtle = Color(0x10FFFFFF);

  // Accent (teal)
  static const accent = Color(0xFF20C997);
  static Color get accentMuted => accent.withValues(alpha: 0.12);
  static Color get accentBorder => accent.withValues(alpha: 0.40);

  // Text
  static const textPrimary = Color(0xFFE8E8E8);
  static const textSecondary = Colors.white70;
  static const textTertiary = Colors.white38;
  static const textDisabled = Colors.white24;

  // Semantic
  static const danger = Colors.redAccent;
  static const warning = Colors.orangeAccent;
  static const success = Color(0xFF20C997);
}

// ── Spacing ──────────────────────────────────────────────────────────────────

abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
}

// ── Responsive breakpoints ───────────────────────────────────────────────────

enum LayoutClass { compact, medium, expanded }

abstract final class AppBreakpoints {
  static const double compactMax = 600;
  static const double mediumMax = 1024;

  static LayoutClass of(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width < compactMax) return LayoutClass.compact;
    if (width < mediumMax) return LayoutClass.medium;
    return LayoutClass.expanded;
  }
}

// ── Typography ───────────────────────────────────────────────────────────────

abstract final class AppTypography {
  static final TextStyle heading = GoogleFonts.inter(
    fontSize: 20,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
  );

  static final TextStyle title = GoogleFonts.inter(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  static final TextStyle body = GoogleFonts.inter(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: AppColors.textPrimary,
  );

  static final TextStyle caption = GoogleFonts.inter(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
  );

  static final TextStyle label = GoogleFonts.inter(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    color: AppColors.textSecondary,
  );
}

// ── ThemeData builder ────────────────────────────────────────────────────────

ThemeData buildAppTheme() {
  return ThemeData.dark().copyWith(
    scaffoldBackgroundColor: AppColors.surface0,
    cardColor: AppColors.surface1,
    dividerColor: AppColors.border,
    colorScheme: ColorScheme.dark(
      primary: AppColors.accent,
      surface: AppColors.surface0,
      error: AppColors.danger,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.surface1,
      foregroundColor: AppColors.textPrimary,
      elevation: 0,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface2,
      border: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
        borderSide: BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: const BorderRadius.all(Radius.circular(8)),
        borderSide: BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: const BorderRadius.all(Radius.circular(8)),
        borderSide: BorderSide(color: AppColors.accent),
      ),
      labelStyle: const TextStyle(color: AppColors.textSecondary),
      hintStyle: const TextStyle(color: AppColors.textTertiary),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: AppColors.surface2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: AppColors.surface2,
      contentTextStyle: TextStyle(color: AppColors.textPrimary),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surface2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.surface1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
    ),
  );
}
