#!/bin/bash
# bob-the-builder install script
# Symlinks the controller skill + author agent into ~/.claude/ so repo edits take
# effect immediately, writes a LOCAL.md with absolute paths (for global/symlinked
# runs from any directory), and OPTIONALLY adds a scoped permission allowlist to
# your global ~/.claude/settings.json to cut down on approval prompts.

set -e

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMANDS_DIR="$HOME/.claude/commands"
AGENTS_DIR="$HOME/.claude/agents"

echo "Installing bob-the-builder..."
echo "Repo: $REPO_DIR"

mkdir -p "$COMMANDS_DIR" "$AGENTS_DIR"

# Symlink the controller skill
ln -sf "$REPO_DIR/bob-the-builder.md" "$COMMANDS_DIR/bob-the-builder.md"
echo "  ✓ Linked bob-the-builder.md → $COMMANDS_DIR/"

# Symlink agents
for agent_file in "$REPO_DIR/agents/"*.md; do
  agent_name="$(basename "$agent_file")"
  ln -sf "$agent_file" "$AGENTS_DIR/$agent_name"
  echo "  ✓ Linked $agent_name → $AGENTS_DIR/"
done

# Write LOCAL.md (gitignored) so the skill knows the absolute CLI path when run
# from any working directory.
cat > "$REPO_DIR/LOCAL.md" <<LOCALEOF
# Machine-local override (not committed)

bob-the-builder is installed globally; it may be invoked from any working directory.

## bob-dir (absolute repo path)
$REPO_DIR

## CLI path
Use this absolute path wherever the skill says \`<bob-dir>/scripts/demo_upload.py\`:

    python3 $REPO_DIR/scripts/demo_upload.py

Generated <channel>.json / .md files are written to the caller-supplied output_dir,
defaulting to $REPO_DIR/output/.
LOCALEOF
echo "  ✓ Wrote LOCAL.md with absolute paths"

# Offer the global allowlist
echo ""
read -r -p "Add a scoped allowlist to ~/.claude/settings.json to reduce approval prompts? [y/N] " ans
if [[ "$ans" =~ ^[Yy]$ ]]; then
  python3 "$REPO_DIR/scripts/_install_allowlist.py" "$REPO_DIR"
else
  echo "  Skipped. You can run this later:"
  echo "    python3 $REPO_DIR/scripts/_install_allowlist.py $REPO_DIR"
fi

echo ""
echo "Done. /bob-the-builder is ready."
echo "Next: save a token →  python3 $REPO_DIR/scripts/demo_upload.py login"
