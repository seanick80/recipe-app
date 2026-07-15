import { TABS } from './tabs';

describe('tab configuration', () => {
  it('has exactly four tabs', () => {
    expect(TABS).toHaveLength(4);
  });

  it('matches the tab set (Recipes, Shopping, Scan, Settings)', () => {
    expect(TABS.map((t) => t.name)).toEqual([
      'Recipes',
      'Shopping',
      'Scan',
      'Settings',
    ]);
  });

  it('drops the separate Lists tab (folded into Shopping)', () => {
    expect(TABS.some((t) => t.name === 'Lists')).toBe(false);
  });

  it('drops the Pantry tab (out of scope for the RN app)', () => {
    expect(TABS.some((t) => t.name === 'Pantry')).toBe(false);
  });

  it('gives every tab a distinct home route and icon', () => {
    expect(new Set(TABS.map((t) => t.home)).size).toBe(TABS.length);
    expect(TABS.every((t) => t.icon.length > 0)).toBe(true);
  });
});
