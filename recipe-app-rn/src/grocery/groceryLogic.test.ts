import {
  allItemsChecked,
  CATEGORY_ORDER,
  categorySortIndex,
  generateFromRecipes,
  groupByCategory,
  makeGroceryItem,
  mergeInto,
  planListMerge,
  staplesToAdd,
} from './groceryLogic';
import type { GenerateRecipe, GroceryItem, TemplateItem } from './types';

function idGen(): () => string {
  let n = 0;
  return () => `id-${(n += 1)}`;
}

function item(over: Partial<GroceryItem> = {}): GroceryItem {
  return {
    id: 'x',
    name: 'thing',
    quantity: 1,
    unit: '',
    category: 'Other',
    isChecked: false,
    sourceRecipeName: '',
    sourceRecipeId: '',
    ...over,
  };
}

describe('allItemsChecked', () => {
  it('is false for an empty list (so the action stays "Check all")', () => {
    expect(allItemsChecked([])).toBe(false);
  });
  it('is false when any item is unchecked', () => {
    expect(allItemsChecked([item({ isChecked: true }), item({ isChecked: false })])).toBe(false);
  });
  it('is true only when every item is checked', () => {
    expect(allItemsChecked([item({ isChecked: true }), item({ isChecked: true })])).toBe(true);
  });
});

describe('categorySortIndex', () => {
  it('orders known categories by CATEGORY_ORDER', () => {
    expect(categorySortIndex('Produce')).toBe(0);
    expect(categorySortIndex('Other')).toBe(CATEGORY_ORDER.length - 1);
  });
  it('sorts unknown categories last', () => {
    expect(categorySortIndex('Nonsense')).toBe(CATEGORY_ORDER.length);
  });
});

describe('groupByCategory', () => {
  it('orders sections by aisle and sorts unchecked-first then name within a section', () => {
    const items = [
      item({ id: '1', name: 'Zucchini', category: 'Produce', isChecked: true }),
      item({ id: '2', name: 'Apple', category: 'Produce' }),
      item({ id: '3', name: 'Milk', category: 'Dairy' }),
      item({ id: '4', name: 'Banana', category: 'Produce' }),
    ];
    const sections = groupByCategory(items);
    expect(sections.map((s) => s.category)).toEqual(['Produce', 'Dairy']);
    // unchecked (Apple, Banana) alphabetical, then checked (Zucchini) last
    expect(sections[0].items.map((i) => i.name)).toEqual(['Apple', 'Banana', 'Zucchini']);
  });
});

describe('makeGroceryItem', () => {
  it('auto-assigns a category from the classifier', () => {
    const it = makeGroceryItem('id-1', 'banana', 2, 'each');
    expect(it.category).toBe('Produce');
    expect(it.isChecked).toBe(false);
  });
});

describe('staplesToAdd', () => {
  it('adds only staples not already on the list (name-only dedup)', () => {
    const existing = [item({ name: 'Milk' })];
    const template: TemplateItem[] = [
      { id: 't1', name: 'Milk', quantity: 1, unit: 'gal', category: 'Dairy', sortOrder: 0 },
      { id: 't2', name: 'Eggs', quantity: 12, unit: '', category: 'Dairy', sortOrder: 1 },
    ];
    const added = staplesToAdd(existing, template, idGen());
    expect(added.map((i) => i.name)).toEqual(['Eggs']);
    expect(added[0].id).toBe('id-1');
  });
});

describe('mergeInto', () => {
  it('sums matching name|unit and forces unchecked when an incoming dup is unchecked', () => {
    const target = [item({ id: 'a', name: 'Rice', unit: 'kg', quantity: 1, isChecked: true })];
    const source = [item({ id: 'b', name: 'rice', unit: 'KG', quantity: 2, isChecked: false })];
    const merged = mergeInto(target, [source], idGen());
    expect(merged).toHaveLength(1);
    expect(merged[0].quantity).toBe(3);
    expect(merged[0].isChecked).toBe(false);
  });
  it('clones a new key with a fresh id', () => {
    const merged = mergeInto([item({ id: 'a', name: 'Rice' })], [[item({ name: 'Beans' })]], idGen());
    expect(merged.map((i) => i.name).sort()).toEqual(['Beans', 'Rice']);
    expect(merged.find((i) => i.name === 'Beans')?.id).toBe('id-1');
  });
});

describe('generateFromRecipes', () => {
  const recipes: GenerateRecipe[] = [
    {
      id: 'r1',
      name: 'Soup',
      ingredients: [
        { name: 'Large Onion, Finely Chopped', quantity: 1, unit: '', category: '' },
        { name: 'Carrot', quantity: 2, unit: '', category: '' },
      ],
    },
    {
      id: 'r2',
      name: 'Stew',
      ingredients: [{ name: 'onion', quantity: 3, unit: '', category: '' }],
    },
  ];

  it('strips prep, consolidates across recipes, categorizes, and titles new items', () => {
    const result = generateFromRecipes(recipes, [], idGen());
    const onion = result.find((i) => i.name === 'Onion')!;
    expect(onion).toBeTruthy();
    expect(onion.quantity).toBe(4); // 1 (Soup) + 3 (Stew), units match ('')
    expect(onion.category).toBe('Produce');
    expect(onion.sourceRecipeName).toBe('Soup, Stew');
    expect(result.map((i) => i.name).sort()).toEqual(['Carrot', 'Onion']);
  });

  it('merges into existing list items by name|unit, summing + unioning provenance', () => {
    const existing = [item({ id: 'e', name: 'Onion', unit: '', quantity: 5, sourceRecipeName: 'Curry' })];
    const result = generateFromRecipes(recipes, existing, idGen());
    const onion = result.find((i) => i.id === 'e')!;
    expect(onion.quantity).toBe(9); // 5 existing + 4 generated
    expect(onion.sourceRecipeName).toBe('Curry, Soup, Stew');
  });

  it('does not sum quantities when units differ', () => {
    const rs: GenerateRecipe[] = [
      { id: 'r1', name: 'A', ingredients: [{ name: 'flour', quantity: 1, unit: 'cup', category: '' }] },
      { id: 'r2', name: 'B', ingredients: [{ name: 'flour', quantity: 200, unit: 'g', category: '' }] },
    ];
    const result = generateFromRecipes(rs, [], idGen());
    const flour = result.find((i) => i.name.toLowerCase() === 'flour')!;
    expect(flour.quantity).toBe(1); // second (g) not summed into first (cup)
  });
});

describe('planListMerge', () => {
  it('returns null when fewer than two lists are selected', () => {
    expect(planListMerge(['a', 'b', 'c'], new Set())).toBeNull();
    expect(planListMerge(['a', 'b', 'c'], new Set(['b']))).toBeNull();
  });

  it('targets the first selected list in display order, rest are sources', () => {
    expect(planListMerge(['a', 'b', 'c'], new Set(['b', 'c']))).toEqual({
      targetId: 'b',
      sourceIds: ['c'],
    });
    expect(planListMerge(['a', 'b', 'c'], new Set(['a', 'b', 'c']))).toEqual({
      targetId: 'a',
      sourceIds: ['b', 'c'],
    });
  });

  it('ignores selected ids not present in the ordered list', () => {
    expect(planListMerge(['a', 'b'], new Set(['a', 'b', 'ghost']))).toEqual({
      targetId: 'a',
      sourceIds: ['b'],
    });
    // Only one real id present → not enough to merge.
    expect(planListMerge(['a', 'b'], new Set(['a', 'ghost']))).toBeNull();
  });
});
