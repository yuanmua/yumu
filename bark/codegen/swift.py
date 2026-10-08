#!/usr/bin/env python3
"""Generate Swift constants from bark/tokens/*.json."""
import json
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parents[2]
TOKENS = ROOT / "bark" / "tokens"
TARGET = ROOT / "apps" / "macos" / "Sources" / "Yumu" / "Bark" / "Tokens.generated.swift"

WEIGHTS = {400: ".regular", 500: ".medium", 600: ".semibold", 700: ".bold"}


def animation(spec: dict) -> str:
    if spec["kind"] == "spring":
        return f'Animation.spring(response: {spec["response"]}, dampingFraction: {spec["damping"]})'
    return f'Animation.{spec["kind"]}(duration: {spec["duration"]})'


def rgba(value: str) -> str:
    if value.startswith("#"):
        r, g, b = (int(value[i:i + 2], 16) / 255 for i in (1, 3, 5))
        return f"({r:.3f}, {g:.3f}, {b:.3f}, 1)"
    m = re.match(r"rgba\((\d+),(\d+),(\d+),([\d.]+)\)", value.replace(" ", ""))
    r, g, b, a = m.groups()
    return f"({int(r) / 255:.3f}, {int(g) / 255:.3f}, {int(b) / 255:.3f}, {a})"


def camel(group: str, name: str) -> str:
    return group + name[0].upper() + name[1:]


def main() -> None:
    space = json.loads((TOKENS / "space.json").read_text())
    radius = json.loads((TOKENS / "radius.json").read_text())
    motion = json.loads((TOKENS / "motion.json").read_text())
    color = json.loads((TOKENS / "color.json").read_text())
    type_ = json.loads((TOKENS / "type.json").read_text())
    out = ["// Generated from bark/tokens by bark/codegen/swift.py. Do not edit.", "import SwiftUI", "", "enum Bark {"]
    out.append("    enum Space {")
    out += [f"        static let {name}: CGFloat = {value}" for name, value in space.items()]
    out.append("    }")
    out.append("    enum Radius {")
    out += [f"        static let {name}: CGFloat = {value}" for name, value in radius.items()]
    out.append("    }")
    out.append("    enum Motion {")
    out += [f"        static let {name} = {animation(spec)}" for name, spec in motion.items()]
    out.append("    }")
    out.append("    enum Colors {")
    for group, names in color.items():
        for name, modes in names.items():
            out.append(f"        static let {camel(group, name)} = dynamic(light: {rgba(modes['light'])}, dark: {rgba(modes['dark'])})")
    out.append("    }")
    out.append("    enum Text {")
    for name, spec in type_.items():
        out.append(f"        static let {name} = Font.system(size: {spec['size']}, weight: {WEIGHTS[spec['weight']]})")
        out.append(f"        static let {name}Size: CGFloat = {spec['size']}")
    out.append("    }")
    out.append("}")
    TARGET.parent.mkdir(parents=True, exist_ok=True)
    TARGET.write_text("\n".join(out) + "\n")


if __name__ == "__main__":
    main()
