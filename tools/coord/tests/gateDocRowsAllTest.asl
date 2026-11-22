(module asl-tools/coord/tests/gateDocRowsAllTest
  :x [runTests]
  :i [(asl-tools/coord/conductor :a cd) (asl-tools/coord/docRowsGate :a dg) (asl-tools/coord/store :a st) (asl-tools/fleet/run :a fr) (asl-tools/coord/tests/fixtures/pipeFix :a pf)])

; (:m :ref DOC-THIN :do "the gate stage doc-row check under rule docs on fixture repos anywhere under asl/: a new test file, a new tools export, a body edit and a new fixture owe no row and are green; an added runTests row is refused as a test-file row; an added row on an export no other package uses is refused notPublic; removing an export whose row stays makes the row stale; an added row that does not parse is a load finding")
fn fakeTool -> String
  "#!/bin/sh\nif [ \"$1\" = check ]; then exit 0; fi\necho \"(:know :missing :new 0)\"\n"

fn sh c: String -> String
  (pf/sh c)

fn ! g dir: String words: String -> fr/Done
  (cd/gitOut dir (stringSplit words " "))

fn trieSrc -> String
  "(module asl-utils/trie\n  :x [empty debt]\n  :i [])\n\nfn empty -> Int64\n  1\n\nfn debt -> Int64\n  1\n"

fn testSrc -> String
  "(module asl-utils/tests/trieTest\n  :x [runTests]\n  :i [])\n\nfn runTests -> Bool\n  true\n"

fn toolSrc -> String
  "(module asl-tools/coord/foo\n  :x [fooRun!]\n  :i [])\n\nfn ! fooRun! -> Int64\n  1\n"

fn ! repoOf! root: String -> String
  (let [(repo (str root "/repo"))
        (w (sh (str "mkdir -p " repo "/asl/packages/asl-gates/tests " repo "/bin " repo "/asl/packages/asl-utils/src " repo "/asl/tools/coord " repo "/asl/doc " root "/wts && echo initOk")))
        (_ (g repo "init -q -b main"))
        (_ (fileWrite (str repo "/bin/asl") (fakeTool)))
        (_ (fileWrite (str repo "/asl/packages/asl-utils/src/trie.asl") (trieSrc)))
        (_ (fileWrite (str repo "/asl/packages/asl-utils/doc.asn") (baseLedger)))
        (_ (fileWrite (str repo "/asl/doc/tools.asn") "(:doc :symbol \"asl/tools/coord/old.asl#oldRun!\" :text \"old\")\n"))
        (_ (sh (str "chmod +x " repo "/bin/asl")))
        (a (g repo "add -A"))
        (made (g repo "-c user.email=t@example.invalid -c user.name=t commit -qm c0"))]
    (if (and (stringContains? w "initOk") (and (= a.exit 0) (= made.exit 0))) repo ""))

; (:m :do "a unit worktree on sh/ID off main with the files (path, text) written and committed")
fn ! unitFiles! root: String id: String files: (List (Pair String String)) -> cd/CUnit
  (let [(wt (str root "/wts/w-" id))
        (made (g (str root "/repo") (str "worktree add -q -b sh/" id " " wt " main")))
        (_ (sh (str "mkdir -p " wt "/asl/packages/asl-utils/tests " wt "/asl/tools/coord " wt "/asl/tools/coord/tests/fixtures " wt "/.asl/mem/docs " wt "/asl/doc")))
        (_ (map (fn [(f (Pair String String))] -> Bool (ok? (fileWrite (str wt "/" (pairFirst f)) (pairSecond f)))) files))
        (a (g wt "add -A"))
        (c (g wt "-c user.email=t@example.invalid -c user.name=t commit -qm unit"))]
    (if (and (= made.exit 0) (and (= a.exit 0) (= c.exit 0))) (pf/cuIn id "gating" wt (str "sh/" id)) (pf/cuIn id "gating" "" "")))

fn unitOf id: String -> st/Task
  (with (pf/unitIn id "echo '(:gate :asserts 1 :failed 0)'") :owns (list "asl/packages/asl-utils/tests/trieTest.asl"))

fn ! gate! u: st/Task c: cd/CUnit -> (Pair cd/Res String)
  (cd/gatesResN 60 60 "" u c)

fn baseLedger -> String
  (str "(:doc :symbol \"asl/packages/asl-utils/src/trie.asl#empty\" :text \"Shared by the router and the cache so both see one empty value\")\n"
       "(:doc :symbol \"asl/packages/asl-utils/src/trie.asl#debt\" :text \"Kept for the old wire readers until the v2 format lands\")\n")

fn ! runTests -> Bool
  (let [(root (pf/scratch "gdra" "x"))
        (_ (pf/cleanup root))
        (repo (repoOf! root))
        (cT (unitFiles! root "T" (list (pair "asl/packages/asl-utils/tests/trieTest.asl" (testSrc)))))
        (cR (unitFiles! root "R" (list (pair "asl/packages/asl-utils/tests/trieTest.asl" (testSrc)) (pair "asl/packages/asl-utils/doc.asn" (str (baseLedger) "(:doc :symbol \"asl/packages/asl-utils/tests/trieTest.asl#runTests\" :text \"Runs the trie suite against the router fixtures\")\n")))))
        (cA (unitFiles! root "A" (list (pair "asl/tools/coord/foo.asl" (toolSrc)))))
        (cB (unitFiles! root "B" (list (pair "asl/packages/asl-utils/src/trie.asl" "(module asl-utils/trie\n  :x [empty debt]\n  :i [])\n\nfn empty -> Int64\n  2\n\nfn debt -> Int64\n  1\n"))))
        (cF (unitFiles! root "F" (list (pair "asl/tools/coord/tests/fixtures/fixA.asl" (toolSrc)))))
        (cS (unitFiles! root "S" (list (pair "asl/tools/coord/foo.asl" (toolSrc)) (pair "asl/doc/tools.asn" "(:doc :symbol \"asl/tools/coord/old.asl#oldRun!\" :text \"old\")\n(:doc :symbol \"asl/tools/coord/foo.asl#fooRun!\" :text \"Starts the run once per lease so that a retry does not double it\")\n"))))
        (cX (unitFiles! root "X" (list (pair "asl/packages/asl-utils/src/trie.asl" "(module asl-utils/trie\n  :x [empty]\n  :i [])\n\nfn empty -> Int64\n  1\n"))))
        (cL (unitFiles! root "L" (list (pair "asl/packages/asl-utils/doc.asn" (str (baseLedger) "(:doc :bogus 1)\n")) (pair "asl/packages/asl-utils/tests/trieTest.asl" (testSrc)))))
        (cM (unitFiles! root "M" (list (pair ".asl/mem/docs/harness.asn" "(:doc :symbol \"harness/src/gone.asl#run\" :text \"Kept for the replay of old logs\")\n"))))
        (cW (unitFiles! root "W" (list (pair "asl/doc/web.asn" "(:doc :symbol \"harness/src/gone.asl#run\" :text \"Kept for the replay of old logs\")\n"))))
        (rT (gate! (unitOf "T") cT))
        (rR (gate! (unitOf "R") cR))
        (rA (gate! (unitOf "A") cA))
        (rB (gate! (unitOf "B") cB))
        (rF (gate! (unitOf "F") cF))
        (rS (gate! (unitOf "S") cS))
        (rX (gate! (unitOf "X") cX))
        (rL (gate! (unitOf "L") cL))
        (rM (gate! (unitOf "M") cM))
        (rW (gate! (unitOf "W") cW))
        (gT (dg/main (list cT.wt "main")))
        (gR (dg/main (list cR.wt "main")))
        (_ (pf/cleanup root))]
    (do (assert (not (stringEmpty? repo)) "fixture repo exists")
        (assert (and (not (stringEmpty? cT.wt)) (and (not (stringEmpty? cR.wt)) (and (not (stringEmpty? cA.wt)) (not (stringEmpty? cB.wt))))) "the unit worktrees exist")
        (assert (= (pairFirst rT).exit 0) (str "T: a new test file owes no row: " (pairFirst rT).sig))
        (assert (and (= (pairFirst rR).exit 3) (and (stringStartsWith? (pairFirst rR).sig "docRows:") (and (stringContains? (pairFirst rR).sig "trieTest.asl#runTests") (stringContains? (pairFirst rR).sig "testFile")))) (str "R: an added runTests row is refused as a test-file row: " (pairFirst rR).sig))
        (assert (= (pairFirst rA).exit 0) (str "A: a new tools export owes no row in asl/doc/tools.asn: " (pairFirst rA).sig))
        (assert (= (pairFirst rB).exit 0) (str "B: a body edit is green: " (pairFirst rB).sig))
        (assert (= (pairFirst rF).exit 0) (str "F: a new file under fixtures/ is green: " (pairFirst rF).sig))
        (assert (and (= (pairFirst rS).exit 3) (and (stringContains? (pairFirst rS).sig "foo.asl#fooRun!") (and (stringContains? (pairFirst rS).sig "notPublic") (not (stringContains? (pairFirst rS).sig "oldRun"))))) (str "S: an added row on an export no other package uses is refused, the untouched old row is not judged: " (pairFirst rS).sig))
        (assert (and (= (pairFirst rX).exit 3) (and (stringContains? (pairFirst rX).sig "trie.asl#debt") (stringContains? (pairFirst rX).sig "removed symbol"))) (str "X: removing an export whose row stays makes the row stale: " (pairFirst rX).sig))
        (assert (and (= (pairFirst rL).exit 3) (stringContains? (pairFirst rL).sig "does not load")) (str "L: an added row that does not parse is a load finding: " (pairFirst rL).sig))
        (assert (and (= (pairFirst rM).exit 3) (stringContains? (pairFirst rM).sig "gone.asl#run")) (str "M: a row added to .asl/mem/docs/TOP.asn is judged like any ledger row: " (pairFirst rM).sig))
        (assert (= (pairFirst rW).exit 0) (str "W: asl/doc/web.asn is no doc ledger, the gate leaves it alone as the tree scan does: " (pairFirst rW).sig))
        (assert (= gT (ok 0)) "docRowsGate: the new test file exits 0")
        (assert (= gR (ok 1)) "docRowsGate: the refused row exits 1")
        true))
