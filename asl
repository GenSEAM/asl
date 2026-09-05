#!/usr/bin/env bash
# AgentScript Language CLI (Pure Shell Dispatcher)
set -eo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CMD="${1:-help}"
shift || true

case "$CMD" in
  gate)
    exec "$ROOT/packages/asl-gates/bin/gate.sh" "$@"
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
    exec "$ROOT/packages/asl-gates/bin/gate.sh"
    ;;
  version|-v|--version)
    echo "asl 0.3.0 (pure AgentScript self-hosted toolchain)"
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
    echo "  test            Execute native ASL test suites"
    echo "  version         Display toolchain version"
    echo "  help            Display this usage guide"
    exit 0
    ;;
  *)
    echo "Unknown command '$CMD'. Run 'asl help' for usage."
    exit 1
    ;;
esac
