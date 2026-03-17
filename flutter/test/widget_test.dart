import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wf_solvr/models/dictionary_metadata.dart';
import 'package:wf_solvr/pages/solver_home_page.dart';
import 'package:wf_solvr/services/dictionary_assets_repository.dart';
import 'package:wf_solvr/services/dictionary_selection_store.dart';
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

  testWidgets('SolverHomePage restores the saved dictionary on startup', (
    tester,
  ) async {
    final store = FakeDictionarySelectionStore(
      selectedId: swedishDictionary.id,
    );
    final worker = FakeSolverWorker();

    await tester.pumpWidget(
      MaterialApp(
        home: SolverHomePage(
          title: 'Wordfeud Solver',
          worker: worker,
          assetsRepository: FakeDictionaryAssetsRepository(),
          selectionStore: store,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Swedish'), findsOneWidget);
    expect(worker.initializedDictText, equals('SV_DICT'));
  });

  testWidgets(
    'SolverHomePage falls back to first dictionary for stale saved id',
    (tester) async {
      final store = FakeDictionarySelectionStore(selectedId: 'missing-id');
      final worker = FakeSolverWorker();

      await tester.pumpWidget(
        MaterialApp(
          home: SolverHomePage(
            title: 'Wordfeud Solver',
            worker: worker,
            assetsRepository: FakeDictionaryAssetsRepository(),
            selectionStore: store,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('English (International)'), findsOneWidget);
      expect(worker.initializedDictText, equals('EN_DICT'));
    },
  );

  testWidgets('SolverHomePage saves a dictionary after a successful change', (
    tester,
  ) async {
    final store = FakeDictionarySelectionStore();
    final worker = FakeSolverWorker();

    await tester.pumpWidget(
      MaterialApp(
        home: SolverHomePage(
          title: 'Wordfeud Solver',
          worker: worker,
          assetsRepository: FakeDictionaryAssetsRepository(),
          selectionStore: store,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final dropdown = tester.widget<DropdownButton<DictionaryMetadata>>(
      find.byType(DropdownButton<DictionaryMetadata>),
    );

    dropdown.onChanged?.call(swedishDictionary);
    await tester.pumpAndSettle();

    expect(store.savedIds, equals([swedishDictionary.id]));
    expect(store.selectedId, equals(swedishDictionary.id));
    expect(worker.changedDictText, equals('SV_DICT'));
    expect(find.text('Swedish'), findsOneWidget);
  });

  testWidgets('SolverHomePage does not save failed dictionary changes', (
    tester,
  ) async {
    final store = FakeDictionarySelectionStore();
    final worker = FakeSolverWorker(changeShouldThrow: true);

    await tester.pumpWidget(
      MaterialApp(
        home: SolverHomePage(
          title: 'Wordfeud Solver',
          worker: worker,
          assetsRepository: FakeDictionaryAssetsRepository(),
          selectionStore: store,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final dropdown = tester.widget<DropdownButton<DictionaryMetadata>>(
      find.byType(DropdownButton<DictionaryMetadata>),
    );

    dropdown.onChanged?.call(swedishDictionary);
    await tester.pumpAndSettle();

    expect(store.savedIds, isEmpty);
    expect(store.selectedId, isNull);
    expect(worker.changedDictText, equals('SV_DICT'));
    expect(find.text('English (International)'), findsOneWidget);
  });
}

void _onMoveSelectedStub(Move move) {}

final englishDictionary = DictionaryMetadata(
  title: 'English (International)',
  language: 'english',
  dictionaryName: 'SOWPODS',
  dictPath: 'assets/static/dictionaries/english/sowpods/dictionary.txt',
  csvPath: 'assets/static/dictionaries/english/sowpods/letter_values.csv',
);

final swedishDictionary = DictionaryMetadata(
  title: 'Swedish',
  language: 'swedish',
  dictionaryName: 'All word forms',
  dictPath: 'assets/static/dictionaries/swedish/swedish/dictionary.txt',
  csvPath: 'assets/static/dictionaries/swedish/swedish/letter_values.csv',
);

class FakeDictionaryAssetsRepository implements DictionaryAssetsRepository {
  final Map<String, DictionaryData> _data = {
    englishDictionary.id: DictionaryData(dictText: 'EN_DICT', csvText: 'A,1'),
    swedishDictionary.id: DictionaryData(dictText: 'SV_DICT', csvText: 'A,1'),
  };

  @override
  Future<DictionaryLoadResult> load() async {
    return DictionaryLoadResult(
      dictionaries: [englishDictionary, swedishDictionary],
      templateBytes: const {},
    );
  }

  @override
  Future<DictionaryData> loadDictionaryData(
    DictionaryMetadata dictionary,
  ) async {
    return _data[dictionary.id]!;
  }
}

class FakeDictionarySelectionStore implements DictionarySelectionStore {
  FakeDictionarySelectionStore({this.selectedId});

  @override
  String? selectedId;

  final List<String> savedIds = [];

  @override
  Future<String?> loadSelectedDictionaryId() async {
    return selectedId;
  }

  @override
  Future<void> saveSelectedDictionaryId(String id) async {
    savedIds.add(id);
    selectedId = id;
  }
}

class FakeSolverWorker implements SolverWorker {
  FakeSolverWorker({this.changeShouldThrow = false});

  final bool changeShouldThrow;
  String? initializedDictText;
  String? changedDictText;

  @override
  bool isReady = false;

  @override
  Future<void> changeDictionary(String dictText, String csvText) async {
    changedDictText = dictText;
    if (changeShouldThrow) {
      throw Exception('change failed');
    }
  }

  @override
  Future<void> initialize({
    required String dictText,
    required String csvText,
    required Map<String, List<Uint8List>> templateBytes,
  }) async {
    initializedDictText = dictText;
    isReady = true;
  }

  @override
  Future<SolveResponse> solve(String imagePath) async {
    return SolveResponse([], []);
  }
}
