INSERT INTO recipes (name, summary, instructions, prep_time_minutes, cook_time_minutes, servings) VALUES
('Spaghetti Bolognese', 'Classic Italian meat sauce with pasta', 'Brown the ground beef. Add onion, garlic, and tomatoes. Simmer 20 minutes. Cook pasta. Serve sauce over pasta.', 15, 30, 4),
('Chicken Stir Fry', 'Quick and healthy weeknight dinner', 'Slice chicken and vegetables. Heat oil in wok. Cook chicken first, then add vegetables. Add soy sauce and serve over rice.', 20, 15, 2),
('Caesar Salad', 'Crispy romaine with creamy dressing', 'Wash and chop romaine. Make dressing with anchovy, garlic, lemon, egg yolk, and oil. Toss with croutons and parmesan.', 15, 0, 2);

-- Ingredients for Spaghetti Bolognese
INSERT INTO ingredients (name, quantity, unit, recipe_id)
SELECT 'Spaghetti', '1', 'lb', id FROM recipes WHERE name = 'Spaghetti Bolognese';
INSERT INTO ingredients (name, quantity, unit, recipe_id)
SELECT 'Ground Beef', '1', 'lb', id FROM recipes WHERE name = 'Spaghetti Bolognese';
INSERT INTO ingredients (name, quantity, unit, recipe_id)
SELECT 'Tomato Sauce', '2', 'cups', id FROM recipes WHERE name = 'Spaghetti Bolognese';
INSERT INTO ingredients (name, quantity, unit, recipe_id)
SELECT 'Onion', '1', '', id FROM recipes WHERE name = 'Spaghetti Bolognese';

-- Ingredients for Chicken Stir Fry
INSERT INTO ingredients (name, quantity, unit, recipe_id)
SELECT 'Chicken Breast', '1', 'lb', id FROM recipes WHERE name = 'Chicken Stir Fry';
INSERT INTO ingredients (name, quantity, unit, recipe_id)
SELECT 'Soy Sauce', '3', 'tbsp', id FROM recipes WHERE name = 'Chicken Stir Fry';
INSERT INTO ingredients (name, quantity, unit, recipe_id)
SELECT 'Mixed Vegetables', '2', 'cups', id FROM recipes WHERE name = 'Chicken Stir Fry';

-- Sample grocery list
INSERT INTO grocery_lists (name) VALUES ('This Week');
INSERT INTO grocery_items (name, quantity, unit, category, grocery_list_id)
SELECT 'Whole Milk', 1, 'gallon', 'Dairy', id FROM grocery_lists WHERE name = 'This Week';
INSERT INTO grocery_items (name, quantity, unit, category, grocery_list_id)
SELECT 'Eggs', 12, '', 'Dairy', id FROM grocery_lists WHERE name = 'This Week';
INSERT INTO grocery_items (name, quantity, unit, category, grocery_list_id)
SELECT 'Chicken Breast', 2, 'lbs', 'Meat', id FROM grocery_lists WHERE name = 'This Week';
INSERT INTO grocery_items (name, quantity, unit, category, grocery_list_id)
SELECT 'Broccoli', 1, 'bunch', 'Produce', id FROM grocery_lists WHERE name = 'This Week';
