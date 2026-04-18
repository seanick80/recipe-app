#!/usr/bin/env python3
"""Statically validate that app-extension targets in project.yml will
produce a valid Info.plist with NSExtension at build time.

xcodegen's `info: path:` alone does NOT carry custom plist keys like
NSExtension into the generated project (confirmed 2026-04-18). This
script catches that class of error without needing xcodegen or Xcode.

Exit 0 = OK, exit 1 = validation failure (printed to stderr).
"""

import plistlib
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    print("SKIP: pyyaml not installed", file=sys.stderr)
    sys.exit(0)

REPO_ROOT = Path(__file__).resolve().parent.parent
PROJECT_YML = REPO_ROOT / "RecipeApp" / "project.yml"

errors = []


def err(msg: str) -> None:
    errors.append(msg)
    print(f"  [extension-plist] FAIL: {msg}", file=sys.stderr)


def info(msg: str) -> None:
    print(f"  [extension-plist] {msg}")


def validate_extension_target(name: str, target: dict) -> None:
    """Validate that an app-extension target has NSExtension configured."""
    info_block = target.get("info")
    if not info_block:
        err(f"{name}: no `info:` block — extension will have no Info.plist")
        return

    ns_extension_in_properties = False
    ns_extension_in_plist = False

    # Check info.properties for NSExtension
    properties = info_block.get("properties", {})
    if "NSExtension" in properties:
        ns_extension_in_properties = True
        ext = properties["NSExtension"]
        if "NSExtensionPointIdentifier" not in ext:
            err(f"{name}: info.properties.NSExtension missing NSExtensionPointIdentifier")
        if "NSExtensionPrincipalClass" not in ext:
            err(f"{name}: info.properties.NSExtension missing NSExtensionPrincipalClass")

    # Check info.path plist file for NSExtension
    plist_path_str = info_block.get("path")
    if plist_path_str:
        plist_path = REPO_ROOT / "RecipeApp" / plist_path_str
        if not plist_path.exists():
            err(f"{name}: info.path points to {plist_path_str} but file not found at {plist_path}")
        else:
            try:
                with open(plist_path, "rb") as f:
                    plist = plistlib.load(f)
                if "NSExtension" in plist:
                    ns_extension_in_plist = True
            except Exception as e:
                err(f"{name}: failed to parse {plist_path_str}: {e}")
    else:
        err(f"{name}: no `info.path` — xcodegen requires this field")

    # At least one source of NSExtension must exist
    if not ns_extension_in_properties and not ns_extension_in_plist:
        err(
            f"{name}: NSExtension not found in info.properties OR in the "
            f"plist file. xcodegen info:path alone drops custom keys — "
            f"use info.properties to inject NSExtension."
        )
    elif ns_extension_in_properties:
        info(f"{name}: NSExtension found in info.properties (reliable)")
    elif ns_extension_in_plist:
        err(
            f"{name}: NSExtension found ONLY in the plist file at "
            f"{plist_path_str}, NOT in info.properties. xcodegen "
            f"info:path is known to drop custom keys — add NSExtension "
            f"to info.properties to ensure it survives."
        )


def main() -> int:
    if not PROJECT_YML.exists():
        print(f"SKIP: {PROJECT_YML} not found", file=sys.stderr)
        return 0

    with open(PROJECT_YML) as f:
        project = yaml.safe_load(f)

    targets = project.get("targets", {})
    extension_count = 0

    for name, target in targets.items():
        target_type = target.get("type", "")
        if "extension" in target_type:
            extension_count += 1
            validate_extension_target(name, target)

    if extension_count == 0:
        info("no extension targets found — nothing to validate")

    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
