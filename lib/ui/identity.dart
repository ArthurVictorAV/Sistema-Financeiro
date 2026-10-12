import 'package:flutter/material.dart';

const gold = Color(0xFFD3B16B),
    green = Color(0xFF75D5A6),
    red = Color(0xFFFF818B);
ThemeData appTheme() => ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,
  colorScheme: ColorScheme.fromSeed(
    seedColor: gold,
    brightness: Brightness.dark,
    primary: gold,
    surface: const Color(0xFF17191D),
  ),
  scaffoldBackgroundColor: const Color(0xFF0D0F12),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: const Color(0xFF202328),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
  ),
  cardTheme: CardThemeData(
    color: const Color(0xFF17191D),
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: const BorderSide(color: Color(0xFF292C31)),
    ),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      minimumSize: const Size(48, 48),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  ),
);

/// Viewport over the original asset; no recoloring or redrawing of the logo.
class Brand extends StatelessWidget {
  final double size;
  const Brand({super.key, this.size = 54});
  @override
  Widget build(BuildContext context) => ClipRect(
    child: SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          Positioned(
            left: -200 / 330 * size,
            top: -135 / 330 * size,
            width: 1254 / 330 * size,
            height: 1254 / 330 * size,
            child: Image.asset('assets/brand.png', excludeFromSemantics: true),
          ),
        ],
      ),
    ),
  );
}
