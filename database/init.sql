CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TABLE recipes (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    summary TEXT DEFAULT '',
    instructions TEXT DEFAULT '',
    prep_time_minutes INTEGER DEFAULT 0,
    cook_time_minutes INTEGER DEFAULT 0,
    servings INTEGER DEFAULT 1,
    cuisine TEXT DEFAULT '',
    course TEXT DEFAULT '',
    tags TEXT DEFAULT '',
    source_url TEXT DEFAULT '',
    difficulty TEXT DEFAULT '',
    is_favorite BOOLEAN DEFAULT FALSE,
    is_published BOOLEAN DEFAULT FALSE,
    image_data BYTEA,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE ingredients (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    quantity FLOAT DEFAULT 0,
    unit TEXT DEFAULT '',
    category TEXT DEFAULT 'Other',
    display_order INTEGER DEFAULT 0,
    notes TEXT DEFAULT '',
    recipe_id UUID NOT NULL REFERENCES recipes(id) ON DELETE CASCADE
);

CREATE TABLE grocery_lists (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    archived_at TIMESTAMP WITH TIME ZONE
);

CREATE TABLE grocery_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    quantity FLOAT DEFAULT 1.0,
    unit TEXT DEFAULT '',
    category TEXT DEFAULT 'Other',
    is_checked BOOLEAN DEFAULT FALSE,
    source_recipe_name TEXT DEFAULT '',
    source_recipe_id TEXT DEFAULT '',
    grocery_list_id UUID NOT NULL REFERENCES grocery_lists(id) ON DELETE CASCADE
);

CREATE TABLE shopping_templates (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    sort_order INTEGER DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE template_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    quantity FLOAT DEFAULT 0,
    unit TEXT DEFAULT '',
    category TEXT DEFAULT 'Other',
    sort_order INTEGER DEFAULT 0,
    template_id UUID NOT NULL REFERENCES shopping_templates(id) ON DELETE CASCADE
);

CREATE TABLE allowed_users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email TEXT NOT NULL UNIQUE,
    name TEXT DEFAULT '',
    role TEXT DEFAULT 'editor',
    invited_by TEXT DEFAULT '',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_ingredients_recipe ON ingredients(recipe_id);
CREATE INDEX idx_grocery_items_list ON grocery_items(grocery_list_id);
CREATE INDEX idx_template_items_template ON template_items(template_id);

INSERT INTO allowed_users (email, name, role, invited_by)
VALUES ('seanickharlson@gmail.com', 'Nick', 'admin', 'system');
