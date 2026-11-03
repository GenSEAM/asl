(module asl-gates/tests/auditLandedTest
  :x [runTests]
  :i [(asl-gates/auditLanded :a al) (asl-gates/auditGates :a ag) (asl-proc/gitFixture :a gf)])

; (:m :ref LANDED-AUDIT :do "pure: ev ids, newest verdict wins, exemptions, the per-commit decision, log parsing, the date; then a git fixture under the test's scratch dir: a graded commit and a wip commit pass, an ungraded one fails the audit with exit 1 and passes once its pass row is in the ledger; no checkpoint fails")
fn commit sha: String parents: Int64 msg: String files: (List String) -> al/Commit
  (al/Commit :sha sha :parents parents :msg msg :files files)

fn ledgerText -> String
  (str "(:gradesHead :since \"abc\")\n"
       "(:grade :ev \"X1\" :sha \"r1\" :verdict pass :by \"google\" :at \"2026-11-02T00:00:00Z\")\n"
       "(:grade :ev \"X2\" :sha \"r2\" :verdict pass :by \"google\" :at \"2026-11-02T00:00:00Z\")\n"
       "(:grade :ev \"X2\" :sha \"r2\" :verdict fixNeeded :by \"anthropic\" :at \"2026-11-02T01:00:00Z\")\n"
       "(:grade :ev \"X5\" :sha \"r5\" :verdict pass :by \"google\" :at \"2026-11-02T02:00:00Z\")\n")

; (:m :ref LANDED-AUDIT :do "fake ancestry: a candidate is covered by a row sha only when the pair is listed")
fn covers cand: String row: String base: String -> Bool
  (listContains? (list "c1>r1" "c8>r1" "c2>r2" "p9>r5" "src>r5") (str cand ">" row))

fn realMessage -> String
  "(:c :a coord :do \"W1b-FIX: gradeLand! rebuilds the ledger from the committed HEAD version plus its one row, never the worktree file; a writer commit touching .asl/mem/grades.asn (anything but the conductor grade commit) fails the write result and a review pass as LEDGER_FORGED; audit landed covers a commit only by sha (a pass row whose reviewed head is that commit or a descendant, or a source named by cherry-pick -x), so a later reuse of a passed id is ungraded; evIds reads :ev from the commit message parsed as an ASN form; wip commits on main are findings; servedField reads the final receipt row (last (: line with :usage) parsed as a form\" :g \"auditLandedTest 46, conductorTest 314, conductorWireTest 110, worktreeTest 119, gradeTest 32, auditGatesTest 50, manifestGateTest 20, docLedgerTest 68, noSelfHostTest 18 exit 0; red before: worktree-file ledger read, ledger guard removed, first-row receipt read and covers-always-true each fail their assert; check exit 0\" :ev (W1b-FIX))"

fn ! testPure -> Bool
  (let [(cs (list (commit "c1" 1 "(:c :a x :do \"d\" :g \"g\" :ev (X1 Z9))" (list "a.asl"))
                  (commit "c2" 1 "(:c :a x :do \"d\" :ev (X2))" (list "a.asl"))
                  (commit "c3" 1 "(:c :a x :do \"d\" :ev (X3))" (list "a.asl"))
                  (commit "c4" 1 "just words" (list "a.asl"))
                  (commit "c5" 2 "Merge branch" (list))
                  (commit "c6" 1 "(:c :a wip :do \"unit U stopped: x\" :g none :ev (U))" (list "a.asl"))
                  (commit "c7" 1 "(:c :a grade :do \"g\" :g review :ev (X9))" (list ".asl/mem/grades.asn"))
                  (commit "c8" 1 "(:c :a x :do \"d\" :ev X1)" (list "b.asl"))
                  (commit "c9" 1 "(:c :a x :do \"d\" :ev (X3))" (list ".asl/mem/grades.asn" "b.asl"))
                  (commit "c10" 1 "(:c :a x :do \"reuse\" :ev (X1))" (list "b.asl"))
                  (commit "c11" 1 "(:c :a x :do \"picked\" :ev (X5))\n\n(cherry picked from commit src)" (list "b.asl"))
                  (commit "c12" 1 "(:c :a x :do \"picked blind\" :ev (X5))" (list "b.asl"))))
        (checks (al/landedChecks cs (ledgerText) covers))
        (ids (map (fn [(c ag/Check)] -> String c.id) checks))]
    (do (assert (= (al/evIds "(:c :a x :ev (A B-1 \"C\") :g y)") (list "A" "B-1" "C")) "a parenthesised list")
        (assert (= (al/evIds "(:c :a x :ev \"coordTouched?\")") (list "coordTouched?")) "a quoted word")
        (assert (= (al/evIds "(:c :a x :ev ID1)") (list "ID1")) "a bare word")
        (assert (= (al/evIds "no evidence here") (list)) "no :ev, no ids")
        (assert (= (al/evIds "(:c :a x :do \"note :ev (FAKE) in text\" :ev (REAL))") (list "REAL")) (str "an :ev inside a string never counts: " (stringJoin (al/evIds "(:c :a x :do \"note :ev (FAKE) in text\" :ev (REAL))") ",")))
        (assert (= (al/evIds "(:c :a x :do \"note :ev (FAKE) in text\")") (list)) "and without a real :ev there are none")
        (assert (= (al/evIds "(:c :a x :do \"d\" :ev (X1)") (list "X1")) "an unterminated form still reads its own :ev through the tolerant scan")
        (assert (= (al/evIds (realMessage)) (list "W1b-FIX")) "the real message of 3bea93623, which the ASN reader refuses, yields its :ev")
        (assert (= (al/evIds "(:c :a x :do \"fake :ev (EVIL) here\" :ev (Wb-FIX))") (list "Wb-FIX")) "a refused symbol still never reads an :ev inside a string")
        (assert (= (al/evIds "(:c :a x :do \"fake :ev (EVIL) here\" :g y)") (list)) "and without its own :ev there is none")
        (assert (= (al/stripStrings "a \"b \\\" c\" d") "a   d") "strings with escapes are dropped")
        (assert (= (al/fromShas "(:c :a x)\n\n(cherry picked from commit abc123)") (list "abc123")) "cherry-pick -x sources")
        (assert (= (al/headSince (ledgerText)) "abc") "the head row names the checkpoint")
        (assert (= (al/headSince "") "") "no head row, no checkpoint")
        (assert (= (listLength (al/gradeRows (ledgerText))) 4) "four verdict rows")
        (assert (= (al/exemptKind (commit "m" 2 "x" (list "a"))) "merge") "a merge commit is exempt")
        (assert (= (al/exemptKind (commit "w" 1 "(:c :a wip :do \"x\")" (list "a"))) "") "a wip commit is not exempt on main")
        (assert (= (al/exemptKind (commit "l" 1 "x" (list ".asl/mem/grades.asn"))) "ledger") "a ledger-only commit is exempt")
        (assert (= (al/exemptKind (commit "n" 1 "x" (list ".asl/mem/grades.asn" "a.asl"))) "") "a ledger edit plus code is not")
        (assert (= (al/exemptKind (commit "e" 1 "x" (list))) "") "an empty file list is not ledger-only")
        (assert (= ids (list "ungraded-c2" "ungraded-c3" "ungraded-c4" "ungraded-c6" "ungraded-c9" "ungraded-c10" "ungraded-c12")) (str "ungraded commits: " (stringJoin ids ",")))
        (assert (= (map (fn [(c ag/Check)] -> String c.err) checks) (list "ERR_UNGRADED" "ERR_UNGRADED" "ERR_NO_EV" "ERR_WIP_ON_MAIN" "ERR_UNGRADED" "ERR_UNGRADED" "ERR_UNGRADED")) "no :ev and wip are told apart")
        (assert (not (listContains? ids "ungraded-c1")) "c1 is covered by the pass row of its reviewed head")
        (assert (not (listContains? ids "ungraded-c8")) "c8 is covered by the same head")
        (assert (listContains? ids "ungraded-c2") "a later fixNeeded row for the covering head ungrades c2")
        (assert (listContains? ids "ungraded-c10") "a later commit reusing a passed id is not covered by an old head")
        (assert (not (listContains? ids "ungraded-c11")) "a cherry-pick -x is covered through its source")
        (assert (listContains? ids "ungraded-c12") "a blind cherry-pick is not")
        (assert (= (map (fn [(c ag/Check)] -> String c.status) (al/landedChecks (list (commit "c1" 1 "(:c :ev (X1))" (list "a"))) (ledgerText) covers)) (list ":passed")) "all graded passes")
        (assert (= (al/isoOfMs 0) "1970-01-01T00:00:00Z") "epoch")
        (assert (= (al/isoOfMs 951782400000) "2000-02-29T00:00:00Z") "a leap day")
        (assert (= (al/isoOfMs 1793577600000) "2026-11-02T00:00:00Z") "today")
        (assert (= (al/isoOfMs 1793577600000) (al/isoOfMs 1793577600999)) "milliseconds are dropped")
        (assert (= (al/gradeRow "U1" "abc" "" "pass" "google" "2026-11-02T00:00:00Z") "(:grade :ev \"U1\" :sha \"abc\" :verdict pass :by \"google\" :at \"2026-11-02T00:00:00Z\")") "row text")
        true))

fn ! parseTest -> Bool
  (let [(out (str "@@C@@aaa@@@@one :ev (X1)@@F@@\n\na.asl\nb.asl\n@@C@@bbb@@aaa ccc@@merge@@F@@\n\n@@C@@ddd@@bbb@@two\nbody@@F@@\n\n.asl/mem/grades.asn\n"))
        (cs (al/parseLog out))]
    (do (assert (= (map (fn [(c al/Commit)] -> String c.sha) cs) (list "ddd" "bbb" "aaa")) "the fold reverses git order, so oldest first for real log output")
        (assert (= (map (fn [(c al/Commit)] -> Int64 c.parents) cs) (list 1 2 0)) "parent counts")
        (assert (= (map (fn [(c al/Commit)] -> (List String) c.files) cs) (list (list ".asl/mem/grades.asn") (list) (list "a.asl" "b.asl"))) "files per commit")
        (assert (stringContains? (optionOr (listHead cs) (commit "" 0 "" (list))).msg "body") "a multi-line message is kept")
        true))

fn ! g dir: String args: (List String) -> Bool
  (ok? (gf/gitWrite! dir (listAppend (list "-c" "user.name=t" "-c" "user.email=t@example.invalid" "-c" "commit.gpgsign=false") args) (none)))

fn ! put dir: String name: String text: String -> Bool
  (match (fileWrite (str dir "/" name) text) ((ok _) true) ((err _) false))

fn ! step dir: String name: String text: String msg: String -> Bool
  (and (put dir name text) (and (g dir (list "add" "-A")) (g dir (list "commit" "-q" "-m" msg))))

fn ! revOf dir: String -> String
  (match (ag/git! dir (list "rev-parse" "HEAD")) ((ok s) s) ((err _) ""))

fn ! gitTest -> Bool
  (let [(root (str (resultOr (realPath ".") ".") "/.asl/cache/auditLandedTest-" (stringFromInt64 (procSelf))))
        (_ (pathRemove root))
        (_ (dirCreate root))
        (ok0 (and (ok? (gf/initContained! root)) (step root "a.txt" "1\n" "base")))
        (base (revOf root))
        (_ (dirCreate (str root "/.asl")))
        (_ (dirCreate (str root "/.asl/mem")))
        (okA (step root "a.txt" "2\n" "(:c :a x :do \"first\" :g g :ev (X1))"))
        (shaA (revOf root))
        (okL (step root ".asl/mem/grades.asn" (str "(:gradesHead :since \"" base "\")\n" (al/gradeRow "X1" shaA "" "pass" "google" "2026-11-02T00:00:00Z") "\n") "(:c :a grade :do \"g\" :g review :ev (X1))"))
        (okB (step root "a.txt" "3\n" "(:c :a x :do \"second\" :g g :ev (X2))"))
        (shaB (revOf root))
        (red (al/cmdLanded! root (list)))
        (redSince (al/cmdLanded! root (list "--since" base)))
        (okR (step root ".asl/mem/grades.asn" (str "(:gradesHead :since \"" base "\")\n" (al/gradeRow "X1" shaA "" "pass" "google" "2026-11-02T00:00:00Z") "\n" (al/gradeRow "X2" shaB "" "pass" "anthropic" "2026-11-02T00:01:00Z") "\n") "(:c :a grade :do \"g\" :g review :ev (X2))"))
        (green (al/cmdLanded! root (list)))
        (okC (step root "a.txt" "4\n" "(:c :a x :do \"reuse of a passed id\" :g g :ev (X1))"))
        (reuse (al/cmdLanded! root (list)))
        (okW (step root "a.txt" "5\n" "(:c :a wip :do \"unit U stopped: x\" :g none :ev (X2))"))
        (wipOnMain (al/cmdLanded! root (list)))
        (okN (put root ".asl/mem/grades.asn" "(:grade :ev \"X1\" :sha \"s\" :verdict pass :by \"g\" :at \"t\")\n"))
        (none (al/cmdLanded! root (list)))
        (_ (pathRemove root))]
    (do (assert (and ok0 (and okA (and okL (and okB okR)))) "fixture history built")
        (assert (= red.exitCode 1) (str "an ungraded commit fails the audit: " red.receipt))
        (assert (and (stringContains? red.receipt "ungraded-") (not (stringContains? red.receipt "ERR_NO_EV")) (stringContains? red.receipt ":since")) "named, with its checkpoint")
        (assert (= redSince.exitCode 1) "--since works too")
        (assert (= green.exitCode 0) (str "the pass row of the reviewed head makes it green: " green.receipt))
        (assert (stringContains? green.receipt ":n 2") (str "the ledger commits are not audited: " green.receipt))
        (assert (and okC (= reuse.exitCode 1) (stringContains? reuse.receipt "ERR_UNGRADED")) (str "a later commit reusing a passed id is not covered: " reuse.receipt))
        (assert (and okW (= wipOnMain.exitCode 1) (stringContains? wipOnMain.receipt "ERR_WIP_ON_MAIN")) "a wip commit on main is a finding")
        (assert (and okN (= none.exitCode 1) (stringContains? none.receipt "ERR_NO_CHECKPOINT")) "no checkpoint is a failure, never a guess")
        true))

fn ! baseTest -> Bool
  (let [(root (str (resultOr (realPath ".") ".") "/.asl/cache/auditLandedBase-" (stringFromInt64 (procSelf))))
        (_ (pathRemove root))
        (_ (dirCreate root))
        (ok0 (and (ok? (gf/initContained! root)) (step root "a.txt" "1\n" "base")))
        (base (revOf root))
        (_ (dirCreate (str root "/.asl")))
        (_ (dirCreate (str root "/.asl/mem")))
        (okO (step root "a.txt" "2\n" "(:c :a x :do \"old main commit\" :g g :ev (X7))"))
        (shaOld (revOf root))
        (okK (step root "a.txt" "3\n" "(:c :a x :do \"reviewed branch commit\" :g g :ev (X7))"))
        (shaK (revOf root))
        (okL (step root ".asl/mem/grades.asn" (str "(:gradesHead :since \"" base "\")\n" (al/gradeRow "X7" shaK shaOld "pass" "google" "2026-11-02T00:00:00Z") "\n") "(:c :a grade :do \"g\" :g review :ev (X7))"))
        (withBase (al/cmdLanded! root (list)))
        (okR (step root ".asl/mem/grades.asn" (str "(:gradesHead :since \"" base "\")\n" (al/gradeRow "X7" shaK "" "pass" "google" "2026-11-02T00:00:00Z") "\n") "(:c :a grade :do \"g2\" :g review :ev (X7))"))
        (noBase (al/cmdLanded! root (list)))
        (_ (pathRemove root))]
    (do (assert (and ok0 (and okO (and okK (and okL okR)))) "base fixture history built")
        (assert (and (= withBase.exitCode 1) (stringContains? withBase.receipt (str "ungraded-" (optionOr (stringSlice shaOld 0 9) shaOld)))) (str "an older commit citing the id, below the row's base, is not covered: " withBase.receipt))
        (assert (not (stringContains? withBase.receipt (str "ungraded-" (optionOr (stringSlice shaK 0 9) shaK)))) "the reviewed branch commit itself is covered")
        (assert (= noBase.exitCode 0) (str "an old row without :base covers by ancestry as before: " noBase.receipt))
        (assert (= (al/gradeRow "U1" "abc" "b0" "pass" "google" "t") "(:grade :ev \"U1\" :sha \"abc\" :base \"b0\" :verdict pass :by \"google\" :at \"t\")") "the row records its base")
        true))

fn ! runTests -> Bool
  (do (assert (testPure) "pure rules")
      (assert (parseTest) "log parsing")
      (assert (gitTest) "git fixture")
      (assert (baseTest) "base fixture")
      true)
