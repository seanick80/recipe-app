"""Validate all code surfaces against schema/canonical.yaml.

Runnable standalone or via pytest:
    python scripts/test_schema_sync.py
    pytest scripts/test_schema_sync.py
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).resolve().parent.parent


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def camel_to_snake(name: str) -> str:
    """Convert camelCase to snake_case, handling consecutive caps like URL."""
    # Handle special all-caps suffixes (sourceURL -> source_url)
    name = re.sub(r"([a-z])([A-Z]{2,})$", lambda m: m.group(1) + "_" + m.group(2).lower(), name)
    # Handle remaining camelCase transitions
    name = re.sub(r"([a-z0-9])([A-Z])", r"\1_\2", name)
    return name.lower()


def load_canonical() -> dict:
    """Load and return the canonical schema."""
    path = REPO_ROOT / "schema" / "canonical.yaml"
    with open(path, encoding="utf-8") as f:
        return yaml.safe_load(f)


# ---------------------------------------------------------------------------
# Parsers — each returns {model_name: set_of_field_names}
# ---------------------------------------------------------------------------

def parse_sql() -> dict[str, set[str]]:
    """Parse database/init.sql for column names per table."""
    path = REPO_ROOT / "database" / "init.sql"
    content = path.read_text(encoding="utf-8")

    table_map = {
        "recipes": "Recipe",
        "ingredients": "Ingredient",
        "grocery_lists": "GroceryList",
        "grocery_items": "GroceryItem",
        "shopping_templates": "ShoppingTemplate",
        "template_items": "TemplateItem",
    }

    result: dict[str, set[str]] = {}
    for match in re.finditer(
        r"CREATE TABLE (\w+)\s*\((.*?)\);", content, re.DOTALL
    ):
        table_name = match.group(1)
        if table_name not in table_map:
            continue
        model_name = table_map[table_name]
        body = match.group(2)
        fields: set[str] = set()
        for line in body.split("\n"):
            line = line.strip().rstrip(",")
            if not line or line.startswith("--"):
                continue
            # Skip constraints
            col_match = re.match(r"(\w+)\s+", line)
            if not col_match:
                continue
            col = col_match.group(1).lower()
            if col in ("primary", "foreign", "unique", "check", "constraint"):
                continue
            # Skip FK columns (those with REFERENCES)
            if "REFERENCES" in line.upper():
                continue
            fields.add(col)
        result[model_name] = fields
    return result


def parse_sqlalchemy() -> dict[str, set[str]]:
    """Parse SQLAlchemy model files for Column and relationship declarations."""
    files = [
        REPO_ROOT / "server" / "models" / "recipe.py",
        REPO_ROOT / "server" / "models" / "grocery.py",
    ]
    result: dict[str, set[str]] = {}
    class_re = re.compile(r"^class (\w+)\(Base\):")
    col_re = re.compile(r"^\s+(\w+)\s*=\s*Column\(")
    rel_re = re.compile(r"^\s+(\w+)\s*=\s*relationship\(")

    for path in files:
        content = path.read_text(encoding="utf-8")
        current_class = None
        for line in content.split("\n"):
            cm = class_re.match(line)
            if cm:
                current_class = cm.group(1)
                result.setdefault(current_class, set())
                continue
            if current_class is None:
                continue
            # Column
            col_m = col_re.match(line)
            if col_m:
                col_name = col_m.group(1)
                # Skip FK columns (name ends with _id and has ForeignKey)
                if col_name.endswith("_id") and "ForeignKey" in line:
                    continue
                result[current_class].add(col_name)
                continue
            # Relationship
            rel_m = rel_re.match(line)
            if rel_m:
                rel_name = rel_m.group(1)
                # Skip back-references (back_populates but singular names)
                if "back_populates" in line:
                    # Collection relationships are plural (ingredients, items)
                    # Back-refs are singular (recipe, grocery_list, template)
                    if rel_name in ("recipe", "grocery_list", "template"):
                        continue
                result[current_class].add(rel_name)
    return result


def parse_pydantic() -> dict[str, set[str]]:
    """Parse Pydantic Response models for field names."""
    files = [
        REPO_ROOT / "server" / "schemas" / "recipe.py",
        REPO_ROOT / "server" / "schemas" / "grocery.py",
    ]
    result: dict[str, set[str]] = {}
    # Only match *Response classes
    class_re = re.compile(r"^class (\w+Response)\(")
    field_re = re.compile(r"^\s+(\w+)\s*:")

    # Map response class names to canonical model names
    name_map = {
        "RecipeResponse": "Recipe",
        "IngredientResponse": "Ingredient",
        "GroceryItemResponse": "GroceryItem",
        "GroceryListResponse": "GroceryList",
        "ShoppingTemplateResponse": "ShoppingTemplate",
        "TemplateItemResponse": "TemplateItem",
    }

    for path in files:
        content = path.read_text(encoding="utf-8")
        current_class = None
        for line in content.split("\n"):
            cm = class_re.match(line)
            if cm:
                current_class = cm.group(1)
                continue
            if current_class is None or current_class not in name_map:
                continue
            # End of class body
            if line and not line.startswith(" ") and not line.startswith("\t"):
                if not line.startswith("class") and line.strip():
                    current_class = None
                    continue
                cm2 = class_re.match(line)
                if cm2:
                    current_class = cm2.group(1)
                    continue
                current_class = None
                continue
            fm = field_re.match(line)
            if fm:
                field_name = fm.group(1)
                if field_name in ("model_config",):
                    continue
                model_name = name_map[current_class]
                result.setdefault(model_name, set()).add(field_name)
    return result


def parse_typescript() -> dict[str, set[str]]:
    """Parse TypeScript interfaces for field names."""
    path = REPO_ROOT / "frontend" / "src" / "api" / "recipes.ts"
    content = path.read_text(encoding="utf-8")

    # Only parse response interfaces (Recipe, Ingredient — not RecipeCreate)
    result: dict[str, set[str]] = {}
    name_map = {"Recipe": "Recipe", "Ingredient": "Ingredient"}

    interface_re = re.compile(r"^export interface (\w+)\s*\{")
    field_re = re.compile(r"^\s+(\w+)\s*:")

    current_iface = None
    brace_depth = 0
    for line in content.split("\n"):
        im = interface_re.match(line)
        if im:
            iname = im.group(1)
            if iname in name_map:
                current_iface = iname
                brace_depth = 1
            else:
                current_iface = None
            continue
        if current_iface is None:
            continue
        brace_depth += line.count("{") - line.count("}")
        if brace_depth <= 0:
            current_iface = None
            continue
        fm = field_re.match(line)
        if fm:
            model_name = name_map[current_iface]
            result.setdefault(model_name, set()).add(fm.group(1))
    return result


def parse_swiftdata() -> dict[str, set[str]]:
    """Parse SwiftData @Model classes for var declarations."""
    files = {
        "Recipe": REPO_ROOT / "RecipeApp" / "RecipeApp" / "Models" / "Recipe.swift",
        "Ingredient": REPO_ROOT / "RecipeApp" / "RecipeApp" / "Models" / "Ingredient.swift",
        "GroceryList": REPO_ROOT / "RecipeApp" / "RecipeApp" / "Models" / "GroceryList.swift",
        "GroceryItem": REPO_ROOT / "RecipeApp" / "RecipeApp" / "Models" / "GroceryItem.swift",
        "ShoppingTemplate": REPO_ROOT / "RecipeApp" / "RecipeApp" / "Models" / "ShoppingTemplate.swift",
        "TemplateItem": REPO_ROOT / "RecipeApp" / "RecipeApp" / "Models" / "TemplateItem.swift",
    }

    # Back-reference vars to skip (single-object relationships)
    back_refs = {"recipe", "groceryList", "template"}

    result: dict[str, set[str]] = {}
    var_re = re.compile(r"^\s+var (\w+)\s*:")

    for model_name, path in files.items():
        content = path.read_text(encoding="utf-8")
        fields: set[str] = set()
        in_class = False
        for line in content.split("\n"):
            if "@Model" in line or "final class" in line:
                in_class = True
                continue
            if not in_class:
                continue
            # Skip computed properties (those with { ... } on same line or next)
            vm = var_re.match(line)
            if vm:
                var_name = vm.group(1)
                # Skip computed properties (contain { after type)
                rest = line[vm.end():]
                if "{" in rest and "=" not in rest.split("{")[0]:
                    continue
                # Skip back-references
                if var_name in back_refs:
                    continue
                fields.add(camel_to_snake(var_name))
        result[model_name] = fields
    return result


def parse_testfixtures() -> dict[str, set[str]]:
    """Parse TestFixtures struct definitions for var/let declarations."""
    files = [
        REPO_ROOT / "TestFixtures" / "Recipe.swift",
        REPO_ROOT / "TestFixtures" / "GroceryItem.swift",
        REPO_ROOT / "TestFixtures" / "ShoppingTemplate.swift",
    ]

    struct_map = {
        "RecipeModel": "Recipe",
        "IngredientModel": "Ingredient",
        "GroceryItemModel": "GroceryItem",
        "GroceryListModel": "GroceryList",
        "ShoppingTemplateModel": "ShoppingTemplate",
        "TemplateItemModel": "TemplateItem",
    }

    result: dict[str, set[str]] = {}
    struct_re = re.compile(r"^struct (\w+)")
    var_re = re.compile(r"^\s+(var|let) (\w+)\s*:")

    for path in files:
        content = path.read_text(encoding="utf-8")
        current_struct = None
        brace_depth = 0
        for line in content.split("\n"):
            sm = struct_re.match(line)
            if sm:
                sname = sm.group(1)
                if sname in struct_map:
                    current_struct = sname
                    brace_depth = 0
                continue
            if current_struct is None:
                continue
            brace_depth += line.count("{") - line.count("}")
            if brace_depth < 0:
                current_struct = None
                continue
            vm = var_re.match(line)
            if vm:
                var_name = vm.group(2)
                # Skip computed properties
                rest = line[vm.end():]
                if "{" in rest and "=" not in rest.split("{")[0]:
                    continue
                model_name = struct_map[current_struct]
                result.setdefault(model_name, set()).add(camel_to_snake(var_name))
    return result


def parse_static_site() -> dict[str, set[str]]:
    """Parse publish-recipes.py for recipe/ingredient field access."""
    path = REPO_ROOT / "scripts" / "publish-recipes.py"
    content = path.read_text(encoding="utf-8")

    # Aliases: static_site key -> canonical field name
    recipe_aliases = {"title": "name", "sourceURL": "source_url"}
    ingredient_aliases: dict[str, str] = {}

    recipe_fields: set[str] = set()
    ingredient_fields: set[str] = set()

    # Match recipe["key"], recipe.get("key"), r["key"], r.get("key")
    recipe_re = re.compile(r'(?:recipe|r)\[?"(\w+)"\]?|(?:recipe|r)\.get\("(\w+)"')
    # Match ing["key"], ing.get("key"), i["key"]
    ing_re = re.compile(r'(?:ing|i)\[?"(\w+)"\]?|(?:ing|i)\.get\("(\w+)"')

    for line in content.split("\n"):
        for m in recipe_re.finditer(line):
            key = m.group(1) or m.group(2)
            if key in ("published", "publishedBy"):
                continue
            canonical = recipe_aliases.get(key, camel_to_snake(key))
            recipe_fields.add(canonical)
        for m in ing_re.finditer(line):
            key = m.group(1) or m.group(2)
            canonical = ingredient_aliases.get(key, camel_to_snake(key))
            ingredient_fields.add(canonical)

    return {"Recipe": recipe_fields, "Ingredient": ingredient_fields}


# ---------------------------------------------------------------------------
# Wire format validation — RecipeDTO (Swift) vs RecipeResponse (Pydantic)
# ---------------------------------------------------------------------------

def parse_dto_coding_keys() -> dict[str, set[str]]:
    """Parse RecipeDTO and IngredientDTO CodingKeys from APIClient.swift.

    Returns snake_case field names as they appear on the wire.
    """
    path = (
        REPO_ROOT
        / "RecipeApp"
        / "RecipeApp"
        / "Services"
        / "APIClient.swift"
    )
    content = path.read_text(encoding="utf-8")
    result: dict[str, set[str]] = {}

    dto_map = {"RecipeDTO": "Recipe", "IngredientDTO": "Ingredient"}
    struct_re = re.compile(r"^struct (\w+DTO)\s*:")
    coding_key_re = re.compile(
        r'^\s+case\s+(\w+)\s*=\s*"(\w+)"'
    )
    bare_case_re = re.compile(r"^\s+case\s+(.+)")

    current_struct: str | None = None
    in_coding_keys = False

    for line in content.split("\n"):
        sm = struct_re.match(line)
        if sm:
            if sm.group(1) in dto_map:
                current_struct = sm.group(1)
                in_coding_keys = False
            else:
                current_struct = None
            continue
        if current_struct is None:
            continue

        if "enum CodingKeys" in line:
            in_coding_keys = True
            continue
        if in_coding_keys:
            if line.strip() == "}":
                in_coding_keys = False
                continue
            # Explicit mapping: case foo = "bar"
            ck = coding_key_re.match(line)
            if ck:
                model = dto_map[current_struct]
                result.setdefault(model, set()).add(ck.group(2))
                continue
            # Bare cases: case id, name, summary
            bk = bare_case_re.match(line)
            if bk:
                model = dto_map[current_struct]
                for name in bk.group(1).split(","):
                    name = name.strip()
                    if name:
                        result.setdefault(model, set()).add(
                            camel_to_snake(name),
                        )

    return result


def check_wire_format(
    pydantic_fields: dict[str, set[str]],
) -> list[str]:
    """Validate RecipeDTO CodingKeys match RecipeResponse fields.

    Checks both directions:
    - Every pydantic response field must exist in the DTO (or be exempted)
    - Every DTO field must exist in the pydantic response
    """
    failures: list[str] = []

    try:
        dto_fields = parse_dto_coding_keys()
    except FileNotFoundError:
        return ["WIRE FORMAT: APIClient.swift not found"]

    # Fields the iOS DTO intentionally omits from the server response
    dto_exemptions: dict[str, set[str]] = {
        "Recipe": {"deleted_at"},
    }

    for model in ("Recipe", "Ingredient"):
        pydantic = pydantic_fields.get(model, set())
        dto = dto_fields.get(model, set())
        exempt = dto_exemptions.get(model, set())

        # Server → iOS: every response field should be decodable
        for field in pydantic - dto - exempt:
            failures.append(
                f"WIRE DRIFT: {model}.{field} in server response "
                f"but missing from {model}DTO CodingKeys",
            )

        # iOS → Server: every encoded field should be accepted
        for field in dto - pydantic:
            failures.append(
                f"WIRE DRIFT: {model}.{field} in {model}DTO CodingKeys "
                f"but missing from server response",
            )

    return failures


# ---------------------------------------------------------------------------
# Main comparison logic
# ---------------------------------------------------------------------------

def run_checks() -> list[str]:
    """Run all schema checks. Returns list of failure messages."""
    canonical = load_canonical()
    failures: list[str] = []

    parsers: dict[str, callable] = {
        "sql": parse_sql,
        "sqlalchemy": parse_sqlalchemy,
        "pydantic_response": parse_pydantic,
        "typescript": parse_typescript,
        "swiftdata": parse_swiftdata,
        "testfixtures": parse_testfixtures,
        "static_site": parse_static_site,
    }

    # Parse all surfaces
    surface_data: dict[str, dict[str, set[str]]] = {}
    for surface_name, parser_fn in parsers.items():
        try:
            surface_data[surface_name] = parser_fn()
        except FileNotFoundError as e:
            failures.append(f"[{surface_name}] file not found: {e}")
            surface_data[surface_name] = {}

    # Compare each model/field against canonical
    for model_name, model_def in canonical["models"].items():
        for field_name, field_def in model_def["fields"].items():
            expected_surfaces = field_def.get("surfaces", [])
            for surface in expected_surfaces:
                if surface not in surface_data:
                    continue
                actual_fields = surface_data[surface].get(model_name, set())
                if not actual_fields:
                    failures.append(
                        f"MISSING MODEL: {model_name} not found in {surface}"
                    )
                    continue
                if field_name not in actual_fields:
                    # Check aliases
                    aliases = field_def.get("aliases", {})
                    alias = aliases.get(surface)
                    if alias and alias in actual_fields:
                        continue
                    failures.append(
                        f"MISSING FIELD: {model_name}.{field_name} not in {surface}"
                    )

    # Wire format check: RecipeDTO CodingKeys vs RecipeResponse fields
    pydantic_fields = surface_data.get("pydantic_response", {})
    if pydantic_fields:
        failures.extend(check_wire_format(pydantic_fields))

    return failures


# ---------------------------------------------------------------------------
# Test entrypoint (pytest-compatible)
# ---------------------------------------------------------------------------

def test_schema_sync() -> None:
    """All code surfaces match schema/canonical.yaml."""
    failures = run_checks()
    if failures:
        msg = f"{len(failures)} schema drift(s) found:\n" + "\n".join(
            f"  - {f}" for f in failures
        )
        raise AssertionError(msg)


if __name__ == "__main__":
    failures = run_checks()
    if failures:
        print(f"FAIL: {len(failures)} schema drift(s) found:", file=sys.stderr)
        for f in failures:
            print(f"  - {f}", file=sys.stderr)
        sys.exit(1)
    else:
        print("OK: all surfaces match canonical schema")
        sys.exit(0)
