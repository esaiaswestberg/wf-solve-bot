import 'package:flutter/material.dart';
import 'package:qy/wordfeud.dart';

class SolverResultsList extends StatelessWidget {
  const SolverResultsList({
    super.key,
    required this.solutions,
    required this.selectedMove,
    required this.onMoveSelected,
  });

  final List<Move> solutions;
  final Move? selectedMove;
  final ValueChanged<Move> onMoveSelected;

  @override
  Widget build(BuildContext context) {
    if (solutions.isEmpty) {
      return const Center(
        child: Text('No solutions found or no image selected.'),
      );
    }

    return ListView.separated(
      itemCount: solutions.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final move = solutions[index];
        final isSelected = selectedMove == move;

        return ListTile(
          selected: isSelected,
          selectedTileColor: Colors.green.shade50,
          leading: CircleAvatar(
            backgroundColor: isSelected ? Colors.green : Colors.grey.shade300,
            child: Text(
              '${index + 1}',
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.black87,
              ),
            ),
          ),
          title: Text.rich(
            TextSpan(
              children: move.word.split('').map((char) {
                final isWildcard =
                    char == char.toLowerCase() && char != char.toUpperCase();
                return TextSpan(
                  text: char.toUpperCase(),
                  style: TextStyle(color: isWildcard ? Colors.red : null),
                );
              }).toList(),
            ),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Text(
            'Dir: ${move.direction == 'H' ? 'Across' : 'Down'} | Row: ${move.row}, Col: ${move.col}',
          ),
          trailing: Text(
            '${move.score} pts',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: Colors.green,
            ),
          ),
          onTap: () => onMoveSelected(move),
        );
      },
    );
  }
}
