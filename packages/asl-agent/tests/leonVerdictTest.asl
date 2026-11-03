(module aslAgent/tests/leonVerdictTest
  :x [runTests]
  :i [(aslAgent/main :a m) (aslAgent/tests/gitInitKit :a kit) (aslHarness/tests/agentLoopRecorderKit :a rk)])

; (:m :ref LEON-FAIL-STATUS :do "the VPS case 17a69539c9c7f99b: a first reply made only of colon-headed fragments becomes ad-hoc findings data, then a later turn writes the owned file and the declared gate goes green; with no patch delivery named the run ended failed (findings without a claim) although the final gate was green. A green final gate over written owned files ends ok; the same fragments with a red final gate, or in a findings delivery, still do not; a downgrade names its cause in the journal")

fn ! freshRoot! tag: String -> String
  (let [base (optionOr (envGet "TMPDIR") "/tmp")
        path (str base "/leonVerdictTest_" (stringFromInt64 (procSelf)) "_" (stringFromInt64 (nowNs)) "_" tag)
        made (dirCreate path)]
    (resultOr (realPath path) path))

fn ! journalOf! root: String -> String
  (let [dir (str root "/.asl/run/agentLoop")
        name (optionOr (listHead (filter (fn [n] (stringEndsWith? n ".journal")) (resultOr (dirList dir) (list)))) "")]
    (if (stringEmpty? name) "" (resultOr (fileReadString (str dir "/" name)) "")))

fn ! runCase! tag: String replies: (List String) gates: String extra: String -> String
  (let [root (freshRoot! tag)
        _cfg (fileWrite (str root "/.asl.config.asn") "(:aslConfig :agentLoop (:specCheck false :baseline false))\n")
        _gate (fileWrite (str root "/gate.sh") "if grep -q good w.txt\nthen\necho '(:gate :asserts 1 :failed 0)'\nelse\necho '(:gate :asserts 1 :failed 1)'\nexit 1\nfi\n")
        _subject (fileWrite (str root "/subject.txt") "s\n")
        _git (kit/initGitRepo! root "leonVerdictTest" "verdict@example.invalid")
        dir (str root "/tests/fixtures/agentLoop/mvp")
        _dir (dirCreate dir)
        _fix (fileWrite (str dir "/" tag ".asn") (rk/scriptFixtureTextFromReplies! tag replies))
        form (str "(:agent :task \"write w.txt\" :backend \"script/" tag "\" :root \"" root "\" :owns (\"w.txt\") :gates (" gates ") :budget 20 :contextTokens 8000 :gateTimeout 30" extra ")")
        exit (m/main (list form))
        journal (journalOf! root)
        _gone (pathRemove root)]
    journal)

fn fragment -> String
  "(:note \"I will write the file now\")"

fn writeAndDone content: String -> String
  (str "(:step :op \"write\" :file \"w.txt\" :content \"" content "\")\n(:done)")

fn ! runTests -> Bool
  (let [green (runCase! "green" (list (fragment) (writeAndDone "good")) "\"sh gate.sh\"" "")
        red (runCase! "red" (list (fragment) (writeAndDone "bad") (writeAndDone "bad") (writeAndDone "bad") (writeAndDone "bad") (writeAndDone "bad") (writeAndDone "bad")) "\"sh gate.sh\"" " :budget 4")
        nogate (runCase! "nogate" (list (fragment) "(:done)") "" "")]
    (do
      (assert (stringContains? green "(:result :status :ok") "findings fragments before a green final gate over a written owned file end ok")
      (assert (stringContains? nogate "(:verdict :failed :why") "a run with findings and no written green work still fails, and the journal says why")
      (assert (not (stringContains? red "(:result :status :ok")) "the same fragments with a gate that never goes green do not end ok")
      true))
