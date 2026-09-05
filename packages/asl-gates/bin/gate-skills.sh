#!/usr/bin/env bash
# Pure ASL Modular Skills Consistency & Freshness Gate
set -eo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
cd "$ROOT"

echo "--> Auditing modular skills consistency and freshness..."

ERRORS=0
TOTAL_SKILLS=0

# Check for accidental reappearance of legacy skyloom
if [ -d "skills/skyloom" ]; then
  echo "    ✗ Policy violation: legacy 'skills/skyloom' directory still exists (must be replaced by seambus / agent-bus)."
  ERRORS=$((ERRORS + 1))
fi

# Find all SKILL.md files across workspace
for skill_file in $(find . -name "SKILL.md" -not -path "*/node_modules/*" -not -path "*/.git/*" | sort); do
  # Skip dangling symlinks
  if [ ! -f "$skill_file" ]; then
    continue
  fi
  TOTAL_SKILLS=$((TOTAL_SKILLS + 1))
  
  # Verify YAML frontmatter presence
  has_frontmatter=$(awk 'NR==1 && /^---$/ {found=1} NR>1 && /^---$/ {if (found) {print 1; exit}} END {if (!found) print 0}' "$skill_file")
  if [ "$has_frontmatter" != "1" ]; then
    echo "    ✗ Malformed skill: $skill_file missing valid '---' YAML frontmatter."
    ERRORS=$((ERRORS + 1))
    continue
  fi

  # Check name field
  has_name=$(grep -E '^name:[ \t]+[a-zA-Z0-9_-]+' "$skill_file" || true)
  if [ -z "$has_name" ]; then
    echo "    ✗ Malformed skill: $skill_file missing 'name:' field in frontmatter."
    ERRORS=$((ERRORS + 1))
  fi

  # Check description field
  has_desc=$(grep -E '^description:' "$skill_file" || true)
  if [ -z "$has_desc" ]; then
    echo "    ✗ Malformed skill: $skill_file missing 'description:' field in frontmatter."
    ERRORS=$((ERRORS + 1))
  fi

  # Check for unmigrated skyloom mentions in description
  if grep -i "skyloom" "$skill_file" | grep -v -i "alias" >/dev/null 2>&1; then
    echo "    ✗ Stale skill: $skill_file contains unmigrated references to 'skyloom' (use seambus / agent-bus)."
    ERRORS=$((ERRORS + 1))
  fi
done

if [ "$ERRORS" -gt 0 ]; then
  echo "    ✗ Skills audit failed with $ERRORS error(s)."
  exit 1
fi

echo "    ✓ Audited $TOTAL_SKILLS modular skills. All frontmatters, trigger descriptions, and protocol names are fresh."
exit 0
