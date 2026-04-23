import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class SpinnerTheme {
  static const bg = Color(0xFF0A0A0A);
  static const surface = Color(0xFF1A1A1A);
  static const card = Color(0xFF222222);
  static const border = Color(0xFF333333);
  static const white = Colors.white;
  static const grey = Color(0xFF888888);
  static const greyLight = Color(0xFF555555);
  static const accent = Color(0xFF6C5CE7);
  static const green = Color(0xFF00B894);
  static const red = Color(0xFFE17055);
  static const amber = Color(0xFFFDCB6E);

  static TextStyle nunito({
    double size = 14,
    FontWeight weight = FontWeight.normal,
    Color color = Colors.white,
    double? height,
  }) =>
      GoogleFonts.nunito(
        fontSize: size,
        fontWeight: weight,
        color: color,
        height: height,
      );

  static ThemeData get theme => ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: bg,
        colorScheme: const ColorScheme.dark(
          surface: bg,
          primary: accent,
        ),
        textTheme: GoogleFonts.nunitoTextTheme(ThemeData.dark().textTheme),
        appBarTheme: AppBarTheme(
          backgroundColor: bg,
          elevation: 0,
          titleTextStyle: nunito(size: 18, weight: FontWeight.w700),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: bg,
          selectedItemColor: white,
          unselectedItemColor: grey,
        ),
      );
}
