(module asl-tools/coord/tests/gateDocRowsTest
  :x [runTests]
  :i [(asl-tools/coord/conductor :a cd) (asl-tools/coord/docRowsGate :a dg) (asl-tools/coord/store :a st) (asl-tools/fleet/run :a fr) (asl-tools/coord/tests/fixtures/pipeFix :a pf)])

; (:m :ref DOC-THIN :do "the gate stage doc-row check under rule docs on fixture repos in a temp dir; the worktree bin/asl is a fake that logs every call to .fakeLog: a new export without a row is green (no row is owed) and the know tool is never started; an added row that echoes the name or that no other package needs is red with the symbol, the reason and the ledger; a row with a reason on an export another package uses is green; docRowsGate.asl, the writer gate, answers the same")
fn fakeTool -> String
  "#!/bin/sh\necho \"$@\" >> \"$ASL_ROOT/.fakeLog\"\nif [ \"$1\" = check ]; then exit 0; fi\nif [ -f \"$ASL_ROOT/.fakeRows\" ]; then cat \"$ASL_ROOT/.fakeRows\"; else echo \"(:know :missing :new 0)\"; fi\nif [ -f \"$ASL_ROOT/.fakeFail\" ]; then exit 7; fi\n"

fn trieBase -> String
  "(module asl-utils/trie\n  :x [empty]\n  :i [])\n\nfn empty -> Int64\n  1\n"

fn trieNew -> String
  "(module asl-utils/trie\n  :x [empty insert]\n  :i [])\n\nfn empty -> Int64\n  1\n\nfn insert k: Int64 -> Int64\n  k\n"

fn trieBody -> String
  "(module asl-utils/trie\n  :x [empty]\n  :i [])\n\nfn empty -> Int64\n  2\n"

fn ! repoOf! root: String -> String
  (let [(repo (str root "/repo"))
        (w (sh (str "mkdir -p " repo "/bin " repo "/asl/packages/asl-utils/src " repo "/docs " root "/wts && echo initOk")))
        (_ (g repo "init -q -b main"))
        (_ (fileWrite (str repo "/bin/asl") (fakeTool)))
        (_ (fileWrite (str repo "/docs/readme.txt") "r\n"))
        (_ (fileWrite (str repo "/asl/packages/asl-utils/src/trie.asl") (trieBase)))
        (_ (fileWrite (str repo "/asl/packages/asl-utils/doc.asn") "(:doc :symbol \"asl/packages/asl-utils/src/trie.asl#\" :text \"Prefix lookups for the router, kept apart so the hot path allocates nothing\")\n"))
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

; (:m :ref DOC-THIN :do "the unit also adds a row for insert with the given text to its package doc.asn")
fn ! withRow! c: cd/CUnit text: String -> Bool
  (let [(_ (fileAppend (str c.wt "/asl/packages/asl-utils/doc.asn") (str "(:doc :symbol \"asl/packages/asl-utils/src/trie.asl#insert\" :text \"" text "\")\n")))
        (a (g c.wt "add -A"))
        (m (g c.wt "-c user.email=t@example.invalid -c user.name=t commit -q --amend --no-edit"))]
    (= m.exit 0))

fn unitOf id: String -> st/Task
  (with (pf/unitIn id "echo '(:gate :asserts 1 :failed 0)'") :owns (list "asl/packages/asl-utils/src/trie.asl"))

fn logOf wt: String -> String
  (resultOr (fileReadString (str wt "/.fakeLog")) "")

fn toolRuns log: String -> Int64
  (listLength (filter (fn [(l String)] -> Bool (stringContains? l "know.asl")) (stringLines log)))

fn userSrc -> String
  "(module asl-other/user\n  :x [go]\n  :i [(asl-utils/trie :a tr)])\n\nfn go -> Int64\n  (tr/insert 1)\n"

fn why -> String
  "Counts once per batch so that a retried insert does not double the size"

fn ! runTests -> Bool
  (let [(root (pf/scratch "gdr" "x"))
        (_ (pf/cleanup root))
        (repo (repoOf! root))
        (cA (unitWith! root "A" "asl/packages/asl-utils/src/trie.asl" (trieNew) ""))
        (rA (cd/gatesResN 60 60 "" (unitOf "A") cA))
        (cB (unitWith! root "B" "asl/packages/asl-utils/src/trie.asl" (trieNew) ""))
        (_ (withRow! cB "inserts"))
        (rB (cd/gatesResN 60 60 "" (unitOf "B") cB))
        (cC (unitWith! root "C" "docs/a.txt" "x\n" ""))
        (rC (cd/gatesResN 60 60 "" (unitOf "C") cC))
        (cD (unitWith! root "D" "asl/packages/asl-utils/src/trie.asl" (trieBody) ""))
        (rD (cd/gatesResN 60 60 "" (unitOf "D") cD))
        (cE (unitWith! root "E" "asl/packages/asl-utils/src/trie.asl" (trieNew) ""))
        (_ (withRow! cE (why)))
        (rE (cd/gatesResN 60 60 "" (unitOf "E") cE))
        (cF (unitWith! root "F" "asl/packages/asl-utils/src/trie.asl" (trieNew) ""))
        (_ (sh (str "mkdir -p " cF.wt "/asl/packages/asl-other/src")))
        (_ (fileWrite (str cF.wt "/asl/packages/asl-other/src/user.asl") (userSrc)))
        (_ (withRow! cF (why)))
        (rF (cd/gatesResN 60 60 "" (unitOf "F") cF))
        (lA (logOf cA.wt)) (lB (logOf cB.wt)) (lE (logOf cE.wt)) (lF (logOf cF.wt))
        (gA (dg/main (list cA.wt "main")))
        (gB (dg/main (list cB.wt "main")))
        (gBw (dg/main (list cB.wt "main" "--writer")))
        (gF (dg/main (list cF.wt "main")))
        (rcW (cd/realCfg (list "--repo" repo "--home" (str root "/home") "--worktrees" (str root "/wts")) (str root "/store")))
        (unitNoPkg (with (unitOf "A") :owns (list "asl/tools/coord/x.asl")))
        (gatesPlain (cd/writerGates rcW cA.wt unitNoPkg ""))
        (gatesOwnPkg (cd/writerGates rcW cA.wt (unitOf "A") ""))
        (gatesDoc (cd/writerGates rcW cA.wt (unitOf "A") "fail: docRows: 2 doc row findings"))
        (gatesHop (cd/writerGates rcW cA.wt (unitOf "A") "tierHop free->paid: docRows: 2 doc row findings"))
        (_ (pf/cleanup root))]
    (do (assert (not (stringEmpty? repo)) "fixture repo exists")
        (assert (and (not (stringEmpty? cA.wt)) (and (not (stringEmpty? cB.wt)) (and (not (stringEmpty? cC.wt)) (and (not (stringEmpty? cD.wt)) (and (not (stringEmpty? cE.wt)) (not (stringEmpty? cF.wt))))))) "six unit worktrees exist")
        (assert (= (pairFirst rA).exit 0) (str "A: a new export without a row is green, no row is owed: " (pairFirst rA).sig))
        (assert (stringContains? (pairSecond rA) ":docRows :ran true :charged 0") (str "A: the note says ran and charged 0: " (pairSecond rA)))
        (assert (= (toolRuns (str lA lB lE lF)) 0) (str "the know tool is never started: " lA))
        (assert (= (pairFirst rB).exit 3) (str "B: an added row that echoes the name is red: " (pairFirst rB).sig))
        (assert (and (stringContains? (pairFirst rB).sig "trie.asl#insert") (and (stringContains? (pairFirst rB).sig "nameEcho") (stringContains? (pairFirst rB).sig "asl/packages/asl-utils/doc.asn"))) (str "B: symbol, reason and ledger named: " (pairFirst rB).sig))
        (assert (stringStartsWith? (pairFirst rB).sig "docRows:") "B: the sig starts with docRows: so the fix round adds docRowsGate")
        (assert (= (pairFirst rC).exit 0) "C: a diff without code or ledger is green")
        (assert (= (pairFirst rD).exit 0) (str "D: a body edit is green: " (pairFirst rD).sig))
        (assert (and (= (pairFirst rE).exit 3) (stringContains? (pairFirst rE).sig "notPublic")) (str "E: a row with a reason on an export no other package uses is red: " (pairFirst rE).sig))
        (assert (= (pairFirst rF).exit 0) (str "F: the same row is green once another package uses insert: " (pairFirst rF).sig))
        (assert (= gA (ok 0)) "docRowsGate: no row owed, exit 0")
        (assert (= gB (ok 1)) "docRowsGate: a refused row exits 1")
        (assert (= gBw (ok 1)) "docRowsGate --writer: a refused row is red in the writer's run too")
        (assert (= gF (ok 0)) "docRowsGate: a row on a used export with a reason exits 0")
        (assert (and (= (listLength gatesPlain) 1) (= (listLength gatesOwnPkg) 2) (= (listLength gatesDoc) 2) (= (listLength gatesHop) 2)) (str "the docRows gate is added after the fail: form, after a tierHop form and from the first attempt when the unit owns package src (COND-OWNS-DOC), not otherwise: " (stringFromInt64 (listLength gatesPlain))))
        (assert (= (optionOr (listLast gatesDoc) "") "./bin/asl run asl/tools/coord/docRowsGate.asl . main --writer") (str "the added command runs the jail-relative ./bin/asl and docRowsGate.asl on . with --writer: " (optionOr (listLast gatesDoc) "")))
        true))
