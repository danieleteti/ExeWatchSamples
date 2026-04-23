#!/usr/bin/env python3
"""
check_secrets.py — block ExeWatch API keys from being committed.

Scans files for the ExeWatch API key pattern:

    ew_(win|lin|mac|and|ios|web)_[A-Za-z0-9_-]{30,}

Exits 1 (blocking the commit / CI) when any match is found.

Usage:
    python scripts/check_secrets.py --staged      # scan git-staged files (pre-commit)
    python scripts/check_secrets.py --all         # scan full working tree
    python scripts/check_secrets.py path [path…]  # scan explicit paths

Allow-list a known test/fixture key by putting the marker
`exewatch:allow-secret` anywhere on the same line as the key.

Configuration (optional): create `.secretsignore` in the repo root with
one glob pattern per line — matching paths are skipped entirely. Lines
beginning with `#` are comments.
"""
from __future__ import annotations

import argparse
import fnmatch
import os
import re
import subprocess
import sys
from pathlib import Path

KEY_RE = re.compile(r"ew_(?:win|lin|mac|and|ios|web)_[A-Za-z0-9_-]{30,}")
ALLOW_MARKER = "exewatch:allow-secret"
REPO_ROOT = Path(__file__).resolve().parent.parent
IGNORE_FILE = REPO_ROOT / ".secretsignore"

# Binary and build-artifact extensions: never scan these, they cannot plausibly
# hold a source-level secret, and matching random bytes would generate noise.
BINARY_EXT = {
    ".exe", ".dll", ".so", ".dylib", ".bin", ".o", ".obj", ".lib", ".a",
    ".dcu", ".drc", ".res", ".rsm", ".map",
    ".zip", ".7z", ".tar", ".gz", ".xz",
    ".png", ".jpg", ".jpeg", ".gif", ".ico", ".webp", ".svg",
    ".mp4", ".mov", ".wav", ".mp3", ".ogg",
    ".pdf", ".pptx", ".docx", ".xlsx",
    ".ewlog", ".ewdevice", ".ewmetric", ".sending",
}


def load_ignore_patterns() -> list[str]:
    if not IGNORE_FILE.exists():
        return []
    patterns: list[str] = []
    for raw in IGNORE_FILE.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        patterns.append(line)
    return patterns


def is_ignored(rel_path: str, patterns: list[str]) -> bool:
    rel_path = rel_path.replace("\\", "/")
    for pat in patterns:
        if fnmatch.fnmatch(rel_path, pat):
            return True
    return False


def staged_files() -> list[Path]:
    out = subprocess.run(
        ["git", "diff", "--cached", "--name-only", "--diff-filter=ACMR", "-z"],
        capture_output=True, text=True, cwd=REPO_ROOT, check=True,
    ).stdout
    return [REPO_ROOT / p for p in out.split("\0") if p]


def all_tracked_files() -> list[Path]:
    out = subprocess.run(
        ["git", "ls-files", "-z"],
        capture_output=True, text=True, cwd=REPO_ROOT, check=True,
    ).stdout
    return [REPO_ROOT / p for p in out.split("\0") if p]


def scan_file(path: Path) -> list[tuple[int, str]]:
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except (OSError, UnicodeError):
        return []
    hits: list[tuple[int, str]] = []
    for lineno, line in enumerate(text.splitlines(), start=1):
        m = KEY_RE.search(line)
        if not m:
            continue
        if ALLOW_MARKER in line:
            continue
        hits.append((lineno, line.rstrip()))
    return hits


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    g = ap.add_mutually_exclusive_group()
    g.add_argument("--staged", action="store_true", help="scan git-staged files only")
    g.add_argument("--all", action="store_true", help="scan every tracked file")
    ap.add_argument("paths", nargs="*", help="explicit paths to scan")
    args = ap.parse_args()

    if args.staged:
        files = staged_files()
    elif args.all:
        files = all_tracked_files()
    elif args.paths:
        files = [Path(p).resolve() for p in args.paths]
    else:
        files = staged_files() or all_tracked_files()

    patterns = load_ignore_patterns()
    violations: list[tuple[Path, int, str]] = []

    for f in files:
        if not f.is_file():
            continue
        if f.suffix.lower() in BINARY_EXT:
            continue
        try:
            rel = f.relative_to(REPO_ROOT)
        except ValueError:
            rel = f
        if is_ignored(str(rel), patterns):
            continue
        for lineno, line in scan_file(f):
            violations.append((rel, lineno, line))

    if not violations:
        return 0

    print("ExeWatch API key(s) detected — commit blocked", file=sys.stderr)
    print("-" * 60, file=sys.stderr)
    for rel, lineno, line in violations:
        print(f"{rel}:{lineno}: {line}", file=sys.stderr)
    print("-" * 60, file=sys.stderr)
    print(
        "Fix options:\n"
        "  1. Replace the key with a placeholder (e.g. 'YOUR_API_KEY_HERE').\n"
        "  2. For local-only test fixtures, append the marker "
        f"'{ALLOW_MARKER}' on the same line as the key.\n"
        "  3. Add the path to .secretsignore (never do this for real leaks).\n"
        "Real leaked keys MUST be revoked on the ExeWatch console.",
        file=sys.stderr,
    )
    return 1


if __name__ == "__main__":
    sys.exit(main())
