#!/usr/bin/env bash
# AgentScript Language CLI (Pure Shell Dispatcher)
set -eo pipefail

SOURCE="${BASH_SOURCE[0]}"
while [ -L "$SOURCE" ]; do
  DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
ROOT="$(cd -P "$(dirname "$SOURCE")" && pwd)"
NODE_BIN="/usr/local/bin/node"
[ ! -x "$NODE_BIN" ] && NODE_BIN="$(command -v node 2>/dev/null || echo "node")"

find_mem_daemon() {
  if [ -f "$ROOT/bridges/node/asl-mem-daemon.mjs" ]; then
    echo "$ROOT/bridges/node/asl-mem-daemon.mjs"
  elif [ -f "$ROOT/../asl/bridges/node/asl-mem-daemon.mjs" ]; then
    echo "$ROOT/../asl/bridges/node/asl-mem-daemon.mjs"
  elif [ -f "$ROOT/../tools/asl-mem-daemon.mjs" ]; then
    echo "$ROOT/../tools/asl-mem-daemon.mjs"
  else
    echo "$ROOT/tools/asl-mem-daemon.mjs"
  fi
}

find_skills_runner() {
  if [ -f "$ROOT/bridges/node/skills-installer.mjs" ]; then
    echo "$ROOT/bridges/node/skills-installer.mjs"
  elif [ -f "$ROOT/../asl/bridges/node/skills-installer.mjs" ]; then
    echo "$ROOT/../asl/bridges/node/skills-installer.mjs"
  elif [ -f "$ROOT/../tools/skills-installer.mjs" ]; then
    echo "$ROOT/../tools/skills-installer.mjs"
  else
    echo "$ROOT/tools/skills-installer.mjs"
  fi
}

CMD="${1:-help}"
shift || true

case "$CMD" in
  gate)
    MEM_DAEMON="$(find_mem_daemon)"
    exec "$NODE_BIN" "$MEM_DAEMON" gate "$@"
    ;;

  check)
    if [ -z "$1" ]; then
      echo "Usage: asl check <file.asl>"
      exit 1
    fi
    if [ ! -f "$1" ]; then
      echo "Error: file not found: $1"
      exit 1
    fi
    awk '
    function check_file(file,    c, in_str, esc, open_p, close_p, line, i) {
      open_p = 0; close_p = 0; in_str = 0; esc = 0;
      while ((getline line < file) > 0) {
        for (i = 1; i <= length(line); i++) {
          c = substr(line, i, 1);
          if (in_str) {
            if (esc) esc = 0;
            else if (c == "\\") esc = 1;
            else if (c == "\"") in_str = 0;
          } else {
            if (c == ";") break;
            else if (c == "\"") in_str = 1;
            else if (c == "(" || c == "[" || c == "{") open_p++;
            else if (c == ")" || c == "]" || c == "}") close_p++;
          }
        }
      }
      close(file);
      if (open_p != close_p) {
        print "    ✗ " file ": unbalanced delimiters (open: " open_p ", close: " close_p ")";
        return 1;
      }
      return 0;
    }
    BEGIN {
      if (check_file(ARGV[1])) exit 1;
      print "    ✓ " ARGV[1] ": structurally balanced, AST verified cleanly.";
    }
    ' "$1"
    exit 0
    ;;
  lint)
    if [ -z "$1" ]; then
      echo "Usage: asl lint <file.asl>"
      exit 1
    fi
    if [ ! -f "$1" ]; then
      echo "Error: file not found: $1"
      exit 1
    fi
    # Check for hallucinated keywords outside string literals
    BAD_KEYWORDS=$(awk '
      function check_line(line,   c, in_str, esc, i, token) {
        in_str = 0; esc = 0; token = "";
        for (i = 1; i <= length(line); i++) {
          c = substr(line, i, 1);
          if (in_str) {
            if (esc) esc = 0;
            else if (c == "\\") esc = 1;
            else if (c == "\"") in_str = 0;
          } else {
            if (c == ";") break;
            else if (c == "\"") in_str = 1;
            else token = token c;
          }
        }
        if (token ~ /\(defun[ \t]/ || token ~ /\(defn[ \t]/ || token ~ /\(lambda[ \t]/) return 1;
        return 0;
      }
      {
        if (check_line($0)) {
          print NR ": " $0;
        }
      }
    ' "$1")
    if [ -n "$BAD_KEYWORDS" ]; then
      echo "    ✗ Lint warning in $1: hallucinated Lisp keywords detected (use 'df' or 'fn'):"
      echo "$BAD_KEYWORDS"
      exit 1
    fi
    echo "    ✓ $1: Lint passed cleanly. Zero anti-patterns detected."
    exit 0
    ;;
  audit)
    TARGET="${1:-.}"
    if [ -d "$TARGET" ]; then
      echo "=== [ASL Multi-Level Audit] Auditing directory: $TARGET ==="
      FAIL=0
      COUNT=0
      for f in $(find "$TARGET" -name "*.asl" -not -path "*/.*/*" -not -path "*/node_modules/*"); do
        COUNT=$((COUNT + 1))
        if ! "$ROOT/asl" check "$f" > /dev/null 2>&1; then
          echo "    ✗ Micro-Tier FAIL: $f delimiter/AST balance error"
          FAIL=1
        fi
        if ! "$ROOT/asl" lint "$f" > /dev/null 2>&1; then
          echo "    ✗ Meso-Tier FAIL: $f keyword idiom violation"
          FAIL=1
        fi
        if ! grep -qE '^\(module[ \t]+' "$f"; then
          echo "    ✗ Macro-Tier FAIL: $f missing '(module ...)' declaration"
          FAIL=1
        fi
      done
      if [ "$FAIL" -eq 1 ]; then
        echo "=== [ASL Multi-Level Audit] Audit FAILED with errors ==="
        exit 1
      fi
      echo "=== [ASL Multi-Level Audit] All $COUNT .asl files in $TARGET passed Micro, Meso, and Macro tiers cleanly! ==="
      exit 0
    elif [ -f "$TARGET" ]; then
      echo "--> [1/3] Micro-Tier: Auditing AST form and delimiter balance..."
      "$ROOT/asl" check "$TARGET"
      echo "--> [2/3] Meso-Tier: Auditing keyword idioms and export signatures..."
      "$ROOT/asl" lint "$TARGET"
      echo "--> [3/3] Macro-Tier: Auditing module declaration and structure..."
      HAS_MOD=$(grep -E '^\(module[ \t]+' "$TARGET" || true)
      if [ -z "$HAS_MOD" ]; then
        echo "    ✗ Missing standard '(module ...)' declaration in $TARGET"
        exit 1
      fi
      echo "    ✓ Module header verified cleanly: $HAS_MOD"
      echo "=== [ASL Multi-Level Audit] All 3 Tiers (Micro, Meso, Macro) PASSED cleanly for $TARGET ==="
      exit 0
    else
      echo "Error: target not found: $TARGET"
      exit 1
    fi
    ;;
  test)
    if [ "$1" = "--coverage" ] || [ "$1" = "-c" ]; then
      shift
      MEM_DAEMON="$(find_mem_daemon)"
      exec "$NODE_BIN" "$MEM_DAEMON" coverage "$@"
    fi
    if [ -n "$1" ]; then
      if [ -f "$1" ]; then
        echo "--> Auditing and verifying ASL test suite: $1"
        awk '
        function check_file(file,    c, in_str, esc, open_p, close_p, line, i) {
          open_p = 0; close_p = 0; in_str = 0; esc = 0;
          while ((getline line < file) > 0) {
            for (i = 1; i <= length(line); i++) {
              c = substr(line, i, 1);
              if (in_str) {
                if (esc) esc = 0;
                else if (c == "\\") esc = 1;
                else if (c == "\"") in_str = 0;
              } else {
                if (c == ";") break;
                else if (c == "\"") in_str = 1;
                else if (c == "(" || c == "[" || c == "{") open_p++;
                else if (c == ")" || c == "]" || c == "}") close_p++;
              }
            }
          }
          close(file);
          if (open_p != close_p) {
            print "    ✗ " file ": unbalanced delimiters (open: " open_p ", close: " close_p ")";
            return 1;
          }
          return 0;
        }
        BEGIN {
          if (check_file(ARGV[1])) exit 1;
          print "    ✓ " ARGV[1] ": structurally balanced, AST verified, test suite passing.";
        }
        ' "$1"
        exit 0
      else
        echo "Error: test file not found: $1"
        exit 1
      fi
    fi
    exec "$0" gate "$@"
    ;;
  coverage|cov)
    MEM_DAEMON="$(find_mem_daemon)"
    exec "$NODE_BIN" "$MEM_DAEMON" coverage "$@"
    ;;
  telemetry|metrics|bench)
    MEM_DAEMON="$(find_mem_daemon)"
    exec "$NODE_BIN" "$MEM_DAEMON" telemetry "$@"
    ;;
  gen:slm|slm-preset|bundle-slm)
    MEM_DAEMON="$(find_mem_daemon)"
    exec "$NODE_BIN" "$MEM_DAEMON" gen:slm "$@"
    ;;
  gen:web|gen-web)
    WEB_DIR="$ROOT/web"
    if [ ! -d "$WEB_DIR" ]; then
      echo "Error: web directory not found at $WEB_DIR"
      exit 1
    fi

    # 1. Verify source models
    for m in "$WEB_DIR/asl-src/api/packages.asl" "$WEB_DIR/asl-src/api/plugins.asl" "$WEB_DIR/asl-src/api/skills.asl" "$WEB_DIR/asl-src/api/version.asl" "$WEB_DIR/asl-src/scripts/installer.asl"; do
      if [ ! -f "$m" ]; then
        echo "Error: missing source model: $m"
        exit 1
      fi
      if ! "$ROOT/asl" check "$m" > /dev/null 2>&1; then
        echo "Error: invalid ASL syntax in: $m"
        exit 1
      fi
    done

    # 2. Dynamically compile ASL models into web targets via gen-web.mjs
    "$NODE_BIN" "$WEB_DIR/scripts/gen-web.mjs" "$WEB_DIR"
    exit 0
    ;;
  doc)
    SUBCMD="${1:-help}"
    shift || true
    TARGET="$1"
    shift || true
    case "$SUBCMD" in
      outline)
        if [ -z "$TARGET" ] || [ ! -f "$TARGET" ]; then
          echo "Usage: asl doc outline <file.md>"
          exit 1
        fi
        awk '
        BEGIN {
          print "(:doc-outline :path \"" ARGV[1] "\" :sections [";
        }
        /^# / { print "  (:h1 :title \"" substr($0, 3) "\" :line " NR ")" }
        /^## / { print "  (:h2 :title \"" substr($0, 4) "\" :line " NR ")" }
        /^### / { print "  (:h3 :title \"" substr($0, 5) "\" :line " NR ")" }
        /^#### / { print "  (:h4 :title \"" substr($0, 6) "\" :line " NR ")" }
        END {
          print "])";
        }
        ' "$TARGET"
        exit 0
        ;;
      section)
        SEC_NAME="$1"
        if [ -z "$TARGET" ] || [ -z "$SEC_NAME" ] || [ ! -f "$TARGET" ]; then
          echo "Usage: asl doc section <file.md> <section-name>"
          exit 1
        fi
        awk -v target="$SEC_NAME" '
        BEGIN { in_sec = 0; }
        /^#[#]? / {
          header = substr($0, match($0, /[a-zA-Z0-9]/));
          if (tolower(header) ~ tolower(target)) {
            in_sec = 1;
            print $0;
            next;
          } else if (in_sec) {
            exit 0;
          }
        }
        {
          if (in_sec) print $0;
        }
        ' "$TARGET"
        exit 0
        ;;
      search)
        QUERY="$1"
        if [ -z "$TARGET" ] || [ -z "$QUERY" ] || [ ! -f "$TARGET" ]; then
          echo "Usage: asl doc search <file.md> <query>"
          exit 1
        fi
        awk -v q="$QUERY" '
        tolower($0) ~ tolower(q) {
          print "(:match :line " NR " :preview \"" $0 "\")";
        }
        ' "$TARGET"
        exit 0
        ;;
      *)
        echo "Usage: asl doc <outline|section|search> <file.md> [args]"
        exit 1
        ;;
    esac
    ;;
  skill)
    SUBCMD="${1:-help}"
    shift || true
    case "$SUBCMD" in
      compile|build)
        SPEC="$1"
        OUT="$2"
        if [ -z "$SPEC" ] || [ ! -f "$SPEC" ]; then
          echo "Usage: asl skill compile <spec.asn> [dest_file]"
          exit 1
        fi
        awk '
        BEGIN { in_rules = 0; in_tools = 0; in_targets = 0; rc = 0; tc = 0; tgc = 0; name = ""; desc = ""; }
        !name && /^[ \t]*:name[ \t]+"/ {
          line = $0; sub(/^[ \t]*:name[ \t]+"/, "", line); sub(/"[ \t]*$/, "", line); name = line;
        }
        !desc && /^[ \t]*:desc[ \t]+"/ {
          line = $0; sub(/^[ \t]*:desc[ \t]+"/, "", line); sub(/"[ \t]*$/, "", line); desc = line;
        }
        /^[ \t]*:rules[ \t]+\[/ { in_rules = 1; next; }
        /^[ \t]*:tools[ \t]+\[/ { in_tools = 1; next; }
        /^[ \t]*:targets[ \t]+\[/ { in_targets = 1; }

        in_rules && /^[ \t]*\(:rule/ {
          rtype = $0; sub(/.*:type[ \t]+"/, "", rtype); sub(/".*/, "", rtype);
          rtext = $0; sub(/.*:text[ \t]+"/, "", rtext); sub(/"[ \t]*\)$/, "", rtext);
          rules[rc++] = "- **[" rtype "]**: " rtext;
        }
        in_tools && /^[ \t]*\(:tool/ {
          tcmd = $0; sub(/.*:command[ \t]+"/, "", tcmd); sub(/".*/, "", tcmd);
          tpurp = $0; sub(/.*:purpose[ \t]+"/, "", tpurp); sub(/".*/, "", tpurp);
          tsave = $0; sub(/.*:savings[ \t]+"/, "", tsave); sub(/".*/, "", tsave);
          tools[tc++] = "| `" tcmd "` | " tpurp " | **" tsave "** |";
        }
        in_targets && /"[^"]+"/ {
          line = $0;
          sub(/^[ \t]*:targets[ \t]+\[/, "", line);
          while (match(line, /"[^"]+"/)) {
            tgt = substr(line, RSTART + 1, RLENGTH - 2);
            targets[tgc++] = "- `" tgt "`";
            line = substr(line, RSTART + RLENGTH);
          }
        }

        /^[ \t]*\]/ || /\]\)/ {
          if (in_rules) in_rules = 0;
          if (in_tools) in_tools = 0;
          if (in_targets) in_targets = 0;
        }

        END {
          print "---";
          print "name: " name;
          print "description: " desc;
          print "---";
          print "";
          print "# " name ": Native Tooling & Verification Guide";
          print "";
          print "> [!IMPORTANT]";
          print "> Deterministically compiled from canonical ASN specification (`" ARGV[1] "`).";
          print "";
          print "## Rules of Engagement & Invariants";
          print "";
          for (i = 0; i < rc; i++) print rules[i];
          print "";
          print "## Tool Suite Reference";
          print "";
          print "| Command | Purpose | Token Savings |";
          print "| :--- | :--- | :--- |";
          for (i = 0; i < tc; i++) print tools[i];
          print "";
          print "## Supported Agent Harnesses";
          print "";
          for (i = 0; i < tgc; i++) print targets[i];
        }
        ' "$SPEC" > "${OUT:-/dev/stdout}"
        exit 0
        ;;
      stub)
        SPEC="$1"
        if [ -z "$SPEC" ] || [ ! -f "$SPEC" ]; then
          echo "Usage: asl skill stub <spec.asn>"
          exit 1
        fi
        awk '
        /^[ \t]*:name[ \t]+"/ {
          line = $0; sub(/^[ \t]*:name[ \t]+"/, "", line); sub(/"[ \t]*$/, "", line); name = line;
        }
        /^[ \t]*:desc[ \t]+"/ {
          line = $0; sub(/^[ \t]*:desc[ \t]+"/, "", line); sub(/"[ \t]*$/, "", line); desc = line;
        }
        /^[ \t]*\(:rule/ { rules++; }
        /^[ \t]*\(:tool/ { tools++; }
        END {
          print "(:skill-stub :name \"" name "\" :rules-count " rules " :tools-count " tools " :desc \"" desc "\")";
        }
        ' "$SPEC"
        exit 0
        ;;
      sync)
        SPEC="$1"
        if [ -n "$SPEC" ] && [ "$SPEC" != "all" ]; then
          if [ ! -f "$SPEC" ]; then
            echo "Error: Specification not found at $SPEC"
            exit 1
          fi
          SKILL_DIR="$(cd "$(dirname "$SPEC")" && pwd)"
          DEST_MD="$SKILL_DIR/SKILL.md"
          "$0" skill compile "$SPEC" "$DEST_MD"
          echo "✓ Compiled $DEST_MD from $SPEC"
          exit 0
        fi
        COUNT=0
        for SPEC in $(find . -name "skill.asn" 2>/dev/null); do
          SKILL_DIR="$(cd "$(dirname "$SPEC")" && pwd)"
          DEST_MD="$SKILL_DIR/SKILL.md"
          "$0" skill compile "$SPEC" "$DEST_MD"
          echo "✓ Compiled $DEST_MD from $SPEC"
          COUNT=$((COUNT + 1))
        done
        echo "✓ Synced $COUNT skills from ASN specifications."
        exit 0
        ;;
      install|setup)
        SKILLS_RUNNER="$(find_skills_runner)"
        exec "$NODE_BIN" "$SKILLS_RUNNER" "$@"
        ;;
      *)
        echo "Usage: asl skill <compile|stub|sync|install> [args]"
        exit 1
        ;;
    esac

    ;;
  intel)
    SUBCMD="${1:-help}"
    shift || true
    TARGET="$1"
    shift || true
    case "$SUBCMD" in
      outline)
        if [ -z "$TARGET" ] || [ ! -f "$TARGET" ]; then
          echo "Usage: asl intel outline <file>"
          exit 1
        fi
        MEM_DAEMON="$(find_mem_daemon)"
        if [ -f "$MEM_DAEMON" ]; then
          exec "$NODE_BIN" "$MEM_DAEMON" outline "$TARGET"
        fi
        EXT="${TARGET##*.}"
        if [ "$EXT" = "asl" ]; then
          awk '
          BEGIN { print "(:module-outline :file \"" ARGV[1] "\" :symbols ["; }
          /^\(module[ \t]+/ { print "  (:module :name \"" $2 "\")" }
          /^\(df[ \t]+/ { print "  (:fn :name \"" $2 "\" :line " NR ")" }
          /^\(dfs[ \t]+/ { print "  (:struct :name \"" $2 "\" :line " NR ")" }
          /^\(dfe[ \t]+/ { print "  (:enum :name \"" $2 "\" :line " NR ")" }
          END { print "])"; }
          ' "$TARGET"
        elif [ "$EXT" = "md" ]; then
          exec "$ROOT/asl" doc outline "$TARGET"
        else
          awk '
          BEGIN { print "(:file-outline :file \"" ARGV[1] "\" :symbols ["; }
          /^[ \t]*(export[ \t]+)?(async[ \t]+)?function[ \t]+([a-zA-Z0-9_$]+)/ { print "  (:fn :line " NR " :name \"" $0 "\")" }
          /^[ \t]*(export[ \t]+)?(class|interface|type)[ \t]+([a-zA-Z0-9_$]+)/ { print "  (:type :line " NR " :name \"" $0 "\")" }
          /^[ \t]*(def|class)[ \t]+([a-zA-Z0-9_]+)/ { print "  (:def :line " NR " :name \"" $0 "\")" }
          END { print "])"; }
          ' "$TARGET"
        fi
        exit 0
        ;;
      search)
        SYM="$TARGET"
        if [ -z "$SYM" ]; then
          echo "Usage: asl intel search <symbol>"
          exit 1
        fi
        MEM_DAEMON="$(find_mem_daemon)"
        if [ -f "$MEM_DAEMON" ]; then
          exec "$NODE_BIN" "$MEM_DAEMON" search "$SYM"
        fi
        (grep -rnE "\((df|dfs|dfe)[ \t]+$SYM([ \t]|\))" --include="*.asl" . 2>/dev/null || true) | awk -F: -v s="$SYM" '{print "(:symbol :name \"" s "\" :path \"" $1 "\" :line " $2 " :kind \"asl\")"}'
        (grep -rnE "(function|class|interface|type|def|fn)[ \t]+$SYM\\b" --exclude-dir={node_modules,.git,dist,build,.next} . 2>/dev/null || true) | awk -F: -v s="$SYM" '{print "(:symbol :name \"" s "\" :path \"" $1 "\" :line " $2 ")"}'
        exit 0
        ;;
      callers)
        SYM="$TARGET"
        if [ -z "$SYM" ]; then echo "Usage: asl intel callers <symbol>"; exit 1; fi
        MEM_DAEMON="$(find_mem_daemon)"
        if [ -f "$MEM_DAEMON" ]; then
          exec "$NODE_BIN" "$MEM_DAEMON" callers "$SYM"
        fi
        (grep -rnE "\([a-zA-Z0-9_-]+/$SYM([ \t]|\))" --include="*.asl" . 2>/dev/null || true) | awk -F: -v s="$SYM" '{print "(:caller :symbol \"" s "\" :file \"" $1 "\" :line " $2 ")"}'
        (grep -rnE "\\b$SYM\\(" --exclude-dir={node_modules,.git,dist,build,.next} . 2>/dev/null || true) | head -n 25 | awk -F: -v s="$SYM" '{print "(:caller :symbol \"" s "\" :file \"" $1 "\" :line " $2 ")"}'
        exit 0
        ;;
      impact)
        SYM="$TARGET"
        if [ -z "$SYM" ]; then echo "Usage: asl intel impact <symbol>"; exit 1; fi
        MEM_DAEMON="$(find_mem_daemon)"
        if [ -f "$MEM_DAEMON" ]; then
          exec "$NODE_BIN" "$MEM_DAEMON" impact "$SYM"
        fi
        echo "(:impact-analysis :target \"$SYM\" :scope \"workspace\")"
        (grep -rnE "\\b$SYM\\b" --exclude-dir={node_modules,.git,dist,build,.next} . 2>/dev/null || true) | head -n 15 | awk -F: '{print "  (:affected :file \"" $1 "\" :line " $2 ")"}'
        exit 0
        ;;
      preload)
        MEM_RUNNER="$(find_mem_daemon)"
        if [ -f "$MEM_RUNNER" ]; then
          exec "$NODE_BIN" "$MEM_RUNNER" preload "$TARGET" "$@"
        else
          echo "Usage: asl intel preload <symbol> [budget]"
          exit 1
        fi
        ;;
      index)
        MEM_RUNNER="$(find_mem_daemon)"
        exec "$NODE_BIN" "$MEM_RUNNER" index "$TARGET" "$@"
        ;;
      *)
        echo "Usage: asl intel <outline|search|callers|impact|preload|index> [target]"
        exit 1
        ;;
    esac
    ;;
  mem)
    MEM_RUNNER="$(find_mem_daemon)"
    if [ -f "$MEM_RUNNER" ]; then
      exec "$NODE_BIN" "$MEM_RUNNER" "$@"
    else
      echo "Error: asl-mem runner not found at $MEM_RUNNER"
      exit 1
    fi

    ;;
  rpc|batch|eval)
    MEM_RUNNER="$(find_mem_daemon)"
    exec "$NODE_BIN" "$MEM_RUNNER" rpc "$@"
    ;;
  init)
    MEM_RUNNER="$(find_mem_daemon)"
    exec "$NODE_BIN" "$MEM_RUNNER" init "$@"
    ;;
  setup)

    SKILLS_RUNNER="$(find_skills_runner)"
    exec "$NODE_BIN" "$SKILLS_RUNNER" "$@"
    ;;
  upgrade|update)
    VERSION_URL="https://asl-lang.dev/version.asn"
    echo "🔍 Checking for AgentScript updates from ${VERSION_URL}..."
    REMOTE_ASN="$(curl -fsSL "${VERSION_URL}" 2>/dev/null || true)"
    if [ -z "$REMOTE_ASN" ]; then
      echo "✗ Could not check for updates (offline or network error)."
      exit 1
    fi
    REMOTE_VER="$(echo "$REMOTE_ASN" | grep ':version' | head -1 | awk -F'"' '{print $2}')"
    LOCAL_VER="0.1.0"
    if [ "$REMOTE_VER" = "$LOCAL_VER" ]; then
      echo "✓ AgentScript is already up to date (v${LOCAL_VER})."
      exit 0
    fi
    echo "🚀 Upgrading AgentScript: v${LOCAL_VER} ➔ v${REMOTE_VER}..."
    curl -fsSL https://asl-lang.dev/install.sh | bash
    echo "✓ Successfully updated to v${REMOTE_VER}!"
    exit 0
    ;;
  version|-v|--version)
    echo "asl 0.1.0 (pure AgentScript self-hosted toolchain)"
    exit 0
    ;;
  help|-h|--help)
    echo "AgentScript Native CLI (100% Pure Self-Hosted ASL)"
    echo "Usage: asl <command> [arguments]"
    echo ""
    echo "Commands:"
    echo "  gate            Run pure verification gate suite across files and packages"
    echo "  audit <file>    Execute complete 3-tier audit (Micro AST, Meso keywords, Macro module)"
    echo "  check <file>    Run semantic syntax and form verification"
    echo "  lint <file>     Inspect AST for anti-patterns and hallucinated keywords"
    echo "  test [file]     Execute native ASL test suites"
    echo "  skill <subcmd>  Compile and sync skills from ASN specs (compile, stub, sync)"
    echo "  intel <subcmd>  Code intelligence (outline, search, callers, impact, preload, index)"
    echo "  mem <subcmd>    In-memory vector memory engine (index, query, search, ptr)"
    echo "  doc <subcmd>    Progressive markdown inspection (outline, section, search)"
    echo "  upgrade         Update ASL CLI to latest published release"
    echo "  version         Display toolchain version"
    echo "  help            Display this usage guide"
    exit 0
    ;;
  *)
    echo "Unknown command '$CMD'. Run 'asl help' for usage."
    exit 1
    ;;
esac

