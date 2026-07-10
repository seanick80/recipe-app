import { TABS } from './tabs';

describe('tab configuration', () => {
  it('has exactly five tabs', () => {
    expect(TABS).toHaveLength(5);
  });

  it('matches the tab set (Recipes, Shopping, Scan, Lists, Settings)', () => {
    expect(TABS.map((t) => t.name)).toEqual([
      'Recipes',
      'Shopping',
      'Scan',
      'Lists',
      'Settings',
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
