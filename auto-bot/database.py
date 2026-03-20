import os
import sqlite3

DB_PATH = os.environ.get('WF_DB_PATH', os.path.join(os.path.dirname(__file__), 'wf_bot.db'))

MOVE_HISTORY_LIMIT = 20


def get_connection() -> sqlite3.Connection:
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA foreign_keys=ON")
    return conn


def init_db(conn: sqlite3.Connection) -> None:
    conn.executescript("""
        CREATE TABLE IF NOT EXISTS player_moves (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            username TEXT NOT NULL,
            game_id INTEGER NOT NULL,
            move_score INTEGER NOT NULL,
            recorded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );

        CREATE TABLE IF NOT EXISTS game_snapshots (
            game_id INTEGER PRIMARY KEY,
            opponent_username TEXT NOT NULL,
            opponent_score INTEGER NOT NULL,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );
    """)
    conn.commit()


def get_opponent_avg_score(conn: sqlite3.Connection, username: str) -> float | None:
    rows = conn.execute(
        "SELECT move_score FROM player_moves WHERE username = ? ORDER BY recorded_at DESC LIMIT ?",
        (username, MOVE_HISTORY_LIMIT)
    ).fetchall()
    if not rows:
        return None
    return sum(r['move_score'] for r in rows) / len(rows)


def record_opponent_move(conn: sqlite3.Connection, username: str, game_id: int, move_score: int) -> None:
    conn.execute(
        "INSERT INTO player_moves (username, game_id, move_score) VALUES (?, ?, ?)",
        (username, game_id, move_score)
    )
    conn.commit()


def get_game_snapshot(conn: sqlite3.Connection, game_id: int) -> dict | None:
    row = conn.execute(
        "SELECT opponent_username, opponent_score FROM game_snapshots WHERE game_id = ?",
        (game_id,)
    ).fetchone()
    if row is None:
        return None
    return {'opponent_username': row['opponent_username'], 'opponent_score': row['opponent_score']}


def upsert_game_snapshot(conn: sqlite3.Connection, game_id: int, opponent_username: str, opponent_score: int) -> None:
    conn.execute(
        "INSERT OR REPLACE INTO game_snapshots (game_id, opponent_username, opponent_score) VALUES (?, ?, ?)",
        (game_id, opponent_username, opponent_score)
    )
    conn.commit()
