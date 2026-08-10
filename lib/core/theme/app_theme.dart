import 'package:flutter/material.dart';

abstract final class AppColors {
  static const primary = Color(0xFF004B61);
  static const secondary = Color(0xFF77BC75);
  static const background = Color(0xFFFFFFFF);

  static const primarySoft = Color(0xFFEAF3F5);
  static const primarySoftStrong = Color(0xFFD5E6EA);
  static const secondarySoft = Color(0xFFEDF7EC);
  static const secondarySoftStrong = Color(0xFFDCEFDA);
  static const border = Color(0xFFDCE5E7);
  static const textPrimary = Color(0xFF172126);
  static const textSecondary = Color(0xFF5D696E);
}

abstract final class AppTheme {
  static const _fontFamily = 'Vazirmatn';

  static ThemeData get light {
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: Brightness.light,
        ).copyWith(
          primary: AppColors.primary,
          onPrimary: Colors.white,
          primaryContainer: AppColors.primarySoft,
          onPrimaryContainer: AppColors.primary,
          secondary: AppColors.secondary,
          onSecondary: const Color(0xFF0C2E12),
          secondaryContainer: AppColors.secondarySoft,
          onSecondaryContainer: const Color(0xFF153D1A),
          surface: AppColors.background,
          onSurface: AppColors.textPrimary,
          onSurfaceVariant: AppColors.textSecondary,
          outline: const Color(0xFF8A989D),
          outlineVariant: AppColors.border,
          surfaceContainerLowest: AppColors.background,
          surfaceContainerLow: const Color(0xFFFAFCFC),
          surfaceContainer: const Color(0xFFF6F9F9),
          surfaceContainerHigh: AppColors.primarySoft,
          surfaceContainerHighest: AppColors.secondarySoft,
          surfaceTint: AppColors.primary,
          inverseSurface: AppColors.primary,
          onInverseSurface: Colors.white,
        );
    final baseTheme = ThemeData(
      useMaterial3: true,
      fontFamily: _fontFamily,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.background,
    );

    return baseTheme.copyWith(
      textTheme: baseTheme.textTheme.copyWith(
        headlineSmall: baseTheme.textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: AppColors.primary,
        ),
        titleLarge: baseTheme.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w600,
          color: AppColors.primary,
        ),
        titleMedium: baseTheme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
        labelLarge: baseTheme.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      iconTheme: const IconThemeData(color: AppColors.primary),
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.primary,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: baseTheme.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          color: AppColors.primary,
        ),
      ),
      cardTheme: CardThemeData(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: AppColors.background,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.background,
        prefixIconColor: AppColors.primary,
        suffixIconColor: AppColors.primary,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 15,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        labelStyle: const TextStyle(fontFamily: _fontFamily),
        hintStyle: const TextStyle(
          fontFamily: _fontFamily,
          fontWeight: FontWeight.w400,
          color: AppColors.textSecondary,
        ),
        helperStyle: const TextStyle(fontFamily: _fontFamily),
        errorStyle: const TextStyle(fontFamily: _fontFamily),
        suffixStyle: const TextStyle(
          fontFamily: _fontFamily,
          color: AppColors.textSecondary,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.primarySoftStrong,
          disabledForegroundColor: AppColors.textSecondary,
          minimumSize: const Size(64, 50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontFamily: _fontFamily,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(64, 50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontFamily: _fontFamily,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.primary),
          minimumSize: const Size(64, 46),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontFamily: _fontFamily,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          textStyle: const TextStyle(
            fontFamily: _fontFamily,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 70,
        elevation: 0,
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        indicatorColor: AppColors.secondarySoftStrong,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? AppColors.primary
                : AppColors.textSecondary,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => baseTheme.textTheme.labelMedium?.copyWith(
            fontFamily: _fontFamily,
            color: states.contains(WidgetState.selected)
                ? AppColors.primary
                : AppColors.textSecondary,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w500,
          ),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          textStyle: const WidgetStatePropertyAll(
            TextStyle(fontFamily: _fontFamily, fontWeight: FontWeight.w600),
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? AppColors.primary
                : AppColors.textSecondary,
          ),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? AppColors.secondarySoftStrong
                : AppColors.background,
          ),
          side: const WidgetStatePropertyAll(
            BorderSide(color: AppColors.border),
          ),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.secondary,
        linearTrackColor: AppColors.secondarySoftStrong,
        circularTrackColor: AppColors.secondarySoftStrong,
      ),
      chipTheme: baseTheme.chipTheme.copyWith(
        backgroundColor: AppColors.secondarySoft,
        selectedColor: AppColors.secondarySoftStrong,
        side: const BorderSide(color: AppColors.border),
        labelStyle: const TextStyle(
          fontFamily: _fontFamily,
          color: AppColors.primary,
        ),
      ),
      dividerTheme: const DividerThemeData(color: AppColors.border),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.primary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        contentTextStyle: baseTheme.textTheme.bodyMedium?.copyWith(
          fontFamily: _fontFamily,
          color: Colors.white,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titleTextStyle: baseTheme.textTheme.titleLarge?.copyWith(
          fontFamily: _fontFamily,
          fontWeight: FontWeight.w700,
          color: AppColors.primary,
        ),
        contentTextStyle: baseTheme.textTheme.bodyMedium?.copyWith(
          fontFamily: _fontFamily,
          color: AppColors.textPrimary,
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
      ),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: AppColors.primary,
        selectionColor: AppColors.secondarySoftStrong,
        selectionHandleColor: AppColors.primary,
      ),
    );
  }
}
