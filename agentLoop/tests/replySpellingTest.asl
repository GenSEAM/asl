(module asl/agentLoop/tests/replySpellingTest
  :x [runTests]
  :i [(asl/agentLoop/reply :a r)])

; (:m :do "STATICHINT gap 3: autoRepairReply renames the retired heads mt, == and not= (heal retiredHeadFor) inside a reply form before parsing and records the kind; a string payload that merely mentions them is untouched")

fn runTests -> Bool
  (let [(fixed (r/autoRepairReply "(:check :path \"a.asl\" :when (== 1 (mt 2 (_ 3))) :unless (not= 1 2))"))
        (kept (r/autoRepairReply "(:note :text \"use (== a b) and (mt x)\")"))]
    (do (assert (stringContains? fixed.text "(= 1 (match 2 (_ 3)))") (str "== and mt renamed, got " fixed.text))
        (assert (stringContains? fixed.text "(!= 1 2)") (str "not= renamed, got " fixed.text))
        (assert (listContains? fixed.kinds "spelling") (str "kind recorded, got " (stringJoin fixed.kinds " ")))
        (assert (stringContains? kept.text "(== a b) and (mt x)") (str "string payload untouched, got " kept.text))
        (assert (not (listContains? kept.kinds "spelling")) "no spelling kind for an untouched form")
        true))
