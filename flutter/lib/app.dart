import 'package:flutter/material.dart';
import 'package:qy/pages/solver_home_page.dart';

class WordfeudSolverApp extends StatelessWidget {
  const WordfeudSolverApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Qy',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
      ),
      home: const SolverHomePage(title: 'Qy'),
    );
  }
}
