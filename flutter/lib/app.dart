import 'package:flutter/material.dart';
import 'package:wf_solvr/pages/solver_home_page.dart';

class WordfeudSolverApp extends StatelessWidget {
  const WordfeudSolverApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Wordfeud Solver',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
      ),
      home: const SolverHomePage(title: 'Wordfeud Solver'),
    );
  }
}
