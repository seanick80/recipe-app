/** Mirror of `TestFixtures/TestPrepNoteStripper.swift`. */
import { stripPrepNotes } from './prepNoteStripper';

describe('stripPrepNotes', () => {
  it('strips a basic comma prep', () => {
    const r = stripPrepNotes('Onion, Finely Chopped');
    expect(r.name).toBe('Onion');
    expect(r.prep).toBe('finely chopped');
  });

  it('handles multiple comma preps', () => {
    const r = stripPrepNotes('Zucchini, Grated, Excess Moisture Squeezed Out');
    expect(r.name).toBe('Zucchini');
    expect(r.prep).toContain('grated');
  });

  it('leaves a clean name unchanged', () => {
    const r = stripPrepNotes('Chicken Breast');
    expect(r.name).toBe('Chicken Breast');
    expect(r.prep).toBe('');
  });

  it('strips a leading size adjective', () => {
    const r = stripPrepNotes('Large Onion, Finely Chopped');
    expect(r.name).toBe('Onion');
    expect(r.sizeAdjective).toBe('large');
  });

  it('leaves a bare size word alone', () => {
    const r = stripPrepNotes('Large');
    expect(r.name).toBe('Large');
  });

  it('strips a parenthesized quantity prefix', () => {
    const r = stripPrepNotes('(1 Cup) White Self Raising Flour, Sifted');
    expect(r.name).toBe('White Self Raising Flour');
    expect(r.prep).toBe('sifted');
  });

  it('returns empty for empty input', () => {
    expect(stripPrepNotes('').name).toBe('');
  });

  it('strips a multi-word phrase (room temperature)', () => {
    const r = stripPrepNotes('Butter, At Room Temperature');
    expect(r.name).toBe('Butter');
    expect(r.prep).toContain('at room temperature');
  });
});
