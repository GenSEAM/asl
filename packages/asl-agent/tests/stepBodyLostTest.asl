(module aslAgent/tests/stepBodyLostTest
  :x [runTests]
  :i [(aslAgent/core :a c) (aslAgent/main :a m) (aslAgent/turn :a tr) (aslAgent/toolCalls :a tc) (aslAgent/attractor :a at) (aslAgent/nativeTools :a nt)
      (asl-json/json :a j) (aslHarness/tests/agentLoopRecorderKit :a rk) (aslAgent/tests/gitInitKit :a gk)])

; (:m :ref LEON-STEP-BODY-LOST :do "node2 journals 2026-11-17 recorded these turns as (:step) followed by a parenthesised JSON object, e.g. 2a012de453ae302e turn 1 (:turn 1 :reply \"(:step)\\n\\n({\\\"form\\\\\\\": ...})\"); each raw below is the text tool call the model sent after the (:step prefill, and on base 0843eeec0 at/continueReply then tr/turnReply turn it into exactly the recorded reply row; after the fix each one is the step it names, with its full arguments")

fn wallRead -> String
  "<tool_call>\n{\"form\": \"(:step :op \\\"read\\\" :file \\\"asl/tools/tests/nativeSuiteWallTest.asl\\\")\"}\n</tool_call>"

fn wallSymbol -> String
  "<tool_call>\n{\"form\": \"(:step :op \\\"read\\\" :file \\\"asl/tools/tests/nativeSuiteWallTest.asl\\\" :symbol \\\"declaredWallS\\\")\"}\n</tool_call>"

fn runArgv -> String
  "<tool_call>\n{\"form\":\"(:step :op \\\"run\\\" :argv \\\"./bin/asl test asl/tools/tests/auditFindingTest.asl\\\")\"}\n</tool_call>"

fn hermesGate -> String
  "<tool_call>\n{\"name\": \"step\", \"arguments\": {\"form\": \"(:step :op \\\"gate\\\")\"}}\n</tool_call>"

fn opKeys -> String
  "<tool_call>\n{\"op\": \"read\", \"file\": \"asl/packages/asl-agent/src/replyWaste.asl\"}\n</tool_call>"

fn greetWrite -> String
  "<tool_call>\n{\"form\": \"(:step :op \\\"write\\\" :file \\\"asl/examples/greet.asl\\\" :content :raw)\\n```\\n(module asl/examples/greet\\n  :x [greet]\\n  :i [])\\n\\nfn greet name: String -> String\\n  (stringConcat \\\"hello, \\\" name)\\n```\"}\n</tool_call>"

fn greetText -> String
  "(module asl/examples/greet\n  :x [greet]\n  :i [])\n\nfn greet name: String -> String\n  (stringConcat \"hello, \" name)\n"

fn turnOf raw: String -> tr/TurnReply
  (tr/turnReply (at/continueReply "(:step" raw) (some (list)))

fn argOf op: (List (Pair String c/KvVal)) key: String -> String
  (match (c/dictGet op key) ((some (c/kvStr s)) s) ((some (c/kvInt n)) n) (_ "?"))

fn opsOf t: tr/TurnReply -> String
  (stringJoin (map (fn [op] (argOf op "op")) t.facts.ops) " ")

fn firstArg t: tr/TurnReply key: String -> String
  (match (listHead t.facts.ops) ((some op) (argOf op key)) ((none) "?"))

fn call name: String args: String -> j/Json
  (j/jobj (list (pair "function" (j/jobj (list (pair "name" (j/jstr name)) (pair "arguments" (j/jstr args)))))))

(schema Run (:f journal String) (:f receipt String) (:f subject String))

fn doneGate root: String -> String
  (str "if grep -q done " root "/subject.txt; then echo '1 assertion(s) executed (1 passed)'; else echo '1 assertion(s) executed (0 passed, 1 failed)'; exit 1; fi\n")

fn ! runWith! tag: String replies: (List String) -> Run
  (let [root (rk/freshRecorderRoot! tag)
        wroteS (fileWrite (str root "/subject.txt") "base\n")
        wroteCfg (fileWrite (str root "/.asl.config.asn") "(:aslConfig :agentLoop (:specCheck false :baseline false))")
        gateDir (dirCreate (str root "/.asl"))
        wroteGate (fileWrite (str root "/.asl/gate.sh") (doneGate root))
        repo (gk/initGitRepo! root "stepBodyLost" "step-body-lost@example.invalid")
        fixtureDir (str root "/tests/fixtures/agentLoop/mvp")
        dir (dirCreate fixtureDir)
        fixture (fileWrite (str fixtureDir "/sbl" tag ".asn") (rk/scriptFixtureTextFromReplies! (str "sbl" tag) replies))
        form (str "(:agent :task \"make subject say done\" :backend \"script/sbl" tag "\" :root \"" (c/escapeAsn root)
               "\" :mode \"scout\" :owns (\"subject.txt\") :gates (\"sh " (c/escapeAsn root) "/.asl/gate.sh\") :budget 6 :contextTokens 8000 :attractor \"asn\" :commit true)")
        repoRoot (resultOr (realPath ".") ".")
        res (m/mainWithRoots (list form) repoRoot repoRoot)
        journalDir (str root "/.asl/run/agentLoop")
        journalName (optionOr (listHead (filter (fn [n] (stringEndsWith? n ".journal")) (resultOr (dirList journalDir) (list)))) "")
        journal (resultOr (fileReadString (str journalDir "/" journalName)) "")
        subject (resultOr (fileReadString (str root "/subject.txt")) "")
        cleaned (ok? (pathRemove root))]
    (Run :journal journal :receipt res.stdout :subject subject))

fn receiptLine out: String -> String
  (optionOr (listHead (filter (fn [l] (stringContains? l "(:agentReceipt ")) (stringSplit out "\n"))) "")

fn rows journal: String key: String -> (List String)
  (filter (fn [l] (stringContains? l key)) (stringSplit journal "\n"))

fn ! runTests -> Bool
  (let [wall (turnOf (wallRead))
        sym (turnOf (wallSymbol))
        argv (turnOf (runArgv))
        hermes (turnOf (hermesGate))
        keys (turnOf (opKeys))
        greet (turnOf (greetWrite))
        bareJson (turnOf "{\"form\": \"(:step :op \\\"gate\\\")\"}")
        notStep (turnOf "<tool_call>\n{\"form\": \"read the file first\"}\n</tool_call>")
        extraKey (turnOf "<tool_call>\n{\"name\": \"step\", \"arguments\": {\"form\": \"(:step :op \\\"gate\\\")\"}, \"why\": \"check\"}\n</tool_call>")
        broken (turnOf "<tool_call>\n{\"form\": \"(:step :op \\\"read\\\"\n</tool_call>")
        twice (nt/callForm "step" "\"{\\\"form\\\": \\\"(:step :op \\\\\\\"read\\\\\\\" :file \\\\\\\"a.asl\\\\\\\")\\\"}\"")
        stepOp (nt/callForm "step" "{\"op\":\"read\",\"file\":\"a.asl\",\"start\":3}")
        stepSelf (nt/callForm "step" "{\"op\":\"step\"}")
        closeThenCall (turnOf (nt/callsText ")" (list (call "step" "{\"op\":\"gate\"}"))))
        writeRaw "<tool_call>\n{\"form\": \"(:step :op \\\"write\\\" :file \\\"subject.txt\\\" :content \\\"done\\\")\"}\n</tool_call>"
        longRaw (str "(:step)\nx" (stringRepeat "é" 1100))
        run (runWith! "Tagged" (list writeRaw longRaw "(:done)"))]
    (do
      (assert (= (opsOf wall) "read") (str "2a012de453ae302e turn 1: the tagged step(form) call is the read it names, got ops " (opsOf wall) " text " wall.text))
      (assert (= (firstArg wall "file") "asl/tools/tests/nativeSuiteWallTest.asl") (str "with its file, got " (firstArg wall "file")))
      (assert (= (c/joinSep wall.shapeRepaired " ") "jsonCall") (str "the receipt counts one jsonCall repair and no empty step, got " (c/joinSep wall.shapeRepaired " ")))
      (assert (listEmpty? wall.shapeLeft) "and leaves nothing")
      (assert (= (firstArg sym "symbol") "declaredWallS") (str "2a012de453ae302e turn 3 keeps :symbol, got " (firstArg sym "symbol")))
      (assert (= (firstArg argv "argv") "./bin/asl test asl/tools/tests/auditFindingTest.asl") (str "e334323ba236cc69 turn 1 (no space after the colon) keeps :argv, got " (firstArg argv "argv")))
      (assert (= (opsOf hermes) "gate") (str "cb277ec724154340 turn 1: a {name, arguments} call maps like a native one, got " (opsOf hermes)))
      (assert (= (opsOf keys) "read") (str "242a3c52954aff5d turn 1: step arguments that name op and file are that read, got " (opsOf keys)))
      (assert (= (firstArg keys "file") "asl/packages/asl-agent/src/replyWaste.asl") (str "with its file, got " (firstArg keys "file")))
      (assert (= (opsOf greet) "write") (str "13911c79d8e4df6e turn 8: the write inside the call is a write, got " (opsOf greet)))
      (assert (= (firstArg greet "content") (greetText)) (str "and its raw block is the whole file content, got " (firstArg greet "content")))
      (assert (listEmpty? greet.missingRaw) "no raw field is missing")
      (assert (= (opsOf bareJson) "gate") (str "a reply that is only the JSON object maps too, got " (opsOf bareJson)))
      (assert (and (= (c/joinSep notStep.shapeLeft " ") "jsonCall") (not (stringContains? notStep.text ":op \"read\""))) (str "a form value that is not a step form is left and listed, got left " (c/joinSep notStep.shapeLeft " ") " text " notStep.text))
      (assert (and (= (c/joinSep extraKey.shapeLeft " ") "jsonCall") (not (stringContains? extraKey.text "(:step :op \"gate\")"))) (str "a call with an extra key is left and listed, got left " (c/joinSep extraKey.shapeLeft " ") " text " extraKey.text))
      (assert (not (stringContains? broken.text ":op \"read\")")) (str "a JSON object that does not parse is not run, got " broken.text))
      (assert (= twice "(:step :op \"read\" :file \"a.asl\")") (str "double-encoded step arguments decode one more level, got " twice))
      (assert (= stepOp "(:step :op \"read\" :file \"a.asl\" :start 3)") (str "a native step call naming op is that op call, got " stepOp))
      (assert (= stepSelf "") (str "a step call whose op is step does not recurse, got " stepSelf))
      (assert (= (opsOf closeThenCall) "gate") (str "content ) after the prefill beside a step call that names op runs that op, got " (opsOf closeThenCall)))
      (assert (stringContains? (receiptLine run.receipt) "(:agentReceipt :status :ok") (str "a run whose writer sends the tagged call ends ok: " (receiptLine run.receipt) " rows " (c/joinSep (rows run.journal "Reply \"") " | ") (c/joinSep (rows run.journal ":reply") " | ") " gates " (c/joinSep (map (fn [l] (c/sliceOf l 0 (min (stringLength l) 400))) (filter (fn [l] (or (stringContains? l "(:gate ") (stringContains? l ":observation"))) (stringSplit run.journal "\n"))) " | ")))
      (assert (= run.subject "done") (str "the owned file holds the written content, got " run.subject))
      (assert (stringContains? run.journal "(:turn 1 :shape :repaired (jsonCall) :left ())") (str "the journal names the repaired turn: " (c/joinSep (rows run.journal ":shape") " | ")))
      (assert (stringContains? run.journal "(:turn 1 :rawReply \"<tool_call>\\n{\\\"form\\\": ") (str "the journal keeps the raw reply of that turn: " (c/joinSep (rows run.journal ":rawReply") " | ")))
      (assert (stringContains? run.journal (str "(:turn 2 :rawReply \"(:step)\\nx" (stringRepeat "é" 995) "\" :chars 2209)")) (str "a raw reply over 2000 bytes is cut at a character boundary and keeps its full length: " (c/joinSep (map (fn [l] (c/sliceOf l 0 60)) (rows run.journal ":rawReply")) " | ")))
      (assert (not (stringContains? run.journal "(:turn 3 :rawReply")) "a turn with a canonical step has no raw row")
      true))
