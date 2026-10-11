import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'src/controller.dart';
import 'src/ui/home.dart';
import 'src/ui/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = ClipController();
  runApp(LanClipApp(controller: controller));
  controller.initialize();
}

class LanClipApp extends StatelessWidget {
  const LanClipApp({super.key, required this.controller});
  final ClipController controller;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '轻贴',
    debugShowCheckedModeBanner: false,
    theme: appTheme,
    locale: const Locale('zh', 'CN'),
    supportedLocales: const [Locale('zh', 'CN')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: ClipHome(controller: controller),
  );
}
