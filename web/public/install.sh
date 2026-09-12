#!/bin/bash
# AgentScript Universal Installer (Pre-built Binaries + Source Fallback + Agent Toolbelt Setup)
# Canonical URL: https://aslang.dev/install.sh
# Usage: curl -fsSL https://aslang.dev/install.sh | bash
set -eo pipefail

# ---- rules single source of truth: asl/grammar/rules.asn -> every exported surface ----
rules_main() {
  local MODE="$1"
  local RULES_ROOT; RULES_ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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
      /^    :(why|not|now|bias) "/ { if (w=="") { s=$0; sub(/^    :(why|not|now|bias) "/,"",s); sub(/"[)]*$/,"",s); w=s } }
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
    for d in "$HOME/.agents/skills" "$HOME/.claude/skills" "$HOME/.cursor/skills" "$HOME/.codeium/windsurf/skills" "$HOME/.gemini/skills" "$HOME/.gemini/config/skills" "$HOME/.factory/skills" "$HOME/.codex/skills"; do
      t="$d/asl-toolbelt/SKILL.md"; [ -f "$t" ] && cp "$RULES_ROOT/.agents/skills/asl-toolbelt/SKILL.md" "$t" && echo "  refreshed $t"
    done
  fi
  [ "$MODE" = "--check" ] && { [ $rc -eq 0 ] && echo "rules: all surfaces identical to $SRC" || echo "rules: drift detected" >&2; }

  exit $rc
}
case "${1:-}" in
  --render-rules) rules_main render ;;
  --check-rules)  rules_main --check ;;
  --render-home)  rules_main --home ;;
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
  if [ -f "$LOCAL_ASL" ]; then
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
(:rules :v 7 :src ADR-0081 :when [:scout :plan :implement :grade :all]
  (:rule :id tools :when [:scout :implement]
    :do "prefer asl rpc (:batch (:sym x) (:out f) (:read f a b) (:sec f h) (:ls d) (:callers x) (:impact x)) in one roundtrip; use host tools for content search and file edits until :grep and staged :edit ship; :edit reports immediate mode and staging ops (:diff :flush :discard) reject under :ERR_UNSUPPORTED"
    :not "treat :status ok as success; :find is a filename glob; :q is unimplemented; assume staging exists before Phase438; :edit writes disk immediately and :diff :discard do not stage")
  (:rule :id context :when [:all]
    :do "load by symbol and slice, not by file; keep the invariant prefix byte-stable and append step-scoped context after it; never change tool definitions mid-session"
    :why "retrieval beat full-context in AutoExperiment (41.7 vs 36.1; AST retrieval 33.3); cached prefix reads are discounted at model-specific rates; a tool-definition change invalidates the cached prefix")
  (:rule :id output :when [:all]
    :do "return typed receipts as ASN with path and line; reversible formatting and deduplication are fine; never drop evidence or constraints to save tokens; compare end-to-end success and total cost before adopting a compact representation"
    :why "compact tool-result notations lost accuracy on several model and benchmark pairs (Notation Matters, up to 9-14pp); the effect is not uniform, so measure, do not assume")
  (:rule :id names :when [:implement]
    :do "CamelCase for composite identifiers, structs and tests; precise conventional names; do not shorten a name only to save tokens; domain aliases are allowed when they carry meaning"
    :why "CamelCase measured cheaper than kebab-case on cl100k for the documented identifiers, pending reproduction in Task43806; alias costs in the lock are context-dependent; semantic names carry meaning the model uses")
  (:rule :id semantics :when [:implement :grade]
    :do "imports bind; an unknown symbol is an error; a test returning non-true fails"
    :now "the evaluator abandons a body at exit 0 on unknown symbols until Phase436 (prior audit: about half of declared assertions never ran); treat green as unverified and confirm asserts executed")
  (:rule :id gates :when [:plan :implement :grade]
    :do "every change carries a gate that fails before and passes after, and the baseline failure must be the intended semantic failure, not a missing command or a grep label; report exit code and executed asserts; assertion inversion measures reachability, production-code mutation measures fault detection, report both"
    :not "weaken, skip, loosen, mock, or stub to reach green; exit 0 is not non-vacuity; a printed label is not a result")
  (:rule :id grading :when [:grade]
    :do "the writer never grades its own work; a reviewer runs the gates in a clean context and verification rests on reproducible evidence, not on role labels; scouts are read-only and parallel"
    :why "self-correction without external feedback tends to degrade results; self-preference bias in self-evaluation; persona prompts showed no overall benefit on factual QA")
  (:rule :id concepts :when [:plan]
    :do "a normative principle may be adopted explicitly without measurement, but every number in a rule needs source, scope and uncertainty; an empirical claim enters only with a measurable definition and a baseline-failing gate"
    :why "SNR 0.75, sovereignty, homeostasis and 72% compaction were stated as measurements without sources and failed audit")
  (:rule :id foreign :when [:implement]
    :do "pure ASL inside packages; the C host at asl/tools is declared, not hidden; no MCP; seed compiler, build tools and independent test hosts are declared boundaries and the deployed runtime must not require them; no new ecosystem dependency beyond those boundaries"
    :now "core is C plus an embedded JS evaluator on JavaScriptCore, macOS only, until Phase438")
  (:rule :id git :when [:implement]
    :do "concise commits; verify base, diff and log before merge; intended changes only"
    :coAuthor (:claude :host :agy false))
  (:rule :id parallel :when [:plan]
    :do "independent reads and scouts in one wave; one writer per owned partition and serialized conflicting commits; subagents soft 4 hard 6 are defaults, not optima")
  (:rule :id anchor :when [:all]
    :do "the plan lives in the ledger, not in memory: (:plan) once, (:where) before every mutation and after every gate, act from what it returns; until the ledger ops exist keep the plan in the task file and re-read it"
    :why "compliance odds declined per generated function within a session (OR 0.944, exploratory, 2605.10039); whether re-anchoring restores it is the Task44106 hypothesis")
  (:rule :id oneStep :when [:implement]
    :do "a step is a transaction with an owned write set and a closing gate; batch independent edits inside it; advance only with a runner-issued receipt bound to session, step, gate and source digest"
    :not "batch several steps then verify; claim progress with a caller-supplied exit code")
  (:rule :id budget :when [:all]
    :do "run a gate after a provisional six tool calls without one; when (:budget) says :compact true, prefer recoverable observation masking, then (:handoff) and reset; thresholds are set by Task44106"
    :why "instruction-load effects are model-dependent (IFScale); compaction at task boundaries and observation masking both reduced context without measured accuracy loss in their studies")
  (:rule :id hiddenTests :when [:implement :grade]
    :do "the implementer cannot modify grader-owned acceptance tests; read-only public regression tests and author-owned development tests are allowed; enforced by :owns in the engine and tool allowlists, not by prompt"
    :why "protected hidden evaluation reduced test exploitation (ImpossibleBench); prompting effects were model and task dependent")
  (:rule :id bounded :when [:scout :implement]
    :do "every read carries :limit and continues with :more; bound the output, not file completeness: a small relevant file may fit the bound"
    :why "degradation with context length is nonuniform and distractor-sensitive across 18 models (Chroma)")
  (:rule :id edge :when [:all]
    :do "when no plan step covers the situation: if the action is unauthorized or cannot be safely contained, escalate at once; otherwise recognize ((:where) has no matching step), preserve optionality (read before write, stage before flush, branch before merge, ask before delete), contain (smallest diff inside :owns), refute (run the cheapest thing that would prove you wrong), escalate ((:escalate :seen :tried :fork :resolves) to the principal)"
    :bias "declared: reversibility over optimality, evidence over confidence, stated intent over inferred intent"
    :why "no rule set matches edge-case variety; models fill gaps fluently instead of noticing them; the loop ends in a receipt to someone else because self-correction without external signal degrades")
  (:rule :id ssot :when [:all]
    :do "rules live in one tracked source, asl/grammar/rules.asn; every exported surface is rendered from it by scripts/install.sh --render-rules and checked by --check-rules; per-client or per-tier editions are checked against their deterministic rendering; editing a rendered surface by hand is a defect"
    :why "the same rules existed in seven places and drifted; hand-synchronising them is the maintenance mode that fails")
  (:rule :id capabilities :when [:all]
    :do "know what you can do before you try: asl/grammar/capabilities.asn keys every capability by situation (orient find read understand plan change verify recover handoff observe) with a measured :status and a named :fallback; (:where) delivers the slice for the current step; when a capability is :absent or :lies, take its fallback and say so, never present the fallback result as the capability"
    :not "assume an op works because it is declared, or because it returned :status ok; 22 of 36 capabilities are :absent or :lies today"
    :why "measured, not declared: :status is written by asl doctor into capabilities.lock, and a hand-edited status that contradicts measurement fails gate 7"))
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
(:rules :v 7 :src ADR-0081 :when [:scout :plan :implement :grade :all]
  (:rule :id tools :when [:scout :implement]
    :do "prefer asl rpc (:batch (:sym x) (:out f) (:read f a b) (:sec f h) (:ls d) (:callers x) (:impact x)) in one roundtrip; use host tools for content search and file edits until :grep and staged :edit ship; :edit reports immediate mode and staging ops (:diff :flush :discard) reject under :ERR_UNSUPPORTED"
    :not "treat :status ok as success; :find is a filename glob; :q is unimplemented; assume staging exists before Phase438; :edit writes disk immediately and :diff :discard do not stage")
  (:rule :id context :when [:all]
    :do "load by symbol and slice, not by file; keep the invariant prefix byte-stable and append step-scoped context after it; never change tool definitions mid-session"
    :why "retrieval beat full-context in AutoExperiment (41.7 vs 36.1; AST retrieval 33.3); cached prefix reads are discounted at model-specific rates; a tool-definition change invalidates the cached prefix")
  (:rule :id output :when [:all]
    :do "return typed receipts as ASN with path and line; reversible formatting and deduplication are fine; never drop evidence or constraints to save tokens; compare end-to-end success and total cost before adopting a compact representation"
    :why "compact tool-result notations lost accuracy on several model and benchmark pairs (Notation Matters, up to 9-14pp); the effect is not uniform, so measure, do not assume")
  (:rule :id names :when [:implement]
    :do "CamelCase for composite identifiers, structs and tests; precise conventional names; do not shorten a name only to save tokens; domain aliases are allowed when they carry meaning"
    :why "CamelCase measured cheaper than kebab-case on cl100k for the documented identifiers, pending reproduction in Task43806; alias costs in the lock are context-dependent; semantic names carry meaning the model uses")
  (:rule :id semantics :when [:implement :grade]
    :do "imports bind; an unknown symbol is an error; a test returning non-true fails"
    :now "the evaluator abandons a body at exit 0 on unknown symbols until Phase436 (prior audit: about half of declared assertions never ran); treat green as unverified and confirm asserts executed")
  (:rule :id gates :when [:plan :implement :grade]
    :do "every change carries a gate that fails before and passes after, and the baseline failure must be the intended semantic failure, not a missing command or a grep label; report exit code and executed asserts; assertion inversion measures reachability, production-code mutation measures fault detection, report both"
    :not "weaken, skip, loosen, mock, or stub to reach green; exit 0 is not non-vacuity; a printed label is not a result")
  (:rule :id grading :when [:grade]
    :do "the writer never grades its own work; a reviewer runs the gates in a clean context and verification rests on reproducible evidence, not on role labels; scouts are read-only and parallel"
    :why "self-correction without external feedback tends to degrade results; self-preference bias in self-evaluation; persona prompts showed no overall benefit on factual QA")
  (:rule :id concepts :when [:plan]
    :do "a normative principle may be adopted explicitly without measurement, but every number in a rule needs source, scope and uncertainty; an empirical claim enters only with a measurable definition and a baseline-failing gate"
    :why "SNR 0.75, sovereignty, homeostasis and 72% compaction were stated as measurements without sources and failed audit")
  (:rule :id foreign :when [:implement]
    :do "pure ASL inside packages; the C host at asl/tools is declared, not hidden; no MCP; seed compiler, build tools and independent test hosts are declared boundaries and the deployed runtime must not require them; no new ecosystem dependency beyond those boundaries"
    :now "core is C plus an embedded JS evaluator on JavaScriptCore, macOS only, until Phase438")
  (:rule :id git :when [:implement]
    :do "concise commits; verify base, diff and log before merge; intended changes only"
    :coAuthor (:claude :host :agy false))
  (:rule :id parallel :when [:plan]
    :do "independent reads and scouts in one wave; one writer per owned partition and serialized conflicting commits; subagents soft 4 hard 6 are defaults, not optima")
  (:rule :id anchor :when [:all]
    :do "the plan lives in the ledger, not in memory: (:plan) once, (:where) before every mutation and after every gate, act from what it returns; until the ledger ops exist keep the plan in the task file and re-read it"
    :why "compliance odds declined per generated function within a session (OR 0.944, exploratory, 2605.10039); whether re-anchoring restores it is the Task44106 hypothesis")
  (:rule :id oneStep :when [:implement]
    :do "a step is a transaction with an owned write set and a closing gate; batch independent edits inside it; advance only with a runner-issued receipt bound to session, step, gate and source digest"
    :not "batch several steps then verify; claim progress with a caller-supplied exit code")
  (:rule :id budget :when [:all]
    :do "run a gate after a provisional six tool calls without one; when (:budget) says :compact true, prefer recoverable observation masking, then (:handoff) and reset; thresholds are set by Task44106"
    :why "instruction-load effects are model-dependent (IFScale); compaction at task boundaries and observation masking both reduced context without measured accuracy loss in their studies")
  (:rule :id hiddenTests :when [:implement :grade]
    :do "the implementer cannot modify grader-owned acceptance tests; read-only public regression tests and author-owned development tests are allowed; enforced by :owns in the engine and tool allowlists, not by prompt"
    :why "protected hidden evaluation reduced test exploitation (ImpossibleBench); prompting effects were model and task dependent")
  (:rule :id bounded :when [:scout :implement]
    :do "every read carries :limit and continues with :more; bound the output, not file completeness: a small relevant file may fit the bound"
    :why "degradation with context length is nonuniform and distractor-sensitive across 18 models (Chroma)")
  (:rule :id edge :when [:all]
    :do "when no plan step covers the situation: if the action is unauthorized or cannot be safely contained, escalate at once; otherwise recognize ((:where) has no matching step), preserve optionality (read before write, stage before flush, branch before merge, ask before delete), contain (smallest diff inside :owns), refute (run the cheapest thing that would prove you wrong), escalate ((:escalate :seen :tried :fork :resolves) to the principal)"
    :bias "declared: reversibility over optimality, evidence over confidence, stated intent over inferred intent"
    :why "no rule set matches edge-case variety; models fill gaps fluently instead of noticing them; the loop ends in a receipt to someone else because self-correction without external signal degrades")
  (:rule :id ssot :when [:all]
    :do "rules live in one tracked source, asl/grammar/rules.asn; every exported surface is rendered from it by scripts/install.sh --render-rules and checked by --check-rules; per-client or per-tier editions are checked against their deterministic rendering; editing a rendered surface by hand is a defect"
    :why "the same rules existed in seven places and drifted; hand-synchronising them is the maintenance mode that fails")
  (:rule :id capabilities :when [:all]
    :do "know what you can do before you try: asl/grammar/capabilities.asn keys every capability by situation (orient find read understand plan change verify recover handoff observe) with a measured :status and a named :fallback; (:where) delivers the slice for the current step; when a capability is :absent or :lies, take its fallback and say so, never present the fallback result as the capability"
    :not "assume an op works because it is declared, or because it returned :status ok; 22 of 36 capabilities are :absent or :lies today"
    :why "measured, not declared: :status is written by asl doctor into capabilities.lock, and a hand-edited status that contradicts measurement fails gate 7"))
```

## Tool Suite Reference (verified 2026-09-11)

| Op | Status | Use |
| :--- | :--- | :--- |
| `(:sym "x")` `(:out "f")` `(:read "f" a b)` `(:sec "f" "h")` `(:ls "d")` | works | structure, slices, sections, listings |
| `(:callers "x")` `(:impact "x")` | works | call graph, blast radius before changing an interface |
| `(:find "glob")` | works, filename glob only | not a content search |
| `(:grep "x")` `(:q "x")` | not implemented | use host search until Phase438 |
| `(:edit "f" "old" "new")` | writes disk immediately | no staging; `(:diff)` `(:flush)` `(:discard)` report clean unconditionally until Phase438 |
| `(:write "f" "text")` | works inside workspace | rejects paths outside the workspace |
| `asl check <f>` `asl lint <f>` | work; exit 1 on violation | delimiters, C1, C2, C5 |
| `asl test <f>` | delimiter check plus reached asserts | unreached asserts pass silently until Phase436 |
| `(:plan …)` `(:where)` `(:step-done N :exit c :receipt r)` `(:checklist)` | planned (Phase441) | external working memory: re-anchor before each mutation, advance only with a receipt |
| `(:budget)` `(:handoff)` `(:resume)` `(:recall q)` | planned (Phase441) | know when to compact; snapshot, reset, resume |
| `:limit` / `:more` on every read op | planned (Phase441) | nothing enters the context unbounded |
| `asl audit gates` `asl audit consistency` | work | see ADR-0081 for which gates are vacuous today |
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
