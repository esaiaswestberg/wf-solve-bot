import os
import sys
from dotenv import load_dotenv
load_dotenv()
from wordfeud_api import Wordfeud
from solver import find_all_moves
from scorer import rank_moves, load_point_values

# Maps the integer board square codes returned by the Wordfeud API
# to the string format expected by the solver.
BOARD_CODE_MAP = {0: 'EMPTY', 1: 'DL', 2: 'TL', 3: 'DW', 4: 'TW'}

DICTIONARIES = {
    'swedish': {
        'words': os.path.join(os.path.dirname(__file__), '..', 'py-solver', 'dictionaries', 'swedish', 'swedish', 'dictionary.txt'),
        'points': os.path.join(os.path.dirname(__file__), '..', 'py-solver', 'dictionaries', 'swedish', 'swedish', 'letter_values.csv'),
        'ruleset': 4,
    },
    'english': {
        'words': os.path.join(os.path.dirname(__file__), '..', 'py-solver', 'dictionaries', 'english', 'sowpods', 'dictionary.txt'),
        'points': os.path.join(os.path.dirname(__file__), '..', 'py-solver', 'dictionaries', 'english', 'sowpods', 'letter_values.csv'),
        'ruleset': 0,
    },
}


def load_dictionary(language):
    config = DICTIONARIES.get(language)
    if not config:
        print(f"Unknown language '{language}'. Supported: {list(DICTIONARIES.keys())}")
        sys.exit(1)

    with open(config['words'], 'r', encoding='utf-8') as f:
        return f.readlines()


def build_board(game, board_layout):
    """
    Constructs a 15x15 board in solver format from API game state.

    board_layout is the 15x15 grid of integer codes from get_board().
    game['tiles'] is a list of [row, col, letter, is_wildcard] for placed tiles.
    """
    board = [[BOARD_CODE_MAP.get(board_layout[r][c], 'EMPTY') for c in range(15)] for r in range(15)]

    for tile in game.get('tiles', []):
        row, col, letter, is_wildcard = tile[0], tile[1], tile[2], tile[3]
        # Wildcards are stored as lowercase so scorer/solver can distinguish them
        board[row][col] = letter.lower() if is_wildcard else letter.upper()

    return board


def convert_rack(api_rack):
    """Converts the API rack (list of letters, "" for wildcard) to solver format."""
    return ['?' if tile == '' else tile.upper() for tile in api_rack]


def get_my_player(game):
    """Returns the player dict for the local (authenticated) user."""
    for player in game.get('players', []):
        if player.get('is_local'):
            return player
    return None


def is_my_turn(game):
    """Returns True if it's the local player's turn and the game is still running."""
    if not game.get('is_running', False):
        return False
    my_player = get_my_player(game)
    if not my_player:
        return False
    return my_player.get('position') == game.get('current_player')


def convert_move_to_tiles(move, board):
    """
    Converts a solver move to the API tile placement format.

    Only tiles that land on empty/bonus squares are new placements.
    Returns a list of [col, row, letter_upper, is_wildcard].
    Wildcard tiles are identified by lowercase letters in the solver's word output.
    """
    word = move['word']
    start_r = move['row']
    start_c = move['col']
    direction = move['direction']
    tiles = []

    for i, char in enumerate(word):
        r = start_r + i if direction == 'V' else start_r
        c = start_c + i if direction == 'H' else start_c

        # Only submit tiles that are newly placed (board square is not an existing letter)
        if len(board[r][c]) != 1:
            is_wildcard = char.islower()
            tiles.append([c, r, char.upper(), is_wildcard])

    return tiles


def play_best_move(wf, game, board_layout, dictionary, points_dict):
    game_id = game['id']
    ruleset = game['ruleset']

    board = build_board(game, board_layout)
    my_player = get_my_player(game)
    rack = convert_rack(my_player['rack'])

    print(f"  Rack: {rack}")

    moves = find_all_moves(board, rack, dictionary)
    print(f"  Found {len(moves)} valid moves.")

    if not moves:
        print("  No valid moves — skipping turn.")
        wf.skip_turn(game_id, ruleset)
        return

    ranked = rank_moves(moves, board, points_dict)
    best = ranked[0]

    print(f"  Best move: '{best['word']}' at row={best['row']}, col={best['col']}, "
          f"dir={best['direction']}, score={best['score']}")

    for move in ranked:
        tiles = convert_move_to_tiles(move, board)
        word = move['word'].upper()
        print(f"  Trying '{word}' (score={move['score']}) — tiles: {tiles}")
        res = wf.place(game_id, ruleset, tiles, word)
        if res and res.get('status') == 'error' and res.get('content', {}).get('type') == 'illegal_word':
            print(f"  Rejected (illegal_word), trying next move...")
            continue
        print(f"  Played successfully. API response: {res}")
        return

    print("  All moves rejected — skipping turn.")
    wf.skip_turn(game_id, ruleset)


def main():
    email = os.environ.get('WF_EMAIL')
    password = os.environ.get('WF_PASSWORD')
    language = os.environ.get('WF_LANGUAGE', 'swedish')

    if not email or not password:
        print("Error: WF_EMAIL and WF_PASSWORD environment variables must be set.")
        sys.exit(1)

    print(f"Logging in as {email}...")
    wf = Wordfeud()
    wf.login_email(email, password)
    print("Logged in.")

    lang_config = DICTIONARIES[language]
    print(f"Loading {language} dictionary...")
    dictionary = load_dictionary(language)
    points_dict = load_point_values(lang_config['points'])
    print(f"Dictionary loaded ({len(dictionary)} words).")

    print("Checking for pending invites...")
    status = wf.get_status()
    invites = status.get('invites_received', [])
    if invites:
        print(f"Found {len(invites)} invite(s) — accepting all.")
        for invite in invites:
            wf.accept_invite(invite['id'])
            print(f"  Accepted invite {invite['id']}.")
    else:
        print("No pending invites.")

    print("Fetching games...")
    games_response = wf.get_games()
    games = games_response if isinstance(games_response, list) else games_response.get('games', [])
    print(f"Found {len(games)} active game(s).")

    pending = [g for g in games if is_my_turn(g)]
    print(f"{len(pending)} game(s) waiting for your move.")

    for game in pending:
        game_id = game['id']
        opponent = next((p['username'] for p in game['players'] if not p.get('is_local')), 'Unknown')
        print(f"\nGame {game_id} vs {opponent}:")

        board_layout = wf.get_board(game['board'])
        play_best_move(wf, game, board_layout, dictionary, points_dict)

    print("\nDone.")


if __name__ == '__main__':
    main()
