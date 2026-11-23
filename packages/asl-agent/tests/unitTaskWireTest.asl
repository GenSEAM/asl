(module aslAgent/tests/unitTaskWireTest
  :x [runTests]
  :i [(aslAgent/core :a c) (aslAgent/main :a m)
      (aslHarness/tests/agentLoopRecorderKit :a rk) (aslAgent/tests/gitInitKit :a gk)])

; (:m :ref LEON-GREEN-BLOCK :do "the run's :unitTask, not its briefed :task, reaches the unwired check: a script writer adds an exported streamOpen! no code calls to an existing module, the gate stops compiling on revert; named in :unitTask the run ends ok, named only in :task it ends failed with gateIntegrity and a gateUnwired form")

(schema Run (:f journal String) (:f receipt String))

fn baseSrc -> String
  "(module w\n  :x [old]\n  :i [])\n\nfn old -> Int64\n  1\n"

fn writeReply -> String
  "(:step :op \"write\" :file \"src/w.asl\" :content \"(module w\\n  :x [old streamOpen!]\\n  :i [])\\n\\nfn old -> Int64\\n  1\\n\\nfn ! streamOpen! p: String -> Int64\\n  2\\n\")\n(:done)"

fn gateScript root: String -> String
  (str "if grep -q 'streamOpen!' " root "/src/w.asl; then echo '1 assertion(s) executed (1 passed)'; else echo 'ERR_UNRESOLVED_SYMBOL streamOpen!'; exit 1; fi\n")

fn ! runWith! tag: String task: String unitTask: String -> Run
  (let [root (rk/freshRecorderRoot! tag)
        srcDir (dirCreate (str root "/src"))
        wroteSrc (fileWrite (str root "/src/w.asl") (baseSrc))
        wroteCfg (fileWrite (str root "/.asl.config.asn") "(:aslConfig :agentLoop (:specCheck false :baseline false))")
        gateDir (dirCreate (str root "/.asl"))
        wroteGate (fileWrite (str root "/.asl/gate.sh") (gateScript root))
        repo (gk/initGitRepoWith! root "unitTaskWire" "unit-task-wire@example.invalid" (list "src/w.asl"))
        fixtureDir (str root "/tests/fixtures/agentLoop/mvp")
        dir (dirCreate fixtureDir)
        fixture (fileWrite (str fixtureDir "/utw" tag ".asn") (rk/scriptFixtureTextFromReplies! (str "utw" tag) (list (writeReply) "(:done)" "(:done)" "(:done)")))
        form (str "(:agent :task \"" (c/escapeAsn task) "\"" (if (stringEmpty? unitTask) "" (str " :unitTask \"" (c/escapeAsn unitTask) "\""))
               " :backend \"script/utw" tag "\" :root \"" (c/escapeAsn root)
               "\" :mode \"scout\" :owns (\"src/w.asl\") :gates (\"sh " (c/escapeAsn root) "/.asl/gate.sh\") :budget 8 :contextTokens 8000)")
        repoRoot (resultOr (realPath ".") ".")
        res (m/mainWithRoots (list form) repoRoot repoRoot)
        journalDir (str root "/.asl/run/agentLoop")
        journalName (optionOr (listHead (filter (fn [n] (stringEndsWith? n ".journal")) (resultOr (dirList journalDir) (list)))) "")
        journal (resultOr (fileReadString (str journalDir "/" journalName)) "")
        cleaned (ok? (pathRemove root))]
    (Run :journal journal :receipt res.stdout))

fn receiptLine out: String -> String
  (optionOr (listHead (filter (fn [l] (stringContains? l "(:agentReceipt ")) (stringSplit out "\n"))) "")

fn ! runTests -> Bool
  (let [brief "w.asl gains exported streamOpen! p: String -> Int64\n\n(:prior :last \"unwired: new fns with no caller outside tests: streamOpen!\")"
        named (runWith! "Named" brief "w.asl gains exported streamOpen! p: String -> Int64")
        briefOnly (runWith! "BriefOnly" brief "")
        namedRow (receiptLine named.receipt)
        briefRow (receiptLine briefOnly.receipt)]
    (do
      (assert (stringContains? named.journal "(:gateIntegrity :ok true") (str "an export named in :unitTask passes the integrity check: " (optionOr (listLast (filter (fn [l] (stringStartsWith? l "(:gateIntegrity")) (stringSplit named.journal "\n"))) "none")))
      (assert (and (not (stringContains? namedRow ":stop gateIntegrity")) (not (stringContains? named.journal "(:gateUnwired"))) (str "no unwired retry and no gateIntegrity stop when :unitTask names the export: " namedRow))
      (assert (stringContains? briefOnly.journal "(:gateUnwired :fns (\\\"streamOpen!\\\")") (str "a name only in the briefed :task (prior failure) is still unwired: " (optionOr (listLast (filter (fn [l] (stringContains? l "gateUnwired")) (stringSplit briefOnly.journal "\n"))) "none")))
      (assert (stringContains? briefRow ":stop gateIntegrity") (str "past the retry cap the brief-only run ends gateIntegrity: " briefRow))
      true))
