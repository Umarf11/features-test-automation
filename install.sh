#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
SKILLS_DIR="${ORCA_SKILLS_DIR:-$HOME/.agents/skills}"

mkdir -p "$SKILLS_DIR"

echo "Installing skills to $SKILLS_DIR ..."
for skill_dir in "$REPO_ROOT"/*/; do
  skill_dir="${skill_dir%/}"
  if [ -f "$skill_dir/SKILL.md" ]; then
    skill_name="$(basename "$skill_dir")"
    echo "  -> $skill_name"
    rm -rf "$SKILLS_DIR/$skill_name"
    cp -r "$skill_dir" "$SKILLS_DIR/$skill_name"
  fi
done

echo ""
echo "Done! Restart your agent session to pick up new skills."
echo ""
echo "test-features automation:"
echo "  - 'test features'  : runs the four feature agents sequentially (fail-fast)"
echo "  - 'report feature' : shows the latest report"
echo "  - Each agent can also run alone: 'test vault', 'test secrets',"
echo "    'test orchestration', 'test telemetry'"
echo "  - Reports are written to reports/features/ in this repo clone."
