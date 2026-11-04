(module aslAgent/tests/repeatFailureTest
  :x [runTests]
  :i [(aslAgent/main :a m) (aslAgent/core :a c) (aslHarness/tests/agentLoopRecorderKit :a rk) (aslAgent/tests/gitInitKit :a gk)])

; (:m :ref LEON-REPEAT-OP :do "a VCAL run sent the same rejected edit (an :old it never read) 24 turns in a row until the wall kill; the same reply whose ops fail and change nothing escalates on its third consecutive turn")

fn replies -> (List String)
  (listAppend (list "(:step :op \"read\" :file \"subject.txt\")")
    (listAppend (map (fn [_] "(:step :op \"edit\" :file \"subject.txt\" :old \"not in the file\" :new \"green\")") (range 0 5))
      (list "(:step :op \"write\" :file \"subject.txt\" :content \"green\\n\") (:done)")))

fn turnForm num: Int64 reply: String -> String
  (str "    (:turn :num " (stringFromInt64 num) " :reply \"" (c/escapeAsn reply) "\")\n")

fn ! runTests -> Bool
  (let [(root (rk/freshRecorderRoot! "repeatFailure"))
        (seeded (and (ok? (fileWrite (str root "/subject.txt") "before\n")) (gk/initGitRepo! root "repeatFailureTest" "repeat-failure@example.invalid")))
        (fixtureDir (str root "/tests/fixtures/agentLoop/mvp"))
        (_ (dirCreate fixtureDir))
        (turns (map (fn [p] (turnForm (+ (pairFirst p) 1) (pairSecond p))) (enumerate (replies))))
        (_ (fileWrite (str fixtureDir "/repeatFailure.asn") (str "(:script :id \"repeatFailure\" :mode :scout\n  :turns (\n" (stringJoin turns "") "  )\n)\n")))
        (form (str "(:agent :task \"make subject.txt say green\" :backend \"script/repeatFailure\" :root \"" (c/escapeAsn root)
                   "\" :mode \"scout\" :owns (\"subject.txt\") :budget 12 :contextTokens 8000)"))
        (_ (m/main (list form)))
        (journalDir (str root "/.asl/run/agentLoop"))
        (name (optionOr (listHead (filter (fn [n] (stringEndsWith? n ".journal")) (resultOr (dirList journalDir) (list)))) ""))
        (journal (resultOr (fileReadString (str journalDir "/" name)) ""))
        (sent (listLength (filter (fn [l] (and (stringStartsWith? l "(:turn ") (stringContains? l " :sent \""))) (stringSplit journal "\n"))))
        (written (resultOr (fileReadString (str root "/subject.txt")) ""))
        (_ (pathRemove root))]
    (do
      (assert seeded "the fixture repo is seeded")
      (assert (stringContains? journal ":signal :repeatFailure") (str "the third identical failing reply signals repeatFailure; turns sent " (stringFromInt64 sent)))
      (assert (stringContains? journal "(:result :status :escalated") "the run ends escalated")
      (assert (= sent 4) (str "one read and three identical failing edits, then stop: " (stringFromInt64 sent) " turns"))
      (assert (= written "before\n") "nothing was written")
      true))
