(module asl/agentLoop/tests/gateIntegrityTest
  :x [runTests]
  :i [(asl/agentLoop/gateIntegrity :a gi) (asl/agentLoop/gates :a g) (asl/agentLoop/core :a c)])

fn kvGet kv: (List (Pair String c/KvVal)) key: String -> (Option c/KvVal)
  (mt (listHead (filter (fn [p] (= (pairFirst p) key)) kv))
    ((some p) (some (pairSecond p))) ((none) (none)))

fn kvText value: c/KvVal -> String
  (mt value ((c/kvStr s) s) ((c/kvInt _) ""))

fn expected fixture: String id: String -> String
  (let [prefix (str "(:case :id \"" id "\"")
        line (optionOr (listHead (filter (fn [l] (stringStartsWith? l prefix)) (stringLines fixture))) "")]
    (mt (kvGet (c/parseKv line) "want")
      ((some value) (kvText value))
      ((none) "")))

fn ! testPure fixture: String -> Bool
  (let [fields (gi/gateFields (g/makeGateResult "sh gate.sh" 3 "out" "err" true 4))
        green (gi/gateResultsGreen (list "sh gate.sh" "pytest")
          (list (pair "sh gate.sh" (list (pair "exit" "0")))
                (pair "pytest" (list (pair "exit" "1")))))
        prefix (gi/cutParsePrefix "éλtail" 3)
        receipt (gi/evidenceForm (gi/claimOf (some "claim") (some "git \"show\" λ") (some "cmd") (some 7) false))
        claims (list (gi/claimOf (some "visible text") (none) (none) (none) false)
          (gi/claimOf (none) (some "receipt") (none) (some 0) false)
          (gi/claimOf (some "supported") (none) (none) (none) true))
        unbacked (gi/unbackedTexts claims)
        noted (gi/noteUnbacked (list "visible text") claims)
        commandEvidence (gi/evidenceForm (gi/claimOf (none) (none) (some "git status --short") (some 3) false))]
    (do
      (assert (= (c/joinSep fields "\n") (expected fixture "fields")) "gateFields fixture")
      (assert (= (if green "true" "false") (expected fixture "green")) "gateResultsGreen fixture")
      (assert (= prefix (expected fixture "cutUtf8")) "cutParsePrefix UTF-8 fixture")
      (assert (= receipt (expected fixture "evidenceReceipt")) "evidenceForm fixture")
      (assert (= commandEvidence "(:evidence (:cmd \"git status --short\" :exit 3))") "evidenceForm preserves command without receipt")

      (assert (= (c/joinSep unbacked "\n") (expected fixture "unbacked")) "unbackedTexts fixture")
      (assert (= (c/joinSep noted "\n") (expected fixture "noteUnbacked")) "noteUnbacked fixture")
      true))

fn ! run command: String -> ProcessOutput
  (processRun command)

fn ! makeRoot -> String
  (stringTrim (run "mktemp -d /tmp/asl_gate_integrity_test.XXXXXX").stdout)

fn ! write root: String name: String contents: String -> Bool
  (ok? (fileWrite (str root "/" name) contents))

fn ! initRepo root: String -> Bool
  (and (= (run (str "git -C " root " init -q")).exitCode 0)
    (and (= (run (str "git -C " root " add -A")).exitCode 0)
      (= (run (str "git -C " root " -c user.email=t@t -c user.name=t commit -qm base")).exitCode 0)))

fn ! cleanRoot root: String -> Bool
  (= (run (str "rm -rf " root)).exitCode 0)

fn actual result: (Pair Bool String) -> String
  (str (if (pairFirst result) "true" "false") "\n" (pairSecond result))

fn testVacuous! fixture: String -> Bool
  (let [root (makeRoot)
        setup (and (write root "gate.sh" "exit 0\n") (initRepo root))
        changed (write root "gate.sh" "exit 1\n")
        result (gi/gateIntegrity! (list "sh gate.sh") (list "gate.sh") root
          (list (g/makeGateResult "sh gate.sh" 1 "" "" false 0)) 30 (none))
        matches (= (actual result) (expected fixture "vacuous"))
        cleaned (cleanRoot root)]
    (and setup (and changed (and matches cleaned))))

fn testOnlyGateFiles! fixture: String -> Bool
  (let [root (makeRoot)
        setup (and (write root "gate.sh" "exit 0\n") (initRepo root))
        changed (write root "gate.sh" "echo changed\n")
        result (gi/gateIntegrity! (list "sh gate.sh") (list "gate.sh") root
          (list (g/makeGateResult "sh gate.sh" 0 "(:gate :asserts 1 :failed 0)\n" "" false 0)) 30 (none))
        matches (= (actual result) (expected fixture "onlyGateFiles"))
        cleaned (cleanRoot root)]
    (and setup (and changed (and matches cleaned))))

fn testRedOnHead! fixture: String -> Bool
  (let [root (makeRoot)
        script "echo x >> runs; if grep -qx old impl.txt; then echo '(:gate :asserts 1 :failed 1)'; exit 1; else echo '(:gate :asserts 1 :failed 0)'; fi\n"
        setup (and (write root "impl.txt" "old\n") (and (write root "gate.sh" script) (initRepo root)))
        changed (write root "impl.txt" "new\n")
        before (resultOr (fileReadBytes (str root "/impl.txt")) (bytesAlloc 0))
        result (gi/gateIntegrity! (list "sh gate.sh") (list "impl.txt" "gate.sh") root
          (list (g/makeGateResult "sh gate.sh" 0 "(:gate :asserts 1 :failed 0)\n" "" false 0)) 30 (none))
        after (resultOr (fileReadBytes (str root "/impl.txt")) (bytesAlloc 0))
        runs (resultOr (fileReadString (str root "/runs")) "")
        matches (and (= (actual result) (expected fixture "redOnHead")) (= runs "x\n"))
        cleaned (cleanRoot root)]
    (and setup (and changed (and matches (and (= before after) cleaned)))))

fn testNewFileRevert! fixture: String -> Bool
  (let [root (makeRoot)
        script "echo x >> runs; echo '(:gate :asserts 1 :failed 0)'\n"
        setup (and (write root "gate.sh" script) (initRepo root))
        added (write root "added.txt" "new bytes λ\n")
        before (resultOr (fileReadBytes (str root "/added.txt")) (bytesAlloc 0))
        result (gi/gateIntegrity! (list "sh gate.sh") (list "added.txt" "gate.sh") root
          (list (g/makeGateResult "sh gate.sh" 0 "(:gate :asserts 1 :failed 0)\n" "" false 0)) 30 (none))
        after (resultOr (fileReadBytes (str root "/added.txt")) (bytesAlloc 0))
        runs (resultOr (fileReadString (str root "/runs")) "")
        matches (and (= (actual result) (expected fixture "newFileRevert")) (= runs "x\n"))
        cleaned (cleanRoot root)]
    (and setup (and added (and matches (and (= before after) cleaned)))))

fn ! mixedRevert! fixture: String id: String script: String -> Bool
  (let [root (makeRoot)
        setup (and (write root "impl.txt" "old\n") (and (write root "gate.sh" script) (initRepo root)))
        changed (and (write root "impl.txt" "new\n") (write root "added.txt" "new\n"))
        result (gi/gateIntegrity! (list "sh gate.sh") (list "impl.txt" "added.txt" "gate.sh") root
          (list (g/makeGateResult "sh gate.sh" 0 "(:gate :asserts 1 :failed 0)\n" "" false 0)) 30 (none))
        impl (resultOr (fileReadString (str root "/impl.txt")) "")
        added (resultOr (fileReadString (str root "/added.txt")) "")
        matches (and (= (actual result) (expected fixture id)) (and (= impl "new\n") (= added "new\n")))
        cleaned (cleanRoot root)]
    (and setup (and changed (and matches cleaned))))

fn testScanSwallowed! fixture: String -> Bool
  (let [root (makeRoot)
        source "try:\n    pass\nexcept:\n    pass\n"
        wrote (write root "swallowed.py" source)
        plainWrote (write root "swallowed.txt" source)
        hits (gi/scanSwallowedErrors! root (list (pair (str root "/./swallowed.py") (none))) (list (str root "/./swallowed.py")))
        plainHits (gi/scanSwallowedErrors! root (list (pair (str root "/./swallowed.txt") (none))) (list (str root "/./swallowed.txt")))
        unchangedHits (gi/scanSwallowedErrors! root (list (pair (str root "/./swallowed.py") (some source))) (list (str root "/./swallowed.py")))
        numbers (c/joinSep (map (fn [hit] (stringFromInt64 (pairSecond hit))) hits) "\n")
        plainNumbers (c/joinSep (map (fn [hit] (stringFromInt64 (pairSecond hit))) plainHits) "\n")
        matches (and (= numbers (expected fixture "scanSwallowed")) (and (= plainNumbers "") (listEmpty? unchangedHits)))
        cleaned (cleanRoot root)]
    (and wrote (and plainWrote (and matches cleaned))))

fn ! testTimeoutMetadata! -> Bool
  (let [root (makeRoot)
        setup (and (write root "impl.txt" "old\n") (and (write root "gate.sh" "sleep 2; echo '(:gate :asserts 1 :failed 0)'\n") (initRepo root)))
        changed (write root "impl.txt" "new\n")
        result (gi/gateIntegrity! (list "sh gate.sh") (list "impl.txt" "gate.sh") root
          (list (g/makeGateResult "sh gate.sh" 0 "(:gate :asserts 1 :failed 0)\n" "" false 0)) 1 (none))
        matches (stringContains? (pairSecond result) ":timeout true :seconds 1")
        cleaned (cleanRoot root)]
    (and setup (and changed (and matches cleaned))))

fn ! testChangedFilesError! -> Bool
  (let [root (makeRoot)
        removed (cleanRoot root)
        result (gi/gateIntegrity! (list) (list "missing.txt") root (list) 1 (none))]
    (and removed (and (not (pairFirst result)) (stringStartsWith? (pairSecond result) "changedOwnedFiles failed:"))))

fn ! runTests -> Bool
  (let [root (resultOr (realPath ".") ".")
        fixture (resultOr (fileReadString (str root "/asl/agentLoop/tests/gateIntegrityFixture.asn")) "")]
    (do
      (assert (= (stringLength (expected fixture "scanSwallowed")) 1) "fixture has scanned line number")
      (assert (testPure fixture) "pure helpers match Python fixture")
      (assert (testVacuous! fixture) "vacuous gate reports false and detail")
      (assert (testOnlyGateFiles! fixture) "only gate files skip revert")
      (assert (testScanSwallowed! fixture) "except-pass line is reported for a changed Python file, not for a plain-text file or an unchanged snapshot")
      (assert (testNewFileRevert! fixture) "new-file revert matches the recorded Python result and restores bytes")
      (assert (testRedOnHead! fixture) "red on HEAD content proves a green implementation after one gate run")
      (assert (mixedRevert! fixture "mixedKeptNew" "if grep -qx new impl.txt; then echo '(:gate :asserts 1 :failed 0)'; else echo '(:gate :asserts 1 :failed 1)'; exit 1; fi\n") "a first-run failure with a new file kept names it, and both files are restored")
      (assert (mixedRevert! fixture "gateNeedsNewFile" "if [ -f added.txt ]; then echo '(:gate :asserts 1 :failed 0)'; else echo '(:gate :asserts 1 :failed 1)'; exit 1; fi\n") "the second run removes the new file, so a gate that needs it fails on revert")
      (assert (testChangedFilesError!) "changed-owned-files failure is not treated as a skipped pass")
      (assert (testTimeoutMetadata!) "gate timeout metadata survives the revert check")
      true))
