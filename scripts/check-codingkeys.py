#!/usr/bin/env python3
"""Check this app's CodingKeys contract without a maintainer-only dependency.

With convertFromSnakeCase, both `case some_key` and
`case someKey = "some_key"` silently lose fields. Check the effective raw value.
"""
import re
import sys
from pathlib import Path


def check(root):
    files = sorted((root / "Sources").rglob("*.swift"))
    if not files:
        print(f"No Swift sources in {root / 'Sources'}", file=sys.stderr)
        return 1
    sources = {path: path.read_text(encoding="utf-8") for path in files}
    if not any(re.search(r"keyDecodingStrategy\s*=\s*\.convertFromSnakeCase", text)
               for text in sources.values()):
        return 0
    errors = []
    for path, text in sources.items():
        # CodingKeys in this app contain only enum cases. Strip comments so a
        # commented-out example cannot trigger the check or end an enum early.
        text = re.sub(r"/\*.*?\*/|//[^\n]*", lambda m: "\n" * m[0].count("\n"),
                      text, flags=re.S)
        for enum in re.finditer(r"\benum\s+CodingKeys\b[^{}]*\{([^{}]*)\}", text):
            for case in re.finditer(r"\bcase\s+([^\n}]+)", enum[1]):
                for item in case[1].split(","):
                    key = item.split("=", 1)[-1].strip().strip('"`; ')
                    if "_" in key:
                        line = text.count("\n", 0, enum.start(1) + case.start()) + 1
                        errors.append(f"{path.relative_to(root)}:{line}: CodingKey {key!r} "
                                      "conflicts with convertFromSnakeCase")
    for error in errors:
        print(error, file=sys.stderr)
    if not errors:
        print("CodingKeys contract OK")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(check(Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[1]))
