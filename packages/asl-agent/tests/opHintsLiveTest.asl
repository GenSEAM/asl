(module aslAgent/tests/opHintsLiveTest
  :x [runTests]
  :i [(aslHarness/tests/agentLoopRecorderKit :a rk) (aslAgent/main :a m) (aslAgent/core :a c) (aslAgent/tests/gitInitKit :a gk)])

; (:m :ref LEON-OP-HINTS :do "a write sent under a synonym op (savefile) or a key alias (:filename) is canonicalised before liveExecOps! classifies it, so it is snapshotted and restored when the run ends on a red gate, like the canonical write")

fn initRepo! root: String -> Bool
  (and (ok? (fileWrite (str root "/subject.txt") "before\n"))
    (gk/initGitRepo! root "opHintsLiveTest" "op-hints-live-test@example.invalid"))

fn ! drive! tag: String step: String -> (Pair String String)
  (let [root (rk/freshRecorderRoot! (str "opHintsLive" tag))
        ready (initRepo! root)
        fixtureDir (str root "/tests/fixtures/agentLoop/mvp")
        _dir (dirCreate fixtureDir)
        reply (str step "\n```\nafter\n```")
        _fixture (fileWrite (str fixtureDir "/opHintsLive" tag ".asn") (rk/scriptFixtureTextFromReplies! (str "opHintsLive" tag) (list reply)))
        form (str "(:agent :task \"Write subject.txt.\" :backend \"script/opHintsLive" tag "\" :root \"" (c/escapeAsn root) "\" :mode \"implement\" :owns (\"subject.txt\") :gates (\"grep -qx green subject.txt\") :budget 1 :contextTokens 8000)")
        repoRoot (resultOr (realPath ".") ".")
        res (m/mainWithRoots (list form) repoRoot repoRoot)
        after (resultOr (fileReadString (str root "/subject.txt")) "?")
        jrel (match (stringIndexOf res.stdout ":journal \"") ((some i) (optionOr (listHead (stringSplit (optionOr (stringSlice res.stdout (+ i 10) (stringLength res.stdout)) "") "\"")) "")) ((none) ""))
        journal (resultOr (fileReadString (str root "/" jrel)) "")
        cleaned (ok? (pathRemove root))]
    (pair (if ready journal "NOT READY") after))

fn ! runTests -> Bool
  (let [canon (drive! "Canon" "(:step :op \"write\" :file \"subject.txt\" :content :raw)")
        syn (drive! "Syn" "(:step :op \"savefile\" :file \"subject.txt\" :content :raw)")
        key (drive! "Key" "(:step :op \"write\" :filename \"subject.txt\" :content :raw)")]
    (do
      (assert (= (pairSecond canon) "before\n") (str "the canonical write is restored after the red gate: " (pairSecond canon)))
      (assert (= (pairSecond syn) "before\n") (str "a write under the synonym savefile is restored too: " (pairSecond syn) " / " (pairFirst syn)))
      (assert (= (pairSecond key) "before\n") (str "a write under the :filename alias is restored too: " (pairSecond key) " / " (pairFirst key)))
      (assert (and (stringContains? (pairFirst syn) ":name \"write\"") (not (stringContains? (pairFirst syn) ":name \"savefile\""))) (str "the journal row of the synonym write carries the canonical name: " (pairFirst syn)))
      true))
