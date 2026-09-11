#!/usr/bin/env bash
set -eo pipefail

SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do
  DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
ASL_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
ASL_BIN="$ASL_DIR/bin/asl"

if [ ! -x "$ASL_BIN" ]; then
  if [ -x "$ASL_DIR/../bin/asl" ]; then
    ASL_BIN="$ASL_DIR/../bin/asl"
  elif [ -x "$ASL_DIR/../asl/bin/asl" ]; then
    ASL_BIN="$ASL_DIR/../asl/bin/asl"
  else
    echo "Error: sovereign asl binary not found at $ASL_BIN" >&2
    exit 1
  fi
fi

find_workspace_root() {
  local dir="$PWD"
  while [ "$dir" != "/" ] && [ "$dir" != "." ]; do
    if [ -f "$dir/.asl.config.asn" ] || [ -f "$dir/asl.config.asn" ] || [ -e "$dir/.git" ]; then
      echo "$dir"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  if [ -f "$ROOT/../.asl.config.asn" ] || [ -e "$ROOT/../.git" ]; then
    (cd -P "$ROOT/.." && pwd)
    return 0
  fi
  echo "$PWD"
}


run_launch() {
    TARGET_AGENT=""
    DRY_RUN=0
    NO_STASH=0
    ORCHESTRATOR=0
    ORCH_MODEL="gemini-3.8-flash"
    ORCH_REASONING="high"
    RESEARCH_MODEL="flash"
    PLANNING_MODEL="pro"
    EXECUTION_MODEL="inherit"
    MAX_AGENTS=6
    SOFT_LIMIT=4
    HARD_LIMIT=6
    CODE_EXEC=1
    MULTI_PROJECT=1
    SEPARATE_AGENTS=0
    ORCH_TARGET="sub-agents"
    INITIAL_PROMPT=""
    EXTRA_ARGS=()

    while [ $# -gt 0 ]; do
      case "$1" in
        agy|antigravity|claude|claude-code|cursor|windsurf|gemini|agi)
          if [ -z "$TARGET_AGENT" ]; then
            TARGET_AGENT="$1"
            shift
          else
            EXTRA_ARGS+=("$1")
            shift
          fi
          ;;
        --orchestrator|-o|orchestrator)
          ORCHESTRATOR=1
          shift
          ;;
        --preset|-P)
          ORCHESTRATOR=1
          PRESET="$2"
          shift 2
          case "$PRESET" in
            fast-research|research)
              ORCH_MODEL="gemini-3.8-flash"
              ORCH_REASONING="low"
              SOFT_LIMIT=4
              HARD_LIMIT=6
              MAX_AGENTS=6
              RESEARCH_MODEL="flash"
              PLANNING_MODEL="flash"
              EXECUTION_MODEL="inherit"
              ;;
            deep-architecture|architecture|arch)
              ORCH_MODEL="gemini-3.8-flash"
              ORCH_REASONING="max"
              SOFT_LIMIT=2
              HARD_LIMIT=4
              MAX_AGENTS=4
              RESEARCH_MODEL="flash"
              PLANNING_MODEL="pro"
              EXECUTION_MODEL="inherit"
              ;;
            audit-hardening|audit)
              ORCH_MODEL="gemini-3.8-flash"
              ORCH_REASONING="high"
              SOFT_LIMIT=4
              HARD_LIMIT=6
              MAX_AGENTS=6
              RESEARCH_MODEL="flash"
              PLANNING_MODEL="pro"
              EXECUTION_MODEL="inherit"
              ;;
            canvas-interactive|canvas)
              ORCH_MODEL="gemini-3.8-flash"
              ORCH_REASONING="medium"
              SOFT_LIMIT=3
              HARD_LIMIT=6
              MAX_AGENTS=6
              RESEARCH_MODEL="flash"
              PLANNING_MODEL="pro"
              EXECUTION_MODEL="inherit"
              ;;
            balanced|*)
              ORCH_MODEL="gemini-3.8-flash"
              ORCH_REASONING="medium"
              SOFT_LIMIT=4
              HARD_LIMIT=6
              MAX_AGENTS=6
              RESEARCH_MODEL="flash"
              PLANNING_MODEL="pro"
              EXECUTION_MODEL="inherit"
              ;;
          esac
          ;;
        --model|-m)
          ORCH_MODEL="$2"
          shift 2
          ;;
        --reasoning|-r)
          ORCH_REASONING="$2"
          shift 2
          ;;
        --soft-limit)
          SOFT_LIMIT="$2"
          shift 2
          ;;
        --hard-limit)
          HARD_LIMIT="$2"
          MAX_AGENTS="$2"
          shift 2
          ;;
        --max-agents)
          HARD_LIMIT="$2"
          MAX_AGENTS="$2"
          shift 2
          ;;
        --code-exec)
          CODE_EXEC=1
          shift
          ;;
        --no-code-exec)
          CODE_EXEC=0
          shift
          ;;
        --multi-project)
          MULTI_PROJECT=1
          shift
          ;;
        --no-multi-project)
          MULTI_PROJECT=0
          shift
          ;;
        --separate-agents)
          SEPARATE_AGENTS=1
          ORCH_TARGET="separate-agents"
          shift
          ;;
        --subagents)
          SEPARATE_AGENTS=0
          ORCH_TARGET="sub-agents"
          shift
          ;;
        --dry-run|-n)
          DRY_RUN=1
          shift
          ;;
        --no-stash)
          NO_STASH=1
          shift
          ;;
        --prompt|-p)
          INITIAL_PROMPT="$2"
          shift 2
          ;;
        --)
          shift
          while [ $# -gt 0 ]; do
            case "$1" in
              orchestrator|--orchestrator|-o)
                ORCHESTRATOR=1
                shift
                ;;
              --dry-run|-n)
                DRY_RUN=1
                shift
                ;;
              *)
                EXTRA_ARGS+=("$1")
                shift
                ;;
            esac
          done
          break
          ;;
        *)
          EXTRA_ARGS+=("$1")
          shift
          ;;
      esac
    done

    TARGET_AGENT="${TARGET_AGENT:-agy}"
    TARGET_AGENT="$(echo "$TARGET_AGENT" | tr '[:upper:]' '[:lower:]')"
    case "$TARGET_AGENT" in
      agi) TARGET_AGENT="agy" ;;
    esac

    case "$TARGET_AGENT" in
      agy|antigravity|gemini|agi)
        CLIENT_ID="agy"
        CLIENT_NAME="agy (Antigravity CLI)"
        PROMPT_CHANNEL="<RULE[user_global]>"
        BIN_NAMES=("agy" "antigravity" "$HOME/.gemini/antigravity-cli/bin/agy" "$HOME/.gemini/bin/agy" "$HOME/.local/bin/agy" "/usr/local/bin/agy")
        ;;
      claude|claude-code)
        CLIENT_ID="claude"
        CLIENT_NAME="Claude Code"
        PROMPT_CHANNEL="CLAUDE.md"
        BIN_NAMES=("claude" "/usr/local/bin/claude" "$HOME/.local/bin/claude")
        ;;
      cursor)
        CLIENT_ID="cursor"
        CLIENT_NAME="Cursor"
        PROMPT_CHANNEL=".cursorrules"
        BIN_NAMES=("cursor" "/usr/local/bin/cursor")
        ;;
      windsurf)
        CLIENT_ID="windsurf"
        CLIENT_NAME="Windsurf"
        PROMPT_CHANNEL=".codeium/windsurf/memories/global_rules.md"
        BIN_NAMES=("windsurf" "/usr/local/bin/windsurf")
        ;;
      help|--help|-h)
        echo "Usage: asl launch <agy|claude|cursor|windsurf> [--orchestrator|-o] [--preset <name>] [--model <name>] [--reasoning <level>] [--soft-limit <n>] [--hard-limit <n>] [--multi-project] [--code-exec] [--dry-run] [--no-stash] [--prompt <msg>] [-- <agent-args...>]"
        echo ""
        echo "Launches target agent with runtime ASL toolbelt injection and consultative AGENTS.md isolation."
        echo ""
        echo "Orchestration Options:"
        echo "  --orchestrator, -o    Enable autonomous multi-agent orchestration supervisor mode"
        echo "                        (Claude Code: automatic mode; Antigravity: dangerous rescue permissions)"
        echo "  --preset, -P <name>   Preset: fast-research, balanced, deep-architecture, audit-hardening, canvas-interactive"
        echo "  --model, -m <model>   Supervisory orchestrator model (default: gemini-3.8-flash)"
        echo "  --reasoning, -r <lvl> Reasoning depth: low, medium, high, max (default: high)"
        echo "  --soft-limit <n>      Soft limit for concurrent subagents within single project (default: 4)"
        echo "  --hard-limit <n>      Hard limit for concurrent subagents across multi-project bursts (default: 6)"
        echo "  --multi-project       Enable multi-project workspace routing across projects"
        echo "  --code-exec           Enable supervised code execution and gate verification (default: 1)"
        exit 0
        ;;
      *)
        echo "Usage: asl launch <agy|claude|cursor|windsurf> [--orchestrator|-o] [--preset <name>] [--model <name>] [--reasoning <level>] [--soft-limit <n>] [--hard-limit <n>] [--multi-project] [--code-exec] [--dry-run] [--no-stash] [--prompt <msg>] [-- <agent-args...>]"
        echo ""
        echo "Launches target agent with runtime ASL toolbelt injection and consultative AGENTS.md isolation."
        echo ""
        echo "Orchestration Options:"
        echo "  --orchestrator, -o    Enable autonomous multi-agent orchestration supervisor mode"
        echo "                        (Claude Code: automatic mode; Antigravity: dangerous rescue permissions)"
        echo "  --preset, -P <name>   Preset: fast-research, balanced, deep-architecture, audit-hardening, canvas-interactive"
        echo "  --model, -m <model>   Supervisory orchestrator model (default: gemini-3.8-flash)"
        echo "  --reasoning, -r <lvl> Reasoning depth: low, medium, high, max (default: high)"
        echo "  --soft-limit <n>      Soft limit for concurrent subagents within single project (default: 4)"
        echo "  --hard-limit <n>      Hard limit for concurrent subagents across multi-project bursts (default: 6)"
        echo "  --multi-project       Enable multi-project workspace routing across projects"
        echo "  --code-exec           Enable supervised code execution and gate verification (default: 1)"
        exit 1
        ;;
    esac

    WS_ROOT="$(find_workspace_root 2>/dev/null || pwd)"
    AGENTS_FILE="$WS_ROOT/AGENTS.md"
    CHANNEL_FILE=""
    case "$CLIENT_ID" in
      claude)
        CHANNEL_FILE="$WS_ROOT/CLAUDE.md"
        ;;
      cursor)
        CHANNEL_FILE="$WS_ROOT/.cursorrules"
        ;;
      windsurf)
        CHANNEL_FILE="$WS_ROOT/.codeium/windsurf/memories/global_rules.md"
        ;;
      agy)
        CHANNEL_FILE="$WS_ROOT/AGENTS.md"
        ;;
    esac

    DIRECTIVE_PAYLOAD='<!-- ASL_TOOLBELT_START -->
Activate and use the asl-toolbelt skill in priority; asl is available in PATH.
(:rule :tools
  :forbid [:view_file :replace_file_content :write_to_file :find_by_name :list_dir :View :Edit :Write :Grep :Glob :LS]
  :require [(:asl :binary "asl" :batch true)]
  :execution (:mode :maximum-parallel :waves true :concurrency (:soft 4 :hard 6) :git-via-rpc true))
<!-- ASL_TOOLBELT_END -->

<!-- PARALLEL_START -->
(:rule :parallel :batch :wave :scope [:search :scout :audit :patch :git])
<!-- PARALLEL_END -->

<!-- GROUND_TRUTH_START -->
(:rule :ground-truth
  :falsify  (:must-fail true :exit 0)
  :strict   (:forbid [:stub :todo :mock :swallow :co-author] :require [:bounds :errors])
  :critic   (:self false :stance :adversary)
  :receipt  (:format :asn :asserts (> 0) :claims false))
<!-- GROUND_TRUTH_END -->

<!-- GIT_START -->
(:rule :git
  :co-author false
  :commit    (:concise true)
  :branch    (:base :target :verify true)
  :merge     (:verify [:base :diff :log]
              :strict (:require [:intended-only :safe-merge]
                       :forbid  [:unrelated-commits :wrong-base])))
<!-- GIT_END -->'

    if [ "$ORCHESTRATOR" -eq 1 ]; then
      ORCH_DIRECTIVE="

<!-- ORCHESTRATOR_START -->
(:launch-session
  :client \"$CLIENT_ID\""
      if [ "$CLIENT_ID" = "claude" ]; then
        ORCH_DIRECTIVE="$ORCH_DIRECTIVE
  :claude-mode \"system-guided\"
  :auto-flags []"
      elif [ "$CLIENT_ID" = "agy" ]; then
        ORCH_DIRECTIVE="$ORCH_DIRECTIVE
  :permission-tier \"dangerous-rescue\"
  :auto-flags [\"--dangerously-skip-permissions\"]"
      fi
      ORCH_DIRECTIVE="$ORCH_DIRECTIVE
  :channel \"$PROMPT_CHANNEL\"
  :orchestrator-mode true
  :supervisory-model \"$ORCH_MODEL\"
  :reasoning-level \"$ORCH_REASONING\"
  :orchestration-target \"$ORCH_TARGET\"
  :separate-agents-feature-flag $([ "$SEPARATE_AGENTS" -eq 1 ] && echo "true" || echo "false")
  :minimal-orchestrator true
  :soft-limit $SOFT_LIMIT
  :hard-limit $HARD_LIMIT
  :max-subagents $HARD_LIMIT
  :scaling-condition \"Single project -> max 4 agents (soft limit); burst scaling up to 6 agents (hard limit) triggered exclusively when multiple Workspace projects are actively engaged concurrently.\"
  :multi-project-orchestration true
  :code-execution true
  :subagent-tiers (:research \"$RESEARCH_MODEL\" :planning \"$PLANNING_MODEL\" :execution \"$EXECUTION_MODEL\")
  :upgrade-path \"gemini-next\"
  :mandates [
    \"Baseline delegation: Use sub-agents (invoke_subagent in Antigravity, Agent in Claude Code) as the primary execution model.\"
    \"Claude Code permission mandate: Never use dangerous permissions (--dangerously-skip-permissions) with Claude Code. Guide execution strictly via system instructions (--append-system-prompt).\"
    \"Antigravity permission mandate: Antigravity must always execute in dangerous rescue mode (--dangerously-skip-permissions) for unconstrained self-healing.\"
    \"Context hygiene: Keep orchestrator context minimal by offloading search, exploration, and edits into sub-agent conversation branches; ingest only scalar task receipts.\"
    \"Lean supervisor rule: If sub-agent overhead exceeds task complexity, execute directly via compact batch RPC rather than spawning unneeded sub-agents.\"
    \"Feature flag extension: Separate OS-level agent orchestration is decoupled under --separate-agents for future cross-process scaling.\"
    \"Never execute complex multi-part tasks directly; decompose and spawn specialized subagents (invoke_subagent in Antigravity, Agent in Claude Code).\"
    \"Supervised code execution: Run build, tests, and gate verification commands in isolated subagents, strictly requiring exit code 0.\"
    \"Utilize asl rpc (:batch ...) in priority for workspace-aware symbol navigation, callers, and impact analysis.\"
  ]
  :rules [:asl-toolbelt :ground-truth :git :orchestrator])
<!-- ORCHESTRATOR_END -->"
      DIRECTIVE_PAYLOAD="$DIRECTIVE_PAYLOAD$ORCH_DIRECTIVE"
    fi

    STASH_FILE=""
    CHANNEL_STASH=""
    CHANNEL_LINK_TARGET=""
    CHANNEL_CREATED=0

    cleanup_launch() {
      if [ -n "$STASH_FILE" ] && [ -f "$STASH_FILE" ]; then
        cp -f "$STASH_FILE" "$AGENTS_FILE" 2>/dev/null || true
        rm -f "$STASH_FILE" 2>/dev/null || true
      fi
      if [ -n "$CHANNEL_LINK_TARGET" ]; then
        rm -rf "$CHANNEL_FILE" 2>/dev/null || true
        ln -sf "$CHANNEL_LINK_TARGET" "$CHANNEL_FILE" 2>/dev/null || true
      elif [ -n "$CHANNEL_STASH" ] && [ -f "$CHANNEL_STASH" ]; then
        rm -rf "$CHANNEL_FILE" 2>/dev/null || true
        cp -f "$CHANNEL_STASH" "$CHANNEL_FILE" 2>/dev/null || true
        rm -f "$CHANNEL_STASH" 2>/dev/null || true
      elif [ "$CHANNEL_CREATED" -eq 1 ] && [ -f "$CHANNEL_FILE" ]; then
        rm -f "$CHANNEL_FILE" 2>/dev/null || true
      fi
    }

    if [ "$DRY_RUN" -eq 0 ] && [ "$NO_STASH" -eq 0 ]; then
      if [ "$CLIENT_ID" != "claude" ] && [ -n "$CHANNEL_FILE" ] && [ ! -L "$CHANNEL_FILE" ]; then
        if [ -f "$CHANNEL_FILE" ]; then
          CHANNEL_STASH="/tmp/asl_channel_stash_$$"
          cp -f "$CHANNEL_FILE" "$CHANNEL_STASH"
          trap cleanup_launch EXIT INT TERM HUP
          if ! grep -q "ASL_TOOLBELT_START" "$CHANNEL_FILE" 2>/dev/null; then
            EXISTING_CONTENT="$(cat "$CHANNEL_FILE" 2>/dev/null || true)"
            printf '%s\n\n%s\n' "$DIRECTIVE_PAYLOAD" "$EXISTING_CONTENT" > "$CHANNEL_FILE.tmp" && mv -f "$CHANNEL_FILE.tmp" "$CHANNEL_FILE"
          elif [ "$ORCHESTRATOR" -eq 1 ] && ! grep -q "ORCHESTRATOR_START" "$CHANNEL_FILE" 2>/dev/null; then
            EXISTING_CONTENT="$(cat "$CHANNEL_FILE" 2>/dev/null || true)"
            printf '%s\n\n%s\n' "$DIRECTIVE_PAYLOAD" "$EXISTING_CONTENT" > "$CHANNEL_FILE.tmp" && mv -f "$CHANNEL_FILE.tmp" "$CHANNEL_FILE"
          fi
        else
          mkdir -p "$(dirname "$CHANNEL_FILE")" 2>/dev/null || true
          printf '%s\n' "$DIRECTIVE_PAYLOAD" > "$CHANNEL_FILE"
          CHANNEL_CREATED=1
          trap cleanup_launch EXIT INT TERM HUP
        fi
      fi

      if [ "$CLIENT_ID" != "claude" ] && [ "$CHANNEL_FILE" != "$AGENTS_FILE" ] && [ -f "$AGENTS_FILE" ]; then
        if grep -q "ASL_TOOLBELT_START" "$AGENTS_FILE" 2>/dev/null; then
          STASH_FILE="/tmp/asl_agents_stash_$$"
          cp -f "$AGENTS_FILE" "$STASH_FILE"
          trap cleanup_launch EXIT INT TERM HUP
          awk '
          /<!-- ASL_TOOLBELT_START -->/ { in_tb = 1; print "<!-- ASL_LOADER: consultative mode active during asl launch; runtime toolbelt injected via channel -->"; next; }
          /<!-- ASL_TOOLBELT_END -->/ { in_tb = 0; next; }
          !in_tb { print; }
          ' "$AGENTS_FILE" > "$AGENTS_FILE.tmp" && mv -f "$AGENTS_FILE.tmp" "$AGENTS_FILE"
        fi
      fi
    fi

    CLIENT_BIN=""
    for CANDIDATE in "${BIN_NAMES[@]}"; do
      if command -v "$CANDIDATE" >/dev/null 2>&1; then
        CLIENT_BIN="$(command -v "$CANDIDATE")"
        break
      elif [ -x "$CANDIDATE" ]; then
        CLIENT_BIN="$CANDIDATE"
        break
      fi
    done

    export ASL_LAUNCHED=1
    export ASL_CLIENT="$CLIENT_ID"
    export ASL_TOOLBELT_ACTIVE=1
    export ASL_ORCHESTRATOR="$ORCHESTRATOR"
    export ASL_ORCHESTRATOR_MODEL="$ORCH_MODEL"
    export ASL_REASONING_LEVEL="$ORCH_REASONING"
    export ASL_RESEARCH_MODEL="$RESEARCH_MODEL"
    export ASL_PLANNING_MODEL="$PLANNING_MODEL"
    export ASL_EXECUTION_MODEL="$EXECUTION_MODEL"
    export ASL_MAX_SUBAGENTS="$MAX_AGENTS"
    export ASL_SOFT_LIMIT="$SOFT_LIMIT"
    export ASL_HARD_LIMIT="$HARD_LIMIT"
    export ASL_CODE_EXEC="$CODE_EXEC"
    export ASL_MULTI_PROJECT="$MULTI_PROJECT"
    export ASL_SEPARATE_AGENTS="$SEPARATE_AGENTS"
    export ASL_ORCH_TARGET="$ORCH_TARGET"

    AUTO_FLAGS=()
    if [ "$CLIENT_ID" = "claude" ]; then
      # STRICT INVARIANT 1: Never overwrite Claude base system prompt; only append (--append-system-prompt).
      # STRICT INVARIANT 2: Never use dangerous permissions (--dangerously-skip-permissions) with Claude Code.
      FILTERED_ARGS=()
      SKIP_NEXT=0
      CUSTOM_APPEND_PROMPTS=()
      for ((i=0; i<${#EXTRA_ARGS[@]}; i++)); do
        arg="${EXTRA_ARGS[i]}"
        if [ "$SKIP_NEXT" -eq 1 ]; then
          SKIP_NEXT=0
          continue
        fi
        if [ "$arg" = "--dangerously-skip-permissions" ]; then
          echo "⚠️  [ASL] Dangerous permissions forbidden for Claude Code; stripped."
          continue
        fi
        if [ "$arg" = "--system-prompt" ]; then
          next_arg="${EXTRA_ARGS[i+1]}"
          CUSTOM_APPEND_PROMPTS+=("$next_arg")
          SKIP_NEXT=1
          echo "⚠️  [ASL] Direct --system-prompt overwrite blocked for Claude Code; converted to --append-system-prompt."
        else
          FILTERED_ARGS+=("$arg")
        fi
      done
      EXTRA_ARGS=("${FILTERED_ARGS[@]}")

      HAS_APPEND_PROMPT=0
      for arg in "${EXTRA_ARGS[@]}"; do
        if [ "$arg" = "--append-system-prompt" ]; then
          HAS_APPEND_PROMPT=1
          break
        fi
      done
      if [ "$HAS_APPEND_PROMPT" -eq 0 ]; then
        EXTRA_ARGS=("--append-system-prompt" "$DIRECTIVE_PAYLOAD" "${EXTRA_ARGS[@]}")
      fi
      for extra_prompt in "${CUSTOM_APPEND_PROMPTS[@]}"; do
        EXTRA_ARGS+=("--append-system-prompt" "$extra_prompt")
      done
      export CLAUDE_AUTO=0
      unset CLAUDE_PERMISSION_MODE 2>/dev/null || true
    fi

    if [ "$ORCHESTRATOR" -eq 1 ]; then
      if [ "$CLIENT_ID" = "claude" ]; then
        AUTO_FLAGS=()
      elif [ "$CLIENT_ID" = "agy" ]; then
        HAS_DANGEROUS=0
        for arg in "${EXTRA_ARGS[@]}"; do
          if [ "$arg" = "--dangerously-skip-permissions" ]; then
            HAS_DANGEROUS=1
            break
          fi
        done
        if [ "$HAS_DANGEROUS" -eq 0 ]; then
          EXTRA_ARGS=("--dangerously-skip-permissions" "${EXTRA_ARGS[@]}")
        fi
        AUTO_FLAGS=("--dangerously-skip-permissions")
        export AGY_PERMISSION_TIER="dangerous-rescue"
        export AGY_RESCUE=1
        export AGY_DANGEROUSLY_SKIP_PERMISSIONS=1
      fi
    fi

    echo "================================================================================"
    if [ "$ORCHESTRATOR" -eq 1 ]; then
      echo "          AgentScript Autonomous Client Launcher: $CLIENT_NAME"
      echo "                     [ORCHESTRATOR SUPERVISOR MODE]"
    else
      echo "          AgentScript Autonomous Client Launcher: $CLIENT_NAME"
    fi
    echo "================================================================================"
    echo "  • Client ID:            $CLIENT_ID"
    echo "  • Primary Channel:      $PROMPT_CHANNEL"
    if [ "$ORCHESTRATOR" -eq 1 ]; then
      echo "  • Mode:                 AUTONOMOUS MULTI-AGENT ORCHESTRATOR"
      if [ "$CLIENT_ID" = "claude" ]; then
        echo "  • Permission Tier:      SYSTEM-GUIDED (safe permissions; zero dangerous flags)"
      elif [ "$CLIENT_ID" = "agy" ]; then
        echo "  • Permission Tier:      DANGEROUS RESCUE (--dangerously-skip-permissions)"
      fi
      echo "  • Supervisory Model:    $ORCH_MODEL (Reasoning: $ORCH_REASONING)"
      echo "  • Orchestration Target: $ORCH_TARGET (Baseline: native sub-agents; separate-agents decoupled)"
      echo "  • Concurrency Bounds:   Soft limit: $SOFT_LIMIT | Hard limit: $HARD_LIMIT (Burst on Multi-Project)"
      echo "  • Workspace Routing:    Multi-project orchestration across Workspace roots"
      echo "  • Code Execution:       Enabled (supervised gate verification & test runs)"
      echo "  • Context Discipline:   Minimal orchestrator (scalar receipts only; zero context bloat)"
      echo "  • Subagent Routing:"
      echo "      - Research & Web:   $RESEARCH_MODEL (internet browsing, repo-scout, documentation)"
      echo "      - Planning & Arch:  $PLANNING_MODEL (topological DAG, failing gates, ADRs)"
      echo "      - Code Execution:   $EXECUTION_MODEL (isolated branch/share, gate verification)"
      echo "  • Delegation Rule:      MANDATORY SUBAGENT SPAWNING (invoke_subagent in Antigravity, Agent in Claude Code)"
      echo "  • Model Upgrade Path:   gemini-next (forward-compatible architecture)"
    else
      echo "  • Mode:                 DIRECT AGENT HARNESS"
    fi
    if [ -n "$STASH_FILE" ]; then
      echo "  • AGENTS.md Mode:       CONSULTATIVE (inline toolbelt stashed; restore trap armed)"
    else
      echo "  • AGENTS.md Mode:       UNCHANGED (no inline toolbelt found or --no-stash used)"
    fi
    echo "  • Toolbelt Priority:    ASL batch RPC enabled in priority (asl is in PATH)"
    echo "  • Ground Truth:         Strict falsification and git safe-merge enforced"
    if [ -n "$CLIENT_BIN" ]; then
      echo "  • Client Binary:        $CLIENT_BIN"
    else
      echo "  • Client Binary:        [Not found in default PATH]"
    fi
    echo "================================================================================"

    if [ "$DRY_RUN" -eq 1 ]; then
      echo "✓ Pre-flight validation successful (DRY-RUN)."
      echo "Runtime Injection Payload:"
      if [ "$ORCHESTRATOR" -eq 1 ]; then
        echo "  (:launch-session"
        echo "    :client \"$CLIENT_ID\""
        if [ "$CLIENT_ID" = "claude" ]; then
          echo "    :claude-mode \"system-guided\""
          echo "    :auto-flags []"
        elif [ "$CLIENT_ID" = "agy" ]; then
          echo "    :permission-tier \"dangerous-rescue\""
          echo "    :auto-flags [\"--dangerously-skip-permissions\"]"
        fi
        echo "    :channel \"$PROMPT_CHANNEL\""
        echo "    :orchestrator-mode true"
        echo "    :supervisory-model \"$ORCH_MODEL\""
        echo "    :reasoning-level \"$ORCH_REASONING\""
        echo "    :orchestration-target \"$ORCH_TARGET\""
        echo "    :separate-agents-feature-flag $([ "$SEPARATE_AGENTS" -eq 1 ] && echo "true" || echo "false")"
        echo "    :minimal-orchestrator true"
        echo "    :soft-limit $SOFT_LIMIT"
        echo "    :hard-limit $HARD_LIMIT"
        echo "    :max-subagents $HARD_LIMIT"
        echo "    :scaling-condition \"Single project -> max 4 agents (soft limit); burst scaling up to 6 agents (hard limit) triggered exclusively when multiple Workspace projects are actively engaged concurrently.\""
        echo "    :multi-project-orchestration true"
        echo "    :code-execution true"
        echo "    :subagent-tiers (:research \"$RESEARCH_MODEL\" :planning \"$PLANNING_MODEL\" :execution \"$EXECUTION_MODEL\")"
        echo "    :upgrade-path \"gemini-next\""
        echo "    :rules [:asl-toolbelt :ground-truth :git :orchestrator])"
      else
        echo "  (:launch-session :client \"$CLIENT_ID\" :channel \"$PROMPT_CHANNEL\" :toolbelt :active)"
      fi
      cleanup_launch
      trap - EXIT INT TERM HUP
      exit 0
    fi

    if [ -n "$CLIENT_BIN" ]; then
      echo "🚀 Starting $CLIENT_NAME session..."
      EXIT_CODE=0
      if [ -n "$INITIAL_PROMPT" ]; then
        "$CLIENT_BIN" "${EXTRA_ARGS[@]}" "$INITIAL_PROMPT" || EXIT_CODE=$?
      else
        "$CLIENT_BIN" "${EXTRA_ARGS[@]}" || EXIT_CODE=$?
      fi
      cleanup_launch
      trap - EXIT INT TERM HUP
      if [ "$EXIT_CODE" -eq 0 ]; then
        echo "✓ $CLIENT_NAME session ended. Restored consultative buffers."
      else
        echo "Notice: $CLIENT_NAME session ended with exit code $EXIT_CODE."
      fi
      exit "$EXIT_CODE"
    else
      echo "Notice: '$CLIENT_ID' binary was not detected in PATH or standard installation paths."
      echo "The pre-flight environment and consultative AGENTS.md have been staged."
      echo "You can launch $CLIENT_NAME from your terminal/IDE now."
      echo "Press [Enter] to restore AGENTS.md when done, or Ctrl+C to abort."
      read -r _ || true
      cleanup_launch
      trap - EXIT INT TERM HUP
      echo "✓ Restored original workspace configuration."
      exit 0
    fi
}

if [ "$1" = "launch" ]; then
  shift
  run_launch "$@"
  exit $?
fi

exec "$ASL_BIN" "$@"
