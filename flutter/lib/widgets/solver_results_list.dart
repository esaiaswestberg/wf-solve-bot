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
    final colorScheme = Theme.of(context).colorScheme;

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
          selectedTileColor: colorScheme.primaryContainer,
          leading: CircleAvatar(
            backgroundColor: isSelected
                ? colorScheme.primary
                : colorScheme.surfaceContainerHighest,
            child: Text(
              '${index + 1}',
              style: TextStyle(
                color: isSelected
                    ? colorScheme.onPrimary
                    : colorScheme.onSurfaceVariant,
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
                  style: TextStyle(
                    color: isWildcard ? colorScheme.error : null,
                  ),
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
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: colorScheme.primary,
            ),
          ),
          onTap: () => onMoveSelected(move),
        );
      },
    );
  }
}
