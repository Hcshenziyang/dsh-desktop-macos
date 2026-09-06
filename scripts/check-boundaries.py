#!/usr/bin/env python3
"""Check source imports against SwiftPM and the client's layer boundaries."""
import json
import re
import sys
from pathlib import Path

manifest = json.load(sys.stdin)
root = Path(__file__).resolve().parent.parent
targets = {target["name"]: target for target in manifest["targets"]}
errors = []
base = {"DSHCore", "DSHWeb", "DSHUI"}
for name, target in targets.items():
    if target["type"] == "test":
        continue
    dependencies = set()
    for dependency in target["dependencies"]:
        for kind in ("byName", "target"):
            if kind in dependency:
                dependencies.add(dependency[kind][0])
    if name in base and dependencies:
        errors.append(f"{name}: shared infrastructure must not depend on other client modules")
    if target["path"].startswith("Sources/Features/") and not dependencies <= base:
        errors.append(f"{name}: features may only depend on shared infrastructure")
    directory = root / target["path"]
    excluded = [directory / path for path in target.get("exclude", [])]
    for source in directory.rglob("*.swift"):
        if any(source == path or path in source.parents for path in excluded):
            continue
        content = source.read_text()
        for imported in re.findall(r"^\s*(?:@testable\s+)?import\s+(\w+)", content, re.MULTILINE):
            if imported in targets and imported not in dependencies:
                errors.append(f"{source.relative_to(root)}: undeclared dependency on {imported}")
        if re.search(r"\bstatic\s+(?:let|var)\s+shared\b", content):
            errors.append(f"{source.relative_to(root)}: inject client services instead of adding a singleton")
if errors:
    sys.exit("\n".join(errors))
print("Client module boundaries passed.")
