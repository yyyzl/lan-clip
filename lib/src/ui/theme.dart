import 'package:flutter/material.dart';

const canvasColor = Color(0xFFF6F7F3);
const inkColor = Color(0xFF20312A);
const secondaryColor = Color(0xFF627168);
const accentColor = Color(0xFF256D53);
const sageColor = Color(0xFFE7F0E9);
const lineColor = Color(0xFFDCE4DD);

final appTheme = ThemeData(
  useMaterial3: true,
  fontFamilyFallback: const [
    'PingFang SC',
    'Microsoft YaHei',
    'Noto Sans CJK SC',
  ],
  scaffoldBackgroundColor: canvasColor,
  colorScheme: ColorScheme.fromSeed(seedColor: accentColor).copyWith(
    primary: accentColor,
    onPrimary: Colors.white,
    surface: canvasColor,
    onSurface: inkColor,
    onSurfaceVariant: secondaryColor,
    outline: lineColor,
    surfaceContainerHighest: sageColor,
  ),
  textTheme: const TextTheme(
    headlineLarge: TextStyle(
      fontSize: 30,
      fontWeight: FontWeight.w700,
      color: inkColor,
    ),
    headlineMedium: TextStyle(
      fontSize: 27,
      fontWeight: FontWeight.w700,
      color: inkColor,
    ),
    titleLarge: TextStyle(
      fontSize: 21,
      fontWeight: FontWeight.w600,
      color: inkColor,
    ),
    titleMedium: TextStyle(
      fontSize: 17,
      fontWeight: FontWeight.w600,
      color: inkColor,
    ),
    bodyLarge: TextStyle(fontSize: 16, height: 1.5, color: inkColor),
    bodyMedium: TextStyle(fontSize: 14, height: 1.5, color: inkColor),
    bodySmall: TextStyle(fontSize: 13, height: 1.45, color: secondaryColor),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      minimumSize: const Size(48, 56),
      iconSize: 24,
      textStyle: const TextStyle(
        fontFamily: 'Roboto',
        fontFamilyFallback: [
          'PingFang SC',
          'Microsoft YaHei',
          'Noto Sans CJK SC',
        ],
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  ),
  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(
      minimumSize: const Size(48, 48),
      textStyle: const TextStyle(
        fontFamily: 'Roboto',
        fontFamilyFallback: [
          'PingFang SC',
          'Microsoft YaHei',
          'Noto Sans CJK SC',
        ],
        fontSize: 15,
        fontWeight: FontWeight.w600,
      ),
    ),
  ),
  iconButtonTheme: IconButtonThemeData(
    style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: Colors.white,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: lineColor),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: lineColor),
    ),
    contentPadding: const EdgeInsets.all(14),
  ),
  dialogTheme: DialogThemeData(
    backgroundColor: Colors.white,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
  ),
  dividerTheme: const DividerThemeData(
    color: lineColor,
    thickness: 1,
    space: 1,
  ),
  snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
);

class Brand extends StatelessWidget {
  const Brand({super.key, this.small = false});
  final bool small;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Image.asset(
        'assets/brand/icon.png',
        width: small ? 34 : 40,
        height: small ? 34 : 40,
        excludeFromSemantics: true,
      ),
      SizedBox(width: small ? 9 : 12),
      Text(
        '轻贴',
        style: TextStyle(
          fontSize: small ? 20 : 25,
          fontWeight: FontWeight.w700,
          color: inkColor,
        ),
      ),
    ],
  );
}

class OnlineStatus extends StatelessWidget {
  const OnlineStatus(this.online, {super.key});
  final bool online;
  @override
  Widget build(BuildContext context) => Semantics(
    label: online ? '在线' : '离线',
    child: ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: online ? const Color(0xFF279342) : const Color(0xFF929D97),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            online ? '在线' : '离线',
            style: const TextStyle(fontSize: 14, color: secondaryColor),
          ),
        ],
      ),
    ),
  );
}
