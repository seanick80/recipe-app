import styles from "./IngredientRow.module.css";

interface IngredientData {
  name: string;
  quantity: number;
  unit: string;
  category: string;
  display_order: number;
  notes: string;
}

interface IngredientRowProps {
  ingredient: IngredientData;
  index: number;
  onChange: (index: number, field: keyof IngredientData, value: string | number) => void;
  onRemove: (index: number) => void;
}

const CATEGORIES = [
  "Produce",
  "Meat",
  "Dairy",
  "Pantry",
  "Spices",
  "Frozen",
  "Bakery",
  "Beverages",
  "Other",
];

export function IngredientRow({
  ingredient,
  index,
  onChange,
  onRemove,
}: IngredientRowProps) {
  return (
    <div className={styles.row}>
      <input
        type="number"
        className={styles.qty}
        placeholder="Qty"
        value={ingredient.quantity || ""}
        onChange={(e) =>
          onChange(index, "quantity", parseFloat(e.target.value) || 0)
        }
      />
      <input
        type="text"
        className={styles.unit}
        placeholder="Unit"
        value={ingredient.unit}
        onChange={(e) => onChange(index, "unit", e.target.value)}
      />
      <input
        type="text"
        className={styles.name}
        placeholder="Ingredient name"
        value={ingredient.name}
        onChange={(e) => onChange(index, "name", e.target.value)}
      />
      <select
        className={styles.category}
        value={ingredient.category}
        onChange={(e) => onChange(index, "category", e.target.value)}
      >
        <option value="">Category</option>
        {CATEGORIES.map((cat) => (
          <option key={cat} value={cat}>
            {cat}
          </option>
        ))}
      </select>
      <input
        type="text"
        className={styles.notes}
        placeholder="Notes"
        value={ingredient.notes}
        onChange={(e) => onChange(index, "notes", e.target.value)}
      />
      <button
        type="button"
        className={styles.removeBtn}
        onClick={() => onRemove(index)}
        aria-label="Remove ingredient"
      >
        X
      </button>
    </div>
  );
}
