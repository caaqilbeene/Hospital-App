import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Primary Color Theme (Emerald / Forest Green as requested for ALL flows)
  static const Color primaryColor = Color(0xFF00796B);
  static const Color primaryDark = Color(0xFF004D40);
  static const Color primaryLight = Color(0xFFE0F2F1);
  static const Color accentGreen = Color(0xFF00897B);

  // Neutral Colors
  static const Color backgroundColor = Color(0xFFF8FAF9);
  static const Color surfaceColor = Colors.white;
  static const Color textPrimary = Color(0xFF1A1D1E);
  static const Color textSecondary = Color(0xFF6C727F);
  static const Color textLight = Color(0xFF9EA5B1);
  static const Color borderColor = Color(0xFFE5E9EB);
  static const Color inputFill = Color(0xFFF9FAFB);

  // Status Colors
  static const Color successGreen = Color(0xFF10B981);
  static const Color warningOrange = Color(0xFFF59E0B);
  static const Color errorRed = Color(0xFFEF4444);

  static ThemeData get themeData {
    return ThemeData(
      useMaterial3: true,
      primaryColor: primaryColor,
      scaffoldBackgroundColor: backgroundColor,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryColor,
        primary: primaryColor,
        secondary: accentGreen,
        background: backgroundColor,
        surface: surfaceColor,
      ),
      textTheme: GoogleFonts.plusJakartaSansTextTheme().copyWith(
        displayLarge: GoogleFonts.plusJakartaSans(
          color: textPrimary,
          fontWeight: FontWeight.bold,
          fontSize: 28,
        ),
        titleLarge: GoogleFonts.plusJakartaSans(
          color: textPrimary,
          fontWeight: FontWeight.w700,
          fontSize: 20,
        ),
        titleMedium: GoogleFonts.plusJakartaSans(
          color: textPrimary,
          fontWeight: FontWeight.w600,
          fontSize: 16,
        ),
        bodyLarge: GoogleFonts.plusJakartaSans(
          color: textPrimary,
          fontSize: 15,
        ),
        bodyMedium: GoogleFonts.plusJakartaSans(
          color: textSecondary,
          fontSize: 14,
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: surfaceColor,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: textPrimary),
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          textStyle: GoogleFonts.plusJakartaSans(
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: inputFill,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: primaryColor, width: 1.5),
        ),
      ),
    );
  }
}
