(module asl-tools/coord/tests/gateDocRowsTest
  :x [runTests]
  :i [(asl-tools/coord/conductor :a cd) (asl-tools/coord/docRows :a dr) (asl-tools/coord/docRowsGate :a dg) (asl-tools/coord/store :a st) (asl-tools/fleet/run :a fr) (asl-tools/coord/tests/fixtures/pipeFix :a pf)])

; (:m :ref GATE-DOC-ROWS :do "the gate stage's early doc-row check on fixture repos in a temp dir: the worktree's bin/asl is a fake that logs every call to .fakeLog and prints the rows of .fakeRows (exit 7 when .fakeFail exists); a unit that exports a new symbol without a doc row is red with the symbol, the file and the literal row; a diff without package source never starts the tool (asserted on the log); a miss the base already had is not charged; a tool that fails never blocks and the note says infra")
fn fakeTool -> String
  "#!/bin/sh\necho \"$@\" >> \"$ASL_ROOT/.fakeLog\"\nif [ \"$1\" = check ]; then exit 0; fi\nif [ -f \"$ASL_ROOT/.fakeRows\" ]; then cat \"$ASL_ROOT/.fakeRows\"; else echo \"(:know :missing :new 0)\"; fi\nif [ -f \"$ASL_ROOT/.fakeFail\" ]; then exit 7; fi\n"

fn trieBase -> String
  "(module asl-utils/trie\n  :x [empty]\n  :i [])\n\nfn empty -> Int64\n  1\n"

fn trieNew -> String
  "(module asl-utils/trie\n  :x [empty insert]\n  :i [])\n\nfn empty -> Int64\n  1\n\nfn insert k: Int64 -> Int64\n  k\n"

fn trieBody -> String
  "(module asl-utils/trie\n  :x [empty]\n  :i [])\n\nfn empty -> Int64\n  2\n"

fn rowsBoth -> String
  "(:know :missing :new 2)\nasl-utils#asl-utils/trie/empty nodoc\nasl-utils#asl-utils/trie/insert nodoc\n"

fn ! repoOf! root: String -> String
  (let [(repo (str root "/repo"))
        (w (sh (str "mkdir -p " repo "/bin " repo "/asl/packages/asl-utils/src " repo "/docs " root "/wts && echo initOk")))
        (_ (g repo "init -q -b main"))
        (_ (fileWrite (str repo "/bin/asl") (fakeTool)))
        (_ (fileWrite (str repo "/docs/readme.txt") "r\n"))
        (_ (fileWrite (str repo "/asl/packages/asl-utils/src/trie.asl") (trieBase)))
        (_ (fileWrite (str repo "/asl/packages/asl-utils/doc.asn") "(:doc :symbol \"asl/packages/asl-utils/src/trie.asl#\" :text \"tries\")\n"))
        (_ (sh (str "chmod +x " repo "/bin/asl")))
        (a (g repo "add -A"))
        (made (g repo "-c user.email=t@example.invalid -c user.name=t commit -qm c0"))]
    (if (and (stringContains? w "initOk") (and (= a.exit 0) (= made.exit 0))) repo ""))

fn sh c: String -> String
  (pf/sh c)

fn ! g dir: String words: String -> fr/Done
  (cd/gitOut dir (stringSplit words " "))

; (:m :do "a unit worktree on sh/ID off main, the file written and committed, and the rows the fake tool prints; returns the CUnit")
fn ! unitWith! root: String id: String file: String text: String rows: String -> cd/CUnit
  (let [(wt (str root "/wts/w-" id))
        (made (g (str root "/repo") (str "worktree add -q -b sh/" id " " wt " main")))
        (_ (fileWrite (str wt "/" file) text))
        (_ (if (stringEmpty? rows) () (let [(_ (fileWrite (str wt "/.fakeRows") rows))] ())))
        (a (g wt (str "add -A -- " file)))
        (c (g wt "-c user.email=t@example.invalid -c user.name=t commit -qm unit"))]
    (if (and (= made.exit 0) (and (= a.exit 0) (= c.exit 0))) (pf/cuIn id "gating" wt (str "sh/" id)) (pf/cuIn id "gating" "" "")))

; (:m :ref DOC-ROWS-AT-GATE :do "the unit also adds the insert row to its package doc.asn, so the ledger check passes and the know tool stays the judge of the case")
fn ! withRow! c: cd/CUnit -> Bool
  (let [(_ (fileAppend (str c.wt "/asl/packages/asl-utils/doc.asn") "(:doc :symbol \"asl/packages/asl-utils/src/trie.asl#insert\" :text \"inserts\")\n"))
        (a (g c.wt "add -A"))
        (m (g c.wt "-c user.email=t@example.invalid -c user.name=t commit -q --amend --no-edit"))]
    (= m.exit 0))

fn unitOf id: String -> st/Task
  (with (pf/unitIn id "echo '(:gate :asserts 1 :failed 0)'") :owns (list "asl/packages/asl-utils/src/trie.asl"))

fn logOf wt: String -> String
  (resultOr (fileReadString (str wt "/.fakeLog")) "")

fn toolRuns log: String -> Int64
  (listLength (filter (fn [(l String)] -> Bool (stringContains? l "know.asl")) (stringLines log)))

fn ! pureParts -> Bool
  (let [(diff "--- a/x\n+++ b/x\n-  :x [empty]\n+  :x [empty insert]\n+fn insert k: Int64 -> Int64\n")
        (rows (dr/parseRows "(:know :missing :new 2)\nasl-utils#asl-utils/trie/empty nodoc\nasl-utils#asl-utils/trie/insert nodoc\nnoise line\nx#y nodecl\n"))
        (msg (dr/message (dr/charged rows (dr/addedNames diff)) (list (pair "asl/packages/asl-utils/src/trie.asl" (trieNew)))))]
    (do (assert (listContains? (dr/addedNames diff) "insert") "a name the diff adds is listed")
        (assert (not (listContains? (dr/addedNames diff) "empty")) "a name on an edited :x line that the diff also removes is not added")
        (assert (= (listLength rows) 2) (str "the header, noise and a row without a module slash are not rows: " (stringFromInt64 (listLength rows))))
        (assert (stringContains? msg "(:doc :symbol \"asl/packages/asl-utils/src/trie.asl#insert\" :text \"one sentence: what it returns and when it fails\")") (str "the message carries the literal row: " msg))
        (assert (and (stringContains? msg "asl/packages/asl-utils/doc.asn") (not (stringContains? msg "trie/empty"))) "the doc.asn path is named and an uncharged symbol is not")
        (assert (not (stringContains? msg "\n")) "the message is one line")
        (assert (dr/relevant? (list "README.md" "asl/packages/asl-utils/src/trie.asl")) "a package source is relevant")
        (assert (dr/relevant? (list "asl/packages/asl-utils/doc.asn")) "a doc.asn is relevant")
        (assert (not (dr/relevant? (list "asl/packages/asl-utils/tests/xTest.asl" "docs/a.txt" "asl/tools/coord/conductor.asl"))) "tests, docs and tools are not")
        true))

fn ! runTests -> Bool
  (let [(root (pf/scratch "gdr" "x"))
        (_ (pf/cleanup root))
        (repo (repoOf! root))
        (cA (unitWith! root "A" "asl/packages/asl-utils/src/trie.asl" (trieNew) (rowsBoth)))
        (rA (cd/gatesResN 60 60 "" (unitOf "A") cA))
        (cB (unitWith! root "B" "asl/packages/asl-utils/src/trie.asl" (trieNew) ""))
        (_ (fileAppend (str cB.wt "/.fakeRows") "(:know :missing :new 0)\n"))
        (_ (withRow! cB))
        (rB (cd/gatesResN 60 60 "" (unitOf "B") cB))
        (cC (unitWith! root "C" "docs/a.txt" "x\n" (rowsBoth)))
        (rC (cd/gatesResN 60 60 "" (unitOf "C") cC))
        (cD (unitWith! root "D" "asl/packages/asl-utils/src/trie.asl" (trieBody) (str "(:know :missing :new 1)\nasl-utils#asl-utils/trie/empty nodoc\n")))
        (rD (cd/gatesResN 60 60 "" (unitOf "D") cD))
        (cE (unitWith! root "E" "asl/packages/asl-utils/src/trie.asl" (trieNew) (rowsBoth)))
        (_ (fileWrite (str cE.wt "/.fakeFail") "1"))
        (_ (withRow! cE))
        (rE (cd/gatesResN 60 60 "" (unitOf "E") cE))
        (lA (logOf cA.wt)) (lB (logOf cB.wt)) (lC (logOf cC.wt)) (lD (logOf cD.wt)) (lE (logOf cE.wt))
        (gA (dg/main (list cA.wt "main")))
        (gB (dg/main (list cB.wt "main")))
        (gC (dg/main (list cC.wt "main")))
        (gE (dg/main (list cE.wt "main")))
        (gEw (dg/main (list cE.wt "main" "--writer")))
        (gAw (dg/main (list cA.wt "main" "--writer")))
        (rcW (cd/realCfg (list "--repo" repo "--home" (str root "/home") "--worktrees" (str root "/wts")) (str root "/store")))
        (unitNoPkg (with (unitOf "A") :owns (list "asl/tools/coord/x.asl")))
        (gatesPlain (cd/writerGates rcW cA.wt unitNoPkg ""))
        (gatesOwnPkg (cd/writerGates rcW cA.wt (unitOf "A") ""))
        (gatesDoc (cd/writerGates rcW cA.wt (unitOf "A") "fail: docRows: 2 new exported symbols"))
        (gatesHop (cd/writerGates rcW cA.wt (unitOf "A") "tierHop free->paid: docRows: 2 new exported symbols"))
        (_ (pf/cleanup root))]
    (do (assert (not (stringEmpty? repo)) "fixture repo exists")
        (assert (and (not (stringEmpty? cA.wt)) (and (not (stringEmpty? cB.wt)) (and (not (stringEmpty? cC.wt)) (and (not (stringEmpty? cD.wt)) (not (stringEmpty? cE.wt)))))) "five unit worktrees exist")
        (assert (pureParts) "pure parts")
        (assert (= (pairFirst rA).exit 3) (str "A: a new exported fn without a doc row is red: " (pairFirst rA).sig))
        (assert (stringContains? (pairFirst rA).sig "trie.asl#insert") "A: the symbol is named")
        (assert (stringContains? (pairFirst rA).sig "(:doc :symbol \"asl/packages/asl-utils/src/trie.asl#insert\" :text \"one sentence: what it returns and when it fails\")") (str "A: the literal row form: " (pairFirst rA).sig))
        (assert (stringContains? (pairFirst rA).sig "asl/packages/asl-utils/doc.asn") "A: the doc.asn path")
        (assert (not (stringContains? (pairFirst rA).sig "trie/empty")) "A: the base's own miss is not charged")
        (assert (= (toolRuns lA) 0) (str "A: the ledger check answers before the tool starts (DOC-ROWS-AT-GATE): " lA))
        (assert (= (pairFirst rB).exit 0) (str "B: with the row the gate is green: " (pairFirst rB).sig))
        (assert (stringContains? (pairSecond rB) ":ran true :charged 0") (str "B: the note says ran and charged 0: " (pairSecond rB)))
        (assert (= (toolRuns lB) 1) "B: the tool ran")
        (assert (= (toolRuns lC) 0) (str "C: no package source in the diff, the tool is not started: " lC))
        (assert (stringContains? (pairSecond rC) "noPackageSource") (str "C: the note says why: " (pairSecond rC)))
        (assert (= (pairFirst rC).exit 0) "C: the gate runs and is green")
        (assert (and (= (pairFirst rD).exit 0) (stringContains? (pairSecond rD) ":charged 0")) (str "D: a miss only the base had is not charged: " (pairFirst rD).sig " " (pairSecond rD)))
        (assert (= (toolRuns lD) 0) (str "D: the unit edits a body and adds no export, the know run is skipped (cheap gate): " lD))
        (assert (stringContains? (pairSecond rD) "noNewExports") (str "D: the note says why: " (pairSecond rD)))
        (assert (= (pairFirst rE).exit 0) (str "E: a failing tool does not block: " (pairFirst rE).sig))
        (assert (and (stringContains? (pairSecond rE) ":why infra") (stringContains? (pairSecond rE) "exit 7")) (str "E: the note says infra: " (pairSecond rE)))
        (assert (= (toolRuns lE) 1) "E: the tool was started")
        (assert (= gA (ok 1)) (str "docRowsGate: a worktree whose new export has no doc.asn row exits 1: " (match gA ((ok k) (stringFromInt64 k)) ((err e) e))))
        (assert (= gB (ok 0)) "docRowsGate: with the row it exits 0")
        (assert (= gC (ok 0)) "docRowsGate: a tree with no package code in the diff exits 0")
        (assert (= gEw (ok 0)) "docRowsGate --writer: a tool that cannot run is green inside the writer's run, the model is not blamed")
        (assert (= gAw (ok 1)) "docRowsGate --writer: a real missing row is still red")
        (assert (= gE (ok 2)) "docRowsGate: a tool that cannot run is gateInfra exit 2, never a green assert")
        (assert (and (= (listLength gatesPlain) 1) (= (listLength gatesOwnPkg) 2) (= (listLength gatesDoc) 2) (= (listLength gatesHop) 2)) (str "the docRows gate is added after the fail: form, after a tierHop form and from the first attempt when the unit owns package src (COND-OWNS-DOC), not otherwise: " (stringFromInt64 (listLength gatesHop))))
        (assert (= (optionOr (listLast gatesDoc) "") "./bin/asl run asl/tools/coord/docRowsGate.asl . main --writer") (str "the added command runs the jail-relative ./bin/asl and docRowsGate.asl on . with --writer: " (optionOr (listLast gatesDoc) "")))
        true))
