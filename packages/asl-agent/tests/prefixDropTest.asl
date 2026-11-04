(module aslAgent/tests/prefixDropTest
  :x [runTests]
  :i [(aslAgent/journal :a jr) (aslAgent/main :a mn) (aslAgent/exec :a ex) (aslAgent/core :a c)])

; (:m :ref L0-PREFIX :do "a :prefix drop list removes exactly the named rows or groups from the system prompt, an empty list is byte-identical to the full prompt, and focus is a per-turn tail rather than a prompt row")

fn ! promptFor! drop: (List String) -> String
  (match (jr/buildSystemPromptDrop (resultOr (realPath ".") ".") "Fix compactionCut in asl/packages/asl-agent/src/context.asl" "." "main" (list "./bin/asl test asl/packages/asl-agent/tests/prefixCacheRenderTest.asl") (some 24000) false drop)
    ((ok p) p)
    ((err e) ""))

fn opsRowOf prompt: String -> String
  (optionOr (listHead (filter (fn [l] (stringStartsWith? l "(:ops ")) (stringLines prompt))) "")

fn after s: String needle: String -> String
  (match (stringIndexOf s needle)
    ((none) "")
    ((some i) (optionOr (stringSlice s i (stringLength s)) "")))

fn upTo s: String needle: String -> String
  (match (stringIndexOf s needle)
    ((none) s)
    ((some i) (optionOr (stringSlice s 0 i) s)))

fn bare t: String -> String
  (stringReplace (stringReplace (stringReplace (stringReplace t "[" "") "]" "") ")" "") "(" "")

fn keysOf shape: String -> (List String)
  (map bare (filter (fn [t] (and (stringStartsWith? (bare t) ":")
                                 (and (not (stringStartsWith? t "("))
                                      (not (listContains? (list ":step" ":op" ":raw" ":raw|s") (bare t))))))
                    (stringSplit shape " ")))

fn stepTag op: String -> String
  (str "\\\"" op "\\\"")

fn headTag op: String -> String
  (str "\"(:" op)

fn present? row: String op: String -> Bool
  (or (stringContains? row (stepTag op)) (stringContains? row (headTag op)))

; (:m :ref OPS-ROW-CONCRETE :do "the text the row says about one op: its form, its :optional entry and its :choices entry")
fn segmentOf row: String op: String -> String
  (let [form (if (stringContains? row (stepTag op)) (upTo (after row (stepTag op)) ")\"") (upTo (after row (headTag op)) ")\""))
        opt (str (upTo (after (after row ":optional (") (str "(" op " :")) ")") ")")
        choice (upTo (after (after row ":choices (") (str "(" op " :")) "))")]
    (str form " " opt " " choice))

fn named? seg: String k: String -> Bool
  (or (stringContains? seg (str k " ")) (stringContains? seg (str k ")")))

fn missingKeys row: String -> (List String)
  (fold (fn [acc p]
          (let [op (pairFirst p)
                seg (segmentOf row op)]
            (listAppend acc (map (fn [k] (str op " " k)) (filter (fn [k] (not (named? seg k))) (keysOf (pairSecond p)))))))
        (list) (filter (fn [p] (present? row (pairFirst p))) (ex/opShapes)))

fn missingKeys0 row: String -> String
  (c/joinSep (missingKeys row) ",")

fn ! runTests -> Bool
  (let [full (match (jr/buildSystemPrompt (resultOr (realPath ".") ".") "Fix compactionCut in asl/packages/asl-agent/src/context.asl" "." "main" (list "./bin/asl test asl/packages/asl-agent/tests/prefixCacheRenderTest.asl") (some 24000) false)
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
      ; (:m :ref OPS-ROW-CONCRETE :do "the ops row shows each op as one form a model can copy: no [optional] brackets or a|b choices inside a form (110 of 27686 node2 replies copied them, 2026-10-31); optional keys and choices sit in their own lists, and every key of the executor's shape (exec.asl opShapes) is named in the row")
      (assert (not (stringContains? (opsRowOf full) "[")) "no form in the ops row carries [optional] brackets")
      (assert (not (stringContains? (opsRowOf full) "|")) "no form in the ops row carries a|b choices")
      (assert (stringContains? (opsRowOf full) ":optional ((read :symbol :anchor :start :end)") "optional keys are listed per op")
      (assert (stringContains? (opsRowOf full) "(query :in (code text all))") "choices are listed per op key")
      (assert (stringContains? (opsRowOf full) "(:escalate :reason s :seen s :tried s)") "the escalate form carries :seen and :tried as the executor's shape does")
      (assert (stringContains? (opsRowOf full) "(:need :ctx path)") "need, a local op the executor runs, is in the row")
      (assert (listEmpty? (missingKeys (opsRowOf full))) (str "every key of every exec.asl shape is named in the ops row: " (c/joinSep (missingKeys (opsRowOf full)) " ")))
      (assert (stringContains? (missingKeys0 "(:ops :forms (\"(:step :op \\\"read\\\" :file f)\"))") "read :symbol") "seeded: a row without read's optional keys reports them missing")
      (assert (not (stringContains? (opsRowOf lean) "gitShow")) "opsLean drops gitShow from the optional and choices lists too")
      true))
