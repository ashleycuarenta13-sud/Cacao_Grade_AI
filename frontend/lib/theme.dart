import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  // Landing page (brown theme)
  static const brown950 = Color(0xFF1D0E09);
  static const brown900 = Color(0xFF29130C);
  static const brown800 = Color(0xFF3B1D12);
  static const brown700 = Color(0xFF59301E);
  static const cream = Color(0xFFFBF6EF);
  static const cream2 = Color(0xFFF2E8DB);
  static const gold = Color(0xFFE7B55F);
  static const violet = Color(0xFF7852A9);
  static const violetDark = Color(0xFF57357F);
  static const textBrown = Color(0xFF2A1A14);
  static const mutedBrown = Color(0xFF776B64);

  // Dashboards (forest green theme)
  static const forest = Color(0xFF193B2A);
  static const forestLight = Color(0xFF28543A);
  static const leaf = Color(0xFF527C50);
  static const dashGold = Color(0xFFC6A45D);

  // Status colors
  static const red = Color(0xFFBD6257);
  static const green = Color(0xFF64895B);
  static const amber = Color(0xFFE4A52B);
}

/// Light/dark palette helper for the dashboards.
class Pal {
  final bool dark;
  const Pal(this.dark);
  factory Pal.of(BuildContext c) => Pal(Theme.of(c).brightness == Brightness.dark);

  Color get card => dark ? const Color(0xFF16231A) : Colors.white;
  Color get text => dark ? const Color(0xFFE9EFE6) : const Color(0xFF26362B);
  Color get muted => dark ? const Color(0xFF9DAA9E) : const Color(0xFF7A857B);
  Color get border => dark ? const Color(0xFF2A3B2E) : const Color(0xFFE5E9E0);
  Color get soft => dark ? const Color(0xFF1F3325) : const Color(0xFFEDF3E9);
  Color get accent => dark ? AppColors.dashGold : AppColors.forest;
}

class AppTheme {
  static ThemeData _build(Brightness b) {
    final base = ThemeData(
      useMaterial3: true,
      brightness: b,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.forest,
        brightness: b,
      ),
    );
    return base.copyWith(
      scaffoldBackgroundColor:
          b == Brightness.dark ? const Color(0xFF0F1A12) : const Color(0xFFF5F6F0),
      textTheme: GoogleFonts.dmSansTextTheme(base.textTheme),
    );
  }

  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);
}
