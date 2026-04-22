import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Core palette
  // Màu chủ đạo & Màu nhấn (Hệ màu Kẹo - Candy)
  static const Color primaryPurple = Color.fromARGB(255, 179, 232, 255); 
  static const Color lightPurple   = Color.fromARGB(255, 196, 230, 255); 
  static const Color accentBlue    = Color.fromARGB(255, 76, 142, 223); 
  static const Color lightBlue     = Color.fromARGB(255, 177, 207, 245); 
  static const Color accentYellow  = Color.fromARGB(255, 250, 204, 52); 
  static const Color accentOrange  = Color.fromARGB(255, 251, 138, 46); 
  // Màu nền (Nền Pastel sáng)
  static const Color darkBg        = Color.fromARGB(255, 127, 176, 255); 
  static const Color surfaceBg     = Color.fromARGB(255, 208, 220, 253); 
  static const Color cardBg        = Color.fromARGB(255, 255, 244, 244); 
  static const Color cardBg2       = Color.fromARGB(255, 255, 250, 196); 
  // Màu chữ (Đổi sang tông tối để nổi trên nền nhạt)
  static const Color textPrimary   = Color.fromARGB(255, 131, 176, 255); 
  static const Color textSecondary = Color(0xFF64748B);
  static const Color textMuted     = Color(0xFF94A3B8); 
  // Trạng thái
  static const Color success       = Color(0xFF4ADE80); 
  static const Color error         = Color(0xFFF87171);


  // Gradients
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color.fromARGB(255, 75, 156, 255), Color(0xFF93C5FD)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const LinearGradient warmGradient = LinearGradient(
    colors: [Color.fromARGB(255, 255, 126, 21), Color.fromARGB(255, 255, 222, 113)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const LinearGradient coolGradient = LinearGradient(
    colors: [Color(0xFF4ADE80), Color(0xFF2DD4BF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const LinearGradient bgGradient = LinearGradient(
    colors: [Color(0xFFF0F7FF), Color(0xFFFFFBEB), Color(0xFFF5F3FF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    stops: [0.0, 0.5, 1.0],
  );

  // ── Shadows (Đổ bóng kiểu mềm mại, nổi khối Candy) ──────────────────────
  static List<BoxShadow> glowShadow(Color color, {double blur = 20}) => [
        BoxShadow(
          color: color.withValues(alpha: 0.25), // Đổ bóng bằng chính màu của vật thể nhưng nhạt hơn
          blurRadius: blur,
          spreadRadius: 2,
          offset: const Offset(0, 8), // Đổ bóng xuống dưới sâu hơn một chút để tạo độ nổi
        ),
      ];
  static List<BoxShadow> softShadow = [
    BoxShadow(
      color: const Color.fromARGB(255, 38, 51, 69).withValues(alpha: 0.08), // Dùng màu xanh đen rất nhạt thay cho đen kịt
      blurRadius: 20,
      spreadRadius: 0,
      offset: const Offset(0, 10),
    ),
  ];

  // Border radius
  static const BorderRadius radiusXL = BorderRadius.all(Radius.circular(28));
  static const BorderRadius radiusLG = BorderRadius.all(Radius.circular(20));
  static const BorderRadius radiusMD = BorderRadius.all(Radius.circular(16));
  static const BorderRadius radiusSM = BorderRadius.all(Radius.circular(12));

  static ThemeData get theme => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color.fromARGB(255, 142, 187, 255),
        colorScheme: const ColorScheme.light(
          primary: Color.fromARGB(255, 228, 211, 255),
          secondary: Color.fromARGB(255, 48, 141, 255),
          tertiary: Color.fromARGB(255, 255, 225, 126),
          surface: Color.fromARGB(255, 255, 248, 248),
        ),
        textTheme: GoogleFonts.quicksandTextTheme(ThemeData.light().textTheme).copyWith(
          displayLarge: GoogleFonts.quicksand(
            fontSize: 35,
            fontWeight: FontWeight.w900, 
            color: textPrimary,
          ),
          titleLarge: GoogleFonts.quicksand(
            fontSize: 25,
            fontWeight: FontWeight.w800,
            color: textPrimary,
          ),
          titleMedium: GoogleFonts.quicksand(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: textPrimary,
          ),
          bodyLarge: GoogleFonts.quicksand(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: textPrimary,
          ),
          bodyMedium: GoogleFonts.quicksand(
            fontSize: 16,
            color: textSecondary,
          ),
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          titleTextStyle: GoogleFonts.nunito(
            fontSize: 22,
            fontWeight: FontWeight.w900,
            color: textPrimary,
          ),
        ),
      );
}

class AppConstants {
  static const int leverCount = 31;
  static const int autoModeStart = 10;
  static const int autoModeEnd = 22;
  static const String esp32BaseUrl = 'http://192.168.1.100';
  static const String aiApiUrl = 'http://192.168.1.8:8000';
  static const String videoServerUrl = 'https://69becabf17c3d7d97792fceb.mockapi.io/video';
}