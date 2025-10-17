// ABOUTME: Theme service providing Material Design 3 theming
// ABOUTME: Supports dynamic color theming and dark/light mode switching

import 'package:flutter/material.dart';
import 'package:material_color_utilities/material_color_utilities.dart';

class ThemeService {
  static const Color _fallbackSeedColor = Color(0xFF6750A4); // Material Purple

  static ThemeData getTheme({
    required Brightness brightness,
    ColorScheme? dynamicColorScheme,
  }) {
    final colorScheme = dynamicColorScheme ?? 
        ColorScheme.fromSeed(
          seedColor: _fallbackSeedColor,
          brightness: brightness,
        );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      
      // App Bar Theme
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 1,
        surfaceTintColor: colorScheme.surfaceTint,
      ),

      // Navigation Bar Theme
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colorScheme.surface,
        indicatorColor: colorScheme.secondaryContainer,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return TextStyle(color: colorScheme.onSurface, fontSize: 12);
          }
          return TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12);
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: colorScheme.onSecondaryContainer);
          }
          return IconThemeData(color: colorScheme.onSurfaceVariant);
        }),
      ),

      // Card Theme
      cardTheme: CardThemeData(
        elevation: 1,
        color: colorScheme.surface,
        surfaceTintColor: colorScheme.surfaceTint,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),

      // List Tile Theme
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),

      // Input Decoration Theme
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),

      // Elevated Button Theme
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        ),
      ),

      // Filled Button Theme
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        ),
      ),

      // Text Button Theme
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        ),
      ),

      // Icon Button Theme
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),

      // Floating Action Button Theme
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colorScheme.primaryContainer,
        foregroundColor: colorScheme.onPrimaryContainer,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),

      // Dialog Theme
      dialogTheme: DialogThemeData(
        backgroundColor: colorScheme.surface,
        surfaceTintColor: colorScheme.surfaceTint,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),

      // Bottom Sheet Theme
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colorScheme.surface,
        surfaceTintColor: colorScheme.surfaceTint,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),

      // Chip Theme
      chipTheme: ChipThemeData(
        backgroundColor: colorScheme.surfaceContainerHighest,
        selectedColor: colorScheme.secondaryContainer,
        labelStyle: TextStyle(color: colorScheme.onSurface),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),

      // Switch Theme
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colorScheme.onPrimary;
          }
          return colorScheme.outline;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colorScheme.primary;
          }
          return colorScheme.surfaceContainerHighest;
        }),
      ),
    );
  }

  /// Create a custom color scheme from a seed color
  static ColorScheme createColorScheme(Color seedColor, Brightness brightness) {
    final scheme = SchemeTonalSpot(
      sourceColorHct: Hct.fromInt(seedColor.value),
      isDark: brightness == Brightness.dark,
      contrastLevel: 0.0,
    );

    return ColorScheme(
      brightness: brightness,
      primary: Color(MaterialDynamicColors.primary.getArgb(scheme)),
      onPrimary: Color(MaterialDynamicColors.onPrimary.getArgb(scheme)),
      primaryContainer: Color(MaterialDynamicColors.primaryContainer.getArgb(scheme)),
      onPrimaryContainer: Color(MaterialDynamicColors.onPrimaryContainer.getArgb(scheme)),
      secondary: Color(MaterialDynamicColors.secondary.getArgb(scheme)),
      onSecondary: Color(MaterialDynamicColors.onSecondary.getArgb(scheme)),
      secondaryContainer: Color(MaterialDynamicColors.secondaryContainer.getArgb(scheme)),
      onSecondaryContainer: Color(MaterialDynamicColors.onSecondaryContainer.getArgb(scheme)),
      tertiary: Color(MaterialDynamicColors.tertiary.getArgb(scheme)),
      onTertiary: Color(MaterialDynamicColors.onTertiary.getArgb(scheme)),
      tertiaryContainer: Color(MaterialDynamicColors.tertiaryContainer.getArgb(scheme)),
      onTertiaryContainer: Color(MaterialDynamicColors.onTertiaryContainer.getArgb(scheme)),
      error: Color(MaterialDynamicColors.error.getArgb(scheme)),
      onError: Color(MaterialDynamicColors.onError.getArgb(scheme)),
      errorContainer: Color(MaterialDynamicColors.errorContainer.getArgb(scheme)),
      onErrorContainer: Color(MaterialDynamicColors.onErrorContainer.getArgb(scheme)),
      surface: Color(MaterialDynamicColors.surface.getArgb(scheme)),
      onSurface: Color(MaterialDynamicColors.onSurface.getArgb(scheme)),
      surfaceContainerHighest: Color(MaterialDynamicColors.surfaceContainerHighest.getArgb(scheme)),
      onSurfaceVariant: Color(MaterialDynamicColors.onSurfaceVariant.getArgb(scheme)),
      outline: Color(MaterialDynamicColors.outline.getArgb(scheme)),
      outlineVariant: Color(MaterialDynamicColors.outlineVariant.getArgb(scheme)),
      shadow: Color(MaterialDynamicColors.shadow.getArgb(scheme)),
      scrim: Color(MaterialDynamicColors.scrim.getArgb(scheme)),
      inverseSurface: Color(MaterialDynamicColors.inverseSurface.getArgb(scheme)),
      onInverseSurface: Color(MaterialDynamicColors.inverseOnSurface.getArgb(scheme)),
      inversePrimary: Color(MaterialDynamicColors.inversePrimary.getArgb(scheme)),
      surfaceTint: Color(MaterialDynamicColors.primary.getArgb(scheme)),
    );
  }
}