import { TABS } from './tabs';

describe('Phase 0 tab configuration', () => {
  it('has exactly four tabs', () => {
    expect(TABS).toHaveLength(4);
  });

  it('matches the Phase 0 tab set (Recipes, Shopping, Scan, Lists)', () => {
    expect(TABS.map((t) => t.name)).toEqual([
      'Recipes',
      'Shopping',
      'Scan',
      'Lists',
    ]);
  });

  it('drops the Pantry tab (out of scope for the RN app)', () => {
    expect(TABS.some((t) => t.name === 'Pantry')).toBe(false);
  });

  it('gives every tab a distinct home route and icon', () => {
    expect(new Set(TABS.map((t) => t.home)).size).toBe(TABS.length);
    expect(TABS.every((t) => t.icon.length > 0)).toBe(true);
  });
});
