#!/usr/bin/env python3
"""Generate Swift constants from bark/tokens/*.json."""
import json
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[2]
TOKENS = ROOT / "bark" / "tokens"
TARGET = ROOT / "apps" / "macos" / "Sources" / "Yumu" / "Bark" / "Tokens.generated.swift"


def animation(spec: dict) -> str:
    if spec["kind"] == "spring":
        return f'Animation.spring(response: {spec["response"]}, dampingFraction: {spec["damping"]})'
    return f'Animation.{spec["kind"]}(duration: {spec["duration"]})'


def main() -> None:
    space = json.loads((TOKENS / "space.json").read_text())
    radius = json.loads((TOKENS / "radius.json").read_text())
    motion = json.loads((TOKENS / "motion.json").read_text())
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
    out.append("}")
    TARGET.parent.mkdir(parents=True, exist_ok=True)
    TARGET.write_text("\n".join(out) + "\n")


if __name__ == "__main__":
    main()
