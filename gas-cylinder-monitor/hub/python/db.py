import sqlite3
import os
from datetime import datetime

DB_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)),
          '..', 'data', 'monitor.db')


def db_init():
    os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    conn.execute('''CREATE TABLE IF NOT EXISTS readings (
        id             INTEGER PRIMARY KEY AUTOINCREMENT,
        ts             TEXT NOT NULL,
        grams          REAL NOT NULL,
        quality        TEXT NOT NULL,
        sigma          REAL NOT NULL,
        gas_pct        REAL,
        gas_g          REAL,
        alert_level    TEXT,
        cylinder_state TEXT
    )''')
    conn.execute('''CREATE TABLE IF NOT EXISTS config (
        key   TEXT PRIMARY KEY,
        value TEXT NOT NULL
    )''')
    # Add new columns to existing DBs — safe to run repeatedly
    for col_sql in [
        'ALTER TABLE readings ADD COLUMN gas_pct        REAL',
        'ALTER TABLE readings ADD COLUMN gas_g          REAL',
        'ALTER TABLE readings ADD COLUMN alert_level    TEXT',
        'ALTER TABLE readings ADD COLUMN cylinder_state TEXT',
    ]:
        try:
            conn.execute(col_sql)
        except Exception:
            pass  # column already exists
    conn.execute('CREATE INDEX IF NOT EXISTS idx_readings_ts ON readings(ts)')
    conn.execute('CREATE INDEX IF NOT EXISTS idx_readings_state ON readings(cylinder_state)')
    conn.commit()
    conn.close()


def db_insert_reading(ts, grams, quality, sigma,
                      gas_pct=None, gas_g=None,
                      alert_level=None, cylinder_state=None):
    try:
        conn = sqlite3.connect(DB_PATH)
        conn.execute(
            '''INSERT INTO readings
               (ts, grams, quality, sigma, gas_pct, gas_g, alert_level, cylinder_state)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?)''',
            (ts, grams, quality, sigma, gas_pct, gas_g, alert_level, cylinder_state)
        )
        conn.commit()
        conn.close()
        print(f'[DB] inserted: grams={grams:.1f} quality={quality}', flush=True)
    except Exception as e:
        print(f'[DB] insert error: {e}', flush=True)


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


