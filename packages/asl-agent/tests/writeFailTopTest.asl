(module aslAgent/tests/writeFailTopTest
  :x [runTests]
  :i [(aslAgent/core :a c) (aslAgent/main :a m) (aslAgent/turn :a tr) (aslAgent/toolCalls :a tc)
      (aslHarness/tests/agentLoopRecorderKit :a rk) (aslAgent/tests/gitInitKit :a gk)])

; (:m :ref LEON-WRITE-FAIL-TOP :do "replies from node2 agent journals 2026-11-17 (turn reply rows, unescaped once) and script-provider runs of the shapes: an alternate step shape that maps one to one is rewritten and counted under :repaired, one that does not is left and counted under :left, a turn of unnamed steps holds the read streak and ends as malformedReply on the second, and a finished turn whose gate passes on revert goes back to the writer once more")

(schema Run (:f journal String) (:f receipt String) (:f subject String))

fn atAt -> String
  "(:step@@)\n\n\n(:step :op \"read\" :file \"asl/packages/asl-gateway/src/server.asl\" :symbol \"staleHeaderLine\")"

fn argKeyOnly -> String
  "(:step<arg_key>op</arg_key><arg_value>read</arg_value><arg_key>file</arg_key><arg_value>asl/tools/mesh/tests/cmdTest.asl</arg_value><arg_key>start</arg_key><arg_value>340</arg_value><arg_key>end</arg_key><arg_value>346</arg_value>)"

fn argKeyTwice -> String
  "(:step<arg_key>op</arg_key><arg_value>read</arg_value><arg_key>file</arg_key><arg_value>asl/tools/mesh/tests/cmdTest.asl</arg_value><arg_key>start</arg_key><arg_value>388</arg_value><arg_key>end</arg_key><arg_value>460</arg_value>)\n\n\n(:step :op \"read\" :file \"asl/tools/mesh/tests/cmdTest.asl\" :start 388 :end 460)"

fn opNames text: String -> String
  (stringJoin (map (fn [op] (match (c/dictGet op "op") ((some v) (match v ((c/kvStr n) n) (_ "?"))) ((none) "?"))) (tr/turnReply text (some (list))).facts.ops) " ")

fn kinds xs: (List String) -> String
  (stringJoin xs " ")

fn ! runWith! tag: String task: String gate: (fn [String] -> String) owns: String replies: (List String) -> Run
  (runCfg! tag task gate owns replies "")

fn ! runCfg! tag: String task: String gate: (fn [String] -> String) owns: String replies: (List String) cfg: String -> Run
  (let [root (rk/freshRecorderRoot! tag)
        wroteS (fileWrite (str root "/subject.txt") "base\n")
        wroteCfg (fileWrite (str root "/.asl.config.asn") (str "(:aslConfig :agentLoop (:specCheck false :baseline false" cfg "))"))
        gateDir (dirCreate (str root "/.asl"))
        wroteGate (fileWrite (str root "/.asl/gate.sh") (gate root))
        repo (gk/initGitRepo! root "writeFailTop" "write-fail-top@example.invalid")
        fixtureDir (str root "/tests/fixtures/agentLoop/mvp")
        dir (dirCreate fixtureDir)
        fixture (fileWrite (str fixtureDir "/wft" tag ".asn") (rk/scriptFixtureTextFromReplies! (str "wft" tag) replies))
        form (str "(:agent :task \"" (c/escapeAsn task) "\" :backend \"script/wft" tag "\" :root \"" (c/escapeAsn root)
               "\" :mode \"scout\" :owns (" owns ") :gates (\"sh " (c/escapeAsn root) "/.asl/gate.sh\") :budget 8 :contextTokens 8000 :commit true)")
        repoRoot (resultOr (realPath ".") ".")
        res (m/mainWithRoots (list form) repoRoot repoRoot)
        journalDir (str root "/.asl/run/agentLoop")
        journalName (optionOr (listHead (filter (fn [n] (stringEndsWith? n ".journal")) (resultOr (dirList journalDir) (list)))) "")
        journal (resultOr (fileReadString (str journalDir "/" journalName)) "")
        subject (resultOr (fileReadString (str root "/subject.txt")) "")
        cleaned (ok? (pathRemove root))]
    (Run :journal journal :receipt res.stdout :subject subject))

fn doneGate root: String -> String
  (str "if grep -q done " root "/subject.txt; then echo '1 assertion(s) executed (1 passed)'; else echo '1 assertion(s) executed (0 passed, 1 failed)'; exit 1; fi\n")

fn pairGate root: String -> String
  (str "if [ -f " root "/checkTest.txt ] && ! grep -q done " root "/subject.txt; then echo '1 assertion(s) executed (0 passed, 1 failed)'; exit 1; fi; echo '1 assertion(s) executed (1 passed)'\n")

fn replyTurns journal: String -> Int64
  (listLength (filter (fn [l] (and (stringStartsWith? l "(:turn ") (stringContains? l " :reply \""))) (stringSplit journal "\n")))

fn receiptLine out: String -> String
  (optionOr (listHead (filter (fn [l] (stringContains? l "(:agentReceipt ")) (stringSplit out "\n"))) "")

fn heldTurns journal: String -> (List String)
  (filter (fn [l] (stringContains? l ":signal :greenDoneHeld")) (stringSplit journal "\n"))

fn sentCarries journal: String turn: Int64 needle: String -> Bool
  (listAny? (fn [l] (and (stringStartsWith? l (str "(:turn " (stringFromInt64 turn) " :sent")) (stringContains? l needle))) (stringSplit journal "\n"))

fn ! scriptRuns -> (List Run)
  (let [argWrite "(:step<arg_key>op</arg_key><arg_value>write</arg_value><arg_key>file</arg_key><arg_value>subject.txt</arg_value><arg_key>content</arg_key><arg_value>done</arg_value>)\n(:done)"
        writeDone "(:step :op \"write\" :file \"subject.txt\" :content \"done\\n\")\n(:done)"
        writeCheck "(:step :op \"write\" :file \"checkTest.txt\" :content \"check\\n\")\n(:done)"]
    (list
      (runWith! "ArgKey" "make subject say done" doneGate "\"subject.txt\"" (list argWrite "(:step :op \"read\" :file \"subject.txt\")"))
      (runWith! "Unnamed" "make subject say done" doneGate "\"subject.txt\"" (list "(:step@@)" "(:step :op :read :file \"subject.txt\")" "(:step :op \"read\" :file \"subject.txt\")"))
      (runWith! "Vacuous" "add a check and make subject say done" pairGate "\"subject.txt\" \"checkTest.txt\"" (list writeDone writeCheck "(:step :op \"read\" :file \"subject.txt\")"))
      (runCfg! "Streak" "make subject say done" doneGate "\"subject.txt\"" (list "(:step :op \"gate\")" "(:step@@)" "(:step :op \"read\" :file \"subject.txt\" :start 1 :end 1)" "(:step@@)" "(:step :op \"read\" :file \"subject.txt\" :start 1 :end 2)" "(:step :op \"read\" :file \"subject.txt\" :start 1 :end 3)" "(:step :op \"read\" :file \"subject.txt\" :start 2 :end 3)") " :readStreakEscalate 3")
      (runWith! "VacuousCap" "make subject say done" pairGate "\"subject.txt\" \"checkTest.txt\"" (list writeDone "(:done)" "(:done)" "(:done)"))))

fn ! runTests -> Bool
  (let [fixAt (tc/canonSteps (atAt))
        fixOnly (tc/canonSteps (argKeyOnly))
        fixTwice (tc/canonSteps (argKeyTwice))
        fixAlone (tc/canonSteps "(:step@@)")
        fixNoOp (tc/canonSteps "(:step<arg_key>file</arg_key><arg_value>x.asl</arg_value>)")
        fixTwoOps (tc/canonSteps "(:step<arg_key>op</arg_key><arg_value>read</arg_value><arg_key>op</arg_key><arg_value>write</arg_value>)")
        fixTrail (tc/canonSteps "(:step<arg_key>op</arg_key><arg_value>read</arg_value> and more)")
        fixBare (tc/canonSteps "(:step :op read :file \"a.asl\")")
        fixSingle (tc/canonSteps "(:step :op 'read' :file 'a.asl' :start 3)")
        fixKw (tc/canonSteps "(:step :op :read :file \"a.asl\")")
        fixContent (tc/canonSteps "(:step :op \"write\" :file \"t.asl\" :content \"(:step :op read) (:step@@)\")")
        fixFence (tc/canonSteps "(:step :op \"read\" :file \"a\")\n```\n(:step :op read)\n```")
        fixClean (tc/canonSteps "(:step :op \"read\" :file \"a.asl\")")
        probes (list "(:step :op 'write' :file 'a.txt' :content 'hello world')" "(:step :op 'write' :file 'a.txt' :content 'don't')"
                 "(:step :op write :file a.txt :content hello world)" "(:step :op 'run' :cmd 'rm -rf x')" "(:step :op 'write' :file 'a' :content 'it\\'s')"
                 "(:step :op 'write' :file 'a' :file 'b')" "(:step :op 'edit' :file 'a' :old 'x' new 'y')" "(:step :op 'write' :file 'a.txt' 'x')"
                 "(:step :op write :file 'f' :start 007)")
        zeroContent "(:step<arg_key>op</arg_key><arg_value>write</arg_value><arg_key>file</arg_key><arg_value>a.txt</arg_value><arg_key>content</arg_key><arg_value>007</arg_value>)"
        zeroFile "(:step<arg_key>op</arg_key><arg_value>write</arg_value><arg_key>file</arg_key><arg_value>0123</arg_value><arg_key>content</arg_key><arg_value>x</arg_value>)"
        numStart "(:step<arg_key>op</arg_key><arg_value>read</arg_value><arg_key>file</arg_key><arg_value>a</arg_value><arg_key>start</arg_key><arg_value>12</arg_value><arg_key>end</arg_key><arg_value>08</arg_value>)"
        dupKey "(:step<arg_key>op</arg_key><arg_value>write</arg_value><arg_key>content</arg_key><arg_value>a</arg_value><arg_key>content</arg_key><arg_value>b</arg_value>)"
        unnamed (tr/turnReply "(:step@@)" (some (list)))
        journal (str "(:turn 1 :shape :repaired (argKey emptyStep) :left ())\n(:turn 2 :reply \"x\")\n(:turn 3 :shape :repaired () :left (emptyStep))\n(:turn 4 :shape :repaired (argKey) :left ())\n")]
    (do
      (assert (= (opNames (atAt)) "read") (str "(:step@@) before a read step: only the read is run, got ops " (opNames (atAt))))
      (assert (= (kinds fixAt.repaired) "emptyStep") (str "the dropped empty step is counted, got " (kinds fixAt.repaired)))
      (assert (= (opNames (argKeyOnly)) "read") (str "an arg_key step becomes the read it names, got " (opNames (argKeyOnly))))
      (assert (= fixOnly.text "(:step :op \"read\" :file \"asl/tools/mesh/tests/cmdTest.asl\" :start 340 :end 346)") (str "the arg_key chain maps to the canonical step, got " fixOnly.text))
      (assert (= (kinds fixOnly.repaired) "argKey") "the arg_key rewrite is counted")
      (assert (stringStartsWith? fixTwice.text "(:step :op \"read\" :file \"asl/tools/mesh/tests/cmdTest.asl\" :start 388 :end 460)") (str "the arg_key copy before its canonical twin is rewritten, got " fixTwice.text))
      (assert (= (opNames (argKeyTwice)) "read") (str "the two identical reads run once, got " (opNames (argKeyTwice))))
      (assert (= fixAlone.text "(:step@@)") "an empty step with no named step beside it is left as sent")
      (assert (and (listEmpty? fixAlone.repaired) (= (kinds fixAlone.left) "emptyStep")) "and reported under :left")
      (assert (and (= fixNoOp.text "(:step<arg_key>file</arg_key><arg_value>x.asl</arg_value>)") (= (kinds fixNoOp.left) "argKey")) "an arg_key chain naming no op is left and reported")
      (assert (and (listEmpty? fixTwoOps.repaired) (= (kinds fixTwoOps.left) "argKey")) "an arg_key chain naming two ops is ambiguous: left and reported")
      (assert (and (listEmpty? fixTrail.repaired) (= (kinds fixTrail.left) "argKey")) "text after the last arg_value pair is not guessed at: left and reported")
      (assert (= fixBare.text "(:step :op \"read\" :file \"a.asl\")") (str "a bare op word is quoted, got " fixBare.text))
      (assert (= (kinds fixBare.repaired) "bareOp") "the bare op is counted")
      (assert (= fixSingle.text "(:step :op \"read\" :file \"a.asl\" :start 3)") (str "single-quoted op and plain values become double-quoted, got " fixSingle.text))
      (assert (= (kinds fixSingle.repaired) "opQuote argQuote") (str "both kinds are counted, got " (kinds fixSingle.repaired)))
      (assert (and (= fixKw.text "(:step :op :read :file \"a.asl\")") (= (kinds fixKw.left) "opShape")) "a keyword after :op is not guessed at: left and reported")
      (assert (and (= fixContent.text "(:step :op \"write\" :file \"t.asl\" :content \"(:step :op read) (:step@@)\")") (listEmpty? fixContent.repaired)) "step shapes inside a written string are never touched")
      (assert (and (stringContains? fixFence.text "```\n(:step :op read)\n```") (listEmpty? fixFence.repaired)) "canonSteps itself skips a fenced block (turnReply drops fences before it, so a fenced step there is repaired like any other)")
      (assert (and (= fixClean.text "(:step :op \"read\" :file \"a.asl\")") (and (listEmpty? fixClean.repaired) (listEmpty? fixClean.left))) "a canonical step is unchanged and nothing is counted")
      (assert (listAll? (fn [pr] (let [f (tc/canonSteps pr)] (and (= f.text pr) (and (listEmpty? f.repaired) (= (kinds f.left) "opShape"))))) probes) "a single-quoted or bare form that does not parse into pairs without loss is left as sent and reported as opShape")
      (assert (listAll? (fn [pr] (= (opNames pr) "")) probes) "and none of those forms runs as a named op")
      (assert (= (tc/canonSteps zeroContent).text "(:step :op \"write\" :file \"a.txt\" :content \"007\")") (str "arg_key content 007 stays the string 007, got " (tc/canonSteps zeroContent).text))
      (assert (= (tc/canonSteps zeroFile).text "(:step :op \"write\" :file \"0123\" :content \"x\")") (str "arg_key file 0123 stays the path 0123, got " (tc/canonSteps zeroFile).text))
      (assert (= (tc/canonSteps numStart).text "(:step :op \"read\" :file \"a\" :start 12 :end \"08\")") (str "only a canonical integer of a numeric key goes unquoted, got " (tc/canonSteps numStart).text))
      (assert (= (kinds (tc/canonSteps "(:step :op 'read' :file 'a' :symbol 'b')").repaired) "opQuote argQuote") "each kind is counted once per form")
      (assert (let [f (tc/canonSteps dupKey)] (and (= f.text dupKey) (= (kinds f.left) "argKey"))) "an arg_key chain naming one key twice is left and reported")
      (assert (= (opNames dupKey) "") "and does not run as a named op")
      (assert (m/unnamedOnly? unnamed.facts.ops) "a reply of (:step@@) alone is a turn of unnamed steps")
      (assert (not (m/unnamedOnly? (tr/turnReply (atAt) (some (list))).facts.ops)) "after the repair the (:step@@) read reply is not")
      (assert (= (kinds unnamed.shapeLeft) "emptyStep") "turnReply carries the left kinds")
      (assert (= (m/shapeRow 3 (list "argKey") (list)) (some "(:turn 3 :shape :repaired (argKey) :left ())\n")) "one shape row per turn")
      (assert (none? (m/shapeRow 3 (list) (list))) "no row when nothing was rewritten or left")
      (assert (= (m/repairedIn journal) " :repaired (:turns 3 :kinds ((:argKey 2) (:emptyStep 1)) :left ((:emptyStep 1)))") (str "the receipt tallies the shape rows, got " (m/repairedIn journal)))
      (assert (= (m/repairedIn "(:turn 1 :reply \"x\")\n") "") "no :repaired field without a shape row")
      (scriptAsserts)
      true))

fn ! scriptAsserts -> Bool
  (let [runs (scriptRuns)
        argKey (optionOr (listGet runs 0) (Run :journal "" :receipt "" :subject ""))
        unnamed (optionOr (listGet runs 1) (Run :journal "" :receipt "" :subject ""))
        vacuous (optionOr (listGet runs 2) (Run :journal "" :receipt "" :subject ""))
        streak (optionOr (listGet runs 3) (Run :journal "" :receipt "" :subject ""))
        capped (optionOr (listGet runs 4) (Run :journal "" :receipt "" :subject ""))]
    (do
      (assert (stringContains? (receiptLine argKey.receipt) "(:agentReceipt :status :ok") (str "the arg_key write lands and the run ends ok: " (receiptLine argKey.receipt)))
      (assert (= argKey.subject "done") (str "the owned file holds the written content, got " argKey.subject))
      (assert (stringContains? (receiptLine argKey.receipt) ":repaired (:turns 1 :kinds ((:argKey 1)) :left ())") (str "the receipt counts the repair: " (receiptLine argKey.receipt)))
      (assert (stringContains? argKey.journal "(:turn 1 :shape :repaired (argKey) :left ())") "the journal row names the repaired turn")
      (assert (stringContains? (receiptLine unnamed.receipt) ":stop malformedReply") (str "two unnamed turns in a row end as malformedReply, not a read streak: " (receiptLine unnamed.receipt)))
      (assert (sentCarries unnamed.journal 2 "ERR_NO_OP") "the first unnamed turn is answered with the expected shape")
      (assert (stringContains? (receiptLine unnamed.receipt) ":left ((:emptyStep 1) (:opShape 1))") (str "both unrepaired shapes are reported: " (receiptLine unnamed.receipt)))
      (assert (= (listLength (heldTurns vacuous.journal)) 1) (str "the finished turn whose gate passes on revert is held once: " (stringJoin (heldTurns vacuous.journal) " | ")))
      (assert (stringContains? vacuous.journal "(:turn 1 :signal :greenDoneHeld") "it is the first turn")
      (assert (sentCarries vacuous.journal 2 "(:gateVacuous ") "the writer gets the (:gateVacuous) form on the next turn")
      (assert (stringContains? (receiptLine vacuous.receipt) "(:agentReceipt :status :ok") (str "the run that then adds the check ends ok: " (receiptLine vacuous.receipt)))
      (assert (stringContains? streak.journal ":signal :readStreak :reason \"3 turns without a write while a gate is red\"") (str "with :readStreakEscalate 3 the run stops on its read streak: " (receiptLine streak.receipt)))
      (assert (= (replyTurns streak.journal) 5) (str "the two (:step@@) turns hold the streak, so it reaches 3 only on turn 5 (gate, read, read), got " (stringFromInt64 (replyTurns streak.journal)) " turns"))
      (assert (= (listLength (heldTurns capped.journal)) 2) (str "a writer that never fixes the gate is held gateVacuousRounds (2) times: " (stringJoin (heldTurns capped.journal) " | ")))
      (assert (stringContains? (receiptLine capped.receipt) ":stop gateIntegrity") (str "and then fails gateIntegrity as before: " (receiptLine capped.receipt)))
      true))
