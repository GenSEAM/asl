(module aslAgent/tests/absorbArgKeyTest
  :x [runTests]
  :i [(aslAgent/core :a c) (aslAgent/main :a m) (aslAgent/turn :a tr) (aslAgent/toolCalls :a tc)
      (aslHarness/tests/agentLoopRecorderKit :a rk) (aslAgent/tests/gitInitKit :a gk)])

; (:m :ref ABSORB-AGENT-K1-K2-K4 :do "reply rows of node2 agent journals 2026-11-17 (unescaped once; synDs41Flash): the step tool's form argument and op chains written as arg_key markup, closed by DSML parameter tags or followed by a </tool_call>, </function> or </invoke> tail; each is the step it names only when the value is exactly one step form or the chain maps one to one")

fn formPkg -> String
  "(:step<arg_key>form</arg_key><arg_value>(:step :op \"read\" :file \"asl/packages/asl-pack/src/pkgIndex.asl\")</arg_value>)"

fn formFunction -> String
  "(:step<arg_key>form</arg_key><arg_value>(:step :op \"gitDiff\" :path \"asl/packages/asl-agent-bus/src/browserBridge.asl\" :base \"78190f4989e8afb8c65c472a31ae30c8ebf716f2\")</arg_value></function>)"

fn formDsml -> String
  "(:step<arg_key>form</arg_key>\n<arg_value>(:step :op \"read\" :file \"asl/packages/asl-target-llvm/src/target.asl\" :start 1 :end 60)</｜DSML｜ parameter>\n</invoke>)"

fn chainToolCall -> String
  "(:step<arg_key>op</arg_key><arg_value>read</arg_value><arg_key>file</arg_key><arg_value>asl/packages/asl-pack/src/pkgIndex.asl</arg_value></tool_call>)"

fn chainPlain -> String
  "(:step<arg_key>op</arg_key><arg_value>read</arg_value><arg_key>file</arg_key><arg_value>asl/packages/asl-target-llvm/src/libc.asl</arg_value><arg_key>symbol</arg_key><arg_value>RuntimeAbi</arg_value>)"

fn formWord -> String
  "(:step<arg_key>form</arg_key><arg_value>read</arg_value></tool_call>)"

fn argOf op: (List (Pair String c/KvVal)) key: String -> String
  (match (c/dictGet op key) ((some (c/kvStr s)) s) ((some (c/kvInt n)) n) (_ "?"))

fn turnOf text: String -> tr/TurnReply
  (tr/turnReply text (some (list)))

fn opsOf t: tr/TurnReply -> String
  (stringJoin (map (fn [op] (argOf op "op")) t.facts.ops) " ")

fn firstArg t: tr/TurnReply key: String -> String
  (match (listHead t.facts.ops) ((some op) (argOf op key)) ((none) "?"))

(schema Run (:f journal String) (:f receipt String))

fn ! runWith! tag: String tools: String replies: (List String) -> Run
  (let [root (rk/freshRecorderRoot! tag)
        wroteS (fileWrite (str root "/subject.txt") "base\n")
        wroteCfg (fileWrite (str root "/.asl.config.asn") "(:aslConfig :agentLoop (:specCheck false :baseline false))")
        repo (gk/initGitRepo! root "absorbArgKey" "absorb-arg-key@example.invalid")
        fixtureDir (str root "/tests/fixtures/agentLoop/mvp")
        dir (dirCreate fixtureDir)
        fixture (fileWrite (str fixtureDir "/aak" tag ".asn") (rk/scriptFixtureTextFromReplies! (str "aak" tag) replies))
        form (str "(:agent :task \"look and finish\" :backend \"script/aak" tag "\" :root \"" (c/escapeAsn root)
               "\" :mode \"scout\" :owns (\"subject.txt\") :budget 3 :contextTokens 8000 :attractor \"asn\"" tools ")")
        repoRoot (resultOr (realPath ".") ".")
        res (m/mainWithRoots (list form) repoRoot repoRoot)
        journalDir (str root "/.asl/run/agentLoop")
        journalName (optionOr (listHead (filter (fn [n] (stringEndsWith? n ".journal")) (resultOr (dirList journalDir) (list)))) "")
        journal (resultOr (fileReadString (str journalDir "/" journalName)) "")
        cleaned (ok? (pathRemove root))]
    (Run :journal journal :receipt res.stdout))

fn ! runTests -> Bool
  (let [pkg (turnOf (formPkg))
        fun (turnOf (formFunction))
        dsml (turnOf (formDsml))
        chain (turnOf (chainToolCall))
        plain (turnOf (chainPlain))
        word (turnOf (formWord))
        twoForms (turnOf "(:step<arg_key>form</arg_key><arg_value>(:step :op \"read\" :file \"a\") (:step :op \"gate\")</arg_value>)")
        tailOnly (tc/canonSteps "(:step<arg_key>op</arg_key><arg_value>read</arg_value><arg_key>file</arg_key><arg_value>a</arg_value></tool_call> trailing)")
        withTools (runWith! "Tools" "" (list " :op \"gate\")" "(:done)"))
        toolsOff (runWith! "Off" " :nativeTools \"off\"" (list " :op \"gate\")" "(:done)"))
        afterDefect (runWith! "Defect" "" (list "nothing to do yet" " :op \"gate\")" "(:done)"))]
    (do
      (assert (and (= (opsOf pkg) "read") (= (firstArg pkg "file") "asl/packages/asl-pack/src/pkgIndex.asl")) (str "form in one arg_key pair is the read it holds, got " (opsOf pkg) " " pkg.text))
      (assert (= (c/joinSep pkg.shapeRepaired " ") "argKey") (str "counted as an argKey repair, got " (c/joinSep pkg.shapeRepaired " ")))
      (assert (and (= (opsOf fun) "gitDiff") (= (firstArg fun "base") "78190f4989e8afb8c65c472a31ae30c8ebf716f2")) (str "a </function> tail is dropped and the gitDiff keeps :base, got " (opsOf fun) " " fun.text))
      (assert (and (= (opsOf dsml) "read") (and (= (firstArg dsml "start") "1") (and (= (firstArg dsml "end") "60") (= (c/joinSep dsml.shapeRepaired " ") "argKey")))) (str "a DSML parameter close and </invoke> tail map too, got " (opsOf dsml) " " dsml.text))
      (assert (and (= (opsOf chain) "read") (= (firstArg chain "file") "asl/packages/asl-pack/src/pkgIndex.asl")) (str "an op chain ending in </tool_call> is the read it names, got " (opsOf chain) " " chain.text))
      (assert (and (= (opsOf plain) "read") (= (firstArg plain "symbol") "RuntimeAbi")) (str "a plain op chain still maps, got " (opsOf plain)))
      (assert (and (= (c/joinSep word.shapeLeft " ") "argKey") (not (stringContains? word.text ":op \"read\""))) (str "a form value that is a bare word is left, got left " (c/joinSep word.shapeLeft " ") " text " word.text))
      (assert (= (c/joinSep twoForms.shapeLeft " ") "argKey") (str "a form value with two forms is left, got " (c/joinSep twoForms.shapeLeft " ") " text " twoForms.text))
      (assert (= (c/joinSep tailOnly.left " ") "argKey") (str "text after the tail tag is not dropped, so the chain is left, got " (c/joinSep tailOnly.left " ")))
      (assert (not (stringContains? withTools.journal "(:op :turn 1 :name \"gate\"")) (str "with the step tool offered the (:step prefill is not sent, so a bare continuation is not completed into a gate: " (c/joinSep (filter (fn [l] (stringStartsWith? l "(:op ")) (stringSplit withTools.journal "\n")) " | ")))
      (assert (stringContains? toolsOff.journal "(:op :turn 1 :name \"gate\"") (str "with nativeTools off the prefill stays and the continuation runs the gate: " (c/joinSep (filter (fn [l] (stringStartsWith? l "(:op ")) (stringSplit toolsOff.journal "\n")) " | ")))
      (assert (stringContains? afterDefect.journal "(:op :turn 2 :name \"gate\"") (str "after a turn with no step the prefill comes back even with the tool offered, so a route that strips tools still has the text contract: " (c/joinSep (filter (fn [l] (stringStartsWith? l "(:op ")) (stringSplit afterDefect.journal "\n")) " | ")))
      (assert (stringContains? withTools.journal "(:canon :version \"") "the journal names the reply canon version at session start")
      true))
