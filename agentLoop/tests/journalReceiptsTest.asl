(module asl/agentLoop/tests/journalReceiptsTest
  :x [runTests]
  :i [(asl/agentLoop/main :a m) (asl/agentLoop/core :a c) (aslHarness/tests/agentLoopRecorderKit :a rk) (asl/agentLoop/tests/gitInitKit :a gk)])

fn replies -> (List String)
  (list "(:step :op \"read\" :file \"subject.txt\") (:step :op \"write\" :file \"bad.asl\" :content \"(module bad :x [f])\\n\\nfn f x: Int64 -> Int64\\n  (let [(y (+ x 1))]\\n    (+ y 2)\\n\")"
        "(:step :op \"write\" :file \"good.asl\" :content \"(module good :x [f])\\n\\nfn f x: Int64 -> Int64\\n  (+ x 1)\\n\") (:done)")

fn turnForm num: Int64 reply: String -> String
  (str "    (:turn :num " (stringFromInt64 num) " :reply \"" (c/escapeAsn reply) "\")\n")

fn ! runTests -> Bool
  (let [(root (rk/freshRecorderRoot! "journalReceipts"))
        (seeded (and (ok? (fileWrite (str root "/subject.txt") "seed\n")) (gk/initGitRepo! root "journalReceiptsTest" "journal-receipts@example.invalid")))
        (fixtureDir (str root "/tests/fixtures/agentLoop/mvp"))
        (_ (dirCreate fixtureDir))
        (turns (map (fn [p] (turnForm (+ (pairFirst p) 1) (pairSecond p))) (enumerate (replies))))
        (_ (fileWrite (str fixtureDir "/journalReceipts.asn") (str "(:script :id \"journalReceipts\" :mode :scout\n  :turns (\n" (stringJoin turns "") "  )\n)\n")))
        (form (str "(:agent :task \"write good.asl\" :backend \"script/journalReceipts\" :root \"" (c/escapeAsn root)
                   "\" :mode \"scout\" :owns (\"bad.asl\" \"good.asl\") :budget 6 :contextTokens 8000)"))
        (_ (m/main (list form)))
        (journalDir (str root "/.asl/run/agentLoop"))
        (name (optionOr (listHead (filter (fn [n] (stringEndsWith? n ".journal")) (resultOr (dirList journalDir) (list)))) ""))
        (journal (resultOr (fileReadString (str journalDir "/" name)) ""))
        (lines (stringSplit journal "\n"))
        (obs (fn [n] (optionOr (listHead (filter (fn [l] (stringStartsWith? l (str "(:turn " (stringFromInt64 n) " :observation \""))) lines)) "")))
        (has (fn [n part] (stringContains? (obs n) (c/escapeAsn part))))
        (_ (pathRemove root))]
    (do
      (assert seeded "the fixture repo is seeded")
      (assert (has 1 ":op \"write\" :status :rejected :file \"bad.asl\"") "turn 1: the rejected unbalanced write leaves its receipt in the journal")
      (assert (has 1 ":error :ERR_TXN_ABORTED") "the receipt keeps the error code")
      (assert (not (has 1 ":op \"read\"")) "a read receipt stays out of the observation row")
      (assert (has 2 ":op \"write\" :status :ok :file \"good.asl\"") "turn 2: the accepted write leaves its receipt")
      true))
