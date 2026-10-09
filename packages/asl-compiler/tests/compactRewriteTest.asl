(module asl-compiler/compactRewriteTest :x [testCompactRuleCreation testIsCompactionTarget testDefaultCompactionRules testRewriteAstTokensBasic testRewritePreservesLiterals testRewriteIdempotency runTests] :i [(asl-compiler/compactRewrite :a cr)])

fn testCompactRuleCreation -> Bool
  (let [(r1 (cr/makeCompactionRule "stringStartsWith?" "txt/starts?" 2)) (r2 (cr/makeCompactionRule "normalize-path" "v/norm" 2))] (assert (= r1.verbose "stringStartsWith?") "Rule 1 verbose identifier matches") (assert (= r1.compact "txt/starts?") "Rule 1 compact replacement matches") (assert (= r1.savings 2) "Rule 1 token savings count matches") (assert (= r2.verbose "normalize-path") "Rule 2 verbose identifier matches") (assert (= r2.compact "v/norm") "Rule 2 compact replacement matches") true)

fn testIsCompactionTarget -> Bool
  (let [(rules (cr/defaultCompactionRules))] (assert (cr/compactionTarget? "stringStartsWith?" rules) "stringStartsWith? is compaction target") (assert (cr/compactionTarget? "normalize-path" rules) "normalize-path is compaction target") (assert (cr/compactionTarget? "task-claim" rules) "task-claim is compaction target") (assert (cr/compactionTarget? "supervise-step" rules) "supervise-step is compaction target") (assert (not (cr/compactionTarget? "unknown-symbol" rules)) "unknown-symbol is not compaction target") (assert (not (cr/compactionTarget? "+" rules)) "plus operator is not compaction target") true)

fn testDefaultCompactionRules -> Bool
  (let [(rules (cr/defaultCompactionRules)) (cnt (listLength rules))] (assert (>= cnt 14) "Default compaction rules count must be at least 14") (assert (cr/compactionTarget? "vfs-read" rules) "vfs-read must be in default rules") (assert (cr/compactionTarget? "vfs-write" rules) "vfs-write must be in default rules") (assert (cr/compactionTarget? "task-complete" rules) "task-complete must be in default rules") (assert (cr/compactionTarget? "supervise-list" rules) "supervise-list must be in default rules") true)

fn testRewriteAstTokensBasic -> Bool
  (let [(rules (cr/defaultCompactionRules)) (src1 "(stringStartsWith? (normalize-path p) \"/root\")") (res1 (cr/rewriteAstTokens src1 rules)) (src2 "(task-claim t session) (supervise-step proc 0)") (res2 (cr/rewriteAstTokens src2 rules))] (assert (= res1 "(txt/starts? (v/norm p) \"/root\")") "Rewrites stringStartsWith? and normalize-path") (assert (= res2 "(task/claim t session) (proc/status proc 0)") "Rewrites task-claim and supervise-step") true)

fn testRewritePreservesLiterals -> Bool
  (let [(rules (cr/defaultCompactionRules)) (src1 "(let [(msg \"stringStartsWith? in string\")] (stringStartsWith? a b))") (res1 (cr/rewriteAstTokens src1 rules)) (src2 "; stringStartsWith? in comment\n(normalize-path p)") (res2 (cr/rewriteAstTokens src2 rules))] (assert (= res1 "(let [(msg \"stringStartsWith? in string\")] (txt/starts? a b))") "Preserves string literals") (assert (= res2 "; stringStartsWith? in comment\n(v/norm p)") "Preserves comments while rewriting code") true)

fn testRewriteIdempotency -> Bool
  (let [(rules (cr/defaultCompactionRules)) (compactSrc "(if (txt/starts? (v/norm p) \"/dir\") (task/claim t s) (proc/status p 0))") (res1 (cr/rewriteAstTokens compactSrc rules)) (res2 (cr/rewriteAstTokens res1 rules))] (assert (= res1 compactSrc) "First pass on already compact code leaves text unchanged") (assert (= res2 compactSrc) "Second pass remains idempotent") true)

fn runTests -> Bool
  (do (assert (testCompactRuleCreation) "test-compact-rule-creation must pass") (assert (testIsCompactionTarget) "test-is-compaction-target must pass") (assert (testDefaultCompactionRules) "test-default-compaction-rules must pass") (assert (testRewriteAstTokensBasic) "test-rewrite-ast-tokens-basic must pass") (assert (testRewritePreservesLiterals) "test-rewrite-preserves-literals must pass") (assert (testRewriteIdempotency) "test-rewrite-idempotency must pass") true)
