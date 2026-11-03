(module aslAgent/tests/readOnlyGateTest
  :x [runTests]
  :i [(aslAgent/main :a m) (aslAgent/core :a c) (aslHarness/tests/agentLoopRecorderKit :a rk) (aslAgent/tests/gitInitKit :a gk)])

; (:m :ref PER-TURN-GATE :do "the task gates ran after every parsed turn, read-only ones included; with a suite as gate that cost minutes per read turn on node2. A turn whose ops only read, or whose write or edit changed nothing (an edit whose :old is not in the file), reuses the last verdict; a turn that wrote, runs or finishes still runs the gates")

fn fiveReadsThenWrite -> (List String)
  (listAppend (map (fn [_] "(:step :op \"read\" :file \"subject.txt\")") (range 0 4))
    (list "(:step :op \"edit\" :file \"subject.txt\" :old \"not in the file\" :new \"green\")"
          "(:step :op \"write\" :file \"subject.txt\" :content \"green\\n\") (:done)"))

fn turnForm num: Int64 reply: String -> String
  (str "    (:turn :num " (stringFromInt64 num) " :reply \"" (c/escapeAsn reply) "\")\n")

fn countLines text: String -> Int64
  (listLength (filter (fn [l] (not (stringEmpty? (stringTrim l)))) (stringSplit text "\n")))

fn ! runTests -> Bool
  (let [(root (rk/freshRecorderRoot! "readOnlyGate"))
        (counter (str root ".gatecount"))
        (seeded (and (ok? (fileWrite (str root "/subject.txt") "before\n")) (gk/initGitRepo! root "readOnlyGateTest" "read-only-gate@example.invalid")))
        (fixtureDir (str root "/tests/fixtures/agentLoop/mvp"))
        (_ (dirCreate fixtureDir))
        (turns (map (fn [p] (turnForm (+ (pairFirst p) 1) (pairSecond p))) (enumerate (fiveReadsThenWrite))))
        (_ (fileWrite (str fixtureDir "/readOnlyGate.asn") (str "(:script :id \"readOnlyGate\" :mode :scout\n  :turns (\n" (stringJoin turns "") "  )\n)\n")))
        (gate (str "echo g >> " counter "; grep -q green subject.txt && echo '1 assertion(s) executed (1 passed)'"))
        (form (str "(:agent :task \"read subject.txt five times, then write green and finish\" :backend \"script/readOnlyGate\" :root \"" (c/escapeAsn root)
                   "\" :mode \"scout\" :owns (\"subject.txt\") :gates (\"" (c/escapeAsn gate) "\") :budget 12 :contextTokens 8000)"))
        (exitCode (m/main (list form)))
        (journalDir (str root "/.asl/run/agentLoop"))
        (name (optionOr (listHead (filter (fn [n] (stringEndsWith? n ".journal")) (resultOr (dirList journalDir) (list)))) ""))
        (journal (resultOr (fileReadString (str journalDir "/" name)) ""))
        (gateRows (listLength (filter (fn [l] (stringStartsWith? l "(:gate :cmd ")) (stringSplit journal "\n"))))
        (runs (countLines (resultOr (fileReadString counter) "")))
        (written (resultOr (fileReadString (str root "/subject.txt")) ""))
        (_ (pathRemove counter))
        (_ (pathRemove root))]
    (do
      (assert seeded "the fixture repo is seeded")
      (assert (= written "green\n") (str "the write turn landed: " written))
      (assert (stringContains? journal "(:result :status :ok") "the run still finishes ok after the write turn's green gate")
      (assert (= gateRows 1) (str "only the write turn journals a gate run, read-only turns reuse the last verdict: " (stringFromInt64 gateRows) " gate rows"))
      (assert (<= runs 3) (str "the gate command ran at most baseline + write turn + integrity check, got " (stringFromInt64 runs)))
      (assert (= exitCode 0) (str "exit 0, got " (stringFromInt64 exitCode)))
      true))
