import sqlite3
import os
from datetime import datetime

DB_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)),
          '..', 'data', 'monitor.db')


def db_init():
    os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    conn.execute('''CREATE TABLE IF NOT EXISTS readings (
        id      INTEGER PRIMARY KEY AUTOINCREMENT,
        ts      TEXT NOT NULL,
        grams   REAL NOT NULL,
        quality TEXT NOT NULL,
        sigma   REAL NOT NULL
    )''')
    conn.execute('''CREATE TABLE IF NOT EXISTS config (
        key   TEXT PRIMARY KEY,
        value TEXT NOT NULL
    )''')
    conn.commit()
    conn.close()


def db_insert_reading(ts, grams, quality, sigma):
    try:
        conn = sqlite3.connect(DB_PATH)
        conn.execute(
            'INSERT INTO readings (ts, grams, quality, sigma) VALUES (?, ?, ?, ?)',
            (ts, grams, quality, sigma)
        )
        conn.commit()
        conn.close()
        print(f'[DB] inserted: grams={grams:.1f} quality={quality}', flush=True)
    except Exception as e:
        print(f'[DB] insert error: {e}', flush=True)


def db_get_starting_weight():
    try:
        conn = sqlite3.connect(DB_PATH)
        row = conn.execute(
            "SELECT value FROM config WHERE key='starting_weight'"
        ).fetchone()
        conn.close()
        if row:
            return float(row[0])
        return None
    except Exception as e:
        print(f'[DB] get_starting_weight error: {e}', flush=True)
        return None


def db_set_starting_weight(grams):
    try:
        conn = sqlite3.connect(DB_PATH)
        conn.execute(
            "INSERT OR REPLACE INTO config (key, value) VALUES ('starting_weight', ?)",
            (str(round(grams, 1)),)
        )
        conn.commit()
        conn.close()
        print(f'[DB] starting_weight set to {round(grams, 1)}', flush=True)
    except Exception as e:
        print(f'[DB] set_starting_weight error: {e}', flush=True)


def db_get_latest_reading():
    try:
        conn = sqlite3.connect(DB_PATH)
        conn.row_factory = sqlite3.Row
        row = conn.execute(
            'SELECT ts, grams, quality, sigma FROM readings ORDER BY id DESC LIMIT 1'
        ).fetchone()
        conn.close()
        if row:
            return dict(row)
        return None
    except Exception as e:
        print(f'[DB] get_latest_reading error: {e}', flush=True)
        return None


def db_get_dev_mode():
    try:
        conn = sqlite3.connect(DB_PATH)
        row = conn.execute(
            "SELECT value FROM config WHERE key='dev_mode'"
        ).fetchone()
        conn.close()
        if row:
            return row[0] == '1'
        return True  # default: dev mode on
    except Exception as e:
        print(f'[DB] get_dev_mode error: {e}', flush=True)
        return True


def db_set_dev_mode(enabled: bool):
    try:
        conn = sqlite3.connect(DB_PATH)
        conn.execute(
            "INSERT OR REPLACE INTO config (key, value) VALUES ('dev_mode', ?)",
            ('1' if enabled else '0',)
        )
        conn.commit()
        conn.close()
        print(f'[DB] dev_mode set to {enabled}', flush=True)
    except Exception as e:
        print(f'[DB] set_dev_mode error: {e}', flush=True)
