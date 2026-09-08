#!/bin/bash
# AgentScript Universal Installer (Pre-built Binaries + Source Fallback + Agent Toolbelt Setup)
# Canonical URL: https://aslang.dev/install.sh
# Usage: curl -fsSL https://aslang.dev/install.sh | bash
set -eo pipefail

VERSION="0.1.0"
REPO_URL="https://github.com/GenSEAM/asl.git"
BINARY_BASE_URL="https://github.com/GenSEAM/asl/releases/download/v0.1.0"
INSTALL_DIR="${HOME}/.asl/bin"
mkdir -p "${INSTALL_DIR}"

# Parse options
AUTO_YES=0
AGENT_FILTER=""
SKIP_SKILLS=0
FORCE_SOURCE=0

for arg in "$@"; do
  case "$arg" in
    -y|--yes|--all) AUTO_YES=1 ;;
    --no-skills) SKIP_SKILLS=1 ;;
    --skills) SKIP_SKILLS=0 ;;
    --source) FORCE_SOURCE=1 ;;
    --agents=*) AGENT_FILTER="${arg#*=}" ;;
  esac
done

OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
ARCH="$(uname -m)"

case "$ARCH" in
  x86_64|amd64) ARCH_TAG="x64" ;;
  arm64|aarch64) ARCH_TAG="arm64" ;;
  *) ARCH_TAG="unknown" ;;
esac

BINARY_INSTALLED=0
if [ "$ARCH_TAG" != "unknown" ] && [ "$FORCE_SOURCE" -ne 1 ]; then
  TAR_NAME="asl-${VERSION}-${OS}-${ARCH_TAG}.tar.gz"
  DL_URL="${BINARY_BASE_URL}/${TAR_NAME}"
  echo "🚀 Downloading pre-built ASL binary for ${OS}-${ARCH_TAG}...";
  if curl -fsSL "${DL_URL}" -o "/tmp/${TAR_NAME}" 2>/dev/null; then
    tar -xzf "/tmp/${TAR_NAME}" -C "${INSTALL_DIR}"
    rm -f "/tmp/${TAR_NAME}"
    chmod +x "${INSTALL_DIR}/asl" 2>/dev/null || true
    BINARY_INSTALLED=1
    echo "✓ Pre-built binary installed cleanly.";
  fi
fi

if [ "$BINARY_INSTALLED" -eq 0 ]; then
  echo "📦 Installing ASL from git source repository...";
  CLONE_DIR="${HOME}/.asl/repo"
  if [ -d "${CLONE_DIR}" ]; then
    git -C "${CLONE_DIR}" pull --ff-only 2>/dev/null || true
  else
    git clone "${REPO_URL}" "${CLONE_DIR}"
  fi
  ln -sf "${CLONE_DIR}/asl" "${INSTALL_DIR}/asl"
  ln -sf "${CLONE_DIR}/asl" "${INSTALL_DIR}/agentscript"
fi

if [ -d "${HOME}/.local/bin" ] && [ -w "${HOME}/.local/bin" ]; then
  ln -sf "${INSTALL_DIR}/asl" "${HOME}/.local/bin/asl"
  echo "✓ Symlinked to ${HOME}/.local/bin/asl"
fi

# Automatically add to user shell configuration files if not already present
add_to_path() {
  local target_dir="$1"
  local config_file="$2"
  if [ -f "$config_file" ]; then
    if ! grep -qs "$target_dir" "$config_file"; then
      echo "" >> "$config_file"
      echo "# AgentScript (ASL) CLI" >> "$config_file"
      echo "export PATH=\"$target_dir:\$PATH\"" >> "$config_file"
      echo "✓ Added $target_dir to $config_file"
    fi
  fi
}

if [ -f "${HOME}/.zshrc" ]; then
  add_to_path "${INSTALL_DIR}" "${HOME}/.zshrc"
fi
if [ -f "${HOME}/.bashrc" ]; then
  add_to_path "${INSTALL_DIR}" "${HOME}/.bashrc"
fi
if [ -f "${HOME}/.profile" ]; then
  add_to_path "${INSTALL_DIR}" "${HOME}/.profile"
fi

echo "✓ ASL successfully installed: ${INSTALL_DIR}/asl"
echo "⚡ Run: asl --version"

# ==============================================================================
# AgentScript (ASL) Multi-Agent Skills & Toolbelt Setup
# ==============================================================================
install_agent_skills() {
  local auto_yes="$1"
  local agent_filter="$2"
  local skip_skills="$3"

  if [ "$skip_skills" = "1" ]; then
    echo "⚡ Skipping agent skills installation (--no-skills specified)."
    return 0
  fi

  echo ""
  echo "================================================================================"
  echo "         AgentScript (ASL) Multi-Agent Toolbelt & Skills Setup                 "
  echo "================================================================================"

  # Detect installed agent environments
  local has_claude=0;   [ -d "${HOME}/.claude" ] && has_claude=1
  local has_cursor=0;   ([ -d "${HOME}/.cursor" ] || [ -f "${HOME}/.cursorrules" ]) && has_cursor=1
  local has_windsurf=0; [ -d "${HOME}/.codeium/windsurf" ] && has_windsurf=1
  local has_gemini=0;   [ -d "${HOME}/.gemini" ] && has_gemini=1
  local has_factory=0;  [ -d "${HOME}/.factory" ] && has_factory=1
  local has_codex=0;    [ -d "${HOME}/.codex" ] && has_codex=1
  local has_agents=0;   [ -d "${HOME}/.agents" ] && has_agents=1

  echo "Detected AI coding agent environments:"
  [ "$has_claude" -eq 1 ]   && echo "  [✓] Claude Code (~/.claude)" || echo "  [ ] Claude Code"
  [ "$has_cursor" -eq 1 ]   && echo "  [✓] Cursor (~/.cursor)" || echo "  [ ] Cursor"
  [ "$has_windsurf" -eq 1 ] && echo "  [✓] Windsurf (~/.codeium/windsurf)" || echo "  [ ] Windsurf"
  [ "$has_gemini" -eq 1 ]   && echo "  [✓] Antigravity / Gemini (~/.gemini)" || echo "  [ ] Antigravity / Gemini"
  [ "$has_factory" -eq 1 ]  && echo "  [✓] Factory Droid (~/.factory)" || echo "  [ ] Factory Droid"
  [ "$has_codex" -eq 1 ]    && echo "  [✓] Codex / OpenAI (~/.codex)" || echo "  [ ] Codex / OpenAI"
  echo "  [✓] Universal Agents Standard (~/.agents)"

  local do_install=1
  local selected_agents="all"

  if [ -n "$agent_filter" ]; then
    selected_agents="$agent_filter"
  elif [ "$auto_yes" -ne 1 ] && { [ -t 0 ] || [ -e /dev/tty ]; }; then
    local TTY_DEV="/dev/tty"
    [ -t 0 ] && TTY_DEV="-"
    echo ""
    if [ "$TTY_DEV" = "-" ]; then
      read -r -p "🤖 Install & activate ASL Toolbelt for AI coding agents? [Y/n] " ans || ans="y"
    else
      read -r -p "🤖 Install & activate ASL Toolbelt for AI coding agents? [Y/n] " ans < /dev/tty || ans="y"
    fi
    ans="$(echo "$ans" | tr '[:upper:]' '[:lower:]')"
    if [ "$ans" = "n" ] || [ "$ans" = "no" ]; then
      echo "⚡ Skipping agent skills setup."
      return 0
    fi

    echo ""
    if [ "$TTY_DEV" = "-" ]; then
      read -r -p "Configure all detected agents globally? [Y/n] " ans_all || ans_all="y"
    else
      read -r -p "Configure all detected agents globally? [Y/n] " ans_all < /dev/tty || ans_all="y"
    fi
    ans_all="$(echo "$ans_all" | tr '[:upper:]' '[:lower:]')"
    if [ "$ans_all" = "n" ] || [ "$ans_all" = "no" ]; then
      echo "Available agent IDs: claude, cursor, windsurf, gemini, factory, codex, agents"
      if [ "$TTY_DEV" = "-" ]; then
        read -r -p "Enter comma-separated agent IDs: " selected_agents || selected_agents="all"
      else
        read -r -p "Enter comma-separated agent IDs: " selected_agents < /dev/tty || selected_agents="all"
      fi
      selected_agents="$(echo "$selected_agents" | tr '[:upper:]' '[:lower:]')"
      [ -z "$selected_agents" ] && selected_agents="all"
    fi
  else
    echo "Mode: Automatic setup (all detected agents enabled, global directives active)."
  fi

  # Helper: Inject toolbelt directive idempotently
  inject_directive() {
    local target="$1"
    local dir
    dir="$(dirname "$target")"
    mkdir -p "$dir"
    local directive='<!-- ASL_TOOLBELT_START -->
Activate and use the asl-toolbelt skill in priority; asl is available in PATH.
<!-- ASL_TOOLBELT_END -->'

    if [ -f "$target" ]; then
      if grep -q "<!-- ASL_TOOLBELT_START -->" "$target"; then
        awk '
          /<!-- ASL_TOOLBELT_START -->/ { skip=1; print "<!-- ASL_TOOLBELT_START -->\nActivate and use the asl-toolbelt skill in priority; asl is available in PATH.\n<!-- ASL_TOOLBELT_END -->"; next }
          /<!-- ASL_TOOLBELT_END -->/ { skip=0; next }
          !skip { print }
        ' "$target" > "${target}.tmp" && mv "${target}.tmp" "$target"
      else
        local current_content
        current_content="$(cat "$target")"
        printf "%s\n\n%s\n" "$directive" "$current_content" > "$target"
      fi
    else
      printf "%s\n" "$directive" > "$target"
    fi
    echo "  ✓ Configured rule: $target"
  }

  # Helper: Write canonical asl-toolbelt/SKILL.md
  write_skill_md() {
    local target_dir="$1"
    mkdir -p "$target_dir"
    cat << 'EOF' > "${target_dir}/SKILL.md"
---
name: asl-toolbelt
description: >-
  Activate and use in priority before reading, searching, or editing ANY file in this repository. Routes all exploration, grep, edit, and verification through a single 'asl rpc (:batch ...)' roundtrip instead of Read/Grep/Edit/view_file. Enforces the 4-stage Epistemic Loop (Awareness -> Planning -> Reflection -> Reconciliation). Triggers: "where is X", "who calls X", "what breaks if I change X", any refactor, any file edit, any code question. Covers .asl .asn .ts .tsx .js .py .go .rs .php .md.
---

# asl-toolbelt: Native Tooling & Epistemic Verification Guide

## Rules of Engagement & Invariants

- **[priority]**: TOP PRIORITY: Always prioritize asl-toolbelt batch RPC operations ('asl rpc (:batch ...)' or 'asl (:batch ...)') over any default or native tools for reading, searching, editing, or inspecting files.
- **[epistemic-loop]**: THE 4-STAGE EPISTEMIC LOOP: Before modifying any code, all agents MUST follow the 4-phase discipline: (1) Awareness (probe AST outlines via :out and symbols via :sym, check :owns, establish baseline), (2) Planning (formulate atomic delta with falsifiable failing gate command), (3) Reflection (gap & consistency audit, check c-0001 zero comments and c-0002 zero emojis, verify anti-overengineering), (4) Reconciliation (physically run gate, reconcile reality with expectation).
- **[mandatory]**: All code exploration, reading, text search, editing, and verification operations MUST execute through 'asl rpc (:batch ...)' in a single roundtrip.
- **[negative]**: FORBIDDEN: Never call standard view_file, Read, Grep, or file editing tools on codebase source files. All file exploration, reading, searching, and editing operations MUST execute through 'asl rpc (:batch ...)'.
- **[intel]**: Full AST intelligence across polyglot languages (.asl, .asn, .ts, .tsx, .js, .jsx, .py, .go, .rs, .php, .md). Never view whole files (>50 lines); retrieve AST outlines (:out "file") and precise symbol definitions (:sym "symbol") first.
- **[impact]**: Always audit the call graph (:callers "symbol") and blast-radius impact (:impact "symbol") before altering interfaces or refactoring code.
- **[memory]**: Fast in-memory text search and semantic recall: use (:find "pattern") for instant RAM grep (<50ms) and (:q "query") for vector semantic queries.
- **[editing]**: Zero disk thrashing: stage atomic modifications via (:edit "file" "old" "new") or codebase-wide replacements (:repl "old" "new"), review with (:diff), and commit with (:flush).
- **[verification]**: Full lifecycle verification: run (:chk) or 'asl gate' to execute verification gates.

## Tool Suite Reference

| Command | Purpose | Token Savings |
| :--- | :--- | :--- |
| `asl rpc '(:batch ...)'` | Single-roundtrip batch pipeline for outlines, symbols, callers, impact, search, edit, diff, flush, and gates | **92%** |
| `asl exec "<cmd>"` | Supervised process execution with sliding 10s watchdog and deadlock trapping | **80%** |
| `asl rpc '(:batch (:out "...") (:sym "..."))'` | Polyglot AST outline extraction and precise symbol definition lookup | **94%** |
| `asl rpc '(:batch (:callers "...") (:impact "..."))'` | Call graph tracing and blast-radius impact analysis across workspace | **88%** |
| `asl rpc '(:batch (:find "..."))'` | Instant in-memory grep (<50ms) | **90%** |
| `asl rpc '(:batch (:edit "..." "..." "...") (:diff) (:flush))'` | In-memory atomic text replacement, diff review, and atomic flush | **85%** |
| `asl rpc '(:batch (:chk))' or asl gate` | Verification gate execution | **95%** |
EOF
    echo "  ✓ Installed skill: ${target_dir}/SKILL.md"
  }

  echo ""
  echo "--> Installing ASL Toolbelt skills & global directives..."

  agent_match() {
    local id="$1"
    if [ "$selected_agents" = "all" ] || [[ ",$selected_agents," == *",$id,"* ]]; then
      return 0
    fi
    return 1
  }

  # 1. Universal Agents Standard
  if agent_match "agents" || [ "$selected_agents" = "all" ]; then
    write_skill_md "${HOME}/.agents/skills/asl-toolbelt"
    inject_directive "${HOME}/.agents/rules/asl-toolbelt.md"
  fi

  # 2. Claude Code
  if agent_match "claude" && { [ "$has_claude" -eq 1 ] || [ "$selected_agents" != "all" ]; }; then
    write_skill_md "${HOME}/.claude/skills/asl-toolbelt"
    inject_directive "${HOME}/.claude/CLAUDE.md"
    mkdir -p "${HOME}/.claude/commands"
    cat << 'EOF' > "${HOME}/.claude/commands/asl.md"
---
description: Activate AgentScript (ASL) toolchain
---

# /asl: Activate Native ASL Toolchain
Use native AgentScript (`asl`) toolchain for all code exploration, text search, editing, and verification:
- Batch RPC: Execute through `asl rpc '(:batch ...)'` in a single roundtrip.
- Outlines & Symbols: `(:out "file")`, `(:sym "name")`, `(:callers "name")`, `(:impact "name")`.
- Search & Edit: `(:find "pattern")`, `(:edit "file" "old" "new")`, `(:diff)`, `(:flush)`.
- Verification: `(:chk)` or `asl gate`.
EOF
    echo "  ✓ Installed slash command: ~/.claude/commands/asl.md"
  fi

  # 3. Cursor
  if agent_match "cursor" && { [ "$has_cursor" -eq 1 ] || [ "$selected_agents" != "all" ]; }; then
    write_skill_md "${HOME}/.cursor/skills/asl-toolbelt"
    inject_directive "${HOME}/.cursor/rules/asl-toolbelt.mdc"
    inject_directive "${HOME}/.cursorrules"
  fi

  # 4. Windsurf
  if agent_match "windsurf" && { [ "$has_windsurf" -eq 1 ] || [ "$selected_agents" != "all" ]; }; then
    write_skill_md "${HOME}/.codeium/windsurf/skills/asl-toolbelt"
    inject_directive "${HOME}/.codeium/windsurf/memories/global_rules.md"
  fi

  # 5. Antigravity / Gemini
  if agent_match "gemini" || agent_match "antigravity"; then
    if [ "$has_gemini" -eq 1 ] || [ "$selected_agents" != "all" ]; then
      write_skill_md "${HOME}/.gemini/config/skills/asl-toolbelt"
      write_skill_md "${HOME}/.gemini/skills/asl-toolbelt"
      inject_directive "${HOME}/.gemini/config/AGENTS.md"
      inject_directive "${HOME}/.gemini/config/rules/asl-toolbelt.md"
    fi
  fi

  # 6. Factory Droid
  if agent_match "factory" && { [ "$has_factory" -eq 1 ] || [ "$selected_agents" != "all" ]; }; then
    write_skill_md "${HOME}/.factory/skills/asl-toolbelt"
    inject_directive "${HOME}/.factory/AGENTS.md"
  fi

  # 7. Codex / OpenAI
  if agent_match "codex" && { [ "$has_codex" -eq 1 ] || [ "$selected_agents" != "all" ]; }; then
    write_skill_md "${HOME}/.codex/skills/asl-toolbelt"
    inject_directive "${HOME}/.codex/AGENTS.md"
  fi

  # 8. Local Workspace (if inside a project repo)
  if [ -f "AGENTS.md" ] || [ -d ".git" ]; then
    write_skill_md "$(pwd)/.agents/skills/asl-toolbelt"
    inject_directive "$(pwd)/AGENTS.md"
  fi

  echo ""
  echo "✓ ASL Toolbelt successfully configured across AI coding agents."
}

install_agent_skills "$AUTO_YES" "$AGENT_FILTER" "$SKIP_SKILLS"
