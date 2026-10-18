import 'package:flutter/material.dart';

/// Palette sobre : un seul bleu d'accent sur fond ardoise / bleu nuit.
/// Les couleurs vives ne servent QU'aux statuts (vert = ok, ambre = attention, rouge = erreur).
const accent = Color(0xFF4F8CFF);
const accentDeep = Color(0xFF2F63D8);
const accentSoft = Color(0xFFA9C6FF);

const okColor = Color(0xFF3CC795);
const warnColor = Color(0xFFF1B94A);
const errColor = Color(0xFFF07282);

const inkBase = Color(0xFF080D1B);
const panelSolid = Color(0xFF141B2E);

const brandGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [accent, accentDeep],
);

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: accent,
    brightness: Brightness.dark,
  ).copyWith(
    primary: accent,
    secondary: accentSoft,
    tertiary: accentSoft,
    surface: inkBase,
    error: errColor,
    outline: Colors.white38,
    outlineVariant: Colors.white24,
  );

  const radius = 16.0;
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, brightness: Brightness.dark);

  return base.copyWith(
    scaffoldBackgroundColor: Colors.transparent,
    canvasColor: panelSolid,
    textTheme: base.textTheme.apply(bodyColor: Colors.white, displayColor: Colors.white),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: Colors.white),
    ),
    dividerTheme: const DividerThemeData(color: Colors.white12, space: 1),
    listTileTheme: const ListTileThemeData(
      iconColor: Colors.white70,
      textColor: Colors.white,
      subtitleTextStyle: TextStyle(color: Colors.white60, fontSize: 13),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: panelSolid.withValues(alpha: 0.96),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: const BorderSide(color: Colors.white12),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: panelSolid.withValues(alpha: 0.97),
      modalBackgroundColor: panelSolid.withValues(alpha: 0.97),
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: panelSolid,
      contentTextStyle: const TextStyle(color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.05),
      labelStyle: const TextStyle(color: Colors.white70),
      helperStyle: const TextStyle(color: Colors.white54),
      hintStyle: const TextStyle(color: Colors.white38),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius),
        borderSide: const BorderSide(color: Colors.white24),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius),
        borderSide: const BorderSide(color: Colors.white24),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius),
        borderSide: const BorderSide(color: accent, width: 1.6),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius),
        borderSide: const BorderSide(color: Colors.white12),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(50),
        backgroundColor: accent,
        foregroundColor: Colors.white,
        disabledBackgroundColor: Colors.white12,
        disabledForegroundColor: Colors.white38,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: const BorderSide(color: Colors.white30),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: accentSoft)),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: accent,
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      indicatorColor: accent.withValues(alpha: 0.35),
      labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
            fontSize: 12,
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
            color: s.contains(WidgetState.selected) ? Colors.white : Colors.white60,
          )),
      iconTheme: WidgetStateProperty.resolveWith((s) =>
          IconThemeData(color: s.contains(WidgetState.selected) ? Colors.white : Colors.white60)),
    ),
    drawerTheme: const DrawerThemeData(backgroundColor: panelSolid),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.all(Colors.white),
      trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? okColor : Colors.white24),
    ),
    expansionTileTheme: const ExpansionTileThemeData(
      iconColor: Colors.white70,
      collapsedIconColor: Colors.white70,
      textColor: Colors.white,
      collapsedTextColor: Colors.white,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: Colors.white10,
      selectedColor: accent.withValues(alpha: 0.45),
      side: const BorderSide(color: Colors.white24),
      labelStyle: const TextStyle(color: Colors.white),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor:
            WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? accent : Colors.white10),
        foregroundColor: WidgetStateProperty.all(Colors.white),
        side: WidgetStateProperty.all(const BorderSide(color: Colors.white24)),
      ),
    ),
  );
}
