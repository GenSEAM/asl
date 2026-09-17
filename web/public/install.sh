#!/bin/bash
# AgentScript Universal Installer (Pre-built Binaries + Source Fallback + Agent Toolbelt Setup)
# Canonical URL: https://aslang.dev/install.sh
# Usage: curl -fsSL https://aslang.dev/install.sh | bash
set -eo pipefail

RULES_ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ---- rules single source of truth: asl/grammar/rules.asn -> every exported surface ----
rules_main() {
  local MODE="$1"
  local RULES_SRC="$RULES_ROOT/asl/grammar/rules.asn"
  [ -f "$RULES_SRC" ] || { echo "missing $RULES_SRC" >&2; exit 2; }
  SRC="$RULES_SRC"
  S="<!-- ASL_RULES_START -->"; E="<!-- ASL_RULES_END -->"
  src_sum() { shasum < "$RULES_SRC" | cut -d' ' -f1; }
  
  # replace lines strictly between a start-matching line and an end-matching line with the source
  render_between() { # file start_regex end_regex
    local f="$1" sre="$2" ere="$3" tmp
    tmp="$(mktemp)"
    awk -v sre="$sre" -v ere="$ere" -v src="$RULES_SRC" '
      BEGIN { while ((getline l < src) > 0) body = body (n++ ? "\n" : "") l }
      !skip && $0 ~ sre { print; print body; skip=1; next }
      skip && $0 ~ ere { skip=0 }
      !skip { print }
    ' "$f" > "$tmp" && cat "$tmp" > "$f" && rm -f "$tmp"
  }
  extract_between() { # file start_regex end_regex -> stdout
    awk -v sre="$1" -v ere="$2" '
      !skip && $0 ~ sre { skip=1; next }
      skip && $0 ~ ere { exit }
      skip { print }
    ' "$3"
  }
  
  # skill.asn is derived: its :rules [...] section is (:rule :type "<id>" :text "<do> | <why|not|now|bias>") per source rule
  skill_rules() {
    awk '
      function esc(t){ gsub(/\\/,"\\\\",t); gsub(/"/,"\\\"",t); return t }
      /^  \(:rule :id / { if (id!="") flush(); match($0,/:id [A-Za-z]+/); id=substr($0,RSTART+4,RLENGTH-4); d=""; w="" }
      /^    :do "/  { s=$0; sub(/^    :do "/,"",s); sub(/"[)]*$/,"",s); d=s }
      /^    :(why|not|now|bias|defeat) "/ { if (w=="") { s=$0; sub(/^    :(why|not|now|bias|defeat) "/,"",s); sub(/"[)]*$/,"",s); w=s } }
      function flush(){ printf "    (:rule :type \"%s\" :text \"%s%s\")\n", id, esc(d), (w==""?"":" | " esc(w)) }
      END { if (id!="") flush() }
    ' "$RULES_SRC"
  }
  render_skill_asn() { # file
    local f="$1" tmp bodyf; tmp="$(mktemp)"; bodyf="$(mktemp)"; skill_rules > "$bodyf"
    awk -v bodyf="$bodyf" '
      BEGIN { while ((getline l < bodyf) > 0) body = body (n++ ? "\n" : "") l }
      !skip && /^  :rules \[$/ { print; print body; skip=1; next }
      skip && /^  \]$/ { skip=0 }
      !skip { print }
    ' "$f" > "$tmp" && cat "$tmp" > "$f" && rm -f "$tmp" "$bodyf"
  }
  check_skill_asn() { # file -> 0 if identical
    local f="$1"
    [ "$(awk '/^  :rules \[$/{s=1;next} s&&/^  \]$/{exit} s' "$f" | shasum)" = "$(skill_rules | shasum)" ]
  }

  # render_tier: output deterministic tier subset from rules.asn
  render_tier() { # tier_name
    local tier="${1:-full}"
    awk -v target="$tier" '
      BEGIN {
        rank["essential"] = 1
        rank["hot"] = 2
        rank["affordance"] = 2
        rank["orientation"] = 3
        rank["t1"] = 3
        rank["heuristic"] = 4
        rank["t2"] = 4
        rank["pack"] = 5
        rank["full"] = 6
        req = rank[target] ? rank[target] : 6
      }
      function force_rank(f) {
        if (f == ":invariant") return 1
        if (f == ":affordance") return 2
        if (f == ":orientation") return 3
        if (f == ":heuristic") return 4
        return 5
      }
      /^\(:rules/ { print; next }
      /^  \(:rule :id / {
        match($0, /:force :[a-z]+/);
        fc = substr($0, RSTART+7, RLENGTH-7);
        include = (force_rank(fc) <= req)
        if (include) print
        next
      }
      /^  \(:pack / {
        include = (req >= 5)
        if (include) print
        next
      }
      /^\)/ { print; next }
      { if (include) print }
      END { if (req < 6) print ")" }
    ' "$RULES_SRC"
  }
  if [ "$MODE" = "tier" ] || [ "$MODE" = "--tier" ]; then
    render_tier "${2:-essential}"
    exit 0
  fi
  
  # surface table: name|file|start regex|end regex
  SURFACES=(
    "agents-md|$RULES_ROOT/AGENTS.md|^<!-- ASL_RULES_START -->$|^<!-- ASL_RULES_END -->$"
    "skill-md|$RULES_ROOT/.agents/skills/asl-toolbelt/SKILL.md|^\`\`\`asn$|^\`\`\`$"
    "skill-md-asl|$RULES_ROOT/asl/.agents/skills/asl-toolbelt/SKILL.md|^\`\`\`asn$|^\`\`\`$"
    "install-template|$RULES_ROOT/scripts/install.sh|^\`\`\`asn$|^\`\`\`$"
    "install-directive|$RULES_ROOT/scripts/install.sh|local directive='<!-- ASL_RULES_START -->$|^<!-- ASL_RULES_END -->'$"
  )
  HOME_SURFACES=(
    "$HOME/.agents/rules/asl-toolbelt.md|^<!-- ASL_RULES_START -->$|^<!-- ASL_RULES_END -->$"
  )
  
  rc=0
  for row in "${SURFACES[@]}"; do
    IFS='|' read -r name f sre ere <<< "$row"
    [ -f "$f" ] || { echo "  skip $name (missing $f)"; continue; }
    if [ "$MODE" = "--check" ]; then
      got="$(extract_between "$sre" "$ere" "$f" | shasum | cut -d' ' -f1)"
      if [ "$got" = "$(src_sum)" ]; then echo "  ok   $name"; else echo "  DRIFT $name ($f)"; rc=1; fi
    else
      render_between "$f" "$sre" "$ere"; echo "  rendered $name"
    fi
  done
  for f in "$RULES_ROOT/.agents/skills/asl-toolbelt/skill.asn" "$RULES_ROOT/asl/.agents/skills/asl-toolbelt/skill.asn"; do
    [ -f "$f" ] || continue
    if [ "$MODE" = "--check" ]; then
      if check_skill_asn "$f"; then echo "  ok   skill-asn ($f)"; else echo "  DRIFT skill-asn ($f)"; rc=1; fi
    else render_skill_asn "$f"; echo "  rendered skill-asn ($f)"; fi
  done
  if [ "$MODE" = "--home" ] || [ "$MODE" = "render" ]; then
    for row in "${HOME_SURFACES[@]}"; do
      IFS='|' read -r f sre ere <<< "$row"; [ -f "$f" ] && { render_between "$f" "$sre" "$ere"; echo "  rendered $f"; }
    done
    for d in "$HOME/.agents/skills" "$HOME/.claude/skills" "$HOME/.cursor/skills" "$HOME/.codeium/windsurf/skills" "$HOME/.gemini/skills" "$HOME/.gemini/config/skills" "$HOME/.factory/skills" "$HOME/.codex/skills" "$HOME/.eddie/skills" "$HOME/.addie/skills" "$HOME/.gemini/config/plugins/toolbelt/skills" "$HOME/.gemini/config/plugins/toolbelt/harnesses/antigravity/skills"; do
      for s in "$RULES_ROOT/.agents/skills"/*; do
        skill_name=$(basename "$s")
        [ -d "$s" ] && [ -f "$s/SKILL.md" ] && mkdir -p "$d/$skill_name" && cp "$s/SKILL.md" "$d/$skill_name/SKILL.md" && echo "  refreshed $d/$skill_name/SKILL.md"
      done
    done
  fi
  [ "$MODE" = "--check" ] && { [ $rc -eq 0 ] && echo "rules: all surfaces identical to $SRC" || echo "rules: drift detected" >&2; }
  
  exit $rc
}

lexicon_main() {
  local MODE="${1:-render}"
  local LEXICON_SRC="${RULES_ROOT}/asl/grammar/lexicon.asn"
  if [ ! -f "$LEXICON_SRC" ]; then
    LEXICON_SRC="asl/grammar/lexicon.asn"
  fi
  if [ ! -f "$LEXICON_SRC" ]; then
    echo "lexicon: source not found at $LEXICON_SRC" >&2
    exit 1
  fi

  if [ "$MODE" = "--check" ]; then
    local err=0
    if ! grep -q ":canonical \"harness\"" "$LEXICON_SRC"; then
      echo "lexicon: divergence - harness canonical missing from $LEXICON_SRC" >&2
      err=1
    fi
    local local_tables
    local_tables=$(find voice harness asl -name "*alias_table*.asl" 2>/dev/null || true)
    if [ -n "$local_tables" ]; then
      echo "lexicon: forbidden local alias table found: $local_tables" >&2
      err=1
    fi
    local bad_artifacts
    bad_artifacts=$(find voice harness asl -name "*hyness*.asl" 2>/dev/null || true)
    if [ -n "$bad_artifacts" ]; then
      echo "lexicon: spoken form artifact name found: $bad_artifacts" >&2
      err=1
    fi
    for term in "harness" "asex" "shrody" "pcp"; do
      if ! grep -rq "$term" asl/packages voice harness 2>/dev/null; then
        echo "lexicon: canonical term '$term' has no referents in repository" >&2
        err=1
      fi
    done
    if [ $err -ne 0 ]; then
      exit 1
    fi
    echo "lexicon: verified single source $LEXICON_SRC (0 orphan aliases, 0 local tables, 0 mishearings)"
    exit 0
  else
    echo "lexicon: rendered from $LEXICON_SRC"
    exit 0
  fi
}

case "${1:-}" in
  --tier)             rules_main tier "${2:-essential}" ;;
  --render-rules)     rules_main render ;;
  --check-rules)      rules_main --check ;;
  --render-home)      rules_main --home ;;
  --render-lexicon)   lexicon_main render ;;
  --check-lexicon)    lexicon_main --check ;;
  --check-installers)
    ROOT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    SRC="$ROOT_DIR/scripts/install.sh"
    ERR=0
    for target in "$ROOT_DIR/asl/dist/install.sh" "$ROOT_DIR/asl/web/dist/install.sh" "$ROOT_DIR/asl/web/public/install.sh"; do
      if [ -f "$target" ]; then
        if ! cmp -s "$SRC" "$target"; then
          echo "installers: drift detected in $target (not byte-identical to $SRC)" >&2
          ERR=1
        fi
      fi
    done
    NESTED=$(find "$ROOT_DIR" -path "*/dist/dist*" 2>/dev/null || true)
    if [ -n "$NESTED" ]; then
      echo "installers: nested dist directory detected: $NESTED" >&2
      ERR=1
    fi
    if [ $ERR -ne 0 ]; then
      exit 1
    fi
    echo "installers: verified single tracked installer and byte-identical distribution copies"
    exit 0
    ;;
esac

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

if [[ "$OS" == *"mingw"* || "$OS" == *"cygwin"* || "$OS" == *"msys"* || "$OS" == "windows_nt" ]]; then
  echo "Windows environment detected via $OS. Delegating to PowerShell installer..."
  PS1_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)/install.ps1"
  if [ -f "$PS1_SCRIPT" ]; then
    powershell.exe -ExecutionPolicy Bypass -File "$PS1_SCRIPT" || powershell -ExecutionPolicy Bypass -File "$PS1_SCRIPT"
    exit $?
  else
    powershell.exe -ExecutionPolicy Bypass -Command "irm https://aslang.dev/install.ps1 | iex"
    exit $?
  fi
fi

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
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
  LOCAL_ASL="$(cd "$SCRIPT_DIR/.." 2>/dev/null && pwd)/asl/asl"
  LOCAL_ENGINE="$(cd "$SCRIPT_DIR/.." 2>/dev/null && pwd)/asl/bin/asl-engine"
  LOCAL_SRC="$(cd "$SCRIPT_DIR/.." 2>/dev/null && pwd)/engine/asl.c"
  LOCAL_BOOTSTRAP="$(cd "$SCRIPT_DIR/.." 2>/dev/null && pwd)/bootstrap.c"
  LOCAL_INC="$(cd "$SCRIPT_DIR/.." 2>/dev/null && pwd)/engine"
  if [ -f "$LOCAL_BOOTSTRAP" ] && command -v clang >/dev/null 2>&1; then
    echo "📦 Compiling and installing self-hosted ASL from bootstrap.c...";
    if clang -std=c99 -O3 -I "$LOCAL_INC" "$LOCAL_BOOTSTRAP" -o "${INSTALL_DIR}/asl" && "${INSTALL_DIR}/asl" --version >/dev/null 2>&1; then
      chmod +x "${INSTALL_DIR}/asl"
      ln -sf "${INSTALL_DIR}/asl" "${INSTALL_DIR}/agentscript"
      cp -f "${INSTALL_DIR}/asl" "$LOCAL_ASL" 2>/dev/null || true
      BINARY_INSTALLED=1
    fi
  fi
  if [ "$BINARY_INSTALLED" -eq 0 ] && [ -f "$LOCAL_SRC" ] && command -v clang >/dev/null 2>&1; then
    echo "Warning: the self-hosted bootstrap.c path did not produce a working binary; falling back to the JavaScriptCore host build." >&2
    echo "📦 Compiling and installing ASL with embedded source digest...";
    DIGEST=$(shasum -a 256 "$LOCAL_SRC" 2>/dev/null | awk '{print substr($1,1,16)}' || echo "unknown")
    clang -O2 -DASL_SOURCE_DIGEST="\"$DIGEST\"" -framework JavaScriptCore "$LOCAL_SRC" -o "${INSTALL_DIR}/asl"
    chmod +x "${INSTALL_DIR}/asl"
    ln -sf "${INSTALL_DIR}/asl" "${INSTALL_DIR}/agentscript"
    cp -f "${INSTALL_DIR}/asl" "$LOCAL_ASL" 2>/dev/null || true
  elif [ "$BINARY_INSTALLED" -eq 0 ] && [ -f "$LOCAL_ASL" ]; then
    echo "📦 Installing ASL from local workspace: $LOCAL_ASL...";
    ln -sf "$LOCAL_ASL" "${INSTALL_DIR}/asl"
    ln -sf "$LOCAL_ASL" "${INSTALL_DIR}/agentscript"
    if [ -f "$LOCAL_ENGINE" ]; then
      ln -sf "$LOCAL_ENGINE" "${INSTALL_DIR}/asl-engine"
      chmod +x "${INSTALL_DIR}/asl-engine" 2>/dev/null || true
    fi
  else
    echo "📦 Installing ASL from git source repository...";
    CLONE_DIR="${HOME}/.asl/repo"
    if [ -d "${CLONE_DIR}" ]; then
      git -C "${CLONE_DIR}" pull --ff-only 2>/dev/null || true
    else
      git clone "${REPO_URL}" "${CLONE_DIR}"
    fi
    ln -sf "${CLONE_DIR}/asl/asl" "${INSTALL_DIR}/asl"
    ln -sf "${CLONE_DIR}/asl/asl" "${INSTALL_DIR}/agentscript"
    if [ -f "${CLONE_DIR}/asl/bin/asl-engine" ]; then
      ln -sf "${CLONE_DIR}/asl/bin/asl-engine" "${INSTALL_DIR}/asl-engine"
      chmod +x "${INSTALL_DIR}/asl-engine" 2>/dev/null || true
    fi
  fi
fi

if [ -d "${HOME}/.local/bin" ] && [ -w "${HOME}/.local/bin" ]; then
  ln -sf "${INSTALL_DIR}/asl" "${HOME}/.local/bin/asl"
  ln -sf "${INSTALL_DIR}/agentscript" "${HOME}/.local/bin/agentscript"
  if [ -f "${INSTALL_DIR}/asl-engine" ]; then
    ln -sf "${INSTALL_DIR}/asl-engine" "${HOME}/.local/bin/asl-engine"
  fi
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
    local directive='<!-- ASL_RULES_START -->
(:rules :v 9 :src ADR0081 :shortcode D81 :tiers [:essential :hot :affordance :orientation :heuristic :pack :full] :when [:scout :plan :implement :grade :all]
  (:rule :id teleology :force :invariant :tier [:essential :full] :when [:all]
    :do "teleological value hierarchy: (V0 > V1 > V2 > V3 > V4 > V5 > V6); V0 human sovereignty (override requires signed confirmation; restricted to irreversible operations), V1 invariant preservation (:owns, delimiter balance, executed writes only), V2 contractual intent fidelity, V3 evidence-backed falsifiability, V4 minimal causal surface, V5 lexical SNR, V6 velocity; anti-Goodhart: proxy metrics never override ground truth"
    :check "./bin/asl audit consistency"
    :gate "./bin/asl audit consistency"
    :why "explicit lexicographic value dominance ensures safety and boundary invariants strictly dominate speed and prompt compliance; when intent conflicts with invariants, the agent escalates")
  (:rule :id semantics :force :invariant :tier [:essential :full] :when [:implement :grade]
    :do "imports bind; an unknown symbol is an error; zero truthiness; a test returning non-true fails; runner-measured executed assertions must be strictly positive (assertCount > 0); unhandled exceptions in gate scope count as failure; exception swallowing or vacuous assert(true) is a critical defect"
    :check "./bin/asl audit gates"
    :gate "./bin/asl audit gates"
    :why "syntactic green without executed assertions is vacuous pass fraud; verified status requires strictly positive assertion counts and sealed symbol bindings")
  (:rule :id gates :force :invariant :tier [:essential :full] :when [:plan :implement :grade]
    :do "three-point red-green causality: gate(discard) = FAIL, gate(apply) = PASS, gate(revert) = FAIL; baseline failure must be semantic to the claim predicate, not a mechanical missing file; gate hash is pinned at red state; production code mutation must prove fault detection by killing at least one mutant; report exit code, executed asserts, and killed mutants"
    :check "./bin/asl audit gates"
    :gate "./bin/asl audit gates"
    :why "a gate that does not fail on revert or fails to kill production mutants is causally disconnected from the diff and cannot alter epistemic state")
  (:rule :id triMap :force :invariant :tier [:essential :full] :when [:plan :implement :grade]
    :do "Popperian Tri-Map Reconciliation: closed S-Map (intent atoms), F-Map (falsification gates), and B-Map (diff hunks); zero omissions (all S atoms caused by B hunks), zero speculative bloat (all B hunks justified by S atoms), total falsification coverage (every S atom refutable by an F gate); empirical claims enter only with registered measurable definitions and F gates"
    :check "./bin/asl audit consistency"
    :gate "./bin/asl audit consistency"
    :why "tri-map bijection guarantees that prompt intent is completely satisfied without speculative drift or dropped requirements")
  (:rule :id grading :force :invariant :tier [:essential :full] :when [:grade]
    :do "the writer never grades its own work; an independent reviewer executes gates in a hermetic clean context (disjoint context hash, ephemeral sandbox, network denied, deterministic seed); grader-owned acceptance tests and fixtures are strictly read-only and tamper-evident; receipts are runner-issued, signed, and hash-chained"
    :check "sh tests/acceptance/d81/SuperviseGate.sh"
    :gate "sh tests/acceptance/d81/SuperviseGate.sh"
    :why "self-grading and shared context produce self-preference bias; hermetic separation ensures evaluation reflects ground reality")
  (:rule :id astAddressing :force :invariant :tier [:essential :full] :when [:implement :grade]
    :do "Zero-Line-Number Invariant: all code locations, diffs, patches, and receipts are addressed exclusively by path and symbol anchor (:file ?f :symbol ?s :anchor ?a); integer line numbers are strictly forbidden in commands and receipts; edits are idempotent AST splices or content-hash anchored replacements"
    :check "./bin/asl check"
    :gate "./bin/asl check"
    :why "integer line numbers are ephemeral artifacts that drift across edits and invalidate concurrent or rebased patches")
  (:rule :id ramTxn :force :invariant :tier [:essential :full] :when [:implement]
    :do "step is a transaction with declared :owns write set and closing gate; all modifications staged in virtual RAM VFS buffers (:edit -> :diff -> :flush | :discard); flush is atomic with temporary file fsync and rename; process-tree write-set closure strictly contained within :owns; un-staged raw disk writes forbidden; advance only with runner-issued receipt"
    :check "./bin/asl audit steps"
    :gate "./bin/asl audit steps"
    :why "RAM VFS staging prevents workspace corruption during failed attempts and guarantees atomic rollbacks")
  (:rule :id foreign :force :invariant :tier [:essential :full] :when [:implement]
    :do "ASL-first policy: packages contain 100% pure ASL; C host at asl/tools is declared boundary; in foreign target codebases (C, Python, TypeScript, Rust, Go), agents reason in-memory using ASL/ASN action DAGs and lower operations to native diffs with round-trip determinism (project(parse(project(ast))) = project(ast)); zero raw string-blasting"
    :check "./bin/asl audit foreign"
    :gate "./bin/asl audit foreign"
    :why "intermediate representation decouples language-agnostic reasoning from target syntax mechanics, guaranteeing reversibility and formal traceability")
  (:rule :id limitCycle :force :invariant :tier [:essential :full] :when [:all]
    :do "dynamic witness circuit breaker: repeated failure signatures (hash of error class, gate id, hunk digest) capped at 3; three identical failures trip the breaker, halting execution and emitting a structured :witness record; forces basin transition (:build -> :scout or :build -> :plan) or V0 escalation; retries require a distinct causal hypothesis"
    :check "./bin/asl doctor"
    :gate "./bin/asl doctor"
    :why "prevents infinite apology loops and token-burning thrash by turning repeated failure into an explicit phase boundary")
  (:rule :id inMemoryAsl :force :affordance :tier [:affordance :full] :when [:scout :plan :implement]
    :do "in foreign codebases (Python, TypeScript, Rust, Go, C), agents reason in-memory using ASL/ASN action DAGs and typed scratchpads, then lower verified operations to native target diffs"
    :check "./bin/asl check"
    :why "intermediate representation decouples language-agnostic reasoning from target syntax mechanics, guaranteeing reversibility and formal traceability")
  (:rule :id tools :force :affordance :tier [:affordance :full] :when [:scout :implement]
    :do "use ordinary asl invocation with ASN notation as the primary surface; embed scripts, program forms, executable descriptors, code, and tool calls in one validated ASN script; batch independent forms inside that script when useful; RPC is a deprecated compatibility adapter only"
    :check "./bin/asl check"
    :why "ordinary ASN execution is the sole canonical operational surface; valid operations return typed ASN receipts with path and anchor, preventing unvalidated shell execution")
  (:rule :id note :force :affordance :tier [:affordance :full] :when [:all]
    :do "record working memory via asl note write when holding volatile context, architectural discoveries, or empirical findings that would otherwise be lost across steps; query active observations via asl note query or asl note list to prevent duplicate investigation"
    :check "./bin/asl note list"
    :why "working memory reduces context loss and redundant re-reads; grounded findings are promoted at scope close to tasks or ADRs while transient step notes are retired")
  (:rule :id ssot :force :affordance :tier [:affordance :full] :when [:all]
    :do "rules live in one tracked source, asl/grammar/rules.asn; every exported surface is rendered from it by scripts/install.sh --render-rules and checked by --check-rules; per-client or per-tier editions are checked against their deterministic rendering; editing a rendered surface by hand is a defect"
    :check "./scripts/install.sh --check-rules"
    :why "the same rules existed in seven places and drifted; hand-synchronising them is the maintenance mode that fails")
  (:rule :id capabilities :force :affordance :tier [:affordance :full] :when [:all]
    :do "know what you can do before you try: asl/grammar/capabilities.asn keys every capability by situation (orient find read understand plan change verify recover handoff observe) with a measured :status and a named :fallback; (:where) delivers the slice for the current step; when a capability is :absent or :lies, take its fallback and say so, never present the fallback result as the capability"
    :check "./bin/asl doctor"
    :why "epistemic grounding precedes invocation; active capabilities are verified by physical doctor measurement, unmeasured or absent capabilities execute declared fallback paths")
  (:rule :id output :force :orientation :tier [:orientation :full] :when [:all]
    :do "return typed receipts as ASN with path and symbol/anchor; never specify line numbers (Zero-Line-Number Invariant); reversible formatting and deduplication are fine; never drop evidence or constraints to save tokens; compare end-to-end success and total cost before adopting a compact representation"
    :check :none
    :why "compact tool-result notations lost accuracy on several model and benchmark pairs (Notation Matters, up to 9-14pp); the effect is not uniform, so measure, do not assume")
  (:rule :id anchor :force :orientation :tier [:orientation :full] :when [:all]
    :do "the plan lives in the ledger, not in memory: (:plan) once, (:where) before every mutation and after every gate, act from what it returns"
    :check :none
    :why "compliance odds declined per generated function within a session (OR 0.944, exploratory, 2605.10039); whether re-anchoring restores it is the Task44106 hypothesis")
  (:rule :id edge :force :orientation :tier [:orientation :full] :when [:all]
    :do "when no plan step covers the situation: if the action is unauthorized or cannot be safely contained, escalate at once; otherwise recognize ((:where) has no matching step), preserve optionality (read before write, stage before flush, branch before merge, ask before delete), contain (smallest diff inside :owns), refute (run the cheapest thing that would prove you wrong), escalate ((:escalate :seen :tried :fork :resolves) to the principal)"
    :check :none
    :runtimeOnlyReason "Dynamic unplanned contingency escalation and edge case recognition require live runtime decision branching"
    :bias "declared: reversibility over optimality, evidence over confidence, stated intent over inferred intent"
    :why "no rule set matches edge-case variety; models fill gaps fluently instead of noticing them; the loop ends in a receipt to someone else because self-correction without external signal degrades")
  (:rule :id stake :force :orientation :when [:all] :tier [:orientation :full]
    :do "judge work by whether it holds, not by whether it was instructed; report an off-assignment defect rather than stepping over it; responsibility is to system integrity rather than prompt compliance"
    :check :none)
  (:rule :id adaptive :force :orientation :when [:all] :tier [:orientation :full]
    :do "abandon an approach that is not working rather than pressing harder; the trigger to pivot is the absence of new empirical evidence; stop repeating failed operations with superficial edits"
    :check :none)
  (:rule :id problemSolving :force :orientation :when [:all] :tier [:orientation :full]
    :do "when no plan step covers the situation, reduce the uncertainty to the cheapest check that would prove you wrong and run that first; probe reality before generating speculative implementations"
    :check :none)
  (:rule :id context :force :heuristic :tier [:heuristic :full] :when [:all]
    :do "load by symbol and slice, not by file; keep the invariant prefix byte-stable and append step-scoped context after it; never change tool definitions mid-session"
    :check :none
    :defeat "single-prompt workflows or models with unpenalized full-context caching"
    :why "retrieval beat full-context in AutoExperiment (41.7 vs 36.1; AST retrieval 33.3); cached prefix reads are discounted at model-specific rates; a tool-definition change invalidates the cached prefix")
  (:rule :id names :force :heuristic :tier [:heuristic :full] :when [:implement]
    :do "CamelCase for composite identifiers, structs and tests; precise conventional names; do not shorten a name only to save tokens; domain aliases are allowed when they carry meaning"
    :check :none
    :defeat "domain aliases or external foreign interfaces require exact naming"
    :why "CamelCase measured 44-50% cheaper per long identifier on cl100k, and 3.06% corpus-wide across 888 files on 2026-09-12; alias costs in the lock are context-dependent; semantic names carry meaning the model uses")
  (:rule :id git :force :heuristic :tier [:heuristic :full] :when [:implement]
    :do "concise commits; verify base, diff and log before merge; intended changes only"
    :check :none
    :defeat "atomic bulk initialization or machine-generated lockfile updates"
    :coAuthor (:claude :host :agy false))
  (:rule :id parallel :force :heuristic :tier [:heuristic :full] :when [:plan]
    :do "independent reads and scouts in one wave; one writer per owned partition and serialized conflicting commits; subagents soft 4 hard 6 are defaults, not optima"
    :check :none
    :defeat "tightly coupled sequential mutations across identical files")
  (:rule :id budget :force :heuristic :tier [:heuristic :full] :when [:all]
    :do "run a gate after a provisional six tool calls without one; when (:budget) says :compact true, prefer recoverable observation masking, then (:handoff) and reset; thresholds are set by Task44106"
    :check :none
    :runtimeOnlyReason "Tool call budget and observation compaction depend on dynamic runtime execution trace length and cannot be statically evaluated"
    :defeat "lightweight exploratory loops where checkpoint overhead exceeds context savings"
    :why "instruction-load effects are model-dependent (IFScale); compaction at task boundaries and observation masking both reduced context without measured accuracy loss in their studies")
  (:rule :id bounded :force :heuristic :tier [:scout :implement]
    :do "every read carries :limit and continues with :more; bound the output, not file completeness: a small relevant file may fit the bound"
    :check :none
    :defeat "complete whole-file AST analysis or small schema generation"
    :why "degradation with context length is nonuniform and distractor-sensitive across 18 models (Chroma)")
  (:rule :id tokenEconomics :force :heuristic :tier [:heuristic :full] :when [:all]
    :do "attention density law: redundant tokens dilute Softmax attention mass on invariants; preserve KV cache via byte-stable prefixes, batch independent forms in one turn, address code by symbol slices, use CamelCase for BPE subword efficiency, mask execution logs to typed receipts, and enforce lossless reversibility"
    :check "./bin/asl check"
    :gate "./bin/asl check"
    :why "every noise token reduces attention probability mass on constraints; S-expressions cut 55-75% JSON tax and CamelCase saves 44-50% on BPE identifiers")
  (:rule :id reconstructibility :force :affordance :tier [:affordance :full] :when [:all]
    :do "anything reconstructible from code, git history, or a command is not written to durable memory; reconstructible records are refused and the refusal names the command that reports it; rejected alternatives are accepted because no command reports what was not chosen"
    :check :none
    :why "memory records carry strictly novel non-reconstructible delta; tree status and command outputs are reconstructed on-demand from the substrate to eliminate context bloat")
  (:pack :id design :tier [:pack :full]
    :outcomes ["high visual signal to noise ratio" "typography hierarchy" "responsive layout boundaries" "compact VDOM token density"]
    :failureModes ["decorative gratuitous complexity" "unbounded layout shift" "unresponsive component containers"]
    :affordances ["vdom rendering" "asn vector graphics" "color tokens" "spacing scales"])
  (:pack :id development :tier [:pack :full]
    :outcomes ["monorepo invariant compliance" "delimiter balance" "pure ASL packaging" "atomic git transactions" "AST mutation defense"]
    :failureModes ["accidental foreign dependencies" "unbalanced S-expressions" "staged mutation leakage"]
    :affordances ["asl check" "asl lint" "asl rpc batch" "git transaction boundary"])
  (:pack :id research :tier [:pack :full]
    :outcomes ["grounded measurements with method scope and date" "refutation of proxy metrics" "epistemic uncertainty markers" "empirical ledger tracking"]
    :failureModes ["unsourced numeric claims" "evaluating self-preference" "confusing normative principles with empirical findings"]
    :affordances ["bench telemetry" "token profiling" "direct tokenizer evaluation" "principles ledger"])
  (:pack :id multilensAudit :tier [:pack :full]
    :outcomes ["dual-polarity refutation verification" "anti-falsification dynamic roundtripping" "genuine artifact parsing without mocking" "edge-case coverage verification"]
    :failureModes ["static string mocking" "vacuous positive assertions without refutes" "evaluating self-preference"]
    :affordances ["multilens roundtrip validation" "strict falsify harness" "receipt validation"])
  (:pack :id architecture :tier [:pack :full]
    :outcomes ["minimal causal surface" "bounded dependency DAG" "host interface independence" "polymorphic storage hierarchy" "circuit breaker limit cycles"]
    :failureModes ["premature universalism" "unbounded coupling" "hidden ecosystem dependencies" "infinite oscillation cycles"]
    :affordances ["asl audit consistency" "asl audit foreign" "storage engine switch" "circuit breaker escalation"])
  (:pack :id cognitiveSlm :tier [:pack :full]
    :outcomes ["sub-100ms cold start" "unified memory footprint <=24MB" "progressive disclosure bounded retrieval" "thinking-vs-exec budget arbitrage"]
    :failureModes ["unbounded context explosion" "redundant full-file reads" "uncalibrated inference loops"]
    :affordances ["asl mem query" "asl mem tree" "asl-slm telemetry" "observation masking"]))

<!-- ASL_RULES_END -->'

    if [ -f "$target" ]; then
      awk '
        /<!-- ASL_RULES_START -->/ || /<!-- ASL_TOOLBELT_START -->/ || /<!-- GROUND_TRUTH_START -->/ || /<!-- GIT_START -->/ || /<!-- PARALLEL_START -->/ || /<!-- ORCHESTRATOR_START -->/ { skip=1; next }
        /<!-- ASL_RULES_END -->/ || /<!-- ASL_TOOLBELT_END -->/ || /<!-- GROUND_TRUTH_END -->/ || /<!-- GIT_END -->/ || /<!-- PARALLEL_END -->/ || /<!-- ORCHESTRATOR_END -->/ { skip=0; next }
        /<!-- ASL_LOADER:/ { next }
        !skip { print }
      ' "$target" > "${target}.tmp"
      printf "%s\n\n" "$directive" > "$target"
      cat "${target}.tmp" >> "$target" && rm -f "${target}.tmp"
    else
      printf "%s\n" "$directive" > "$target"
    fi
    echo "  ✓ Configured rules: $target"
  }

  # Helper: Write canonical asl-toolbelt/SKILL.md
  write_skill_md() {
    local target_dir="$1"
    mkdir -p "$target_dir"
    cat << 'EOF' > "${target_dir}/SKILL.md"
---
name: asl-toolbelt
description: >-
  Activate and use in priority before reading, searching, or editing ANY file in this repository. Routes all exploration, grep, edit, and verification through a single 'asl rpc (:batch ...)' roundtrip instead of Read/Grep/Edit/view_file. Rules are the ASN block below; reflection is done by a separate reviewer, never by the author. Triggers: "where is X", "who calls X", "what breaks if I change X", any refactor, any file edit, any code question. Covers .asl .asn .ts .tsx .js .py .go .rs .php .md.
---

# asl-toolbelt: Native Tooling & Epistemic Verification Guide

## Rules

```asn
(:rules :v 9 :src ADR0081 :shortcode D81 :tiers [:essential :hot :affordance :orientation :heuristic :pack :full] :when [:scout :plan :implement :grade :all]
  (:rule :id teleology :force :invariant :tier [:essential :full] :when [:all]
    :do "teleological value hierarchy: (V0 > V1 > V2 > V3 > V4 > V5 > V6); V0 human sovereignty (override requires signed confirmation; restricted to irreversible operations), V1 invariant preservation (:owns, delimiter balance, executed writes only), V2 contractual intent fidelity, V3 evidence-backed falsifiability, V4 minimal causal surface, V5 lexical SNR, V6 velocity; anti-Goodhart: proxy metrics never override ground truth"
    :check "./bin/asl audit consistency"
    :gate "./bin/asl audit consistency"
    :why "explicit lexicographic value dominance ensures safety and boundary invariants strictly dominate speed and prompt compliance; when intent conflicts with invariants, the agent escalates")
  (:rule :id semantics :force :invariant :tier [:essential :full] :when [:implement :grade]
    :do "imports bind; an unknown symbol is an error; zero truthiness; a test returning non-true fails; runner-measured executed assertions must be strictly positive (assertCount > 0); unhandled exceptions in gate scope count as failure; exception swallowing or vacuous assert(true) is a critical defect"
    :check "./bin/asl audit gates"
    :gate "./bin/asl audit gates"
    :why "syntactic green without executed assertions is vacuous pass fraud; verified status requires strictly positive assertion counts and sealed symbol bindings")
  (:rule :id gates :force :invariant :tier [:essential :full] :when [:plan :implement :grade]
    :do "three-point red-green causality: gate(discard) = FAIL, gate(apply) = PASS, gate(revert) = FAIL; baseline failure must be semantic to the claim predicate, not a mechanical missing file; gate hash is pinned at red state; production code mutation must prove fault detection by killing at least one mutant; report exit code, executed asserts, and killed mutants"
    :check "./bin/asl audit gates"
    :gate "./bin/asl audit gates"
    :why "a gate that does not fail on revert or fails to kill production mutants is causally disconnected from the diff and cannot alter epistemic state")
  (:rule :id triMap :force :invariant :tier [:essential :full] :when [:plan :implement :grade]
    :do "Popperian Tri-Map Reconciliation: closed S-Map (intent atoms), F-Map (falsification gates), and B-Map (diff hunks); zero omissions (all S atoms caused by B hunks), zero speculative bloat (all B hunks justified by S atoms), total falsification coverage (every S atom refutable by an F gate); empirical claims enter only with registered measurable definitions and F gates"
    :check "./bin/asl audit consistency"
    :gate "./bin/asl audit consistency"
    :why "tri-map bijection guarantees that prompt intent is completely satisfied without speculative drift or dropped requirements")
  (:rule :id grading :force :invariant :tier [:essential :full] :when [:grade]
    :do "the writer never grades its own work; an independent reviewer executes gates in a hermetic clean context (disjoint context hash, ephemeral sandbox, network denied, deterministic seed); grader-owned acceptance tests and fixtures are strictly read-only and tamper-evident; receipts are runner-issued, signed, and hash-chained"
    :check "sh tests/acceptance/d81/SuperviseGate.sh"
    :gate "sh tests/acceptance/d81/SuperviseGate.sh"
    :why "self-grading and shared context produce self-preference bias; hermetic separation ensures evaluation reflects ground reality")
  (:rule :id astAddressing :force :invariant :tier [:essential :full] :when [:implement :grade]
    :do "Zero-Line-Number Invariant: all code locations, diffs, patches, and receipts are addressed exclusively by path and symbol anchor (:file ?f :symbol ?s :anchor ?a); integer line numbers are strictly forbidden in commands and receipts; edits are idempotent AST splices or content-hash anchored replacements"
    :check "./bin/asl check"
    :gate "./bin/asl check"
    :why "integer line numbers are ephemeral artifacts that drift across edits and invalidate concurrent or rebased patches")
  (:rule :id ramTxn :force :invariant :tier [:essential :full] :when [:implement]
    :do "step is a transaction with declared :owns write set and closing gate; all modifications staged in virtual RAM VFS buffers (:edit -> :diff -> :flush | :discard); flush is atomic with temporary file fsync and rename; process-tree write-set closure strictly contained within :owns; un-staged raw disk writes forbidden; advance only with runner-issued receipt"
    :check "./bin/asl audit steps"
    :gate "./bin/asl audit steps"
    :why "RAM VFS staging prevents workspace corruption during failed attempts and guarantees atomic rollbacks")
  (:rule :id foreign :force :invariant :tier [:essential :full] :when [:implement]
    :do "ASL-first policy: packages contain 100% pure ASL; C host at asl/tools is declared boundary; in foreign target codebases (C, Python, TypeScript, Rust, Go), agents reason in-memory using ASL/ASN action DAGs and lower operations to native diffs with round-trip determinism (project(parse(project(ast))) = project(ast)); zero raw string-blasting"
    :check "./bin/asl audit foreign"
    :gate "./bin/asl audit foreign"
    :why "intermediate representation decouples language-agnostic reasoning from target syntax mechanics, guaranteeing reversibility and formal traceability")
  (:rule :id limitCycle :force :invariant :tier [:essential :full] :when [:all]
    :do "dynamic witness circuit breaker: repeated failure signatures (hash of error class, gate id, hunk digest) capped at 3; three identical failures trip the breaker, halting execution and emitting a structured :witness record; forces basin transition (:build -> :scout or :build -> :plan) or V0 escalation; retries require a distinct causal hypothesis"
    :check "./bin/asl doctor"
    :gate "./bin/asl doctor"
    :why "prevents infinite apology loops and token-burning thrash by turning repeated failure into an explicit phase boundary")
  (:rule :id inMemoryAsl :force :affordance :tier [:affordance :full] :when [:scout :plan :implement]
    :do "in foreign codebases (Python, TypeScript, Rust, Go, C), agents reason in-memory using ASL/ASN action DAGs and typed scratchpads, then lower verified operations to native target diffs"
    :check "./bin/asl check"
    :why "intermediate representation decouples language-agnostic reasoning from target syntax mechanics, guaranteeing reversibility and formal traceability")
  (:rule :id tools :force :affordance :tier [:affordance :full] :when [:scout :implement]
    :do "use ordinary asl invocation with ASN notation as the primary surface; embed scripts, program forms, executable descriptors, code, and tool calls in one validated ASN script; batch independent forms inside that script when useful; RPC is a deprecated compatibility adapter only"
    :check "./bin/asl check"
    :why "ordinary ASN execution is the sole canonical operational surface; valid operations return typed ASN receipts with path and anchor, preventing unvalidated shell execution")
  (:rule :id note :force :affordance :tier [:affordance :full] :when [:all]
    :do "record working memory via asl note write when holding volatile context, architectural discoveries, or empirical findings that would otherwise be lost across steps; query active observations via asl note query or asl note list to prevent duplicate investigation"
    :check "./bin/asl note list"
    :why "working memory reduces context loss and redundant re-reads; grounded findings are promoted at scope close to tasks or ADRs while transient step notes are retired")
  (:rule :id ssot :force :affordance :tier [:affordance :full] :when [:all]
    :do "rules live in one tracked source, asl/grammar/rules.asn; every exported surface is rendered from it by scripts/install.sh --render-rules and checked by --check-rules; per-client or per-tier editions are checked against their deterministic rendering; editing a rendered surface by hand is a defect"
    :check "./scripts/install.sh --check-rules"
    :why "the same rules existed in seven places and drifted; hand-synchronising them is the maintenance mode that fails")
  (:rule :id capabilities :force :affordance :tier [:affordance :full] :when [:all]
    :do "know what you can do before you try: asl/grammar/capabilities.asn keys every capability by situation (orient find read understand plan change verify recover handoff observe) with a measured :status and a named :fallback; (:where) delivers the slice for the current step; when a capability is :absent or :lies, take its fallback and say so, never present the fallback result as the capability"
    :check "./bin/asl doctor"
    :why "epistemic grounding precedes invocation; active capabilities are verified by physical doctor measurement, unmeasured or absent capabilities execute declared fallback paths")
  (:rule :id output :force :orientation :tier [:orientation :full] :when [:all]
    :do "return typed receipts as ASN with path and symbol/anchor; never specify line numbers (Zero-Line-Number Invariant); reversible formatting and deduplication are fine; never drop evidence or constraints to save tokens; compare end-to-end success and total cost before adopting a compact representation"
    :check :none
    :why "compact tool-result notations lost accuracy on several model and benchmark pairs (Notation Matters, up to 9-14pp); the effect is not uniform, so measure, do not assume")
  (:rule :id anchor :force :orientation :tier [:orientation :full] :when [:all]
    :do "the plan lives in the ledger, not in memory: (:plan) once, (:where) before every mutation and after every gate, act from what it returns"
    :check :none
    :why "compliance odds declined per generated function within a session (OR 0.944, exploratory, 2605.10039); whether re-anchoring restores it is the Task44106 hypothesis")
  (:rule :id edge :force :orientation :tier [:orientation :full] :when [:all]
    :do "when no plan step covers the situation: if the action is unauthorized or cannot be safely contained, escalate at once; otherwise recognize ((:where) has no matching step), preserve optionality (read before write, stage before flush, branch before merge, ask before delete), contain (smallest diff inside :owns), refute (run the cheapest thing that would prove you wrong), escalate ((:escalate :seen :tried :fork :resolves) to the principal)"
    :check :none
    :runtimeOnlyReason "Dynamic unplanned contingency escalation and edge case recognition require live runtime decision branching"
    :bias "declared: reversibility over optimality, evidence over confidence, stated intent over inferred intent"
    :why "no rule set matches edge-case variety; models fill gaps fluently instead of noticing them; the loop ends in a receipt to someone else because self-correction without external signal degrades")
  (:rule :id stake :force :orientation :when [:all] :tier [:orientation :full]
    :do "judge work by whether it holds, not by whether it was instructed; report an off-assignment defect rather than stepping over it; responsibility is to system integrity rather than prompt compliance"
    :check :none)
  (:rule :id adaptive :force :orientation :when [:all] :tier [:orientation :full]
    :do "abandon an approach that is not working rather than pressing harder; the trigger to pivot is the absence of new empirical evidence; stop repeating failed operations with superficial edits"
    :check :none)
  (:rule :id problemSolving :force :orientation :when [:all] :tier [:orientation :full]
    :do "when no plan step covers the situation, reduce the uncertainty to the cheapest check that would prove you wrong and run that first; probe reality before generating speculative implementations"
    :check :none)
  (:rule :id context :force :heuristic :tier [:heuristic :full] :when [:all]
    :do "load by symbol and slice, not by file; keep the invariant prefix byte-stable and append step-scoped context after it; never change tool definitions mid-session"
    :check :none
    :defeat "single-prompt workflows or models with unpenalized full-context caching"
    :why "retrieval beat full-context in AutoExperiment (41.7 vs 36.1; AST retrieval 33.3); cached prefix reads are discounted at model-specific rates; a tool-definition change invalidates the cached prefix")
  (:rule :id names :force :heuristic :tier [:heuristic :full] :when [:implement]
    :do "CamelCase for composite identifiers, structs and tests; precise conventional names; do not shorten a name only to save tokens; domain aliases are allowed when they carry meaning"
    :check :none
    :defeat "domain aliases or external foreign interfaces require exact naming"
    :why "CamelCase measured 44-50% cheaper per long identifier on cl100k, and 3.06% corpus-wide across 888 files on 2026-09-12; alias costs in the lock are context-dependent; semantic names carry meaning the model uses")
  (:rule :id git :force :heuristic :tier [:heuristic :full] :when [:implement]
    :do "concise commits; verify base, diff and log before merge; intended changes only"
    :check :none
    :defeat "atomic bulk initialization or machine-generated lockfile updates"
    :coAuthor (:claude :host :agy false))
  (:rule :id parallel :force :heuristic :tier [:heuristic :full] :when [:plan]
    :do "independent reads and scouts in one wave; one writer per owned partition and serialized conflicting commits; subagents soft 4 hard 6 are defaults, not optima"
    :check :none
    :defeat "tightly coupled sequential mutations across identical files")
  (:rule :id budget :force :heuristic :tier [:heuristic :full] :when [:all]
    :do "run a gate after a provisional six tool calls without one; when (:budget) says :compact true, prefer recoverable observation masking, then (:handoff) and reset; thresholds are set by Task44106"
    :check :none
    :runtimeOnlyReason "Tool call budget and observation compaction depend on dynamic runtime execution trace length and cannot be statically evaluated"
    :defeat "lightweight exploratory loops where checkpoint overhead exceeds context savings"
    :why "instruction-load effects are model-dependent (IFScale); compaction at task boundaries and observation masking both reduced context without measured accuracy loss in their studies")
  (:rule :id bounded :force :heuristic :tier [:scout :implement]
    :do "every read carries :limit and continues with :more; bound the output, not file completeness: a small relevant file may fit the bound"
    :check :none
    :defeat "complete whole-file AST analysis or small schema generation"
    :why "degradation with context length is nonuniform and distractor-sensitive across 18 models (Chroma)")
  (:rule :id tokenEconomics :force :heuristic :tier [:heuristic :full] :when [:all]
    :do "attention density law: redundant tokens dilute Softmax attention mass on invariants; preserve KV cache via byte-stable prefixes, batch independent forms in one turn, address code by symbol slices, use CamelCase for BPE subword efficiency, mask execution logs to typed receipts, and enforce lossless reversibility"
    :check "./bin/asl check"
    :gate "./bin/asl check"
    :why "every noise token reduces attention probability mass on constraints; S-expressions cut 55-75% JSON tax and CamelCase saves 44-50% on BPE identifiers")
  (:rule :id reconstructibility :force :affordance :tier [:affordance :full] :when [:all]
    :do "anything reconstructible from code, git history, or a command is not written to durable memory; reconstructible records are refused and the refusal names the command that reports it; rejected alternatives are accepted because no command reports what was not chosen"
    :check :none
    :why "memory records carry strictly novel non-reconstructible delta; tree status and command outputs are reconstructed on-demand from the substrate to eliminate context bloat")
  (:pack :id design :tier [:pack :full]
    :outcomes ["high visual signal to noise ratio" "typography hierarchy" "responsive layout boundaries" "compact VDOM token density"]
    :failureModes ["decorative gratuitous complexity" "unbounded layout shift" "unresponsive component containers"]
    :affordances ["vdom rendering" "asn vector graphics" "color tokens" "spacing scales"])
  (:pack :id development :tier [:pack :full]
    :outcomes ["monorepo invariant compliance" "delimiter balance" "pure ASL packaging" "atomic git transactions" "AST mutation defense"]
    :failureModes ["accidental foreign dependencies" "unbalanced S-expressions" "staged mutation leakage"]
    :affordances ["asl check" "asl lint" "asl rpc batch" "git transaction boundary"])
  (:pack :id research :tier [:pack :full]
    :outcomes ["grounded measurements with method scope and date" "refutation of proxy metrics" "epistemic uncertainty markers" "empirical ledger tracking"]
    :failureModes ["unsourced numeric claims" "evaluating self-preference" "confusing normative principles with empirical findings"]
    :affordances ["bench telemetry" "token profiling" "direct tokenizer evaluation" "principles ledger"])
  (:pack :id multilensAudit :tier [:pack :full]
    :outcomes ["dual-polarity refutation verification" "anti-falsification dynamic roundtripping" "genuine artifact parsing without mocking" "edge-case coverage verification"]
    :failureModes ["static string mocking" "vacuous positive assertions without refutes" "evaluating self-preference"]
    :affordances ["multilens roundtrip validation" "strict falsify harness" "receipt validation"])
  (:pack :id architecture :tier [:pack :full]
    :outcomes ["minimal causal surface" "bounded dependency DAG" "host interface independence" "polymorphic storage hierarchy" "circuit breaker limit cycles"]
    :failureModes ["premature universalism" "unbounded coupling" "hidden ecosystem dependencies" "infinite oscillation cycles"]
    :affordances ["asl audit consistency" "asl audit foreign" "storage engine switch" "circuit breaker escalation"])
  (:pack :id cognitiveSlm :tier [:pack :full]
    :outcomes ["sub-100ms cold start" "unified memory footprint <=24MB" "progressive disclosure bounded retrieval" "thinking-vs-exec budget arbitrage"]
    :failureModes ["unbounded context explosion" "redundant full-file reads" "uncalibrated inference loops"]
    :affordances ["asl mem query" "asl mem tree" "asl-slm telemetry" "observation masking"]))

```
## Pure-ASN Toolbelt & Implicit Parallel Batches

Execute all searches, inspections, edits, and verifications via `asl '<form1> <form2> ...'`.
Direct CLI command tables (`asl mem edit`, etc.) do NOT exist for external agents and must never be emitted.
Multiple top-level forms execute concurrently in RAM VFS buffers by default without `:batch` wrappers.

| Tool Form | Dense Contract (Turn 0) | Operational Guarantee |
| :--- | :--- | :--- |
| `(:query <text> [:scope ...])` | `vector semantic search AST` | Sub-15ms BM25 and cosine ranking across AST symbols and ledgers |
| `(:read :file <f> [:start :end])` | `bounded AST slice retrieval` | Targeted AST & code slice reading bounded by symbol |
| `(:edit :file <f> :old <o> :new <n>)` | `stage atomic string replacement` | Virtual RAM buffer staging; isolated from disk until verified |
| `(:diff [:file <f>])` | `inspect staged RAM diffs` | Inspect dirty RAM buffers and unified diffs prior to disk commit |
| `(:flush)` | `persist staged edits disk` | Atomic fsync and rename from RAM staging to disk |
| `(:discard)` | `clear staged RAM buffers` | Rollback pending RAM modifications with zero disk side-effects |
| `(:doc :file <f> :section <s>)` | `read section without disk` | Bounded Markdown section extraction from AST without full reads |
| `(:tree [:path <p>])` | `render dense structural hierarchy` | Dense structural telemetry across packages and ledgers in <80ms |
| `(:check [:file <f>])` | `verify delimiter & syntax integrity` | Formal Dyck-1 balance, C1-C2 purity, and compiler diagnostics |
| `(:test [:file <f>])` | `execute assertions under verification` | Popperian gate execution with executed assert counts > 0 |
| `(:doctor)` | `audit measured capabilities & invariants` | Measured capability audit against capabilities.lock |
| `(:sanitize :prompt <p>)` | `transpile plain text to ASN intent` | Pre-flight natural-language to pure-ASN Intent compiler |
| `(:gate :id <g>)` | `verify dual-polarity red-green gate` | Gate execution with executed assert count > 0 |
| `(:job <:spawn|:await|:status|:cancel> ...)` | `supervise async daemon jobs` | Resident daemon job management with circuit-breaker limit cycles |

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
Execute all searches, inspections, edits, and verifications via `asl '<form1> <form2> ...'`:
- Implicit Parallel Batches: Multiple top-level forms execute concurrently in RAM VFS buffers by default without `:batch` wrappers.
- Query & Bounded Read: `(:query "text")`, `(:read :file "path" :start 1 :end 50)`, `(:doc :file "f" :section "s")`.
- Memory Staging & Edit: `(:edit :file "f" :old "o" :new "n")`, `(:diff)`, `(:flush)`, `(:discard)`.
- Verification & Gate: `(:check)`, `(:test)`, `(:doctor)`, `(:gate :id "g")`.
- Transpiler Sanitizer: `(:sanitize :prompt "...")`.
- Daemon Supervision: `(:job :spawn ...)` / `(:job :await ...)`.
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
      write_skill_md "${HOME}/.gemini/config/plugins/toolbelt/skills/asl-toolbelt"
      write_skill_md "${HOME}/.gemini/config/plugins/toolbelt/harnesses/antigravity/skills/asl-toolbelt"
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
