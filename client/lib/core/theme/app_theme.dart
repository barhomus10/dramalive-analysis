import 'package:flutter/material.dart';

/// Tema oscuro de la réplica.
///
/// La paleta sale del **splash público** de `web.dramalive.cc/index.html`, que
/// es información servida a cualquier navegador:
///
///   background: linear-gradient(135deg, #1a1a2e 0%, #16213e 50%, #0f3460 100%)
///   accent    : #e94560
///   text      : #ffffff / rgba(255,255,255,.6)
///
/// No se copian iconos, logotipo ni textos del producto original.
class AppTheme {
  AppTheme._();

  static const Color bgDeep = Color(0xFF1A1A2E);
  static const Color bgMid = Color(0xFF16213E);
  static const Color bgHigh = Color(0xFF0F3460);
  static const Color accent = Color(0xFFE94560);
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0x99FFFFFF);

  /// Rojo de aviso para tráfico en claro (hallazgo F-02).
  static const Color warning = Color(0xFFFFB300);

  static ThemeData dark() {
    const scheme = ColorScheme.dark(
      primary: accent,
      secondary: bgHigh,
      surface: bgDeep,
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onSurface: textPrimary,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: bgDeep,
      canvasColor: bgDeep,
      fontFamilyFallback: const ['Roboto', 'Segoe UI', 'sans-serif'],
      appBarTheme: const AppBarTheme(
        backgroundColor: bgDeep,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: bgMid,
        indicatorColor: accent.withOpacity(0.22),
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(color: textSecondary, fontSize: 12),
        ),
      ),
      cardTheme: CardThemeData(
        color: bgMid,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: bgMid,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: accent, width: 1.4),
        ),
        labelStyle: const TextStyle(color: textSecondary),
        hintStyle: const TextStyle(color: textSecondary),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: textSecondary,
        textColor: textPrimary,
      ),
      dividerTheme: DividerThemeData(
        color: Colors.white.withOpacity(0.07),
        space: 1,
        thickness: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: bgHigh,
        contentTextStyle: const TextStyle(color: textPrimary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  /// El degradado del splash original, reutilizado como fondo decorativo.
  static const LinearGradient splashGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [bgDeep, bgMid, bgHigh],
    stops: [0.0, 0.5, 1.0],
  );
}
