import { DebugLog } from './debugLog';

// Mirrors TestFixtures/TestDebugLog.swift. The Swift original is file-backed
// with byte-size rotation; this port is an in-memory ring buffer bounded by
// entry count, so the rotation test asserts the entry-count cap instead.

describe('DebugLog', () => {
  it('writes and reads back entries as JSONL', () => {
    const log = new DebugLog();
    log.log('ocr.vision', 'first scan', { lines: '4' });
    log.log('b', 'two');
    log.log('c', 'three');

    const content = log.readActive();
    expect(content).toContain('"cat":"ocr.vision"');
    expect(content).toContain('"lines":"4"');

    const lines = content.split('\n').filter((l) => l.length > 0);
    expect(lines).toHaveLength(3);
  });

  it('drops oldest entries past the capacity', () => {
    const log = new DebugLog(5);
    for (let i = 0; i < 20; i++) {
      log.log('spam', `entry ${i}`);
    }
    expect(log.entries()).toHaveLength(5);
    // Only the most recent 5 survive (entries 15..19).
    expect(log.readActive()).toContain('"msg":"entry 19"');
    expect(log.readActive()).not.toContain('"msg":"entry 0"');
  });

  it('clears all entries', () => {
    const log = new DebugLog();
    for (let i = 0; i < 15; i++) {
      log.log('x', `message number ${i} goes here`);
    }
    log.clear();
    expect(log.readActive()).toBe('');
    expect(log.entries()).toHaveLength(0);
  });

  it('tails the most recent lines', () => {
    const log = new DebugLog();
    for (let i = 0; i < 10; i++) {
      log.log('n', `line ${i}`);
    }
    const last3 = log.tail(3);
    expect(last3).toHaveLength(3);
    expect(last3[2]).toContain('"msg":"line 9"');
  });

  it('encodes categories and details, omitting empty details', () => {
    const line = DebugLog.encode({
      ts: '1970-01-01T00:00:00.000Z',
      cat: 'ocr.blocks',
      msg: 'block 1',
      details: { label: 'ingredients' },
    });
    expect(line).toContain('"cat":"ocr.blocks"');
    expect(line).toContain('"label":"ingredients"');

    const noDetails = DebugLog.encode({ ts: '1970-01-01T00:00:00.000Z', cat: 'x', msg: 'no details' });
    expect(noDetails).not.toContain('"details"');
  });

  it('emits keys in sorted order', () => {
    const line = DebugLog.encode({
      ts: '1970-01-01T00:00:00.000Z',
      cat: 'a',
      msg: 'm',
      details: { z: '1', a: '2' },
    });
    expect(line).toBe('{"cat":"a","details":{"a":"2","z":"1"},"msg":"m","ts":"1970-01-01T00:00:00.000Z"}');
  });
});
