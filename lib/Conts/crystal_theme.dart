import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CrystalTheme {
  // Palette màu
  static const Color primaryBlue = Color(0xFF81D4FA); // Xanh pha lê
  static const Color primaryBlueDark = Color(0xFF29B6F6);
  static const Color lightBlueBg = Color(0xFFF1F9FF); // Nền
  static const Color accentPink = Color(0xFFF48FB1);  // Hồng phấn
  static const Color textDark = Color(0xFF37474F);    // Chữ đậm
  static const Color glassWhite = Color(0xEEFFFFFF);

  // Gradients
  static const LinearGradient blueGradient = LinearGradient(
    colors: [Color(0xFF4FC3F7), Color(0xFFB3E5FC)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient pinkGradient = LinearGradient(
    colors: [Color(0xFFF06292), Color(0xFFF8BBD0)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Decoration Kính mờ (Glassmorphism)
  static BoxDecoration glassDecoration = BoxDecoration(
    color: glassWhite,
    borderRadius: BorderRadius.circular(24),
    border: Border.all(color: Colors.white, width: 1.5),
    boxShadow: [
      BoxShadow(
        color: primaryBlue.withOpacity(0.3),
        blurRadius: 15,
        spreadRadius: 2,
        offset: const Offset(0, 4),
      ),
    ],
  );

  // ThemeData chung
  static ThemeData get themeData {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryBlue,
        primary: primaryBlue,
        secondary: accentPink,
        surface: lightBlueBg,
        background: lightBlueBg,
      ),
      scaffoldBackgroundColor: lightBlueBg,
      fontFamily: 'Roboto',

      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: textDark),
        titleTextStyle: TextStyle(color: textDark, fontSize: 20, fontWeight: FontWeight.bold),
        systemOverlayStyle: SystemUiOverlayStyle.dark,
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryBlue,
          foregroundColor: Colors.white,
          elevation: 4,
          shadowColor: primaryBlue.withOpacity(0.4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Colors.white)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: primaryBlue, width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      ),
    );
  }
}