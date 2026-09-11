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
    PRINT_PAYLOAD=0
    NO_STASH=0
    ORCHESTRATOR=0
    ORCH_MODEL="gemini-3.8-flash"
    ORCH_REASONING="high"
    RESEARCH_MODEL="flash"
    PLANNING_MODEL="pro"
    EXECUTION_MODEL="inherit"
    ROLE_SCOUT=""
    ROLE_PLANNER=""
    ROLE_IMPLEMENTER=""
    ROLE_AUDITOR=""
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
        agy|antigravity|claude|claude-code|codex|openai-codex|openai|cursor|windsurf|gemini|agi)
          if [ -z "$TARGET_AGENT" ]; then
            TARGET_AGENT="$1"
            shift
          else
            EXTRA_ARGS+=("$1")
            shift
          fi
          ;;
        help|--help|-h)
          TARGET_AGENT="help"
          shift
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
            codex-audit|codex-review)
              ORCH_MODEL="gemini-3.8-flash"
              ORCH_REASONING="high"
              SOFT_LIMIT=4
              HARD_LIMIT=6
              MAX_AGENTS=6
              RESEARCH_MODEL="flash"
              PLANNING_MODEL="pro"
              EXECUTION_MODEL="inherit"
              ROLE_SCOUT="asl"
              ROLE_PLANNER="pro"
              ROLE_IMPLEMENTER="agy"
              ROLE_AUDITOR="codex"
              ;;
            codex-astro|codex-astro-high|astro-high|astro)
              ORCH_MODEL="gemini-3.8-flash"
              ORCH_REASONING="high"
              SOFT_LIMIT=4
              HARD_LIMIT=6
              MAX_AGENTS=6
              RESEARCH_MODEL="flash"
              PLANNING_MODEL="astro-high"
              EXECUTION_MODEL="inherit"
              ROLE_SCOUT="asl"
              ROLE_PLANNER="codex"
              ROLE_IMPLEMENTER="agy"
              ROLE_AUDITOR="codex"
              ;;
            codex-planner|codex-plan|codex-planning|codex-plan-audit|codex-architect)
              ORCH_MODEL="gemini-3.8-flash"
              ORCH_REASONING="high"
              SOFT_LIMIT=4
              HARD_LIMIT=6
              MAX_AGENTS=6
              RESEARCH_MODEL="flash"
              PLANNING_MODEL="codex"
              EXECUTION_MODEL="inherit"
              ROLE_SCOUT="asl"
              ROLE_PLANNER="codex"
              ROLE_IMPLEMENTER="agy"
              ROLE_AUDITOR="codex"
              ;;
            antigravity-solo|agy-solo)
              ORCH_MODEL="gemini-3.8-flash"
              ORCH_REASONING="high"
              SOFT_LIMIT=4
              HARD_LIMIT=6
              MAX_AGENTS=6
              RESEARCH_MODEL="flash"
              PLANNING_MODEL="pro"
              EXECUTION_MODEL="inherit"
              ROLE_SCOUT="asl"
              ROLE_PLANNER="pro"
              ROLE_IMPLEMENTER="agy"
              ROLE_AUDITOR="pro"
              ;;
            claude-audit|claude-review)
              ORCH_MODEL="gemini-3.8-flash"
              ORCH_REASONING="high"
              SOFT_LIMIT=4
              HARD_LIMIT=6
              MAX_AGENTS=6
              RESEARCH_MODEL="flash"
              PLANNING_MODEL="pro"
              EXECUTION_MODEL="inherit"
              ROLE_SCOUT="asl"
              ROLE_PLANNER="pro"
              ROLE_IMPLEMENTER="agy"
              ROLE_AUDITOR="claude"
              ;;
            fast-research|research)
              ORCH_MODEL="gemini-3.8-flash"
              ORCH_REASONING="low"
              SOFT_LIMIT=4
              HARD_LIMIT=6
              MAX_AGENTS=6
              RESEARCH_MODEL="flash"
              PLANNING_MODEL="flash"
              EXECUTION_MODEL="inherit"
              ROLE_SCOUT="asl"
              ROLE_PLANNER="flash"
              ROLE_IMPLEMENTER="agy"
              ROLE_AUDITOR="flash"
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
              ROLE_SCOUT="asl"
              ROLE_PLANNER="pro"
              ROLE_IMPLEMENTER="agy"
              ROLE_AUDITOR="codex"
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
              ROLE_SCOUT="asl"
              ROLE_PLANNER="pro"
              ROLE_IMPLEMENTER="agy"
              ROLE_AUDITOR="codex"
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
              ROLE_SCOUT="asl"
              ROLE_PLANNER="pro"
              ROLE_IMPLEMENTER="agy"
              ROLE_AUDITOR="codex"
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
              ROLE_SCOUT="asl"
              ROLE_PLANNER="pro"
              ROLE_IMPLEMENTER="agy"
              ROLE_AUDITOR="codex"
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
        --scout)
          ROLE_SCOUT="$2"
          shift 2
          ;;
        --planner|--plan)
          ROLE_PLANNER="$2"
          shift 2
          ;;
        --plan-model|--planning-model)
          PLANNING_MODEL="$2"
          shift 2
          ;;
        --implementer|--impl)
          ROLE_IMPLEMENTER="$2"
          EXECUTION_MODEL="$2"
          shift 2
          ;;
        --auditor|--audit)
          ROLE_AUDITOR="$2"
          shift 2
          ;;
        --dry-run|-n)
          DRY_RUN=1
          shift
          ;;
        --print-payload)
          PRINT_PAYLOAD=1
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
              --print-payload)
                PRINT_PAYLOAD=1
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
      codex|openai-codex|openai)
        CLIENT_ID="codex"
        CLIENT_NAME="Codex CLI (OpenAI)"
        PROMPT_CHANNEL="AGENTS.md"
        BIN_NAMES=("$HOME/.local/bin/codex" "/opt/homebrew/bin/codex" "/usr/local/bin/codex" "codex")
        ;;
      help|--help|-h)
        echo "Usage: asl launch <agy|claude|codex|cursor|windsurf> [--orchestrator|-o] [--preset <name>] [--model <name>] [--reasoning <level>] [--soft-limit <n>] [--hard-limit <n>] [--multi-project] [--code-exec] [--dry-run] [--no-stash] [--prompt <msg>] [-- <agent-args...>]"
        echo ""
        echo "Launches target agent with runtime ASL toolbelt injection and consultative AGENTS.md isolation."
        echo ""
        echo "Orchestration Options:"
        echo "  --orchestrator, -o    Enable autonomous multi-agent orchestration supervisor mode"
        echo "                        (Claude Code: automatic mode; Antigravity: dangerous rescue permissions)"
        echo "  --preset, -P <name>   Preset: codex-astro-high, codex-planner, codex-audit, codex-plan-audit, antigravity-solo, claude-audit, balanced, deep-architecture, fast-research"
        echo "  --model, -m <model>   Supervisory orchestrator model (default: gemini-3.8-flash)"
        echo "  --reasoning, -r <lvl> Reasoning depth: low, medium, high, max (default: high)"
        echo "  --soft-limit <n>      Soft limit for concurrent subagents within single project (default: 4)"
        echo "  --hard-limit <n>      Hard limit for concurrent subagents across multi-project bursts (default: 6)"
        echo "  --multi-project       Enable multi-project workspace routing across projects"
        echo "  --code-exec           Enable supervised code execution and gate verification (default: 1)"
        echo ""
        echo "Role Assignment Options:"
        echo "  --scout <agent>       Agent/model for Scout role (default: asl)"
        echo "  --planner, --plan <m> Agent/model for Planner/Architect role (default: pro)"
        echo "  --implementer, --impl <agent> Agent/model for Implementer role (default: agy)"
        echo "  --auditor, --audit <agent>   Agent/model for Auditor/Critic role (default: codex)
  --plan-model <model>         Planning model specification (e.g. astro-high, pro, codex)"
        exit 0
        ;;
      *)
        echo "Usage: asl launch <agy|claude|codex|cursor|windsurf> [--orchestrator|-o] [--preset <name>] [--model <name>] [--reasoning <level>] [--soft-limit <n>] [--hard-limit <n>] [--multi-project] [--code-exec] [--dry-run] [--no-stash] [--prompt <msg>] [-- <agent-args...>]"
        echo ""
        echo "Launches target agent with runtime ASL toolbelt injection and consultative AGENTS.md isolation."
        echo ""
        echo "Orchestration Options:"
        echo "  --orchestrator, -o    Enable autonomous multi-agent orchestration supervisor mode"
        echo "                        (Claude Code: automatic mode; Antigravity: dangerous rescue permissions)"
        echo "  --preset, -P <name>   Preset: codex-astro-high, codex-planner, codex-audit, codex-plan-audit, antigravity-solo, claude-audit, balanced, deep-architecture, fast-research"
        echo "  --model, -m <model>   Supervisory orchestrator model (default: gemini-3.8-flash)"
        echo "  --reasoning, -r <lvl> Reasoning depth: low, medium, high, max (default: high)"
        echo "  --soft-limit <n>      Soft limit for concurrent subagents within single project (default: 4)"
        echo "  --hard-limit <n>      Hard limit for concurrent subagents across multi-project bursts (default: 6)"
        echo "  --multi-project       Enable multi-project workspace routing across projects"
        echo "  --code-exec           Enable supervised code execution and gate verification (default: 1)"
        echo ""
        echo "Role Assignment Options:"
        echo "  --scout <agent>       Agent/model for Scout role (default: asl)"
        echo "  --planner, --plan <m> Agent/model for Planner/Architect role (default: pro)"
        echo "  --implementer, --impl <agent> Agent/model for Implementer role (default: agy)"
        echo "  --auditor, --audit <agent>   Agent/model for Auditor/Critic role (default: codex)
  --plan-model <model>         Planning model specification (e.g. astro-high, pro, codex)"
        exit 1
        ;;
    esac

    ROLE_SCOUT="${ROLE_SCOUT:-asl}"
    ROLE_PLANNER="${ROLE_PLANNER:-$PLANNING_MODEL}"
    ROLE_IMPLEMENTER="${ROLE_IMPLEMENTER:-$CLIENT_ID}"
    ROLE_AUDITOR="${ROLE_AUDITOR:-codex}"

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
      agy|codex)
        CHANNEL_FILE="$WS_ROOT/AGENTS.md"
        ;;
    esac

    DIRECTIVE_PAYLOAD='<!-- ASL_RULES_START -->
(:rules :v 7 :src ADR-0081 :when [:scout :plan :implement :grade :all]
  (:rule :id tools :when [:scout :implement]
    :do "prefer asl rpc (:batch (:sym x) (:out f) (:read f a b) (:sec f h) (:ls d) (:callers x) (:impact x)) in one roundtrip; use host tools for content search and file edits until :grep and staged :edit ship"
    :not "treat :status ok as success; :find is a filename glob; :q is unimplemented; :edit writes disk immediately and :diff :discard do not stage")
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
    :do "concise commits; verify base, diff and log before merge; intended changes only; commit only when asked"
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

    AGY_DANGEROUS=0
    for arg in "${EXTRA_ARGS[@]}"; do
      if [ "$arg" = "--dangerously-skip-permissions" ]; then
        AGY_DANGEROUS=1
        break
      fi
    done

    if [ "$ORCHESTRATOR" -eq 1 ]; then
      ORCH_DIRECTIVE="

<!-- ORCHESTRATOR_START -->
(:launch-session
  :client \"$CLIENT_ID\""
      if [ "$CLIENT_ID" = "claude" ]; then
        ORCH_DIRECTIVE="$ORCH_DIRECTIVE
  :claude-mode \"auto\"
  :permission-tier \"auto-approval\"
  :auto-flags [\"--permission-mode\" \"auto\"]"
        ORCH_MANDATES='    \"Delegate read-only discovery and independent review to Agent subagents; writes stay single-threaded; ingest only receipts.\"
    \"Run in native Auto mode; never pass dangerous escape flags; the system prompt is append-only.\"
    \"Prefer asl rpc (:batch ...) in one roundtrip; fall back to host tools where an op is unimplemented.\"'
      elif [ "$CLIENT_ID" = "agy" ]; then
        ORCH_DIRECTIVE="$ORCH_DIRECTIVE
  :permission-tier \"dangerous-rescue\"
  :auto-flags [\"--dangerously-skip-permissions\"]"
        ORCH_MANDATES='    \"Delegate read-only discovery and independent review via invoke_subagent; writes stay single-threaded; ingest only receipts.\"
    \"Execute in dangerous rescue mode for unattended self-healing.\"
    \"Prefer asl rpc (:batch ...) in one roundtrip; fall back to host tools where an op is unimplemented.\"'
      elif [ "$CLIENT_ID" = "codex" ]; then
        ORCH_DIRECTIVE="$ORCH_DIRECTIVE
  :codex-mode \"autorun-supervised\"
  :permission-tier \"bounded-autonomous\"
  :auto-flags [\"-a\" \"never\" \"-s\" \"workspace-write\"]"
        ORCH_MANDATES='    \"Bounded autonomy (-a never -s workspace-write); writes stay single-threaded; ingest only receipts.\"
    \"Prefer asl rpc (:batch ...) in one roundtrip; fall back to host tools where an op is unimplemented.\"'
      fi
      ORCH_DIRECTIVE="$ORCH_DIRECTIVE
  :channel \"$PROMPT_CHANNEL\"
  :orchestrator-mode true
  :soft-limit $SOFT_LIMIT
  :hard-limit $HARD_LIMIT
  :mandates [
$ORCH_MANDATES
  ]
  :rules [:asl-rules-v4])
<!-- ORCHESTRATOR_END -->"
      DIRECTIVE_PAYLOAD="$DIRECTIVE_PAYLOAD$ORCH_DIRECTIVE"
    fi
    if [ "$PRINT_PAYLOAD" -eq 1 ]; then
      printf '%s\n' "$DIRECTIVE_PAYLOAD"
      exit 0
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
          if ! grep -q "ASL_RULES_START" "$CHANNEL_FILE" 2>/dev/null; then
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
        if grep -q "ASL_RULES_START" "$AGENTS_FILE" 2>/dev/null; then
          STASH_FILE="/tmp/asl_agents_stash_$$"
          cp -f "$AGENTS_FILE" "$STASH_FILE"
          trap cleanup_launch EXIT INT TERM HUP
          awk '
          /<!-- ASL_RULES_START -->/ { in_tb = 1; next; }
          /<!-- ASL_RULES_END -->/ { in_tb = 0; next; }
          !in_tb { print; }
          ' "$AGENTS_FILE" > "$AGENTS_FILE.tmp" && mv -f "$AGENTS_FILE.tmp" "$AGENTS_FILE"
        fi
      fi
    fi

    CLIENT_BIN=""
    for CANDIDATE in "${BIN_NAMES[@]}"; do
      RESOLVED=""
      if [ -x "$CANDIDATE" ]; then
        RESOLVED="$CANDIDATE"
      elif command -v "$CANDIDATE" >/dev/null 2>&1; then
        RESOLVED="$(command -v "$CANDIDATE")"
      fi
      if [ -n "$RESOLVED" ]; then
        if "$RESOLVED" --version >/dev/null 2>&1; then
          CLIENT_BIN="$RESOLVED"
          break
        fi
      fi
    done

    CODEX_AUTORUN=0
    CODEX_SANDBOX=0
    CODEX_EXEC=0
    CODEX_DANGEROUS=0
    if [ "$CLIENT_ID" = "codex" ] && [ -n "$CLIENT_BIN" ]; then
      CODEX_HELP="$("$CLIENT_BIN" --help 2>&1 || true)"
      if echo "$CODEX_HELP" | grep -qE -- "--ask-for-approval|-a\b"; then
        CODEX_AUTORUN=1
      fi
      if echo "$CODEX_HELP" | grep -qE -- "--sandbox|-s\b"; then
        CODEX_SANDBOX=1
      fi
      if echo "$CODEX_HELP" | grep -qE -- "\bexec\b"; then
        CODEX_EXEC=1
      fi
      if echo "$CODEX_HELP" | grep -qE -- "--dangerously-bypass-approvals-and-sandbox"; then
        CODEX_DANGEROUS=1
      fi
    fi

    export ASL_LAUNCHED=1
    export ASL_CLIENT="$CLIENT_ID"
    export ASL_TOOLBELT_ACTIVE=1
    export ASL_ORCHESTRATOR="$ORCHESTRATOR"
    export ASL_ORCHESTRATOR_MODEL="$ORCH_MODEL"
    export ASL_REASONING_LEVEL="$ORCH_REASONING"
    export ASL_RESEARCH_MODEL="$RESEARCH_MODEL"
    export ASL_PLANNING_MODEL="$PLANNING_MODEL"
    export ASL_EXECUTION_MODEL="$EXECUTION_MODEL"
    export ASL_ROLE_SCOUT="$ROLE_SCOUT"
    export ASL_ROLE_PLANNER="$ROLE_PLANNER"
    export ASL_ROLE_IMPLEMENTER="$ROLE_IMPLEMENTER"
    export ASL_ROLE_AUDITOR="$ROLE_AUDITOR"
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
        HAS_PERM_MODE=0
        for ((i=0; i<${#EXTRA_ARGS[@]}; i++)); do
          if [ "${EXTRA_ARGS[i]}" = "--permission-mode" ]; then
            HAS_PERM_MODE=1
            break
          fi
        done
        if [ "$HAS_PERM_MODE" -eq 0 ]; then
          EXTRA_ARGS=("--permission-mode" "auto" "${EXTRA_ARGS[@]}")
          AUTO_FLAGS+=("--permission-mode" "auto")
        fi
        export CLAUDE_AUTO=1
        export CLAUDE_PERMISSION_MODE="auto"
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
      elif [ "$CLIENT_ID" = "codex" ]; then
        AUTO_FLAGS=()
        if [ "$CODEX_AUTORUN" -eq 1 ]; then
          HAS_APPROVAL_ARG=0
          for ((i=0; i<${#EXTRA_ARGS[@]}; i++)); do
            if [ "${EXTRA_ARGS[i]}" = "-a" ] || [ "${EXTRA_ARGS[i]}" = "--ask-for-approval" ]; then
              HAS_APPROVAL_ARG=1
              break
            fi
          done
          if [ "$HAS_APPROVAL_ARG" -eq 0 ]; then
            EXTRA_ARGS=("-a" "never" "${EXTRA_ARGS[@]}")
            AUTO_FLAGS+=("-a" "never")
          fi
        fi
        if [ "$CODEX_SANDBOX" -eq 1 ]; then
          HAS_SANDBOX_ARG=0
          for ((i=0; i<${#EXTRA_ARGS[@]}; i++)); do
            if [ "${EXTRA_ARGS[i]}" = "-s" ] || [ "${EXTRA_ARGS[i]}" = "--sandbox" ]; then
              HAS_SANDBOX_ARG=1
              break
            fi
          done
          if [ "$HAS_SANDBOX_ARG" -eq 0 ]; then
            EXTRA_ARGS=("-s" "workspace-write" "${EXTRA_ARGS[@]}")
            AUTO_FLAGS+=("-s" "workspace-write")
          fi
        fi
        export CODEX_ORCHESTRATOR=1
        export CODEX_AUTO=1
        export CODEX_APPROVAL_POLICY="never"
        export CODEX_SANDBOX="workspace-write"
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
        echo "  • Permission Tier:      AUTO-APPROVAL (--permission-mode auto; zero dangerous flags)"
      elif [ "$CLIENT_ID" = "agy" ]; then
        echo "  • Permission Tier:      DANGEROUS RESCUE (--dangerously-skip-permissions)"
      elif [ "$CLIENT_ID" = "codex" ]; then
        if [ "$CODEX_AUTORUN" -eq 1 ]; then
          echo "  • Permission Tier:      AUTORUN SUPERVISED (-a never -s workspace-write)"
          echo "  • Autorun Capability:   DETECTED (Unattended: yes, Sandbox: workspace-write$([ "$CODEX_EXEC" -eq 1 ] && echo ", Exec: available"))"
        else
          echo "  • Permission Tier:      STANDARD INTERACTIVE"
          echo "  • Autorun Capability:   NOT DETECTED (Interactive approvals required)"
        fi
      fi
      echo "  • Supervisory Model:    $ORCH_MODEL (Reasoning: $ORCH_REASONING)"
      echo "  • Orchestration Target: $ORCH_TARGET (Baseline: native sub-agents; separate-agents decoupled)"
      echo "  • Concurrency Bounds:   Soft limit: $SOFT_LIMIT | Hard limit: $HARD_LIMIT (Burst on Multi-Project)"
      echo "  • Workspace Routing:    Multi-project orchestration across Workspace roots"
      echo "  • Code Execution:       Enabled (supervised gate verification & test runs)"
      echo "  • Context Discipline:   Minimal orchestrator (scalar receipts only; zero context bloat)"
      echo "  • Role-to-Agent Mesh:"
      echo "      - Scout (Signal Keeper):        $ROLE_SCOUT"
      echo "      - Planner (Invariant Architect): $ROLE_PLANNER"
      echo "      - Implementer (Delta Executor):  $ROLE_IMPLEMENTER"
      echo "      - Auditor (Falsifiable Critic):  $ROLE_AUDITOR"
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
          echo "    :claude-mode \"auto\""
          echo "    :permission-tier \"auto-approval\""
          echo "    :auto-flags [\"--permission-mode\" \"auto\"]"
        elif [ "$CLIENT_ID" = "agy" ]; then
          echo "    :permission-tier \"dangerous-rescue\""
          echo "    :auto-flags [\"--dangerously-skip-permissions\"]"
        elif [ "$CLIENT_ID" = "codex" ]; then
          echo "    :codex-mode \"autorun-supervised\""
          echo "    :auto-flags [\"-a\" \"never\" \"-s\" \"workspace-write\"]"
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
        echo "    :role-assignments (:scout \"$ROLE_SCOUT\" :planner \"$ROLE_PLANNER\" :implementer \"$ROLE_IMPLEMENTER\" :auditor \"$ROLE_AUDITOR\")"
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
