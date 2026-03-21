import os
import sys
import time
import random
from datetime import datetime, timedelta
from dotenv import load_dotenv
load_dotenv()
from wordfeud_api import Wordfeud
from solver import find_all_moves, build_trie
from scorer import rank_moves, load_point_values
from database import (get_connection, init_db, get_opponent_avg_score, record_opponent_move,
                      get_game_snapshot, upsert_game_snapshot,
                      get_turn_schedule, set_turn_schedule, delete_turn_schedule)

POLL_INTERVAL = int(os.environ.get('WF_POLL_INTERVAL', '30'))
MIN_WAIT_SECONDS = int(os.environ.get('WF_MIN_WAIT_SECONDS', str(5 * 60)))       # default 5 min
MAX_WAIT_SECONDS = int(os.environ.get('WF_MAX_WAIT_SECONDS', str(6 * 60 * 60)))  # default 6 hours
INVITE_CHANCE = float(os.environ.get('WF_INVITE_CHANCE', '0.20'))                # default 20%
MAX_ACTIVE_GAMES = int(os.environ.get('WF_MAX_ACTIVE_GAMES', '30'))


def ts():
    return datetime.now().strftime('[%H:%M:%S]')

# Maps the integer board square codes returned by the Wordfeud API
# to the string format expected by the solver.
BOARD_CODE_MAP = {0: 'EMPTY', 1: 'DL', 2: 'TL', 3: 'DW', 4: 'TW'}

DICTIONARIES = {
    'swedish': {
        'words': os.path.join(os.path.dirname(__file__), '..', 'py-solver', 'dictionaries', 'swedish', 'swedish', 'dictionary.txt'),
        'points': os.path.join(os.path.dirname(__file__), '..', 'py-solver', 'dictionaries', 'swedish', 'swedish', 'letter_values.csv'),
        'rulesets': [4],
    },
    'english': {
        'words': os.path.join(os.path.dirname(__file__), '..', 'py-solver', 'dictionaries', 'english', 'sowpods', 'dictionary.txt'),
        'points': os.path.join(os.path.dirname(__file__), '..', 'py-solver', 'dictionaries', 'english', 'sowpods', 'letter_values.csv'),
        'rulesets': [0, 5],
    },
}

RULESET_TO_LANGUAGE = {rs: lang for lang, cfg in DICTIONARIES.items() for rs in cfg['rulesets']}


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
    Returns a list of [row, col, letter_upper, is_wildcard].
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
            tiles.append([r, c, char.upper(), is_wildcard])

    return tiles



def observe_opponent_move(conn, game, opponent_username):
    """Records the opponent's last move score by diffing their score against the stored snapshot."""
    game_id = game['id']
    opponent = next((p for p in game.get('players', []) if not p.get('is_local')), None)
    if not opponent:
        return

    current_score = opponent.get('score', 0)
    snapshot = get_game_snapshot(conn, game_id)

    if snapshot is not None and snapshot['opponent_username'] == opponent_username:
        delta = current_score - snapshot['opponent_score']
        if delta > 0:
            record_opponent_move(conn, opponent_username, game_id, delta)
            print(f"{ts()}   Recorded opponent move score: {delta}p")


def choose_target_score(conn, opponent_username, is_first_move):
    """
    Returns the target move score the bot should aim for, or None to play best.

    - Known opponent: use their average move score.
    - Unknown opponent, first move: target 17 (midpoint of 15-20).
    - Unknown opponent, not first move: play best (None).
    """
    avg = get_opponent_avg_score(conn, opponent_username)
    if avg is not None:
        target = round(avg)
        print(f"{ts()}   Opponent '{opponent_username}' avg score: {avg:.1f}p → target: {target}p")
        return target
    if is_first_move:
        print(f"{ts()}   Unknown opponent, first move → target: 17p")
        return 17
    return None


def play_best_move(wf, game, board_layout, dictionaries, conn):
    game_id = game['id']
    ruleset = game['ruleset']

    lang = RULESET_TO_LANGUAGE.get(ruleset)
    if lang is None:
        print(f"{ts()}   Unknown ruleset {ruleset} — skipping game {game_id}.")
        return
    trie = dictionaries[lang]['trie']
    points_dict = dictionaries[lang]['points_dict']

    board = build_board(game, board_layout)
    my_player = get_my_player(game)
    rack = convert_rack(my_player['rack'])

    print(f"{ts()}   Rack: {rack}")

    moves = find_all_moves(board, rack, trie)
    print(f"{ts()}   Found {len(moves)} valid moves.")

    if not moves:
        print(f"{ts()}   No valid moves — skipping turn.")
        wf.skip_turn(game_id)
        return

    ranked = rank_moves(moves, board, points_dict)

    opponent_username = next((p['username'] for p in game.get('players', []) if not p.get('is_local')), None)
    is_first_move = len(game.get('tiles', [])) == 0
    target_score = choose_target_score(conn, opponent_username, is_first_move)

    if target_score is None:
        selected = ranked[0]
    else:
        selected = min(ranked, key=lambda m: abs(m['score'] - target_score))

    print(f"{ts()}   Selected move: '{selected['word']}' at row={selected['row']}, col={selected['col']}, "
          f"dir={selected['direction']}, score={selected['score']}")

    attempt_order = [selected] + [m for m in ranked if m is not selected]

    for move in attempt_order:
        tiles = convert_move_to_tiles(move, board)
        word = move['word'].upper()
        print(f"\n{ts()}   Trying '{word}' (score={move['score']}) — tiles: {tiles}")
        res = wf.place(game_id, ruleset, tiles, word)
        if res and res.get('status') == 'error':
            error_type = res.get('content', {}).get('type', 'unknown')
            print(f"{ts()}   Rejected ({error_type}), trying next move...")
            continue
        print(f"{ts()}   Played successfully. API response: {res}")
        return

    print(f"{ts()}   All moves rejected — skipping turn.")
    wf.skip_turn(game_id)


def should_play_now(conn, game) -> bool:
    """
    Returns True if it's time to play this turn, False if still waiting.

    On each new turn, schedules a random delay between MIN_WAIT_SECONDS and
    MAX_WAIT_SECONDS. The schedule is keyed on tile count so a new turn always
    gets a fresh delay, independent of the previous one.
    """
    game_id = game['id']
    tile_count = len(game.get('tiles', []))

    if tile_count == 0:
        return True

    schedule = get_turn_schedule(conn, game_id)

    if schedule is None or schedule['tile_count'] != tile_count:
        delay = random.uniform(MIN_WAIT_SECONDS, MAX_WAIT_SECONDS)
        play_at = datetime.now() + timedelta(seconds=delay)
        set_turn_schedule(conn, game_id, tile_count, play_at.isoformat())
        print(f"{ts()}   Scheduled to play at {play_at.strftime('%H:%M:%S')} "
              f"(in {delay/60:.1f} min)")
        return False

    play_at = datetime.fromisoformat(schedule['play_at'])
    if datetime.now() >= play_at:
        return True

    remaining = (play_at - datetime.now()).total_seconds()
    print(f"{ts()}   Waiting until {play_at.strftime('%H:%M:%S')} "
          f"({remaining/60:.1f} min remaining)")
    return False


def maybe_invite_random_opponent(wf):
    if random.random() >= INVITE_CHANCE:
        return
    all_rulesets = [rs for cfg in DICTIONARIES.values() for rs in cfg['rulesets']]
    ruleset = random.choice(all_rulesets)
    board_type = random.choice([Wordfeud.BoardNormal, Wordfeud.BoardRandom])
    board_name = 'normal' if board_type == Wordfeud.BoardNormal else 'random'
    lang = RULESET_TO_LANGUAGE.get(ruleset, ruleset)
    print(f"{ts()} Sending random opponent invite (ruleset={ruleset}/{lang}, board={board_name})...")
    res = wf.invite_random_opponent(ruleset, board_type)
    if isinstance(res, dict) and res.get('status') == 'error':
        print(f"{ts()} Invite failed: {res.get('content', {}).get('type', 'unknown error')}")
    else:
        print(f"{ts()} Invite sent.")


def run_once(wf, dictionaries, board_cache, conn):
    print(f"{ts()} Checking for pending invites...")
    status = wf.get_status()
    invites = status.get('invites_received', [])
    if invites:
        print(f"{ts()} Found {len(invites)} invite(s) — accepting all.")
        for invite in invites:
            wf.accept_invite(invite['id'])
            print(f"{ts()}   Accepted invite {invite['id']}.")

    print(f"{ts()} Fetching games...")
    games_response = wf.get_games()
    games = games_response if isinstance(games_response, list) else games_response.get('games', [])

    invites_sent = status.get('invites_sent', [])
    if not invites and not invites_sent and len(games) < MAX_ACTIVE_GAMES:
        maybe_invite_random_opponent(wf)

    pending = [g for g in games if is_my_turn(g)]
    print(f"{ts()} {len(games)} active game(s), {len(pending)} waiting for your move.")

    for game in pending:
        game_id = game['id']
        board_id = game['board']
        opponent_username = next((p['username'] for p in game['players'] if not p.get('is_local')), 'Unknown')
        print(f"{ts()} Game {game_id} vs {opponent_username}:")

        observe_opponent_move(conn, game, opponent_username)

        opponent = next((p for p in game['players'] if not p.get('is_local')), None)
        if opponent:
            upsert_game_snapshot(conn, game_id, opponent_username, opponent.get('score', 0))

        if not should_play_now(conn, game):
            continue

        if board_id not in board_cache:
            board_cache[board_id] = wf.get_board(board_id)
        board_layout = board_cache[board_id]

        play_best_move(wf, game, board_layout, dictionaries, conn)
        delete_turn_schedule(conn, game_id)


def main():
    email = os.environ.get('WF_EMAIL')
    password = os.environ.get('WF_PASSWORD')

    if not email or not password:
        print("Error: WF_EMAIL and WF_PASSWORD environment variables must be set.")
        sys.exit(1)

    print(f"{ts()} Logging in as {email}...")
    wf = Wordfeud()
    wf.login_email(email, password)
    print(f"{ts()} Logged in.")

    dictionaries = {}
    for lang, config in DICTIONARIES.items():
        print(f"{ts()} Loading {lang} dictionary...")
        with open(config['words'], 'r', encoding='utf-8') as f:
            words = f.readlines()
        points_dict = load_point_values(config['points'])
        print(f"{ts()} Building Trie for {lang}...")
        trie = build_trie(words)
        dictionaries[lang] = {'trie': trie, 'points_dict': points_dict}
        print(f"{ts()} {lang} dictionary loaded ({len(words)} words).")

    conn = get_connection()
    init_db(conn)
    board_cache = {}
    while True:
        try:
            run_once(wf, dictionaries, board_cache, conn)
        except Exception as e:
            print(f"{ts()} [error] {e}")
        print(f"{ts()} Sleeping {POLL_INTERVAL}s...")
        time.sleep(POLL_INTERVAL)


if __name__ == '__main__':
    main()
