import 'package:flutter/material.dart';

import 'ui/app_controller.dart';
import 'ui/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = await AppController.create();
  runApp(EnXcciApp(controller: controller));
}

class EnXcciApp extends StatelessWidget {
  const EnXcciApp({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'EnXcci',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: const Color(0xFF0C0F18),
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFFFFB84D),
            brightness: Brightness.dark,
            primary: const Color(0xFFFFB84D),
            secondary: const Color(0xFF41D5C3),
            tertiary: const Color(0xFFB58CFF),
            surface: const Color(0xFF121625),
          ),
          useMaterial3: true,
          cardTheme: const CardThemeData(color: Color(0xFF171B2A), margin: EdgeInsets.only(bottom: 12)),
          inputDecorationTheme: const InputDecorationTheme(
            filled: true,
            fillColor: Color(0xFF171B2A),
            border: OutlineInputBorder(),
          ),
          navigationBarTheme: const NavigationBarThemeData(
            backgroundColor: Color(0xFF111522),
            indicatorColor: Color(0x33FFB84D),
          ),
        ),
        home: HomeScreen(controller: controller),
      );
}