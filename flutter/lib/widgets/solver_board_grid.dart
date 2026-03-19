import 'package:flutter/material.dart';
import 'package:qy/wordfeud.dart';

class SolverBoardGrid extends StatelessWidget {
  const SolverBoardGrid({
    super.key,
    required this.boardState,
    required this.selectedMove,
  });

  final List<List<String>> boardState;
  final Move? selectedMove;

  @override
  Widget build(BuildContext context) {
    if (boardState.isEmpty) {
      return const Center(child: Text('Load an image to see the board.'));
    }

    return AspectRatio(
      aspectRatio: 1,
      child: Container(
        padding: const EdgeInsets.all(4),
        color: Colors.black,
        child: GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 15,
            crossAxisSpacing: 1,
            mainAxisSpacing: 1,
          ),
          itemCount: 225,
          itemBuilder: (context, index) {
            final row = index ~/ 15;
            final col = index % 15;
            final cellValue = boardState[row][col];
            final overlay = _resolveCellOverlay(
              row: row,
              col: col,
              cellValue: cellValue,
            );

            return Container(
              alignment: Alignment.center,
              color: _getTileColor(cellValue, overlay.isPartOfMove),
              child: Text(
                overlay.displayChar,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: overlay.isWildcardTile
                      ? Colors.red
                      : (cellValue == 'TL' || cellValue == 'TW') &&
                            !overlay.isPartOfMove
                      ? Colors.white
                      : Colors.black,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  _CellOverlay _resolveCellOverlay({
    required int row,
    required int col,
    required String cellValue,
  }) {
    var displayChar = cellValue;
    var isPartOfMove = false;
    var isWildcardTile = false;

    if (selectedMove != null) {
      final move = selectedMove!;
      final moveRow = move.row;
      final moveCol = move.col;
      final moveLength = move.word.length;

      if (move.direction == 'H' &&
          row == moveRow &&
          col >= moveCol &&
          col < moveCol + moveLength) {
        isPartOfMove = true;
        displayChar = move.word[col - moveCol];
      } else if (move.direction == 'V' &&
          col == moveCol &&
          row >= moveRow &&
          row < moveRow + moveLength) {
        isPartOfMove = true;
        displayChar = move.word[row - moveRow];
      }

      if (isPartOfMove &&
          displayChar == displayChar.toLowerCase() &&
          displayChar != displayChar.toUpperCase()) {
        isWildcardTile = true;
        displayChar = displayChar.toUpperCase();
      }
    }

    if (!isPartOfMove && cellValue.length > 2) {
      displayChar = '';
    }

    return _CellOverlay(
      displayChar: displayChar,
      isPartOfMove: isPartOfMove,
      isWildcardTile: isWildcardTile,
    );
  }

  Color _getTileColor(String cellValue, bool isHighlight) {
    if (isHighlight) {
      return Colors.yellowAccent.shade400;
    }
    if (cellValue.length == 1 && cellValue != '?') {
      return Colors.orange.shade100;
    }

    switch (cellValue) {
      case 'DL':
        return Colors.green.shade300;
      case 'TL':
        return Colors.green.shade700;
      case 'DW':
        return Colors.red.shade300;
      case 'TW':
        return Colors.red.shade700;
      default:
        return Colors.grey.shade200;
    }
  }
}

class _CellOverlay {
  const _CellOverlay({
    required this.displayChar,
    required this.isPartOfMove,
    required this.isWildcardTile,
  });

  final String displayChar;
  final bool isPartOfMove;
  final bool isWildcardTile;
}
