from __future__ import annotations

from main import inject_recipe_meta

INDEX = (
    "<!doctype html><html><head>"
    '<meta charset="UTF-8" />'
    "<title>Recipe App</title>"
    '<meta property="og:title" content="Recipe App" />'
    '<meta property="og:type" content="website" />'
    "</head><body></body></html>"
)


def test_inject_sets_title_and_og_title():
    out = inject_recipe_meta(INDEX, "Marathon Chicken Bake", "A hearty bake.")
    assert "<title>Marathon Chicken Bake · Recipe App</title>" in out
    assert '<meta property="og:title" content="Marathon Chicken Bake" />' in out
    assert '<meta property="og:description" content="A hearty bake." />' in out
    # Defaults are replaced, not duplicated.
    assert "<title>Recipe App</title>" not in out
    assert '<meta property="og:title" content="Recipe App" />' not in out


def test_inject_escapes_html():
    out = inject_recipe_meta(INDEX, 'Fish & "Chips" <x>', "a & b")
    assert "Fish &amp; &quot;Chips&quot; &lt;x&gt;" in out
    assert '<meta property="og:description" content="a &amp; b" />' in out
    # No raw unescaped markup leaked into the document.
    assert "<x>" not in out


def test_inject_without_summary_omits_description():
    out = inject_recipe_meta(INDEX, "Plain", "")
    assert "<title>Plain · Recipe App</title>" in out
    assert "og:description" not in out
