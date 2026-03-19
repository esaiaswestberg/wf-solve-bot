import 'package:flutter/material.dart';
import 'package:qy/pages/solver_home_page.dart';

class WordfeudSolverApp extends StatelessWidget {
  const WordfeudSolverApp({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(seedColor: Colors.green);

    return MaterialApp(
      title: 'Qy',
      theme: ThemeData(colorScheme: colorScheme, useMaterial3: true),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.green,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      home: const SolverHomePage(),
    );
  }
}
