/**
 * Durable SQLite-backed sink for {@link debugLog}, for crash forensics.
 *
 * The in-memory ring buffer in `debugLog.ts` vanishes on crash/restart, which
 * defeats the purpose of a debug log. This store mirrors every entry into a
 * standalone SQLite file (`logs.db`) so the breadcrumb trail survives a crash
 * and can be read back on the next launch.
 *
 * Durability strategy: writes use expo-sqlite's **synchronous** API
 * (`openDatabaseSync` + `runSync`). A synchronous per-entry write guarantees the
 * row is committed before execution continues, so a crash immediately after a
 * `log()` call can't lose the most important entries (e.g. the `app.fatal` line
 * written from the global error handler). WAL is intentionally NOT enabled here:
 * the rollback journal's default synchronous behavior favors "on disk now" over
 * throughput, which is what we want for forensics. Volume is low (per user
 * action), so the cost is negligible.
 *
 * The store lives in its OWN database file, isolated from the synced app data DB
 * (`recipes.db`), so clearing logs never touches recipes and vice versa.
 */
import * as SQLite from 'expo-sqlite';

import { type LogEntry, type LogSink, type LogDetails } from './debugLog';

const DB_NAME = 'logs.db';

/** Keep at most this many rows on disk; older rows are trimmed after each insert. */
const MAX_ROWS = 1000;

/** Shape of a `logs` row as returned by expo-sqlite. */
type LogRow = {
  ts: string;
  cat: string;
  msg: string;
  details: string | null;
};

/**
 * Durable log sink backed by a synchronous SQLite connection. Construct once at
 * startup via {@link openLogStore} and hand it to `debugLog.setSink(...)`.
 */
export class SQLiteLogStore implements LogSink {
  private readonly db: SQLite.SQLiteDatabase;

  private constructor(db: SQLite.SQLiteDatabase) {
    this.db = db;
  }

  /**
   * Open `logs.db` synchronously and create the `logs` table if needed.
   * Throws if the native SQLite module is unavailable (caller should guard).
   */
  static open(): SQLiteLogStore {
    const db = SQLite.openDatabaseSync(DB_NAME);
    db.execSync(
      `CREATE TABLE IF NOT EXISTS logs (
         id      INTEGER PRIMARY KEY AUTOINCREMENT,
         ts      TEXT,
         cat     TEXT,
         msg     TEXT,
         details TEXT
       );`,
    );
    return new SQLiteLogStore(db);
  }

  /** Insert one entry synchronously, then trim to the newest {@link MAX_ROWS}. */
  append(entry: LogEntry): void {
    const details = entry.details && Object.keys(entry.details).length > 0 ? JSON.stringify(entry.details) : null;
    this.db.runSync('INSERT INTO logs (ts, cat, msg, details) VALUES (?, ?, ?, ?)', entry.ts, entry.cat, entry.msg, details);
    // Cheap trim: drop everything older than the newest MAX_ROWS ids. No-op once
    // the table is at steady state (the subquery is a single indexed lookup).
    this.db.runSync('DELETE FROM logs WHERE id <= (SELECT MAX(id) FROM logs) - ?', MAX_ROWS);
  }

  /** All retained entries, newest first. */
  readAll(): LogEntry[] {
    const rows = this.db.getAllSync<LogRow>('SELECT ts, cat, msg, details FROM logs ORDER BY id DESC');
    return rows.map(rowToEntry);
  }

  /** Delete every persisted entry. Idempotent. */
  clear(): void {
    this.db.runSync('DELETE FROM logs');
  }
}

/** Decode a persisted row back into a {@link LogEntry}, tolerating bad JSON. */
function rowToEntry(row: LogRow): LogEntry {
  const entry: LogEntry = { ts: row.ts, cat: row.cat, msg: row.msg };
  if (row.details) {
    try {
      const parsed = JSON.parse(row.details) as LogDetails;
      if (parsed && typeof parsed === 'object') entry.details = parsed;
    } catch {
      // Corrupt payload: keep the entry, drop the unreadable details.
    }
  }
  return entry;
}
