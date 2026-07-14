/**
 * On-device debug log with a bounded in-memory ring buffer.
 *
 * Each entry is a compact JSON object: `{"cat":"...","msg":"...","ts":"..."}`
 * (plus an optional `"details"` object), matching the JSONL wire shape the
 * SwiftUI app writes. Keys are emitted in sorted order so lines are stable and
 * diff-friendly. `readActive()` returns the buffer as newline-delimited JSON;
 * `tail(n)` returns the most recent `n` lines.
 *
 * When the buffer exceeds `maxEntries`, the oldest entries are dropped so the
 * footprint stays bounded (the SwiftUI original bounds by byte size on disk;
 * this port bounds by entry count in memory).
 *
 * Adapted from `SharedLogic/DebugLog.swift` (framework-free). This is NOT a pure
 * 1:1 port: the Swift original persists to a file on disk and rotates by byte
 * size, whereas this React Native port keeps the same JSONL entry shape and the
 * `log`/`clear`/`readActive`/`tail`/`encode` API but backs it with an in-memory
 * ring buffer (bounded by entry count) — so it needs no filesystem access and is
 * trivially testable.
 */

/** Optional key/value payload attached to a log entry. Values are strings. */
export type LogDetails = Record<string, string>;

/**
 * A durable back-end for the log. When one is installed via
 * {@link DebugLog.setSink}, every `log()` call also writes through to it so
 * entries survive a crash/restart. With NO sink the log is purely in-memory
 * (the shape unit tests rely on). See `logStore.ts` for the SQLite sink.
 */
export interface LogSink {
  /** Persist a single entry. Should be synchronous for crash durability. */
  append(entry: LogEntry): void;
  /** All persisted entries, newest first. */
  readAll(): LogEntry[];
  /** Delete every persisted entry. */
  clear(): void;
}

/** One structured log entry. Mirrors the SwiftUI JSONL object shape. */
export interface LogEntry {
  /** ISO-8601 timestamp with fractional seconds (e.g. `2026-07-14T12:34:56.789Z`). */
  ts: string;
  /** Short dotted tag like `sync.run` or `api.error`. */
  cat: string;
  /** Human-readable summary. */
  msg: string;
  /** Optional key/value payload; omitted from the wire form when empty. */
  details?: LogDetails;
}

/** Default cap on retained entries before the oldest are dropped. */
const DEFAULT_MAX_ENTRIES = 2000;

export class DebugLog {
  private readonly maxEntries: number;
  private buffer: LogEntry[] = [];
  private sink: LogSink | null = null;

  /**
   * @param maxEntries Ring-buffer capacity. Once exceeded, the oldest entries
   *   are dropped. Clamped to a minimum of 1.
   */
  constructor(maxEntries: number = DEFAULT_MAX_ENTRIES) {
    this.maxEntries = Math.max(1, maxEntries);
  }

  /**
   * Install (or remove, with `null`) a durable sink. Once set, every `log()`
   * also writes through to the sink, and `clear()` clears it too. Sink write
   * failures are swallowed so a broken sink can never take down the app.
   */
  setSink(sink: LogSink | null): void {
    this.sink = sink;
  }

  /**
   * Replace the in-memory buffer with `entries` (oldest first), trimmed to
   * capacity. Used at startup to load pre-crash entries back from the sink so
   * the viewer shows them. Does not write back to the sink.
   */
  hydrate(entries: LogEntry[]): void {
    this.buffer = entries.slice(Math.max(0, entries.length - this.maxEntries));
  }

  /**
   * Entries for display, newest first. Prefers the durable sink (survives
   * launches) and falls back to the in-memory buffer when none is installed.
   */
  readPersisted(): LogEntry[] {
    if (this.sink) {
      try {
        return this.sink.readAll();
      } catch {
        // Fall through to the buffer if the sink read fails.
      }
    }
    return this.buffer.slice().reverse();
  }

  /**
   * Records a debug event.
   *
   * @param category Short dotted tag like `sync.run` or `api.error`.
   * @param message Human-readable summary.
   * @param details Optional key/value payload; empty is omitted.
   */
  log(category: string, message: string, details: LogDetails = {}): void {
    const entry: LogEntry = {
      ts: new Date().toISOString(),
      cat: category,
      msg: message,
    };
    if (Object.keys(details).length > 0) {
      entry.details = { ...details };
    }
    this.buffer.push(entry);
    if (this.buffer.length > this.maxEntries) {
      this.buffer.splice(0, this.buffer.length - this.maxEntries);
    }
    if (this.sink) {
      try {
        this.sink.append(entry);
      } catch {
        // Never let a persistence failure crash the caller.
      }
    }
  }

  /** Drops every retained entry, in memory and in the durable sink. Idempotent. */
  clear(): void {
    this.buffer = [];
    if (this.sink) {
      try {
        this.sink.clear();
      } catch {
        // Ignore — the in-memory buffer is cleared regardless.
      }
    }
  }

  /** The retained entries, oldest first. Returns a defensive copy. */
  entries(): LogEntry[] {
    return this.buffer.slice();
  }

  /**
   * The full buffer as newline-delimited JSON (one entry per line, oldest
   * first). Empty string when nothing has been logged.
   */
  readActive(): string {
    return this.buffer.map((e) => DebugLog.encode(e)).join('\n');
  }

  /** The last `n` encoded lines, oldest first. */
  tail(n: number): string[] {
    const start = Math.max(0, this.buffer.length - n);
    return this.buffer.slice(start).map((e) => DebugLog.encode(e));
  }

  /**
   * Builds one JSONL line for the given entry with keys in sorted order
   * (`cat`, `details`, `msg`, `ts`). Nested `details` keys are also sorted, and
   * `details` is omitted when empty.
   */
  static encode(entry: LogEntry): string {
    const out: Record<string, unknown> = {};
    out.cat = entry.cat;
    if (entry.details && Object.keys(entry.details).length > 0) {
      const sortedDetails: LogDetails = {};
      for (const key of Object.keys(entry.details).sort()) {
        sortedDetails[key] = entry.details[key];
      }
      out.details = sortedDetails;
    }
    out.msg = entry.msg;
    out.ts = entry.ts;
    return JSON.stringify(out);
  }
}

/**
 * Process-wide shared log used by the app (sync, auth, API). The Logs screen in
 * Settings reads from this instance.
 */
export const debugLog = new DebugLog();
