(module asl-target-sh/tests/combinedRulesTest
  :x [runTests]
  :i [(asl-target-sh/rules :a rules)])

; (:m :ref LLVM-FOR-ENTRY-TESTS :do "combinedRulesText! is the language rules text alone when the workspace has no .asl/rules.asn, and otherwise inserts the workspace rule lines, without their (:workspaceRules header, before the first (:pack line")
fn languageText -> String
  "(:rules :v 1\n  (:rule :id a :do \"x\")\n  (:pack :id p :outcomes (\"o\")))\n"

fn ! ctxAt! root: String -> rules/Ctx
  (rules/Ctx :root root :mode "" :src (str root "/rules.asn") :tools "" :home "")

fn ! runTests -> Bool
  (let [(root (str (optionOr (envGet "TMPDIR") "/tmp") "/combinedRulesTest-" (stringFromInt64 (procSelf)) "-" (stringFromInt64 (monotonicNs))))
        (made (and (ok? (dirCreate root)) (ok? (fileWrite (str root "/rules.asn") (languageText)))))
        (alone (rules/combinedRulesText! (ctxAt! root)))
        (wsMade (and (ok? (dirCreate (str root "/.asl"))) (ok? (fileWrite (str root "/.asl/rules.asn") "(:workspaceRules :v 1\n  (:rule :id w :do \"y\")\n"))))
        (combined (rules/combinedRulesText! (ctxAt! root)))
        (cleaned (pathRemove root))]
    (do
      (assert (and made wsMade) "the fixture rules files are written")
      (assert (= alone (languageText)) (str "without workspace rules the text is the language rules: " alone))
      (assert (stringContains? combined "  (:rule :id w :do \"y\")\n  (:pack :id p") (str "the workspace rule sits right before the pack: " combined))
      (assert (stringContains? combined "  (:rule :id a :do \"x\")\n  (:rule :id w") "the language rule stays before the workspace rule")
      (assert (not (stringContains? combined ":workspaceRules")) "the workspace header line is dropped")
      (assert (ok? cleaned) "the fixture is removed")
      true))
