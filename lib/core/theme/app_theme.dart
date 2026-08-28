import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Brand Color Tokens
  static const Color primaryIndigo = Color(0xFF6366F1);
  static const Color primaryGlow = Color(0x406366F1);
  
  static const Color bgDark = Color(0xFF0B0F19);
  static const Color surfaceDark = Color(0xFF111827);
  static const Color cardDark = Color(0xFF1F2937);
  static const Color borderDark = Color(0xFF374151);

  static const Color bgLight = Color(0xFFF9FAFB);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color cardLight = Color(0xFFF3F4F6);
  static const Color borderLight = Color(0xFFE5E7EB);

  // Status & Priority Accent Colors
  static const Color priorityUrgent = Color(0xFFEF4444); // Red
  static const Color priorityHigh = Color(0xFFF97316);   // Orange
  static const Color priorityMedium = Color(0xFFF59E0B); // Amber
  static const Color priorityLow = Color(0xFF10B981);    // Emerald

  // Glassmorphism Deco Utility
  static BoxDecoration glassBoxDecoration({
    required BuildContext context,
    Color? customBorder,
    double borderRadius = 16,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return BoxDecoration(
      color: isDark ? cardDark.withValues(alpha: 0.7) : cardLight.withValues(alpha: 0.8),
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(
        color: customBorder ?? (isDark ? borderDark.withValues(alpha: 0.5) : borderLight),
        width: 1,
      ),
      boxShadow: [
        BoxShadow(
          color: isDark ? Colors.black.withValues(alpha: 0.3) : Colors.black.withValues(alpha: 0.04),
          blurRadius: 12,
          offset: const Offset(0, 4),
        )
      ],
    );
  }

  // Dark Theme Data
  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bgDark,
      primaryColor: primaryIndigo,
      colorScheme: const ColorScheme.dark(
        primary: primaryIndigo,
        surface: surfaceDark,
        onSurface: Colors.white,
      ),
      textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
      cardTheme: CardThemeData(
        color: cardDark,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: borderDark, width: 1),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surfaceDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: surfaceDark,
        selectedItemColor: primaryIndigo,
        unselectedItemColor: Colors.grey,
      ),
    );
  }

  // Light Theme Data
  static ThemeData get lightTheme {
    return ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: bgLight,
      primaryColor: primaryIndigo,
      colorScheme: const ColorScheme.light(
        primary: primaryIndigo,
        surface: surfaceLight,
        onSurface: Color(0xFF111827),
      ),
      textTheme: GoogleFonts.interTextTheme(ThemeData.light().textTheme),
      cardTheme: CardThemeData(
        color: cardLight,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: borderLight, width: 1),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surfaceLight,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: surfaceLight,
        selectedItemColor: primaryIndigo,
        unselectedItemColor: Colors.grey,
      ),
    );
  }
}
