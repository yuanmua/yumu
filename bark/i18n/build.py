#!/usr/bin/env python3
"""Generate platform localisation files from bark/i18n/*.json. English is the source; CI checks the output is committed."""
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
SOURCE = ROOT / "bark" / "i18n"
MACOS = ROOT / "apps" / "macos" / "Sources" / "Yumu" / "Resources"


def escape(value: str) -> str:
    return value.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")


def main() -> int:
    english = json.loads((SOURCE / "en.json").read_text())
    errors = json.loads((ROOT / "grain" / "schema" / "errors.json").read_text())["kinds"]
    missing = [kind for kind in errors if f"error.{kind}" not in english]
    if missing:
        print(f"missing English translation for error kinds: {missing}", file=sys.stderr)
        return 1
    for path in sorted(SOURCE.glob("*.json")):
        locale = path.stem
        strings = json.loads(path.read_text())
        unknown = set(strings) - set(english)
        if unknown:
            print(f"{locale}: keys not in en.json: {sorted(unknown)}", file=sys.stderr)
            return 1
        target = MACOS / f"{locale}.lproj" / "Localizable.strings"
        target.parent.mkdir(parents=True, exist_ok=True)
        lines = [f'"{key}" = "{escape(value)}";' for key, value in sorted(strings.items())]
        target.write_text("/* Generated from bark/i18n/" + path.name + ". Do not edit. */\n" + "\n".join(lines) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
