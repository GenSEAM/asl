(module asl/tools/coord/tests/briefTest
  :x [runTests]
  :i [(asl-tools/coord/brief :a b)])

; (:m :ref COND-TASK-SPEC :do "the brief on fake owned states: a missing file is told to be created with one write and loses the size advice, an existing one gets its line count, module names derive from the path (asl-utils unit gives asl-utils/NAME, never asl-text), and no owned paths leaves the text alone")
fn testModules -> Bool
  (do (assert (= (b/moduleOfPath "asl/packages/asl-utils/src/textdiff.asl") "asl-utils/textdiff") "package src path")
      (assert (= (b/moduleOfPath "asl/tools/coord/throughput.asl") "asl-tools/coord/throughput") "tools path, not the module name as a path")
      (assert (= (b/moduleOfPath "tools/remote/nodeWatch.asl") "tools/remote/nodeWatch") "plain path")
      (assert (= (b/moduleOfPath "asl/tools/coord/tests/x.asn") "") "non asl has no module")
      true)

fn testBrief -> Bool
  (let [(task "Add the module.\nSMALL EDITS ONLY in large files.\nRun the gate.")
        (miss (b/briefFor task (list (pair "asl/packages/asl-utils/src/textdiff.asl" -1))))
        (have (b/briefFor task (list (pair "asl/tools/coord/risk.asl" 120))))
        (none (b/briefFor task (list)))]
    (do (assert (stringContains? miss "asl/packages/asl-utils/src/textdiff.asl: missing, create it with one write; module asl-utils/textdiff") (str "missing fact: " miss))
        (assert (not (stringContains? miss "SMALL EDITS ONLY")) "size advice dropped for a missing file")
        (assert (stringContains? miss "Run the gate.") "other task lines kept")
        (assert (stringContains? have "asl/tools/coord/risk.asl: exists (120 lines); module asl-tools/coord/risk") (str "existing fact: " have))
        (assert (stringContains? have "SMALL EDITS ONLY") "size advice kept when every owned file exists")
        (assert (= none task) "no owned paths leaves the text")
        true))
; (:m :ref BRIEF-OUTLINE-ANCHORS :do "fixture text of n definitions e0..e(n-1), ten lines each after a one line header: definition i spans lines 2+10i to 3+10i")
fn fixture n: Int64 -> String
  (str "(module fx :x [] :i [])\n"
       (stringJoin (map (fn [(i Int64)] -> String (str "fn e" (stringFromInt64 i) " -> Int64\n  " (stringFromInt64 i) "\n\n\n\n\n\n\n\n\n")) (range 0 n)) ""))

fn countOf s: String sub: String -> Int64
  (- (listLength (stringSplit s sub)) 1)

; (:m :ref BRIEF-OUTLINE-ANCHORS :do "a 352 line owned file gets exact names and ranges, a 100 line owned file gets none, no sources gives no block")
fn testOutlineBasic -> Bool
  (let [(big (b/outlineFor "do the work" (list (pair "pkg/big.asl" (fixture 35)))))
        (small (b/outlineFor "do the work" (list (pair "pkg/small.asl" (fixture 10)))))]
    (do (assert (stringContains? big "(:outline :file \"pkg/big.asl\" :lines 352 :defs ((:d e0 :from 2 :to 3) (:d e1 :from 12 :to 13)") (str "big head: " big))
        (assert (stringContains? big "(:d e34 :from 342 :to 343))") (str "big tail: " big))
        (assert (= (countOf big "(:d ") 35) "35 rows")
        (assert (not (stringContains? big "(:left")) "no cut row when nothing is cut")
        (assert (stringContains? big "(:instruction :do \"read these files by symbol") "instruction row")
        (assert (= small "") (str "100 line file gets nothing: " small))
        (assert (= (b/outlineFor "x" (list)) "") "no sources")
        true))

; (:m :ref BRIEF-OUTLINE-ANCHORS :do "caps: 80 rows per file with the exact left-out count, a definition named in the task first when cut, 200 rows per brief across files with the last file's cut stated")
fn testOutlineCaps -> Bool
  (let [(one (b/outlineFor "nothing relevant" (list (pair "a.asl" (fixture 134)))))
        (rank (b/outlineFor "fix e120 please" (list (pair "a.asl" (fixture 134)))))
        (three (b/outlineFor "nothing relevant" (list (pair "a.asl" (fixture 134)) (pair "b.asl" (fixture 134)) (pair "c.asl" (fixture 134)))))]
    (do (assert (= (countOf one "(:d ") 80) "80 rows per file")
        (assert (stringContains? one "(:d e79 :from 792 :to 793) (:left 54))") (str "cut and left count: " one))
        (assert (stringContains? rank ":defs ((:d e120 :from 1202 :to 1203) (:d e0 :from 2 :to 3)") (str "named definition first: " rank))
        (assert (stringContains? rank "(:left 54))") "ranked cut counted")
        (assert (not (stringContains? rank "(:d e133 ")) "unnamed tail dropped when cut")
        (assert (= (countOf three "(:d ") 200) "200 rows per brief")
        (assert (= (countOf three "(:left ") 3) "every file states its cut")
        (assert (stringContains? three "(:left 94))") (str "third file left count: " three))
        true))

; (:m :ref BRIEF-OUTLINE-ANCHORS :do "files the task names: an unowned existing long file gets an outline, a missing one is skipped, an owned one appears once, and building twice gives identical text")
fn testOutlineNamed -> Bool
  (let [(task "Read asl/tools/coord/trialAnalyze.asl, then asl/tools/coord/noSuchFile.asl and ../etc/x.asl.")
        (a (b/outlineFor! "." (list "asl/tools/coord/brief.asl" "asl/tools/coord/nope/") task))
        (c (b/outlineFor! "." (list "asl/tools/coord/brief.asl") task))]
    (do (assert (stringContains? a "(:outline :file \"asl/tools/coord/trialAnalyze.asl\" :lines ") (str "named file outlined: " a))
        (assert (not (stringContains? a "noSuchFile")) "missing named file skipped")
        (assert (not (stringContains? a "etc/x.asl")) "path escaping the worktree skipped")
        (assert (not (stringContains? a "coord/brief.asl")) "owned file of 300 lines or fewer gets none")
        (assert (= a c) "same text twice")
        (assert (= (b/namedPaths "see (a/b.asl), a/b.asl: and c/d.asn.") (list "a/b.asl" "c/d.asn")) "named paths deduped in order")
        true))

fn ! runTests -> Bool
  (do (assert (testModules) "module names derive from paths")
      (assert (testBrief) "owned states in the brief")
      (assert (testOutlineBasic) "outline of long owned files")
      (assert (testOutlineCaps) "outline caps and ranking")
      (assert (testOutlineNamed) "outline of named files")
      true)
