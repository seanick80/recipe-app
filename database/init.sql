CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TABLE recipes (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(255) NOT NULL,
    summary TEXT DEFAULT '',
    instructions TEXT DEFAULT '',
    prep_time_minutes INTEGER DEFAULT 0,
    cook_time_minutes INTEGER DEFAULT 0,
    servings INTEGER DEFAULT 1,
    image_data BYTEA,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE ingredients (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(255) NOT NULL,
    quantity VARCHAR(50) DEFAULT '0',
    unit VARCHAR(50) DEFAULT '',
    recipe_id UUID NOT NULL REFERENCES recipes(id) ON DELETE CASCADE
);

CREATE TABLE grocery_lists (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(255) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE grocery_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(255) NOT NULL,
    quantity FLOAT DEFAULT 1.0,
    unit VARCHAR(50) DEFAULT '',
    category VARCHAR(100) DEFAULT 'Other',
    is_checked BOOLEAN DEFAULT FALSE,
    grocery_list_id UUID NOT NULL REFERENCES grocery_lists(id) ON DELETE CASCADE
);

CREATE INDEX idx_ingredients_recipe ON ingredients(recipe_id);
CREATE INDEX idx_grocery_items_list ON grocery_items(grocery_list_id);
