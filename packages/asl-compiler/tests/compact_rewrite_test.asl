(module asl-compiler/compactRewriteTest
  :d "Unit tests for AST token alias replacement rules and pure ASL rewriter pass"
  :x [testCompactRuleCreation
      testIsCompactionTarget
      testDefaultCompactionRules
      testRewriteAstTokensBasic
      testRewritePreservesLiterals
      testRewriteIdempotency
      runTests]
  :i [(asl-compiler/compactRewrite :a cr)])

(df testCompactRuleCreation [] -> Bool
  :d "Verifies construction and property access of compaction rules."
  (let [(r1 (cr/makeCompactionRule "string-starts-with?" "txt/starts?" 2))
        (r2 (cr/makeCompactionRule "normalize-path" "v/norm" 2))]
    (assert (= (.-verbose r1) "string-starts-with?") "Rule 1 verbose identifier matches")
    (assert (= (.-compact r1) "txt/starts?") "Rule 1 compact replacement matches")
    (assert (= (.-savings r1) 2) "Rule 1 token savings count matches")
    (assert (= (.-verbose r2) "normalize-path") "Rule 2 verbose identifier matches")
    (assert (= (.-compact r2) "v/norm") "Rule 2 compact replacement matches")
    true))

(df testIsCompactionTarget [] -> Bool
  :d "Verifies symbol matching against compaction target list."
  (let [(rules (cr/defaultCompactionRules))]
    (assert (cr/isCompactionTarget? "string-starts-with?" rules) "string-starts-with? is compaction target")
    (assert (cr/isCompactionTarget? "normalize-path" rules) "normalize-path is compaction target")
    (assert (cr/isCompactionTarget? "task-claim" rules) "task-claim is compaction target")
    (assert (cr/isCompactionTarget? "supervise-step" rules) "supervise-step is compaction target")
    (assert (not (cr/isCompactionTarget? "unknown-symbol" rules)) "unknown-symbol is not compaction target")
    (assert (not (cr/isCompactionTarget? "+" rules)) "plus operator is not compaction target")
    true))

(df testDefaultCompactionRules [] -> Bool
  :d "Verifies default rules count and presence of required canonical rules."
  (let [(rules (cr/defaultCompactionRules))
        (cnt (list-length rules))]
    (assert (>= cnt 14) "Default compaction rules count must be at least 14")
    (assert (cr/isCompactionTarget? "vfs-read" rules) "vfs-read must be in default rules")
    (assert (cr/isCompactionTarget? "vfs-write" rules) "vfs-write must be in default rules")
    (assert (cr/isCompactionTarget? "task-complete" rules) "task-complete must be in default rules")
    (assert (cr/isCompactionTarget? "supervise-list" rules) "supervise-list must be in default rules")
    true))

(df testRewriteAstTokensBasic [] -> Bool
  :d "Verifies single and multi-symbol rewriting of verbose identifiers."
  (let [(rules (cr/defaultCompactionRules))
        (src1 "(string-starts-with? (normalize-path p) \"/root\")")
        (res1 (cr/rewriteAstTokens src1 rules))
        (src2 "(task-claim t session) (supervise-step proc 0)")
        (res2 (cr/rewriteAstTokens src2 rules))]
    (assert (= res1 "(txt/starts? (v/norm p) \"/root\")") "Rewrites string-starts-with? and normalize-path")
    (assert (= res2 "(task/claim t session) (proc/status proc 0)") "Rewrites task-claim and supervise-step")
    true))

(df testRewritePreservesLiterals [] -> Bool
  :d "Verifies that string literals and comments are not mutated during AST token rewrite."
  (let [(rules (cr/defaultCompactionRules))
        (src1 "(let [(msg \"string-starts-with? in string\")] (string-starts-with? a b))")
        (res1 (cr/rewriteAstTokens src1 rules))
        (src2 "; string-starts-with? in comment\n(normalize-path p)")
        (res2 (cr/rewriteAstTokens src2 rules))]
    (assert (= res1 "(let [(msg \"string-starts-with? in string\")] (txt/starts? a b))") "Preserves string literals")
    (assert (= res2 "; string-starts-with? in comment\n(v/norm p)") "Preserves comments while rewriting code")
    true))

(df testRewriteIdempotency [] -> Bool
  :d "Verifies that rewriting already compact code is idempotent."
  (let [(rules (cr/defaultCompactionRules))
        (compactSrc "(if (txt/starts? (v/norm p) \"/dir\") (task/claim t s) (proc/status p 0))")
        (res1 (cr/rewriteAstTokens compactSrc rules))
        (res2 (cr/rewriteAstTokens res1 rules))]
    (assert (= res1 compactSrc) "First pass on already compact code leaves text unchanged")
    (assert (= res2 compactSrc) "Second pass remains idempotent")
    true))

(df runTests [] -> Bool
  :d "Runs all compact rewrite test suites."
  (do
    (assert (testCompactRuleCreation) "test-compact-rule-creation must pass")
    (assert (testIsCompactionTarget) "test-is-compaction-target must pass")
    (assert (testDefaultCompactionRules) "test-default-compaction-rules must pass")
    (assert (testRewriteAstTokensBasic) "test-rewrite-ast-tokens-basic must pass")
    (assert (testRewritePreservesLiterals) "test-rewrite-preserves-literals must pass")
    (assert (testRewriteIdempotency) "test-rewrite-idempotency must pass")
    true))

(runTests)
