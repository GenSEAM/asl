(module asl-tools/coord/tests/gateDocRowsAllTest
  :x [runTests]
  :i [(asl-tools/coord/conductor :a cd) (asl-tools/coord/docRowsGate :a dg) (asl-tools/coord/store :a st) (asl-tools/fleet/run :a fr) (asl-tools/coord/tests/fixtures/pipeFix :a pf)])

; (:m :ref DOC-ROWS-AT-GATE :do "the gate stage's doc-row check on fixture repos: a file a unit adds or changes anywhere under asl/ (a package test file, a tools file) whose :x gains a name without its row in the home ledger is red with docRows:, the symbol and the literal row, though the fake know tool prints nothing; the base's own debts, a body edit and a name with its row are green")
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
        (_ (fileWrite (str repo "/asl/packages/asl-utils/doc.asn") "(:doc :symbol \"asl/packages/asl-utils/src/trie.asl#empty\" :text \"one\")\n"))
        (_ (fileWrite (str repo "/asl/packages/asl-gates/tests/docPackageBaseline.asn") "(:gap \"asl/packages/asl-utils/src/trie.asl#debt\")\n"))
        (_ (fileWrite (str repo "/asl/doc/tools.asn") "(:doc :symbol \"asl/tools/coord/old.asl#oldRun!\" :text \"old\")\n"))
        (_ (sh (str "chmod +x " repo "/bin/asl")))
        (a (g repo "add -A"))
        (made (g repo "-c user.email=t@example.invalid -c user.name=t commit -qm c0"))]
    (if (and (stringContains? w "initOk") (and (= a.exit 0) (= made.exit 0))) repo ""))

; (:m :do "a unit worktree on sh/ID off main with the files (path, text) written and committed")
fn ! unitFiles! root: String id: String files: (List (Pair String String)) -> cd/CUnit
  (let [(wt (str root "/wts/w-" id))
        (made (g (str root "/repo") (str "worktree add -q -b sh/" id " " wt " main")))
        (_ (sh (str "mkdir -p " wt "/asl/packages/asl-utils/tests " wt "/asl/tools/coord " wt "/asl/tools/coord/tests/fixtures")))
        (_ (map (fn [(f (Pair String String))] -> Bool (ok? (fileWrite (str wt "/" (pairFirst f)) (pairSecond f)))) files))
        (a (g wt "add -A"))
        (c (g wt "-c user.email=t@example.invalid -c user.name=t commit -qm unit"))]
    (if (and (= made.exit 0) (and (= a.exit 0) (= c.exit 0))) (pf/cuIn id "gating" wt (str "sh/" id)) (pf/cuIn id "gating" "" "")))

fn unitOf id: String -> st/Task
  (with (pf/unitIn id "echo '(:gate :asserts 1 :failed 0)'") :owns (list "asl/packages/asl-utils/tests/trieTest.asl"))

fn ! gate! u: st/Task c: cd/CUnit -> (Pair cd/Res String)
  (cd/gatesResN 60 60 "" u c)

fn ! runTests -> Bool
  (let [(root (pf/scratch "gdra" "x"))
        (_ (pf/cleanup root))
        (repo (repoOf! root))
        (cT (unitFiles! root "T" (list (pair "asl/packages/asl-utils/tests/trieTest.asl" (testSrc)))))
        (cR (unitFiles! root "R" (list (pair "asl/packages/asl-utils/tests/trieTest.asl" (testSrc)) (pair "asl/packages/asl-utils/doc.asn" (str "(:doc :symbol \"asl/packages/asl-utils/src/trie.asl#empty\" :text \"one\")\n(:doc :symbol \"asl/packages/asl-utils/tests/trieTest.asl#runTests\" :text \"runs\")\n")))))
        (cA (unitFiles! root "A" (list (pair "asl/tools/coord/foo.asl" (toolSrc)))))
        (cB (unitFiles! root "B" (list (pair "asl/packages/asl-utils/src/trie.asl" "(module asl-utils/trie\n  :x [empty debt]\n  :i [])\n\nfn empty -> Int64\n  2\n\nfn debt -> Int64\n  1\n"))))
        (cF (unitFiles! root "F" (list (pair "asl/tools/coord/tests/fixtures/fixA.asl" (toolSrc)))))
        (cS (unitFiles! root "S" (list (pair "asl/packages/asl-utils/doc.asn" (str "(:doc :symbol \"asl/packages/asl-utils/src/trie.asl#empty\" :text \"one\")\n(:doc :symbol \"asl/packages/asl-utils/src/trie.asl#debt\" :text \"now documented\")\n")))))
        (cX (unitFiles! root "X" (list (pair "asl/packages/asl-utils/src/trie.asl" "(module asl-utils/trie\n  :x [empty]\n  :i [])\n\nfn empty -> Int64\n  1\n"))))
        (cL (unitFiles! root "L" (list (pair "asl/packages/asl-utils/doc.asn" "(:doc :bogus 1)\n") (pair "asl/packages/asl-utils/tests/trieTest.asl" (testSrc)))))
        (rF (gate! (unitOf "F") cF))
        (rS (gate! (unitOf "S") cS))
        (rX (gate! (unitOf "X") cX))
        (rL (gate! (unitOf "L") cL))
        (rT (gate! (unitOf "T") cT))
        (rR (gate! (unitOf "R") cR))
        (rA (gate! (unitOf "A") cA))
        (rB (gate! (unitOf "B") cB))
        (gT (dg/main (list cT.wt "main")))
        (gR (dg/main (list cR.wt "main")))
        (_ (pf/cleanup root))]
    (do (assert (not (stringEmpty? repo)) "fixture repo exists")
        (assert (and (not (stringEmpty? cT.wt)) (and (not (stringEmpty? cR.wt)) (and (not (stringEmpty? cA.wt)) (not (stringEmpty? cB.wt))))) "four unit worktrees exist")
        (assert (= (pairFirst rT).exit 3) (str "T: a new package test file whose runTests has no row is red: " (pairFirst rT).sig))
        (assert (stringStartsWith? (pairFirst rT).sig "docRows:") (str "T: the sig starts with docRows: " (pairFirst rT).sig))
        (assert (stringContains? (pairFirst rT).sig "asl/packages/asl-utils/tests/trieTest.asl#runTests") (str "T: the symbol is named: " (pairFirst rT).sig))
        (assert (stringContains? (pairFirst rT).sig "(:doc :symbol \"asl/packages/asl-utils/tests/trieTest.asl#runTests\" :text ") (str "T: the literal row: " (pairFirst rT).sig))
        (assert (and (stringContains? (pairFirst rT).sig "asl/packages/asl-utils/doc.asn") (not (stringContains? (pairFirst rT).sig "debt"))) (str "T: the home ledger is named and the base's debt is not charged: " (pairFirst rT).sig))
        (assert (= (pairFirst rR).exit 0) (str "R: the row added in the same unit makes the gate green: " (pairFirst rR).sig))
        (assert (= (pairFirst rA).exit 3) (str "A: a new tools export without a row in asl/doc/tools.asn is red: " (pairFirst rA).sig))
        (assert (and (stringContains? (pairFirst rA).sig "asl/tools/coord/foo.asl#fooRun!") (stringContains? (pairFirst rA).sig "asl/doc/tools.asn")) (str "A: symbol and ledger named: " (pairFirst rA).sig))
        (assert (= (pairFirst rB).exit 0) (str "B: a body edit in a file whose base has a debt is not charged: " (pairFirst rB).sig))
        (assert (= (pairFirst rF).exit 0) (str "F: a new file under fixtures/ is not scanned, like docLedgerTest: " (pairFirst rF).sig))
        (assert (and (= (pairFirst rS).exit 3) (stringContains? (pairFirst rS).sig "baseline row asl/packages/asl-utils/src/trie.asl#debt is stale: remove it from asl/packages/asl-gates/tests/docPackageBaseline.asn")) (str "S: documenting a baseline symbol makes its baseline row stale: " (pairFirst rS).sig))
        (assert (and (= (pairFirst rX).exit 3) (stringContains? (pairFirst rX).sig "trie.asl#debt is stale")) (str "X: removing a baseline export makes its row stale: " (pairFirst rX).sig))
        (assert (and (= (pairFirst rL).exit 3) (stringContains? (pairFirst rL).sig "does not load")) (str "L: a ledger that does not load is a refusal with the load error, not an empty ledger: " (pairFirst rL).sig))
        (assert (= gT (ok 1)) "docRowsGate: the fix-round gate exits 1 on the test-file gap")
        (assert (= gR (ok 0)) "docRowsGate: with the row it exits 0")
        true))
