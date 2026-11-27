import 'package:flutter/material.dart';

/// App-wide constants. Change [appName] here to rename the app in the UI.
class AppConfig {
  const AppConfig._();

  static const appName = 'SafeSpend';
  static const tagline = 'Know what you can safely spend today.';
}

/// The brand palette. The dark theme uses these exactly:
///
/// * main background: deep navy [navy]
/// * dark surfaces: [surface] and [surfaceAlt]
/// * primary accent: aqua [aqua]; bright icon accent: cyan [cyan]
/// * text: white, 70% white for secondary text, 60% white for muted text
/// * text on aqua buttons: [onAccent]
class AppColors {
  const AppColors._();

  static const Color navy = Color(0xFF00040F);
  static const Color surface = Color(0xFF11101D);
  static const Color surfaceAlt = Color(0xFF14101D);
  static const Color aqua = Color(0xFF5CE1E6);
  static const Color cyan = Color(0xFF00F6FF);
  static const Color text = Color(0xFFFFFFFF);
  static const Color onAccent = Color(0xFF00040E);

  /// White at 70% (secondary text) and 60% (muted text).
  static const Color textSecondary = Color(0xB3FFFFFF);
  static const Color textMuted = Color(0x99FFFFFF);
}

ColorScheme _darkScheme() {
  return const ColorScheme(
    brightness: Brightness.dark,
    primary: AppColors.aqua,
    onPrimary: AppColors.onAccent,
    primaryContainer: Color(0xFF0B3A40),
    onPrimaryContainer: AppColors.text,
    secondary: AppColors.cyan,
    onSecondary: AppColors.onAccent,
    secondaryContainer: Color(0xFF123238),
    onSecondaryContainer: AppColors.text,
    tertiary: Color(0xFF9DB4FF),
    onTertiary: AppColors.onAccent,
    tertiaryContainer: Color(0xFF1D2547),
    onTertiaryContainer: AppColors.text,
    error: Color(0xFFFF6B6B),
    onError: AppColors.onAccent,
    errorContainer: Color(0xFF3A1118),
    onErrorContainer: Color(0xFFFFDAD9),
    surface: AppColors.navy,
    onSurface: AppColors.text,
    onSurfaceVariant: AppColors.textSecondary,
    surfaceContainerLowest: AppColors.navy,
    surfaceContainerLow: AppColors.surface,
    surfaceContainer: AppColors.surface,
    surfaceContainerHigh: AppColors.surface,
    surfaceContainerHighest: AppColors.surfaceAlt,
    outline: AppColors.textMuted,
    outlineVariant: Color(0x1FFFFFFF),
    inverseSurface: Color(0xFF1F1E30),
    onInverseSurface: AppColors.text,
    inversePrimary: Color(0xFF007C85),
    shadow: Colors.black,
    scrim: Colors.black,
  );
}

ColorScheme _lightScheme() {
  return const ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFF007C85),
    onPrimary: Colors.white,
    primaryContainer: Color(0xFFCFF6F8),
    onPrimaryContainer: Color(0xFF00363A),
    secondary: Color(0xFF00929A),
    onSecondary: Colors.white,
    secondaryContainer: Color(0xFFD6F3F5),
    onSecondaryContainer: AppColors.navy,
    tertiary: Color(0xFF4A5BC9),
    onTertiary: Colors.white,
    tertiaryContainer: Color(0xFFE2E6FF),
    onTertiaryContainer: Color(0xFF111A4D),
    error: Color(0xFFBA1A1A),
    onError: Colors.white,
    errorContainer: Color(0xFFFFDAD6),
    onErrorContainer: Color(0xFF410002),
    surface: Color(0xFFF6FAFC),
    onSurface: AppColors.navy,
    onSurfaceVariant: Color(0xB300040F),
    surfaceContainerLowest: Colors.white,
    surfaceContainerLow: Colors.white,
    surfaceContainer: Color(0xFFEEF5F7),
    surfaceContainerHigh: Color(0xFFE6EFF2),
    surfaceContainerHighest: Color(0xFFDDE8EC),
    outline: Color(0xFF6B7C80),
    outlineVariant: Color(0x1F00040F),
    inverseSurface: Color(0xFF14212A),
    onInverseSurface: Colors.white,
    inversePrimary: AppColors.aqua,
    shadow: Colors.black,
    scrim: Colors.black,
  );
}

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = dark ? _darkScheme() : _lightScheme();
  final accentIcon = dark ? AppColors.cyan : scheme.secondary;

  final inputBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: BorderSide.none,
  );
  final buttonShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(12),
  );

  final base = ThemeData(brightness: brightness, useMaterial3: true);
  final textTheme = base.textTheme.apply(
    bodyColor: scheme.onSurface,
    displayColor: scheme.onSurface,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    textTheme: textTheme,
    scaffoldBackgroundColor: scheme.surface,
    canvasColor: scheme.surface,
    hintColor: dark ? AppColors.textMuted : scheme.outline,
    disabledColor: dark ? AppColors.textMuted : scheme.outline,
    dividerTheme: DividerThemeData(color: scheme.outlineVariant),
    iconTheme: IconThemeData(color: scheme.onSurfaceVariant),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      // Taller bar with even space above and below, so the title and the
      // buttons at the top right sit centered instead of pushed up.
      toolbarHeight: 68,
      centerTitle: false,
      titleSpacing: 20,
      titleTextStyle: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700, color: scheme.onSurface),
      actionsIconTheme: IconThemeData(color: accentIcon),
      actionsPadding: const EdgeInsets.only(right: 12),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      indicatorColor: dark ? AppColors.aqua.withValues(alpha: 0.18) : scheme.primaryContainer,
      iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
            color: states.contains(WidgetState.selected) ? accentIcon : scheme.onSurfaceVariant,
          )),
      labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
            color: states.contains(WidgetState.selected) ? scheme.onSurface : scheme.onSurfaceVariant,
          )),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
    ),
    visualDensity: VisualDensity.standard,
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: scheme.surfaceContainerHigh,
      indicatorColor: dark ? AppColors.aqua.withValues(alpha: 0.18) : scheme.primaryContainer,
      selectedIconTheme: IconThemeData(color: accentIcon),
      unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
      selectedLabelTextStyle: TextStyle(color: scheme.onSurface, fontWeight: FontWeight.w700),
      unselectedLabelTextStyle: TextStyle(color: scheme.onSurfaceVariant),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      // On wide screens sheets stay a phone-like width in the middle instead of stretching across.
      constraints: const BoxConstraints(maxWidth: 640),
      backgroundColor: scheme.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: scheme.inverseSurface,
      contentTextStyle: TextStyle(color: scheme.onInverseSurface),
      behavior: SnackBarBehavior.floating,
      insetPadding: const EdgeInsets.all(16),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: scheme.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest,
      hintStyle: TextStyle(color: dark ? AppColors.textMuted : scheme.outline),
      border: inputBorder,
      enabledBorder: inputBorder,
      focusedBorder: inputBorder.copyWith(
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
      errorBorder: inputBorder.copyWith(
        borderSide: BorderSide(color: scheme.error),
      ),
      focusedErrorBorder: inputBorder.copyWith(
        borderSide: BorderSide(color: scheme.error, width: 2),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape: buttonShape,
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape: buttonShape,
        foregroundColor: scheme.primary,
        side: BorderSide(color: scheme.primary.withValues(alpha: 0.6)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: scheme.primary),
    ),
    listTileTheme: ListTileThemeData(iconColor: accentIcon),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: scheme.primary),
  );
}
