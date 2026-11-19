(module asl-tools/coord/tests/docDupTest
  :x [runTests]
  :i [(asl-tools/coord/conductor :a cd) (asl-tools/coord/docDup :a dd) (asl-tools/coord/docRowsGate :a dg) (asl-tools/fleet/run :a fr) (asl-tools/coord/tests/fixtures/pipeFix :a pf)])

; (:m :ref REVIEW-CRITERIA-DOCDUP :do "the duplicate doc row gate on fixture repos in a temp dir (the worktree's bin/asl is the fake of gateDocRowsTest: it prints .fakeRows and exits 7 when .fakeFail exists): a unit that adds two rows of one symbol is red through docRowsGate main with the symbol and both line numbers in the message, one row is green, a duplicate the base already had is not charged, a second row for a symbol the base documented is, an untracked doc.asn counts, and the duplicate stays red when the missing-row check cannot run")
fn fakeTool -> String
  "#!/bin/sh\necho \"$@\" >> \"$ASL_ROOT/.fakeLog\"\nif [ \"$1\" = check ]; then exit 0; fi\nif [ -f \"$ASL_ROOT/.fakeRows\" ]; then cat \"$ASL_ROOT/.fakeRows\"; else echo \"(:know :missing :new 0)\"; fi\nif [ -f \"$ASL_ROOT/.fakeFail\" ]; then exit 7; fi\n"

fn srcBase -> String
  "(module asl-utils/duration\n  :x [zero]\n  :i [])\n\nfn zero -> Int64\n  0\n"

fn srcNew -> String
  "(module asl-utils/duration\n  :x [zero parseDuration]\n  :i [])\n\nfn zero -> Int64\n  0\n\nfn parseDuration s: String -> Int64\n  1\n"

fn row name: String text: String -> String
  (str "(:doc :symbol \"asl/packages/asl-utils/src/duration.asl#" name "\" :text \"" text "\")\n")

; (:m :do "the base ledger: one row for zero and a duplicate pair for old that no unit of the test touches")
fn docBase -> String
  (str (row "zero" "the zero duration") (row "old" "first") (row "old" "second"))

fn docPath -> String
  "asl/packages/asl-utils/doc.asn"

fn sh c: String -> String
  (pf/sh c)

fn ! g dir: String words: String -> fr/Done
  (cd/gitOut dir (stringSplit words " "))

fn ! repoOf! root: String -> String
  (let [(repo (str root "/repo"))
        (w (sh (str "mkdir -p " repo "/bin " repo "/asl/packages/asl-utils/src " root "/wts && echo initOk")))
        (_ (g repo "init -q -b main"))
        (_ (fileWrite (str repo "/bin/asl") (fakeTool)))
        (_ (fileWrite (str repo "/asl/packages/asl-utils/src/duration.asl") (srcBase)))
        (_ (fileWrite (str repo "/" (docPath)) (docBase)))
        (_ (sh (str "chmod +x " repo "/bin/asl")))
        (a (g repo "add -A"))
        (made (g repo "-c user.email=t@example.invalid -c user.name=t commit -qm c0"))]
    (if (and (stringContains? w "initOk") (and (= a.exit 0) (= made.exit 0))) repo ""))

; (:m :do "a unit worktree on sh/ID off main with the ledger and, when src is not empty, the source written and committed; returns the worktree path, empty on a failed fixture")
fn ! unitWith! root: String id: String doc: String src: String -> String
  (let [(wt (str root "/wts/w-" id))
        (made (g (str root "/repo") (str "worktree add -q -b sh/" id " " wt " main")))
        (_ (fileWrite (str wt "/" (docPath)) doc))
        (_ (if (stringEmpty? src) () (let [(_ (fileWrite (str wt "/asl/packages/asl-utils/src/duration.asl") src))] ())))
        (a (g wt "add -A -- asl/packages"))
        (c (g wt "-c user.email=t@example.invalid -c user.name=t commit -qm unit"))]
    (if (and (= made.exit 0) (and (= a.exit 0) (= c.exit 0))) wt ""))

fn exitOf r: (Result Int64 String) -> Int64
  (match r ((ok k) k) ((err _) -1))

fn pureParts -> Bool
  (let [(text (str (row "a" "one") "noise (:doc :symbol \"inline\" :text \"not a row start\")\n" (row "b" "two") "  " (row "a" "three")))
        (a "asl/packages/asl-utils/src/duration.asl#a")
        (b "asl/packages/asl-utils/src/duration.asl#b")
        (diff (str "--- a/x\n+++ b/x\n@@ -0,0 +1 @@\n+" (row "a" "three") "-" (row "b" "gone") "+plain line\n"))
        (dups (dd/dupRows text (list a b)))
        (msg (dd/dupMessage "p/doc.asn" dups))]
    (do (assert (= (dd/symbolOf (row "a" "one")) a) (str "the symbol of a row: " (dd/symbolOf (row "a" "one"))))
        (assert (= (dd/symbolOf "fn a -> Int64") "") "a line that is no row has no symbol")
        (assert (= (dd/addedSymbols diff) (list a)) (str "only an added row is an added symbol, a removed row and the +++ header are not: " (stringJoin (dd/addedSymbols diff) " ")))
        (assert (= (map (fn [(d dd/Dup)] -> String d.symbol) dups) (list a)) "the symbol with two rows is a duplicate, the one with a single row is not")
        (assert (= (optionOr (listHead (map (fn [(d dd/Dup)] -> (List Int64) d.lines) dups)) (list)) (list 1 4)) "both rows are located by their 1-based line, an indented row counts, a row text inside another line does not")
        (assert (listEmpty? (dd/dupRows text (list b))) "a symbol outside the added set is not judged")
        (assert (and (stringContains? msg (str "symbol \"" a "\"")) (and (stringContains? msg "at lines 1 and 4") (stringContains? msg "p/doc.asn"))) (str "the message names file, symbol and both lines: " msg))
        (assert (not (stringContains? msg "\n")) "the message is one line")
        true))

fn ! runTests -> Bool
  (let [(root (pf/scratch "docDup" "x"))
        (_ (pf/cleanup root))
        (repo (repoOf! root))
        (twice (str (docBase) (row "parseDuration" "card copy") (row "parseDuration" "hand-written copy")))
        (wA (unitWith! root "A" twice (srcNew)))
        (wB (unitWith! root "B" (str (docBase) (row "parseDuration" "parses 1h30m")) (srcNew)))
        (wC (unitWith! root "C" (str (docBase) (row "other" "unrelated")) ""))
        (wD (unitWith! root "D" (str (docBase) (row "zero" "a second row for a symbol the base documented")) ""))
        (wE (unitWith! root "E" twice (srcNew)))
        (_ (fileWrite (str wE "/.fakeFail") "1"))
        (wF (unitWith! root "F" (docBase) (srcNew)))
        (madeDir (sh (str "mkdir -p " wF "/asl/packages/asl-new && echo dirOk")))
        (_ (fileWrite (str wF "/asl/packages/asl-new/doc.asn") (str (row "fresh" "one") (row "fresh" "two"))))
        (mA (dd/dupCheckAt! wA "main")) (mB (dd/dupCheckAt! wB "main")) (mC (dd/dupCheckAt! wC "main")) (mD (dd/dupCheckAt! wD "main")) (mF (dd/dupCheckAt! wF "main"))
        (gA (exitOf (dg/main (list wA "main" "--writer"))))
        (gB (exitOf (dg/main (list wB "main" "--writer"))))
        (gC (exitOf (dg/main (list wC "main"))))
        (gD (exitOf (dg/main (list wD "main"))))
        (gEw (exitOf (dg/main (list wE "main" "--writer"))))
        (gE (exitOf (dg/main (list wE "main"))))
        (gF (exitOf (dg/main (list wF "main" "--writer"))))
        (_ (pf/cleanup root))]
    (do (assert (not (stringEmpty? repo)) "fixture repo exists")
        (assert (and (stringContains? madeDir "dirOk") (listAll? (fn [(w String)] -> Bool (not (stringEmpty? w))) (list wA wB wC wD wE wF))) "six unit worktrees exist")
        (assert (pureParts) "pure parts")
        (assert (= gA 1) (str "A: two rows the unit added for one symbol are red in the writer's gate: " (stringFromInt64 gA)))
        (assert (and (stringContains? mA "duration.asl#parseDuration\"") (and (stringContains? mA "at lines 4 and 5") (stringContains? mA (docPath)))) (str "A: the message names the symbol, both lines and the file: " mA))
        (assert (not (stringContains? mA "#old")) (str "A: the base's own duplicate is not charged to the unit: " mA))
        (assert (and (= gB 0) (stringEmpty? mB)) (str "B: one row per added symbol is green: " (stringFromInt64 gB) " " mB))
        (assert (and (= gC 0) (stringEmpty? mC)) (str "C: a unit that adds an unrelated row is not charged the duplicate the base already had: " (stringFromInt64 gC) " " mC))
        (assert (and (= gD 1) (stringContains? mD "#zero\"") (stringContains? mD "at lines 1 and 4")) (str "D: a second row for a symbol the base documented is red, with no source change in the unit: " (stringFromInt64 gD) " " mD))
        (assert (= gEw 1) (str "E: the duplicate is red in the writer's gate though the missing-row check could not run: " (stringFromInt64 gEw)))
        (assert (= gE 1) (str "E: and red, not gateInfra, in the plain gate: " (stringFromInt64 gE)))
        (assert (and (= gF 1) (stringContains? mF "asl/packages/asl-new/doc.asn") (stringContains? mF "#fresh\"")) (str "F: an untracked ledger with two rows of one symbol is red: " (stringFromInt64 gF) " " mF))
        true))
