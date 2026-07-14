/**
 * Startup wiring that makes {@link debugLog} durable for crash forensics.
 *
 * Call {@link initDebugLogPersistence} once, as early as possible in `App.tsx`,
 * before the app renders meaningfully. It:
 *   1. opens the durable SQLite sink (`logs.db`),
 *   2. hydrates the in-memory buffer with pre-crash entries so the viewer shows
 *      them across launches,
 *   3. installs the sink so new entries persist synchronously, and
 *   4. installs a global JS error handler that records an `app.fatal` entry
 *      before the previous handler runs.
 *
 * NOTE: native (non-JS) crashes do NOT route through `ErrorUtils` — they kill
 * the process before any JS runs. That's precisely why durable breadcrumbs
 * matter: even when the fatal cause can't be captured, the persisted trail of
 * what the app was doing right before the crash survives.
 */
import { debugLog } from './debugLog';
import { SQLiteLogStore } from './logStore';

/** Global error hook exposed by the RN runtime (not in the TS lib defs). */
type GlobalErrorHandler = (error: unknown, isFatal?: boolean) => void;
interface ErrorUtilsShape {
  getGlobalHandler?: () => GlobalErrorHandler;
  setGlobalHandler?: (handler: GlobalErrorHandler) => void;
}

let initialized = false;

/** Idempotent. Safe to call more than once (e.g. across hot reloads). */
export function initDebugLogPersistence(): void {
  if (initialized) return;
  initialized = true;

  let store: SQLiteLogStore | null = null;
  try {
    store = SQLiteLogStore.open();
  } catch (err) {
    // No native SQLite (e.g. some test/web contexts): stay in-memory only.
    debugLog.log('app.log', 'durable log sink unavailable; in-memory only', {
      error: String(err),
    });
    return;
  }

  // 1 + 2: load persisted entries (newest-first) back into the buffer oldest-first.
  try {
    debugLog.hydrate(store.readAll().reverse());
  } catch {
    // A read failure shouldn't block installing the sink for new entries.
  }

  // 3: from here on, every log() writes through to disk synchronously.
  debugLog.setSink(store);
  debugLog.log('app.log', 'durable log persistence initialized');

  // 4: capture JS-level fatals before the process dies.
  installGlobalErrorHandler();
}

function installGlobalErrorHandler(): void {
  const errorUtils = (globalThis as { ErrorUtils?: ErrorUtilsShape }).ErrorUtils;
  if (!errorUtils?.setGlobalHandler) return;

  const previous = errorUtils.getGlobalHandler?.();
  errorUtils.setGlobalHandler((error, isFatal) => {
    try {
      const e = error as { message?: string; stack?: string } | undefined;
      // Synchronous write (sink uses runSync) — persisted before the handler chain
      // continues and the process potentially tears down.
      debugLog.log('app.fatal', e?.message ? String(e.message) : String(error), {
        isFatal: String(Boolean(isFatal)),
        stack: e?.stack ? String(e.stack) : '',
      });
    } catch {
      // Best-effort: never mask the original error.
    }
    previous?.(error, isFatal);
  });

  // Best-effort unhandled-promise-rejection breadcrumb, when the runtime exposes it.
  const tracker = (globalThis as { HermesInternal?: { hasPromise?: () => boolean } }).HermesInternal;
  const rejectionHost = globalThis as {
    addEventListener?: (type: string, cb: (ev: unknown) => void) => void;
  };
  if (tracker && typeof rejectionHost.addEventListener === 'function') {
    rejectionHost.addEventListener('unhandledrejection', (ev: unknown) => {
      const reason = (ev as { reason?: unknown })?.reason ?? ev;
      const r = reason as { message?: string; stack?: string } | undefined;
      try {
        debugLog.log('app.rejection', r?.message ? String(r.message) : String(reason), {
          stack: r?.stack ? String(r.stack) : '',
        });
      } catch {
        // Ignore.
      }
    });
  }
}
