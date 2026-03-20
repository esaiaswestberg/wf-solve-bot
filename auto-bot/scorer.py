import os

def load_point_values(filepath):
    """Loads the CSV file containing letter points into a dictionary."""
    points = {}
    if not os.path.exists(filepath):
        print(f"Error: Could not find {filepath}")
        return points

    with open(filepath, 'r') as f:
        for line in f:
            line = line.strip()
            if line and ',' in line:
                letter, value = line.split(',')
                points[letter.upper()] = int(value)

    # Wordfeud wildcard/blank tiles score 0 points
    points['?'] = 0
    return points

def calculate_move_score(move, board, points_dict):
    """
    Calculates the score for a single horizontal or vertical word,
    accounting for board multipliers and the 7-tile bingo bonus.
    """
    word = move['word']
    start_r = move['row']
    start_c = move['col']
    direction = move['direction']

    base_score = 0
    word_multiplier = 1
    tiles_played_from_rack = 0

    for i, char in enumerate(word):
        # Determine current square coordinates
        r = start_r + i if direction == 'V' else start_r
        c = start_c + i if direction == 'H' else start_c

        board_square = board[r][c]
        letter_val = points_dict.get(char, 0)

        # If the square on the board is a single letter, it's an existing tile.
        # Existing tiles do NOT trigger bonus multipliers underneath them.
        if len(board_square) == 1:
            base_score += letter_val
        else:
            # It's an empty square or a multiplier square, so it's a newly placed tile
            tiles_played_from_rack += 1

            if board_square == 'DL':
                base_score += (letter_val * 2)
            elif board_square == 'TL':
                base_score += (letter_val * 3)
            else:
                base_score += letter_val

            # Keep track of word multipliers to apply at the end
            if board_square == 'DW':
                word_multiplier *= 2
            elif board_square == 'TW':
                word_multiplier *= 3

    total_score = base_score * word_multiplier

    # Wordfeud awards a 40-point bonus for playing all 7 tiles in one turn
    if tiles_played_from_rack == 7:
        total_score += 40

    return total_score

def rank_moves(all_moves, board, points_dict):
    """
    Iterates through all valid moves, calculates their scores,
    and returns a list sorted from highest score to lowest.
    """
    ranked_moves = []

    for move in all_moves:
        score = calculate_move_score(move, board, points_dict)

        # Create a new dictionary with the score included
        ranked_move = move.copy()
        ranked_move['score'] = score
        ranked_moves.append(ranked_move)

    # Sort the list of dictionaries by the 'score' key in descending order
    ranked_moves.sort(key=lambda x: x['score'], reverse=True)

    return ranked_moves
