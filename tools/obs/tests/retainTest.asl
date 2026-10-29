(module ws/asl/tools/obs/tests/retainTest
  :x [runTests]
  :i [(ws/asl/tools/obs/retain :a rt)
      (ws/asl/tools/obs/archive :a ar)
      (ws/asl/tools/obs/corpus :a co)
      (ws/asl/tools/obs/obs :a ob)])

fn readText p: String -> String
  (resultOr (fileReadString p) "")

fn fx name: String -> String
  (readText (str "asl/tools/obs/tests/fixtures/" name))

fn nowMs -> Int64
  1792966872999

fn oldSec -> Int64
  1768000000

fn newSec -> Int64
  1792900000

fn oldRow -> String
  "(:call :at 1768000000000 :profile \"p\" :intent \"auto\" :alias \"routeA\" :provider \"provA\" :model \"vendor/model-a\" :in 10 :cached 0 :out 5 :ttftMs absent :ms 100 :outcome \"ok\" :charge 0 :tag absent :temperature 0.2 :topP absent :maxTokens 32768 :effort absent :api \"chat\" :stream false :toolCount 0 :promptBytes 9 :sysHash \"aaaa000000000001\")"

fn newRow -> String
  "(:call :at 1792900000000 :profile \"p\" :intent \"auto\" :alias \"routeA\" :provider \"provA\" :model \"vendor/model-a\" :in 20 :cached 0 :out 6 :ttftMs absent :ms 200 :outcome \"429\" :charge 0 :tag absent :temperature 0.2 :topP absent :maxTokens 32768 :effort absent :api \"chat\" :stream false :toolCount 0 :promptBytes 9 :sysHash \"aaaa000000000001\")"

; (:m :do "builds a scratch home and workspace: old and new journal, old and new obs day file, a ledger with one old and one new row, old harness and trainlog files; returns the base dir")
fn ! rig! tag: String -> String
  (let [(base (str "/tmp/retainTest-" tag "-" (stringFromInt64 (procSelf)) "-" (stringFromInt64 (nowNs))))
        (ws (str base "/ws"))
        (home (str base "/home"))
        (run (str home "/.asl/run"))
        (dirs (list (str ws "/.asl/run/agentLoop") (str ws "/asl/tools/obs") (str run "/usage") (str run "/obs") (str run "/harness/r1") (str run "/trainlogs")))
        (_m (map co/mkdirs! dirs))
        (_1 (fileWrite (str ws "/.asl/run/agentLoop/old.journal") (fx "journal.fixture.asn")))
        (_2 (fileWrite (str ws "/.asl/run/agentLoop/new.journal") (fx "journalOk.fixture.asn")))
        (_3 (fileUtime (str ws "/.asl/run/agentLoop/old.journal") (* (oldSec) 1000000000)))
        (_4 (fileUtime (str ws "/.asl/run/agentLoop/new.journal") (* (newSec) 1000000000)))
        (_5 (fileWrite (str run "/obs/2026-01-05.asn") "(:obs :id \"0000000000000001\" :at 1)\n"))
        (_6 (fileWrite (str run "/obs/2026-10-24.asn") "(:obs :id \"0000000000000002\" :at 2)\n"))
        (_7 (fileWrite (str run "/usage/gatewayCalls.asn") (str (oldRow) "\n" (newRow) "\n")))
        (_8 (fileWrite (str run "/harness/r1/note.md") "old receipt note\n"))
        (_9 (fileUtime (str run "/harness/r1/note.md") (* (oldSec) 1000000000)))
        (_a (fileWrite (str run "/trainlogs/b.log") "new train log\n"))
        (_b (fileUtime (str run "/trainlogs/b.log") (* (newSec) 1000000000)))
        (_c (fileWrite (str ws "/asl/tools/obs/failClasses.asn") (readText "asl/tools/obs/failClasses.asn")))]
    base)

fn testPlanAndApply -> Bool
  (let [(base (rig! "a"))
        (ws (str base "/ws"))
        (home (str base "/home"))
        (original (fx "journal.fixture.asn"))
        (p1 (rt/plan! home ws 14 (nowMs)))
        (p2 (rt/plan! home ws 14 (nowMs)))
        (res (rt/apply! home ws 14 (nowMs) false))
        (idx (ar/readIndex! home))
        (jm (listFind (fn [(m ar/Member)] -> Bool (= m.source "leon")) idx))
        (text (match jm ((some m) (resultOr (ar/extractText! home m) "")) ((none) "no member")))
        (ledger (readText (str home "/.asl/run/usage/gatewayCalls.asn")))
        (p3 (rt/plan! home ws 14 (nowMs)))
        (back (co/collectArchive! ws home "mac" (str base "/restored") "2026-01"))
        (arc (str home "/.asl/run/archive/2026-01.tar.gz"))
        (arcSize (co/sizeOf arc))
        (_z (pathRemove base))]
    (do (assert (= p1 p2) "the plan is identical on the same tree")
        (assert (stringContains? p1 ":items 4") "plan lists old journal, old obs day, old ledger month, old harness file")
        (assert (not (stringContains? p1 "new.journal")) "a new journal is not planned")
        (assert (not (stringContains? p1 "2026-10-24.asn")) "a new obs day file is not planned")
        (assert (not (stringContains? p1 "trainlogs/b.log")) "a new trainlog is not planned")
        (assert (stringContains? res ":removed 4 :unverified 0 :changed 0") "apply removes every packed original after verification")
        (assert (= (listLength idx) 4) "one index row per member")
        (assert (= text original) "a member reads back byte-identical through the index")
        (assert (stringContains? ledger "\"routeA\"") "the ledger keeps its tail")
        (assert (and (stringContains? ledger ":at 1792900000000") (not (stringContains? ledger ":at 1768000000000"))) "ledger keeps the new row and drops the old one")
        (assert (stringContains? p3 ":items 0") "after apply nothing old is left to plan")
        (assert (> arcSize 0) "the month archive exists")
        (assert (stringContains? back ":members 2") "collect reads the archived month: journal and ledger rows")
        (assert (not (stringContains? back ":rows 0")) "archived month yields observations")
        true))

fn testCorruptAborts -> Bool
  (let [(base (rig! "b"))
        (ws (str base "/ws"))
        (home (str base "/home"))
        (cutoff (- (nowMs) (* 14 86400000)))
        (jpath (str ws "/.asl/run/agentLoop/old.journal"))
        (item (rt/Item :source "leon" :path jpath :kind "file" :month "2026-01" :from "2026-01-09" :to "2026-01-09" :bytes (co/sizeOf jpath) :mt (co/mtimeMs jpath) :size (co/sizeOf jpath)))
        (_d (co/mkdirs! (ar/archiveDir home)))
        (packed (rt/packItem! home item cutoff))
        (arc (str (ar/archiveDir home) "/2026-01.tar.gz"))
        (_c (fileWrite arc "this is not a gzip stream"))
        (verdict (match packed ((ok m) (rt/removeVerified! home item m cutoff)) ((err e) (str "packError " e))))
        (still (fileExists? jpath))
        (_z (pathRemove base))]
    (do (assert (= verdict "unverified") "a corrupted member is reported unverified")
        (assert still "a corrupted member never deletes the original")
        true))

fn testChangedFileKept -> Bool
  (let [(base (rig! "c"))
        (ws (str base "/ws"))
        (home (str base "/home"))
        (cutoff (- (nowMs) (* 14 86400000)))
        (jpath (str ws "/.asl/run/agentLoop/old.journal"))
        (item (rt/Item :source "leon" :path jpath :kind "file" :month "2026-01" :from "2026-01-09" :to "2026-01-09" :bytes (co/sizeOf jpath) :mt (co/mtimeMs jpath) :size (co/sizeOf jpath)))
        (_d (co/mkdirs! (ar/archiveDir home)))
        (packed (rt/packItem! home item cutoff))
        (_a (fileAppend jpath "(:turn 99 :late true)\n"))
        (verdict (match packed ((ok m) (rt/removeVerified! home item m cutoff)) ((err e) (str "packError " e))))
        (_z (pathRemove base))]
    (do (assert (= verdict "changed") "a source that grew after planning is kept")
        true))

fn textAt h: Bytes at: Int64 len: Int64 -> String
  (stringJoin (map (fn [(i Int64)] -> String (stringFromInt64 (bytesGet h (+ at i)))) (range 0 len)) ",")

fn asBytesText t: String -> String
  (let [(b (stringToBytes t))]
    (stringJoin (map (fn [(i Int64)] -> String (stringFromInt64 (bytesGet b i))) (range 0 (bytesLength b))) ","))

fn testHeader -> Bool
  (let [(h (ar/tarHeader "leon/x" 1500000 1768000000))
        (sum (listSum (map (fn [(i Int64)] -> Int64 (if (and (>= i 148) (< i 156)) 32 (bytesGet h i))) (range 0 512))))]
    (do (assert (= (textAt h 124 11) (asBytesText "00005561540")) "size field is the octal size, most significant digit first")
        (assert (= (textAt h 257 5) (asBytesText "ustar")) "ustar magic")
        (assert (= (textAt h 148 6) (asBytesText (str (if (< sum 8) "00000" (if (< sum 64) "0000" (if (< sum 512) "000" (if (< sum 4096) "00" (if (< sum 32768) "0" ""))))) (ar/octalText sum)))) "checksum field matches the block sum")
        true))

fn runTests -> Bool
  (and (testHeader) (and (testPlanAndApply) (and (testCorruptAborts) (testChangedFileKept))))
