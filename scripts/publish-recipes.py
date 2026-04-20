"""Generate static recipe pages for GitHub Pages.

Reads JSON recipe files from data/published-recipes/, generates standalone
HTML pages with embedded JSON-LD (schema.org/Recipe) and Open Graph tags,
and writes them to a build directory ready for deployment to gh-pages.

Usage:
    python scripts/publish-recipes.py [--output-dir BUILD_DIR]

Default output: build/gh-pages/
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path


SITE_DOMAIN = "recipes.ouryearofwander.com"
SITE_TITLE = "Our Recipes"
SITE_SUBTITLE = "Shared from the kitchen"


# --- Slug generation ---

def slugify(text: str) -> str:
    """Convert a recipe title to a URL-friendly slug.

    >>> slugify("Marathon Chicken Bake")
    'marathon-chicken-bake'
    >>> slugify("Nick's Habanero Pepper Jelly!")
    'nicks-habanero-pepper-jelly'
    """
    slug = text.lower().strip()
    slug = slug.replace("'", "").replace("'", "")
    slug = re.sub(r"[^a-z0-9]+", "-", slug)
    slug = slug.strip("-")
    return slug


# --- Fraction formatting ---

def format_quantity(value: float) -> str:
    """Format a quantity with unicode fractions where possible.

    >>> format_quantity(1.5)
    '1 ½'
    >>> format_quantity(0.25)
    '¼'
    >>> format_quantity(2.0)
    '2'
    """
    if value <= 0:
        return ""
    whole = int(value)
    frac = value - whole

    fraction_map = [
        (0.25, "¼"), (1 / 3, "⅓"), (0.5, "½"),
        (2 / 3, "⅔"), (0.75, "¾"),
    ]

    frac_str = None
    for target, symbol in fraction_map:
        if abs(frac - target) < 0.04:
            frac_str = symbol
            break

    if frac_str:
        return f"{whole} {frac_str}" if whole > 0 else frac_str
    if frac < 0.01:
        return str(whole)
    return f"{value:.1f}"


# --- Duration formatting ---

def format_duration(minutes: int) -> str:
    """Format minutes into a human-readable duration.

    >>> format_duration(90)
    '1 hr 30 min'
    >>> format_duration(45)
    '45 min'
    """
    if minutes <= 0:
        return ""
    if minutes < 60:
        return f"{minutes} min"
    hours = minutes // 60
    remaining = minutes % 60
    if remaining == 0:
        return f"{hours} hr"
    return f"{hours} hr {remaining} min"


def iso_duration(minutes: int) -> str:
    """Format minutes as ISO 8601 duration for JSON-LD.

    >>> iso_duration(90)
    'PT1H30M'
    >>> iso_duration(45)
    'PT45M'
    """
    if minutes <= 0:
        return ""
    hours = minutes // 60
    remaining = minutes % 60
    if hours and remaining:
        return f"PT{hours}H{remaining}M"
    if hours:
        return f"PT{hours}H"
    return f"PT{remaining}M"


# --- HTML escaping ---

def esc(text: str) -> str:
    """Escape HTML special characters."""
    return (
        text.replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace('"', "&quot;")
        .replace("'", "&#39;")
    )


# --- JSON-LD generation ---

def build_jsonld(recipe: dict) -> str:
    """Build a schema.org/Recipe JSON-LD block."""
    ld: dict = {
        "@context": "https://schema.org",
        "@type": "Recipe",
        "name": recipe["title"],
    }

    if recipe.get("summary"):
        ld["description"] = recipe["summary"]
    if recipe.get("servings"):
        ld["recipeYield"] = str(recipe["servings"])
    if recipe.get("prepTimeMinutes"):
        ld["prepTime"] = iso_duration(recipe["prepTimeMinutes"])
    if recipe.get("cookTimeMinutes"):
        ld["cookTime"] = iso_duration(recipe["cookTimeMinutes"])

    total = (recipe.get("prepTimeMinutes") or 0) + (
        recipe.get("cookTimeMinutes") or 0
    )
    if total > 0:
        ld["totalTime"] = iso_duration(total)

    if recipe.get("cuisine"):
        ld["recipeCuisine"] = recipe["cuisine"]
    if recipe.get("course"):
        ld["recipeCategory"] = recipe["course"]

    ingredients = []
    for ing in recipe.get("ingredients", []):
        qty = format_quantity(ing.get("quantity", 0))
        unit = ing.get("unit", "")
        name = ing.get("name", "")
        parts = [p for p in [qty, unit, name] if p]
        ingredients.append(" ".join(parts))
    if ingredients:
        ld["recipeIngredient"] = ingredients

    instructions = recipe.get("instructions", [])
    if instructions:
        ld["recipeInstructions"] = [
            {"@type": "HowToStep", "text": step} for step in instructions
        ]

    return json.dumps(ld, indent=2, ensure_ascii=False)


# --- HTML template ---

RECIPE_CSS = """\
:root {
    --bg: #faf9f6;
    --text: #2c2c2c;
    --accent: #c45d3e;
    --muted: #7a7a7a;
    --border: #e8e4df;
    --section-bg: #f5f3ef;
}
@media (prefers-color-scheme: dark) {
    :root {
        --bg: #1a1a1a;
        --text: #e8e4df;
        --accent: #e07850;
        --muted: #999;
        --border: #3a3a3a;
        --section-bg: #222;
    }
}
* { margin: 0; padding: 0; box-sizing: border-box; }
body {
    font-family: 'Georgia', serif;
    background: var(--bg);
    color: var(--text);
    max-width: 720px;
    margin: 0 auto;
    padding: 2rem 1.5rem 4rem;
    line-height: 1.6;
}
a { color: var(--accent); text-decoration: none; }
a:hover { text-decoration: underline; }
.back { font-size: 0.9rem; margin-bottom: 1.5rem; display: block; }
h1 { font-size: 2rem; font-weight: 400; margin-bottom: 0.5rem; }
.summary { color: var(--muted); font-size: 1.05rem; margin-bottom: 1.5rem; }
.meta {
    display: flex; flex-wrap: wrap; gap: 1.5rem;
    padding: 1rem 0; border-top: 1px solid var(--border);
    border-bottom: 1px solid var(--border); margin-bottom: 2rem;
    font-size: 0.9rem; color: var(--muted);
}
.meta-item { display: flex; flex-direction: column; }
.meta-label { font-size: 0.75rem; text-transform: uppercase; letter-spacing: 0.05em; }
.meta-value { font-size: 1rem; color: var(--text); }
h2 {
    font-size: 1.2rem; font-weight: 600; text-transform: uppercase;
    letter-spacing: 0.05em; margin: 2rem 0 1rem;
    color: var(--accent);
}
.ingredients {
    background: var(--section-bg); border-radius: 8px;
    padding: 1.25rem 1.5rem; margin-bottom: 0.5rem;
}
.ingredients table { width: 100%; border-collapse: collapse; }
.ingredients td {
    padding: 0.3rem 0; vertical-align: top;
    border-bottom: 1px solid var(--border);
}
.ingredients tr:last-child td { border-bottom: none; }
.ing-qty { width: 3.5rem; text-align: right; padding-right: 0.5rem; white-space: nowrap; }
.ing-unit { width: 4rem; color: var(--muted); padding-right: 0.5rem; }
.ing-name { }
.instructions ol {
    padding-left: 1.5rem; counter-reset: step;
    list-style: none;
}
.instructions li {
    position: relative; padding: 0.75rem 0;
    border-bottom: 1px solid var(--border);
    padding-left: 2.5rem;
}
.instructions li:last-child { border-bottom: none; }
.instructions li::before {
    counter-increment: step;
    content: counter(step);
    position: absolute; left: 0; top: 0.75rem;
    width: 1.75rem; height: 1.75rem;
    background: var(--accent); color: #fff;
    border-radius: 50%; font-size: 0.8rem;
    display: flex; align-items: center; justify-content: center;
    font-family: sans-serif;
}
.source { margin-top: 2rem; font-size: 0.85rem; color: var(--muted); }
.footer {
    margin-top: 3rem; padding-top: 1.5rem;
    border-top: 1px solid var(--border);
    font-size: 0.8rem; color: var(--muted);
    text-align: center;
}
@media print {
    body { max-width: 100%; padding: 1rem; }
    .back, .footer { display: none; }
    .ingredients { background: none; border: 1px solid #ccc; }
    .instructions li::before { background: #666; }
}
@media (max-width: 480px) {
    body { padding: 1.5rem 1rem 3rem; }
    h1 { font-size: 1.5rem; }
    .meta { gap: 1rem; }
}
"""


def render_recipe_page(recipe: dict, username: str) -> str:
    """Render a full HTML page for a single recipe."""
    title = recipe["title"]
    slug = slugify(title)
    url = f"https://{SITE_DOMAIN}/{username}/{slug}"

    # Meta section
    meta_items = []
    if recipe.get("prepTimeMinutes"):
        meta_items.append(
            ("Prep", format_duration(recipe["prepTimeMinutes"]))
        )
    if recipe.get("cookTimeMinutes"):
        meta_items.append(
            ("Cook", format_duration(recipe["cookTimeMinutes"]))
        )
    total = (recipe.get("prepTimeMinutes") or 0) + (
        recipe.get("cookTimeMinutes") or 0
    )
    if total > 0:
        meta_items.append(("Total", format_duration(total)))
    if recipe.get("servings"):
        meta_items.append(("Servings", str(recipe["servings"])))
    if recipe.get("difficulty"):
        meta_items.append(("Difficulty", recipe["difficulty"]))
    if recipe.get("cuisine"):
        meta_items.append(("Cuisine", recipe["cuisine"]))

    meta_html = ""
    if meta_items:
        items = "".join(
            f'<div class="meta-item">'
            f'<span class="meta-label">{esc(label)}</span>'
            f'<span class="meta-value">{esc(value)}</span>'
            f"</div>"
            for label, value in meta_items
        )
        meta_html = f'<div class="meta">{items}</div>'

    # Ingredients
    ing_rows = []
    for ing in recipe.get("ingredients", []):
        qty = format_quantity(ing.get("quantity", 0))
        unit = esc(ing.get("unit", ""))
        name = esc(ing.get("name", ""))
        ing_rows.append(
            f"<tr>"
            f'<td class="ing-qty">{esc(qty)}</td>'
            f'<td class="ing-unit">{unit}</td>'
            f'<td class="ing-name">{name}</td>'
            f"</tr>"
        )
    ing_table = "\n".join(ing_rows)

    # Instructions
    inst_items = []
    for step in recipe.get("instructions", []):
        inst_items.append(f"<li>{esc(step)}</li>")
    inst_list = "\n".join(inst_items)

    # Source URL
    source_html = ""
    source_url = recipe.get("sourceURL", "")
    if source_url:
        source_html = (
            f'<p class="source">Source: '
            f'<a href="{esc(source_url)}" rel="noopener">{esc(source_url)}</a>'
            f"</p>"
        )

    # Summary
    summary_html = ""
    if recipe.get("summary"):
        summary_html = f'<p class="summary">{esc(recipe["summary"])}</p>'

    # JSON-LD
    jsonld = build_jsonld(recipe)

    # OG description
    og_desc = recipe.get("summary", "")
    if not og_desc and recipe.get("ingredients"):
        first_few = [i["name"] for i in recipe["ingredients"][:4]]
        og_desc = "Made with " + ", ".join(first_few) + "..."

    return f"""<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>{esc(title)} — {SITE_TITLE}</title>
    <meta name="description" content="{esc(og_desc)}">
    <meta property="og:title" content="{esc(title)}">
    <meta property="og:description" content="{esc(og_desc)}">
    <meta property="og:type" content="article">
    <meta property="og:url" content="{esc(url)}">
    <meta property="og:site_name" content="{SITE_TITLE}">
    <link rel="canonical" href="{esc(url)}">
    <script type="application/ld+json">
{jsonld}
    </script>
    <style>
{RECIPE_CSS}
    </style>
</head>
<body>
    <a href="/{username}/" class="back">&larr; All recipes</a>
    <h1>{esc(title)}</h1>
    {summary_html}
    {meta_html}
    <h2>Ingredients</h2>
    <div class="ingredients">
        <table>{ing_table}</table>
    </div>
    <h2>Instructions</h2>
    <div class="instructions">
        <ol>{inst_list}</ol>
    </div>
    {source_html}
    <div class="footer">
        Shared from <a href="https://{SITE_DOMAIN}">{SITE_TITLE}</a>
    </div>
</body>
</html>"""


# --- Index page ---

INDEX_CSS = """\
:root {
    --bg: #faf9f6;
    --text: #2c2c2c;
    --accent: #c45d3e;
    --muted: #7a7a7a;
    --border: #e8e4df;
}
@media (prefers-color-scheme: dark) {
    :root {
        --bg: #1a1a1a;
        --text: #e8e4df;
        --accent: #e07850;
        --muted: #999;
        --border: #3a3a3a;
    }
}
* { margin: 0; padding: 0; box-sizing: border-box; }
body {
    font-family: 'Georgia', serif;
    background: var(--bg);
    color: var(--text);
    max-width: 720px;
    margin: 0 auto;
    padding: 3rem 1.5rem;
}
a { color: var(--text); text-decoration: none; }
a:hover { color: var(--accent); }
h1 { font-size: 2rem; font-weight: 400; margin-bottom: 0.5rem; }
.subtitle { color: var(--muted); font-size: 1rem; margin-bottom: 2.5rem; }
.recipe-list { list-style: none; }
.recipe-list li {
    border-bottom: 1px solid var(--border);
    padding: 1rem 0;
}
.recipe-list a { font-size: 1.1rem; }
.recipe-meta {
    color: var(--muted);
    font-size: 0.85rem;
    margin-top: 0.25rem;
}
.empty {
    color: var(--muted);
    font-style: italic;
    margin-top: 2rem;
}
@media (max-width: 480px) {
    body { padding: 1.5rem 1rem; }
    h1 { font-size: 1.5rem; }
}
"""


def render_index_page(
    recipes: list[dict], username: str, is_root: bool = False,
) -> str:
    """Render the recipe index page."""
    if is_root:
        # Root index just redirects/links to user pages
        title = SITE_TITLE
        subtitle = SITE_SUBTITLE
    else:
        title = f"{username}'s recipes"
        subtitle = ""

    items_html = ""
    if recipes:
        items = []
        for r in sorted(recipes, key=lambda x: x["title"].lower()):
            slug = slugify(r["title"])
            href = f"/{username}/{slug}"
            meta_parts = []
            if r.get("cuisine"):
                meta_parts.append(r["cuisine"])
            total = (r.get("prepTimeMinutes") or 0) + (
                r.get("cookTimeMinutes") or 0
            )
            if total > 0:
                meta_parts.append(format_duration(total))
            if r.get("servings"):
                meta_parts.append(f"Serves {r['servings']}")
            meta = " · ".join(meta_parts)
            meta_html = f'<div class="recipe-meta">{esc(meta)}</div>' if meta else ""
            items.append(
                f'<li><a href="{href}">{esc(r["title"])}</a>{meta_html}</li>'
            )
        items_html = f'<ul class="recipe-list">{"".join(items)}</ul>'
    else:
        items_html = '<p class="empty">No recipes published yet.</p>'

    subtitle_html = (
        f'<p class="subtitle">{esc(subtitle)}</p>' if subtitle else ""
    )

    return f"""<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>{esc(title)}</title>
    <meta property="og:title" content="{esc(title)}">
    <meta property="og:type" content="website">
    <meta property="og:url" content="https://{SITE_DOMAIN}/{username}/">
    <meta property="og:site_name" content="{SITE_TITLE}">
    <link rel="canonical" href="https://{SITE_DOMAIN}/{username}/">
    <style>
{INDEX_CSS}
    </style>
</head>
<body>
    <h1>{esc(title)}</h1>
    {subtitle_html}
    {items_html}
</body>
</html>"""


# --- Build pipeline ---

def load_recipes(source_dir: Path) -> list[dict]:
    """Load all published recipe JSON files from the source directory."""
    recipes = []
    for path in sorted(source_dir.glob("*.json")):
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, OSError) as e:
            print(f"  WARN: skipping {path.name}: {e}", file=sys.stderr)
            continue

        if not data.get("published", False):
            print(f"  skip: {path.name} (published=false)")
            continue
        if not data.get("title"):
            print(
                f"  WARN: skipping {path.name}: no title",
                file=sys.stderr,
            )
            continue

        recipes.append(data)
        print(f"  load: {data['title']}")

    return recipes


def build_site(source_dir: Path, output_dir: Path) -> None:
    """Build the full static site."""
    print(f"Loading recipes from {source_dir}/")
    recipes = load_recipes(source_dir)
    print(f"Found {len(recipes)} published recipe(s)")

    # Group by publisher
    by_user: dict[str, list[dict]] = {}
    for r in recipes:
        user = r.get("publishedBy", "seanick")
        by_user.setdefault(user, []).append(r)

    # Clean and create output dir
    if output_dir.exists():
        import shutil
        shutil.rmtree(output_dir)
    output_dir.mkdir(parents=True)

    # Write CNAME
    (output_dir / "CNAME").write_text(
        f"{SITE_DOMAIN}\n", encoding="utf-8",
    )

    # Write root index (redirects to first user or shows user list)
    all_recipes = [r for rs in by_user.values() for r in rs]
    if len(by_user) == 1:
        # Single user — root index shows their recipes
        username = next(iter(by_user))
        root_html = render_index_page(all_recipes, username, is_root=True)
        (output_dir / "index.html").write_text(
            root_html, encoding="utf-8",
        )
    else:
        # Multi-user — root lists users (future)
        root_html = render_index_page([], "", is_root=True)
        (output_dir / "index.html").write_text(
            root_html, encoding="utf-8",
        )

    # Write per-user pages
    for username, user_recipes in by_user.items():
        user_dir = output_dir / username
        user_dir.mkdir(parents=True, exist_ok=True)

        # User index
        index_html = render_index_page(user_recipes, username)
        (user_dir / "index.html").write_text(
            index_html, encoding="utf-8",
        )
        print(f"  wrote: /{username}/ ({len(user_recipes)} recipes)")

        # Individual recipe pages
        for recipe in user_recipes:
            slug = slugify(recipe["title"])
            recipe_dir = user_dir / slug
            recipe_dir.mkdir(parents=True, exist_ok=True)
            page_html = render_recipe_page(recipe, username)
            (recipe_dir / "index.html").write_text(
                page_html, encoding="utf-8",
            )
            print(f"  wrote: /{username}/{slug}/")

    print(f"\nSite built: {output_dir}/ ({len(recipes)} recipes)")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Generate static recipe pages for GitHub Pages",
    )
    parser.add_argument(
        "--source-dir",
        type=Path,
        default=Path("data/published-recipes"),
        help="Directory containing recipe JSON files",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path("build/gh-pages"),
        help="Output directory for generated HTML",
    )
    args = parser.parse_args()

    # Resolve relative to repo root
    repo_root = Path(__file__).resolve().parent.parent
    source = args.source_dir
    if not source.is_absolute():
        source = repo_root / source
    output = args.output_dir
    if not output.is_absolute():
        output = repo_root / output

    if not source.exists():
        print(f"ERROR: source directory not found: {source}", file=sys.stderr)
        sys.exit(1)

    build_site(source, output)


if __name__ == "__main__":
    main()
