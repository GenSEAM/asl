(module asl/agentLoop/tests/prefixDropTest
  :x [runTests]
  :i [(asl/agentLoop/journal :a jr) (asl/agentLoop/main :a mn)])

; (:m :ref L0-PREFIX :do "a :prefix drop list removes exactly the named rows or groups from the system prompt, an empty list is byte-identical to the full prompt, and focus is a per-turn tail rather than a prompt row")

fn ! promptFor! drop: (List String) -> String
  (match (jr/buildSystemPromptDrop (resultOr (realPath ".") ".") "Fix compactionCut in asl/agentLoop/context.asl" "." "main" (list "./bin/asl test asl/agentLoop/tests/prefixCacheRenderTest.asl") (some 24000) false drop)
    ((ok p) p)
    ((err e) ""))

fn ! runTests -> Bool
  (let [full (match (jr/buildSystemPrompt (resultOr (realPath ".") ".") "Fix compactionCut in asl/agentLoop/context.asl" "." "main" (list "./bin/asl test asl/agentLoop/tests/prefixCacheRenderTest.asl") (some 24000) false)
               ((ok p) p) ((err e) ""))
        none0 (promptFor! (list))
        rules (promptFor! (list "rules"))
        protocol (promptFor! (list "protocol"))
        lean (promptFor! (list "opsLean"))
        card (promptFor! (list "aslCard" "glossary"))]
    (do
      (assert (stringContains? full "(:layer :id orient") "the full prompt carries the orient layer")
      (assert (= none0 full) "an empty drop list is byte-identical to the full prompt")
      (assert (not (stringContains? rules "(:layer :id orient")) "rules drops the orient layer")
      (assert (not (stringContains? rules "(:layer :id breaker")) "rules drops the breaker layer")
      (assert (stringContains? rules "(:layer :id clientRules") "rules keeps clientRules")
      (assert (stringContains? rules "(:ops ") "rules keeps the ops row")
      (assert (not (stringContains? protocol "(:layer :id clientRules")) "protocol drops clientRules")
      (assert (not (stringContains? protocol "(:batch ")) "protocol drops the batch row")
      (assert (stringContains? protocol "(:gates ") "protocol keeps the gates row")
      (assert (and (stringContains? lean "\"edit\"") (not (stringContains? lean "\"gitShow\""))) "opsLean keeps edit and drops gitShow")
      (assert (and (not (stringContains? card "(:aslCard")) (not (stringContains? card "(:glossary"))) "aslCard and glossary drop both rows")
      (assert (< (stringLength card) (stringLength full)) "a drop shortens the prompt")
      (assert (= (jr/sectionId "(:layer :id scope (:covers scope searched))") "scope") "a layer row is keyed by its id")
      (assert (= (jr/sectionId "(:base \"main\")") "base") "another row is keyed by its head")
      (assert (mn/validPrefix? "rules, focus") "a known comma list is valid")
      (assert (not (mn/validPrefix? "rules,bogus")) "an unknown token is rejected")
      (assert (= (mn/prefixDrop "focus,glossary") (list "glossary")) "focus is not a drop id")
      (assert (stringContains? (mn/focusTail "focus" "Fix it" (list "g1") false) "(:focus :goal \"Fix it\" :gate \"g1\"") "focus ends the turn with goal and gate")
      (assert (stringContains? (mn/focusTail "focus" "Fix it" (list "g1") true) ":next (:step :op \"gate\")") "after a write the next form is the gate")
      (assert (= (mn/focusTail "rules" "Fix it" (list "g1") false) "") "without focus there is no tail")
      true))
