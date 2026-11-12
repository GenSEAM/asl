(module aslAgent/tests/busEmitLoopTest
  :x [runTests]
  :i [(aslAgent/core :a c) (aslAgent/main :a m) (aslAgent/bus :a bus)
      (aslHarness/tests/agentLoopRecorderKit :a rk) (aslAgent/tests/gitInitKit :a gk)])

; (:m :ref SIGNAL-LEON-DONE :do "a finished live run with a :unit appends exactly one row for that unit to the bus inbox under the run root's :busHome (a scratch dir, never the real HOME); a run without :unit appends none")

fn ! runOnce! root: String tag: String unitPart: String -> Int64
  (let [fixtureDir (str root "/tests/fixtures/agentLoop/mvp")
        dir (dirCreate fixtureDir)
        fixture (fileWrite (str fixtureDir "/be" tag ".asn") (rk/scriptFixtureTextFromReplies! (str "be" tag) (list "(:step :op \"write\" :file \"subject.txt\" :content \"red\\n\")" "(:done)")))
        form (str "(:agent :task \"fix subject\" :backend \"script/be" tag "\" :root \"" (c/escapeAsn root) "\" :mode \"scout\" :owns (\"subject.txt\")"
               unitPart " :budget 4 :contextTokens 8000)")]
    (m/main (list form)))

fn ! runTests -> Bool
  (let [root (rk/freshRecorderRoot! "busEmit")
        home (str root "/busHome")
        wroteS (fileWrite (str root "/subject.txt") "green\n")
        wroteCfg (fileWrite (str root "/.asl.config.asn") (str "(:aslConfig :agentLoop (:specCheck false :busHome \"" (c/escapeAsn home) "\"))"))
        repo (gk/initGitRepo! root "busEmit" "bus-emit@example.invalid")
        code (runOnce! root "u" " :unit \"busUnitX\"")
        rows (match (bus/readEvents! (bus/busPath home)) ((ok r) r) ((err _) (list)))
        mine (filter (fn [e] (= e.unit "busUnitX")) rows)
        code2 (runOnce! root "n" "")
        rows2 (match (bus/readEvents! (bus/busPath home)) ((ok r) r) ((err _) (list)))
        code3 (m/main (list (str "(:agent :task \"fix subject\" :backend \"script/noSuchFixture\" :root \"" (c/escapeAsn root) "\" :mode \"scout\" :unit \"busSetupY\" :budget 4 :contextTokens 8000)")))
        rows3 (match (bus/readEvents! (bus/busPath home)) ((ok r) r) ((err _) (list)))
        setup (filter (fn [e] (= e.unit "busSetupY")) rows3)
        cleaned (pathRemove root)]
    (do
      (assert repo "the fixture repo is committed")
      (assert (= (listLength mine) 1) (str "one finished run with :unit busUnitX leaves exactly one row for it, got " (stringFromInt64 (listLength mine))))
      (assert (= (listLength rows) 1) "the inbox holds no other row")
      (assert (match (listHead mine) ((some e) (= e.exit code)) ((none) false)) "the row carries the run's exit code")
      (assert (match (listHead mine) ((some e) (and (not (stringEmpty? e.stop)) (stringEndsWith? e.receiptPath ".journal"))) ((none) false)) "the row names the stop and the journal")
      (assert (= (listLength rows2) 1) "a run without :unit appends no row")
      (assert (!= code3 0) "a run whose backend fixture is missing is rejected")
      (assert (= (listLength setup) 1) (str "a rejected setup with :unit still leaves exactly one row, got " (stringFromInt64 (listLength setup))))
      (assert (match (listHead setup) ((some e) (and (= e.stop "setupRejected") (= e.exit code3))) ((none) false)) "the setup row says setupRejected with the exit code")
      (assert (ok? cleaned) "the scratch root is removed")
      true))
