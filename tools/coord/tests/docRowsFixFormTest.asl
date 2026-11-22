(module asl-tools/coord/tests/docRowsFixFormTest
  :x [runTests]
  :i [(asl-tools/coord/conductor :a cd) (asl-tools/coord/docRowsGate :a dg) (asl-gates/docLedger :a dl) (asl-tools/fleet/run :a fr) (asl-tools/coord/tests/fixtures/pipeFix :a pf)])

; (:m :ref DOC-THIN :do "docRowsGate in writer mode on fixture repos: a unit that adds a row documenting a test file is red with the printed (:edit) that deletes it, and applying that edit to the ledger text restores the base ledger for a plain row, a row with escapes and a last row without a newline; a unit that adds no row is green and owes none")
fn fakeTool -> String
  "#!/bin/sh\nif [ \"$1\" = check ]; then exit 0; fi\necho \"(:know :missing :new 0)\"\n"

fn romanSrc -> String
  "(module asl-utils/tests/romanTest\n  :x [runTests]\n  :i [])\n\nfn runTests -> Bool\n  true\n"

fn ledgerBase -> String
  "(:doc :symbol \"asl/packages/asl-utils/src/trie.asl#\" :text \"Prefix lookups for the router, kept apart so the hot path allocates nothing\")\n"

fn rowPlain -> String
  "(:doc :symbol \"asl/packages/asl-utils/tests/romanTest.asl#runTests\" :text \"Runs the roman numeral suite\")\n"

fn rowEscaped -> String
  "(:doc :symbol \"asl/packages/asl-utils/tests/romanTest.asl#runTests\" :text \"Runs the \\\"roman\\\" suite with a \\\\ and a tab\")\n"

fn rowLast -> String
  "(:doc :symbol \"asl/packages/asl-utils/tests/romanTest.asl#runTests\" :text \"Runs the roman numeral suite\")"

fn sh c: String -> String
  (pf/sh c)

fn ! g dir: String words: String -> fr/Done
  (cd/gitOut dir (stringSplit words " "))

fn ledgerOf wt: String -> String
  (str wt "/asl/packages/asl-utils/doc.asn")

fn ! unitOf! root: String id: String row: String -> String
  (let [(repo (str root "/repo"))
        (wt (str root "/wts/w-" id))
        (made (if (fileExists? (str repo "/bin/asl")) "ok"
                (let [(w (sh (str "mkdir -p " repo "/bin " repo "/asl/packages/asl-utils/src " repo "/asl/packages/asl-utils/tests " root "/wts && echo initOk")))
                      (_ (g repo "init -q -b main"))
                      (_ (fileWrite (str repo "/bin/asl") (fakeTool)))
                      (_ (fileWrite (str repo "/asl/packages/asl-utils/src/trie.asl") "(module asl-utils/trie\n  :x [empty]\n  :i [])\n\nfn empty -> Int64\n  1\n"))
                      (_ (fileWrite (str repo "/asl/packages/asl-utils/tests/romanTest.asl") (romanSrc)))
                      (_ (fileWrite (str repo "/asl/packages/asl-utils/doc.asn") (ledgerBase)))
                      (_ (sh (str "chmod +x " repo "/bin/asl")))
                      (_ (g repo "add -A"))
                      (_ (g repo "-c user.email=t@example.invalid -c user.name=t commit -qm c0"))]
                  w)))
        (_ (g repo (str "worktree add -q -b sh/" id " " wt " main")))
        (_ (if (stringEmpty? row) true (ok? (fileAppend (ledgerOf wt) row))))
        (_ (fileAppend (str wt "/asl/packages/asl-utils/src/trie.asl") "\n; unit\n"))
        (_ (g wt "add -A"))
        (_ (g wt "-c user.email=t@example.invalid -c user.name=t commit -qm unit"))]
    (if (or (stringContains? made "initOk") (= made "ok")) wt ""))

fn textOf r: (Pair Int64 (List String)) -> String
  (stringJoin (pairSecond r) "\n")

fn stepOf r: (Pair Int64 (List String)) -> String
  (optionOr (listHead (filter (fn [(l String)] -> Bool (stringStartsWith? l "fix docRows: ")) (pairSecond r))) "")

fn oldOf step: String -> String
  (let [(i (optionOr (stringIndexOf step ":old \"") 0))
        (j (optionOr (stringIndexOf step "\" :new \"\")") 0))]
    (dl/renderText (optionOr (stringSlice step (+ i 6) j) "")))

fn ! appliedOf! wt: String r: (Pair Int64 (List String)) -> String
  (stringReplace (resultOr (fileReadString (ledgerOf wt)) "") (oldOf (stepOf r)) "")

fn ! runTests -> Bool
  (let [(root (pf/scratch "drff" "x"))
        (_ (pf/cleanup root))
        (wtRow (unitOf! root "R" (rowPlain)))
        (wtEsc (unitOf! root "E" (rowEscaped)))
        (wtLast (unitOf! root "L" (rowLast)))
        (wtNone (unitOf! root "N" ""))
        (red (dg/runGate (list wtRow "main" "--writer" "--limit" "60")))
        (redEsc (dg/runGate (list wtEsc "main" "--writer" "--limit" "60")))
        (redLast (dg/runGate (list wtLast "main" "--writer" "--limit" "60")))
        (green (dg/runGate (list wtNone "main" "--writer" "--limit" "60")))
        (again (dg/runGate (list wtRow "main" "--writer" "--limit" "60")))
        (okRow (= (appliedOf! wtRow red) (ledgerBase)))
        (okEsc (= (appliedOf! wtEsc redEsc) (ledgerBase)))
        (okLast (= (appliedOf! wtLast redLast) (ledgerBase)))
        (_ (pf/cleanup root))]
    (do (assert (and (not (stringEmpty? wtRow)) (and (not (stringEmpty? wtEsc)) (and (not (stringEmpty? wtLast)) (not (stringEmpty? wtNone))))) "fixture worktrees exist")
        (assert (= (pairFirst red) 1) (str "an added row documenting a test file is red: " (textOf red)))
        (assert (stringContains? (textOf red) "testFile") (str "the refusal names the kind: " (textOf red)))
        (assert (stringContains? (stepOf red) "(:edit :file \"asl/packages/asl-utils/doc.asn\" :old \"(:doc :symbol") (str "the gate prints the delete edit with file and row text: " (textOf red)))
        (assert (stringEndsWith? (stepOf red) ":new \"\") (:flush)") "the printed step ends in the replacement by nothing and a flush")
        (assert okRow "applying the printed :old/:new to the ledger restores the base ledger")
        (assert okEsc (str "the same for a row with escaped quotes and a backslash: " (stepOf redEsc)))
        (assert okLast (str "the same for a last row without a newline: " (stepOf redLast)))
        (assert (not (stringContains? (oldOf (stepOf redLast)) "\n")) "a last row without a newline has no newline in :old")
        (assert (stringContains? (oldOf (stepOf red)) "\n") "a row with a newline has it in :old")
        (assert (= (textOf again) (textOf red)) "the repeat from the memo prints the same steps")
        (assert (= (pairFirst green) 0) (str "a unit that adds no row is green: " (textOf green)))
        (assert (stringContains? (textOf green) "(:docRowsFix :required none :steps 0)") (str "green says no row is required and no step: " (textOf green)))
        true))
