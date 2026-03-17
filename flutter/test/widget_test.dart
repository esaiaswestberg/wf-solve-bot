import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wf_solvr/widgets/solver_board_grid.dart';
import 'package:wf_solvr/widgets/solver_results_list.dart';
import 'package:wf_solvr/wordfeud.dart';

void main() {
  testWidgets('SolverBoardGrid shows placeholder when board is empty', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SolverBoardGrid(boardState: [], selectedMove: null),
        ),
      ),
    );

    expect(find.text('Load an image to see the board.'), findsOneWidget);
  });

  testWidgets('SolverBoardGrid renders a populated board', (tester) async {
    final boardState = List.generate(
      15,
      (_) => List.generate(15, (_) => 'EMPTY'),
    );
    boardState[7][7] = 'A';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SolverBoardGrid(boardState: boardState, selectedMove: null),
        ),
      ),
    );

    expect(find.byType(GridView), findsOneWidget);
    expect(find.text('A'), findsOneWidget);
  });

  testWidgets('SolverResultsList shows empty state when there are no moves', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SolverResultsList(
            solutions: [],
            selectedMove: null,
            onMoveSelected: _onMoveSelectedStub,
          ),
        ),
      ),
    );

    expect(
      find.text('No solutions found or no image selected.'),
      findsOneWidget,
    );
  });

  testWidgets('SolverResultsList renders moves and handles selection', (
    tester,
  ) async {
    final moves = [
      Move(word: 'TEST', row: 7, col: 4, direction: 'H', score: 42),
      Move(word: 'WORD', row: 3, col: 8, direction: 'V', score: 35),
    ];
    Move? selectedMove;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SolverResultsList(
            solutions: moves,
            selectedMove: moves.first,
            onMoveSelected: (move) {
              selectedMove = move;
            },
          ),
        ),
      ),
    );

    expect(find.text('TEST'), findsOneWidget);
    expect(find.text('WORD'), findsOneWidget);
    expect(find.text('42 pts'), findsOneWidget);

    await tester.tap(find.text('WORD'));
    await tester.pump();

    expect(selectedMove, equals(moves.last));
  });
}

void _onMoveSelectedStub(Move move) {}
