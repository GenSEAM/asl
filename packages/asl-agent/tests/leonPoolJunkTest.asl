(module aslAgent/tests/leonPoolJunkTest
  :x [runTests]
  :i [(aslAgent/tests/leonPoolTest :a lt) (asl-tools/fleet/run :a fr)])

fn junkForm -> String
  "(:agent :task \"junk then done\" :backend \"script/junk\" :mode \"implement\" :budget 2)"

fn junkAllForm -> String
  "(:agent :task \"junk always\" :backend \"script/junkAll\" :mode \"implement\" :budget 2)"

; (:m :ref PROVIDER-JUNK-RETRY :do "a reply with template leakage is ok to the transport but is retried as ERR_PROVIDER_JUNK on both paths: junk then a valid step gives one retry row and the valid turn, junk on every attempt ends with the err code in the journal")
fn junkFixture -> String
  "(:script :id \"leonPoolJunk\" :mode :implement\n  :turns (\n    (:turn :num 1 :reply \"step<ifm|tool_calls>\")\n    (:turn :num 2 :reply \"(:done)\")\n  )\n)\n"

fn junkAllFixture -> String
  "(:script :id \"leonPoolJunkAll\" :mode :implement\n  :turns (\n    (:turn :num 1 :reply \"run</ifm|arg_value>\")\n    (:turn :num 2 :reply \"run</ifm|arg_value>\")\n    (:turn :num 3 :reply \"run</ifm|arg_value>\")\n    (:turn :num 4 :reply \"run</ifm|arg_value>\")\n    (:turn :num 5 :reply \"run</ifm|arg_value>\")\n  )\n)\n"

fn ! runTests -> Bool
  (let [(temp (stringTrim (resultOr (fr/shellOut "/usr/bin/mktemp -d /tmp/leonPoolJunkTest.XXXXXX" 5000) "")))
        (repoRoot (resultOr (realPath ".") "."))
        (made (dirCreate (str temp "/spill")))
        (junkPrep (and (lt/prepBase! (str temp "/junkA") "junk" (junkFixture) (list) false) (and (lt/prepBase! (str temp "/junkB") "junk" (junkFixture) (list) false) (and (lt/prepBase! (str temp "/junkAllA") "junkAll" (junkAllFixture) (list) false) (lt/prepBase! (str temp "/junkAllB") "junkAll" (junkAllFixture) (list) false)))))
        (junkA (lt/blocked! repoRoot (str temp "/junkA") (junkForm)))
        (junkB (lt/pooled! temp repoRoot (str temp "/junkB") (junkForm)))
        (junkAllA (lt/blocked! repoRoot (str temp "/junkAllA") (junkAllForm)))
        (junkAllB (lt/pooled! temp repoRoot (str temp "/junkAllB") (junkAllForm)))]
    (do
      (assert junkPrep "junk fixture roots prepared")
      (assert (and (stringContains? junkB.journal "(:retry :turn 1 :attempt 1)") (stringContains? junkA.journal "(:retry :turn 1 :attempt 1)") (= junkA.exit junkB.exit)) (str "junk then valid: one retry row on both paths, exits " (stringFromInt64 junkA.exit) "/" (stringFromInt64 junkB.exit) "\n" junkB.journal))
      (assert (and (not (stringContains? junkB.journal "(:retry :turn 1 :attempt 2)")) (= junkA.journal junkB.journal)) (lt/diffMsg "junk" junkA junkB))
      (assert (and (stringContains? junkAllB.journal "ERR_PROVIDER_JUNK") (stringContains? junkAllA.journal "ERR_PROVIDER_JUNK") (= junkAllA.exit junkAllB.exit)) (str "junk always: the err code ends the run on both paths\n" junkAllB.journal))
      (assert (ok? (fr/shellOut (str "/bin/rm -rf " temp) 120000)) "temp dir removed")
      true))
