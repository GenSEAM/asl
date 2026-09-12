(module asl-compiler/compact-rewrite-test
  :d "Unit tests for AST token alias replacement rules and pure ASL rewriter pass"
  :x [test-compact-rule-creation
      test-is-compaction-target
      test-default-compaction-rules
      test-rewrite-ast-tokens-basic
      test-rewrite-preserves-literals
      test-rewrite-idempotency
      run-tests]
  :i [(asl-compiler/compact-rewrite :a cr)])

(df test-compact-rule-creation [] -> Bool
  :d "Verifies construction and property access of compaction rules."
  (let [(r1 (cr/make-compaction-rule "string-starts-with?" "txt/starts?" 2))
        (r2 (cr/make-compaction-rule "normalize-path" "v/norm" 2))]
    (assert (= (.-verbose r1) "string-starts-with?") "Rule 1 verbose identifier matches")
    (assert (= (.-compact r1) "txt/starts?") "Rule 1 compact replacement matches")
    (assert (= (.-savings r1) 2) "Rule 1 token savings count matches")
    (assert (= (.-verbose r2) "normalize-path") "Rule 2 verbose identifier matches")
    (assert (= (.-compact r2) "v/norm") "Rule 2 compact replacement matches")
    true))

(df test-is-compaction-target [] -> Bool
  :d "Verifies symbol matching against compaction target list."
  (let [(rules (cr/default-compaction-rules))]
    (assert (cr/is-compaction-target? "string-starts-with?" rules) "string-starts-with? is compaction target")
    (assert (cr/is-compaction-target? "normalize-path" rules) "normalize-path is compaction target")
    (assert (cr/is-compaction-target? "task-claim" rules) "task-claim is compaction target")
    (assert (cr/is-compaction-target? "supervise-step" rules) "supervise-step is compaction target")
    (assert (not (cr/is-compaction-target? "unknown-symbol" rules)) "unknown-symbol is not compaction target")
    (assert (not (cr/is-compaction-target? "+" rules)) "plus operator is not compaction target")
    true))

(df test-default-compaction-rules [] -> Bool
  :d "Verifies default rules count and presence of required canonical rules."
  (let [(rules (cr/default-compaction-rules))
        (cnt (list-length rules))]
    (assert (>= cnt 14) "Default compaction rules count must be at least 14")
    (assert (cr/is-compaction-target? "vfs-read" rules) "vfs-read must be in default rules")
    (assert (cr/is-compaction-target? "vfs-write" rules) "vfs-write must be in default rules")
    (assert (cr/is-compaction-target? "task-complete" rules) "task-complete must be in default rules")
    (assert (cr/is-compaction-target? "supervise-list" rules) "supervise-list must be in default rules")
    true))

(df test-rewrite-ast-tokens-basic [] -> Bool
  :d "Verifies single and multi-symbol rewriting of verbose identifiers."
  (let [(rules (cr/default-compaction-rules))
        (src1 "(string-starts-with? (normalize-path p) \"/root\")")
        (res1 (cr/rewrite-ast-tokens src1 rules))
        (src2 "(task-claim t session) (supervise-step proc 0)")
        (res2 (cr/rewrite-ast-tokens src2 rules))]
    (assert (= res1 "(txt/starts? (v/norm p) \"/root\")") "Rewrites string-starts-with? and normalize-path")
    (assert (= res2 "(task/claim t session) (proc/status proc 0)") "Rewrites task-claim and supervise-step")
    true))

(df test-rewrite-preserves-literals [] -> Bool
  :d "Verifies that string literals and comments are not mutated during AST token rewrite."
  (let [(rules (cr/default-compaction-rules))
        (src1 "(let [(msg \"string-starts-with? in string\")] (string-starts-with? a b))")
        (res1 (cr/rewrite-ast-tokens src1 rules))
        (src2 "; string-starts-with? in comment\n(normalize-path p)")
        (res2 (cr/rewrite-ast-tokens src2 rules))]
    (assert (= res1 "(let [(msg \"string-starts-with? in string\")] (txt/starts? a b))") "Preserves string literals")
    (assert (= res2 "; string-starts-with? in comment\n(v/norm p)") "Preserves comments while rewriting code")
    true))

(df test-rewrite-idempotency [] -> Bool
  :d "Verifies that rewriting already compact code is idempotent."
  (let [(rules (cr/default-compaction-rules))
        (compact-src "(if (txt/starts? (v/norm p) \"/dir\") (task/claim t s) (proc/status p 0))")
        (res1 (cr/rewrite-ast-tokens compact-src rules))
        (res2 (cr/rewrite-ast-tokens res1 rules))]
    (assert (= res1 compact-src) "First pass on already compact code leaves text unchanged")
    (assert (= res2 compact-src) "Second pass remains idempotent")
    true))

(df run-tests [] -> Bool
  :d "Runs all compact rewrite test suites."
  (do
    (assert (test-compact-rule-creation) "test-compact-rule-creation must pass")
    (assert (test-is-compaction-target) "test-is-compaction-target must pass")
    (assert (test-default-compaction-rules) "test-default-compaction-rules must pass")
    (assert (test-rewrite-ast-tokens-basic) "test-rewrite-ast-tokens-basic must pass")
    (assert (test-rewrite-preserves-literals) "test-rewrite-preserves-literals must pass")
    (assert (test-rewrite-idempotency) "test-rewrite-idempotency must pass")
    true))

(run-tests)
