#!/usr/bin/env bash
# Pure ASL Grammar & Token Density Verification Gate (Portable POSIX/macOS)
set -eo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
cd "$ROOT"

echo "--> Auditing ASN grammar registries and symbol token density..."

ERRORS=0
TOTAL_CHECKED=0
HIGH_TOKEN_COUNT=0

# Audit grammar.asn registries
for grammar_file in $(find . -maxdepth 4 -name "grammar.asn" | sort); do
  pkg_dir="$(dirname "$grammar_file")"
  echo "    Checking registry: $grammar_file"

  # Extract registered symbol lines (multi-line record aware)
  # Each line: "sym_name:has_rationale"
  registered_map=$(awk '
    /\(:sym/ {
      record = $0;
      while (record !~ /\)/ && (getline next_line) > 0) {
        record = record " " next_line;
      }
      idx = index(record, ":name \"");
      if (idx > 0) {
        rest = substr(record, idx + 7);
        q_idx = index(rest, "\"");
        if (q_idx > 0) {
          name = substr(rest, 1, q_idx - 1);
          has_rat = (record ~ /:rationale[ \t]+"/) ? 1 : 0;
          print name ":" has_rat;
        }
      }
    }
  ' "$grammar_file")

  # Find all exported symbols in package .asl files
  for asl_file in $(find "$pkg_dir" -name "*.asl" 2>/dev/null); do
    # Extract exported symbols from :x [...]
    exported_symbols=$(awk '
      /:x[ \t]*\[/ {
        in_x = 1;
        line = $0;
        sub(/.*:x[ \t]*\[/, "", line);
      }
      in_x {
        if (in_x > 1) line = $0;
        in_x++;
        if (line ~ /\]/) {
          sub(/\].*/, "", line);
          in_x = 0;
        }
        n = split(line, words, /[ \t]+/);
        for (i = 1; i <= n; i++) {
          w = words[i];
          gsub(/^[ \t]+|[ \t]+$/, "", w);
          if (length(w) > 0 && w !~ /^;/) print w;
        }
      }
    ' "$asl_file")

    for sym in $exported_symbols; do
      TOTAL_CHECKED=$((TOTAL_CHECKED + 1))
      # Calculate token count by counting kebab-case hyphen segments
      token_count=$(echo "$sym" | awk -F'-' '{print NF}')
      
      # Check if symbol is in registered_map
      reg_entry=$(echo "$registered_map" | grep "^${sym}:" || true)
      if [ -z "$reg_entry" ]; then
        echo "    ✗ Unregistered symbol: '$sym' in $asl_file (must be registered in $grammar_file)"
        ERRORS=$((ERRORS + 1))
        continue
      fi

      has_rationale=$(echo "$reg_entry" | cut -d':' -f2)

      if [ "$token_count" -gt 2 ]; then
        HIGH_TOKEN_COUNT=$((HIGH_TOKEN_COUNT + 1))
        if [ "$has_rationale" -ne 1 ]; then
          echo "    ✗ High token symbol without rationale: '$sym' ($token_count tokens > 2) in $grammar_file"
          ERRORS=$((ERRORS + 1))
        fi
      fi
    done
  done
done

if [ "$ERRORS" -gt 0 ]; then
  echo "    ✗ Grammar audit failed with $ERRORS error(s)."
  exit 1
fi

echo "    ✓ Audited $TOTAL_CHECKED exported symbols across grammar registries."
echo "    ✓ All symbols <= 2 tokens verified, and all $HIGH_TOKEN_COUNT symbols > 2 tokens carry verified :rationale."
exit 0
