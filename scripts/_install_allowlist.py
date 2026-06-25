#!/usr/bin/env python3
"""Merge bob-the-builder's scoped permission allowlist into GLOBAL ~/.claude/settings.json.

Called by install.sh. Bob runs from arbitrary directories (e.g. a leeroy
customers/<slug>/ folder), so a repo-local settings.local.json would not apply —
the allowlist must be global.

Scope: read-only / local commands only. `upload` (the network mutation) is
deliberately NOT included, so uploads always require an explicit confirm.
Idempotent: only adds entries that aren't already present.
"""
import json
import sys
from pathlib import Path

BOB_DIR = sys.argv[1] if len(sys.argv) > 1 else None
if not BOB_DIR:
    sys.exit("usage: _install_allowlist.py <bob-dir-abs-path>")

CLI = f"{BOB_DIR}/scripts/demo_upload.py"

# Tightly scoped: each entry is a specific read-only/local demo_upload.py subcommand,
# plus the keychain + repo git/gh commands the skill needs. NOT `python3 *`.
ENTRIES = [
    f"Bash(python3 {CLI} doctor *)",
    f"Bash(python3 {CLI} roster *)",
    f"Bash(python3 {CLI} validate *)",
    f"Bash(python3 {CLI} channels *)",
    f"Bash(python3 {CLI} users *)",
    f"Bash(python3 {CLI} bots *)",
    f"Bash(python3 {CLI} list *)",
    f"Bash(python3 {CLI} create-channel *)",
    f"Bash(python3 {CLI} login *)",
    f"Bash(python3 {CLI} --help)",
    "Bash(security find-generic-password *)",
    "Bash(security add-generic-password *)",
    "Bash(security delete-generic-password *)",
]

settings_path = Path.home() / ".claude" / "settings.json"
settings_path.parent.mkdir(parents=True, exist_ok=True)

if settings_path.exists():
    try:
        settings = json.loads(settings_path.read_text())
    except json.JSONDecodeError as e:
        sys.exit(f"Could not parse {settings_path}: {e}\nLeaving it untouched — add the allowlist manually.")
else:
    settings = {}

perms = settings.setdefault("permissions", {})
allow = perms.setdefault("allow", [])

added = [e for e in ENTRIES if e not in allow]
allow.extend(added)

settings_path.write_text(json.dumps(settings, indent=2) + "\n")

if added:
    print(f"Added {len(added)} allowlist entr(y/ies) to {settings_path}:")
    for e in added:
        print(f"  + {e}")
else:
    print(f"All allowlist entries already present in {settings_path} — nothing to add.")
print("\nNote: `upload` is intentionally NOT allowlisted — uploads always confirm.")
