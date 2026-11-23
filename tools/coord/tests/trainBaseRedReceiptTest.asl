(module asl-tools/coord/tests/trainBaseRedReceiptTest
  :x [runTests]
  :i [(asl-tools/coord/conductor :a cd) (asl-tools/fleet/run :a fr) (asl-tools/coord/tests/fixtures/pipeFix :a pf)])

; (:m :ref TRAIN-BASERED-LIST :do "a kept train attempt whose output carries a (:trainBaseRed ...) row leaves it whole at runs/UNIT-baseRed.asn and as one journal row, longer than the 200-char verdict that lost the list on node2; the next train with a receipt and no base red removes the file")

fn longRow -> String
  (str "(:trainBaseRed :onto \"abc\" :merged \"def\" :branches (\"sh/T1\" \"sh/T2\") :holds 0 :suites ("
       "(:suite \"asl/packages/asl-target-llvm/tests/mapReuseTest.asl\" :kind suite :exit 124 :executed 0 :ms 473000 :limitS 1800 :timedOut true :touched false :knownRed false :holds false) "
       "(:suite \"asl/tools/coord/tests/trialSetupTest.asl\" :kind suite :exit 1 :executed 3 :ms 243000 :limitS 1800 :timedOut false :touched false :knownRed false :holds false) "
       "(:suite \"asl/packages/asl-target-llvm/tests/lowerScaleTest.asl\" :kind suite :exit 1 :executed 7 :ms 31000 :limitS 1800 :timedOut false :touched false :knownRed false :holds false)))")

fn receipt -> String
  "(:train :head \"abc\" :merged \"def\" :branches (\"sh/T1\") :red () :preexisting () :assertLoss () :knownRed () :baseRedOutside () :blocked (:fresh 0 :preexisting 0) :seconds 1)"

fn ! done out: String -> fr/Done
  (fr/Done :idx 0 :exit 0 :out out :ms 5 :verdict "")

; (:m :ref TRAIN-BASERED-LIST :do "main health: a suite let through as outside is confirmed alone once per head; red alone upserts one keyed mainRed row, green alone is load with no row")
fn ! testMainRed store: String -> Bool
  (let [(out (str "(:trainBaseRed :onto \"h1\" :merged \"m\" :branches (\"sh/T1\") :holds 1 :suites ((:suite \"a/aTest.asl\" :kind suite :exit 1 :executed 2 :ms 9 :limitS 1800 :timedOut false :touched false :knownRed false :holds false) (:suite \"b/bTest.asl\" :kind suite :exit 1 :executed 2 :ms 9 :limitS 1800 :timedOut false :touched true :knownRed false :holds true) (:suite \"c/cTest.asl\" :kind suite :exit 1 :executed 2 :ms 9 :limitS 1800 :timedOut false :touched false :knownRed true :holds false)))\n"))
        (o (cd/outsideOf out))
        (red (fn [(p String)] -> Bool false))
        (green (fn [(p String)] -> Bool true))
        (n1 (cd/mainRedNote! store "h1" (list "a/aTest.asl") red))
        (n2 (cd/mainRedNote! store "h1" (list "a/aTest.asl") red))
        (n3 (cd/mainRedNote! store "h2" (list "a/aTest.asl") red))
        (n4 (cd/mainRedNote! store "h2" (list "d/dTest.asl") green))
        (n5 (cd/mainRedNote! store "h2" (list "d/dTest.asl") red))
        (rows (filter (fn [(l String)] -> Bool (not (stringEmpty? l))) (stringLines (resultOr (fileReadString (cd/mainRedPath store)) ""))))
        (journal (pf/journalLines store))]
    (do (assert (and (= (pairFirst o) "h1") (= (pairSecond o) (list "a/aTest.asl"))) (str "only the untouched, unlisted suite is outside, with the head: " (pairFirst o) " " (stringJoin (pairSecond o) ",")))
        (assert (and (= n1 1) (= n2 0)) "red alone on h1 writes the row once; the same head is not confirmed again")
        (assert (= n3 1) "a new head counts again")
        (assert (and (= (listLength rows) 1) (stringStartsWith? (optionOr (listHead rows) "") "(:mainRed :suite \"a/aTest.asl\" :firstSha \"h1\" :lastSha \"h2\" :count 2 :at ")) (str "one keyed row per suite, first and last head and the count: " (stringJoin rows "|")))
        (assert (and (= n4 0) (= n5 0)) "green alone is load: no row, and that head is not confirmed again")
        (assert (= (listLength (filter (fn [(l String)] -> Bool (stringStartsWith? l "(:mainRedLoad :suite \"d/dTest.asl\" :onto \"h2\" ")) journal)) 1) "one load journal row")
        (assert (= (listLength (filter (fn [(l String)] -> Bool (stringStartsWith? l "(:mainRed :suite \"a/aTest.asl\" ")) journal)) 2) "each upsert is journalled")
        true))

fn ! runTests -> Bool
  (let [(root (pf/scratch "trainBaseRedReceipt" "w"))
        (_ (pf/cleanup root))
        (made (pf/sh (str "mkdir -p " root "/repo " root "/store && echo madeOk")))
        (store (str root "/store"))
        (rc (cd/realCfg (list "--repo" (str root "/repo") "--worktrees" (str root "/wts") "--home" (str root "/home")) store))
        (path (cd/runPath store "T1" "baseRed" "asn"))
        (k1 (cd/keepTrain! rc store "T1" "sh/T1 sh/T2" (done (str "line\n" (longRow) "\n" (receipt) "\n")) ""))
        (kept (resultOr (fileReadString path) ""))
        (rows (filter (fn [(l String)] -> Bool (stringStartsWith? l "(:trainBaseRed :unit \"T1\" ")) (pf/journalLines store)))
        (k2 (cd/keepTrain! rc store "T1" "sh/T1" (done "killed before the receipt\n") ""))
        (afterKill (fileExists? path))
        (k3 (cd/keepTrain! rc store "T1" "sh/T1" (done (str (receipt) "\n")) ""))
        (afterGreen (fileExists? path))
        (mainRed (testMainRed store))
        (_ (pf/cleanup root))]
    (do (assert (stringContains? made "madeOk") "fixture store")
        (assert (and (not (stringEmpty? k1)) (and (not (stringEmpty? k2)) (not (stringEmpty? k3)))) "three attempts kept")
        (assert (= kept (str (longRow) "\n")) (str "the receipt keeps the whole base-red row: " kept))
        (assert (> (stringLength kept) 400) "longer than the clipped verdict")
        (assert (= (listLength rows) 1) (str "one journal row per base-red train: " (stringJoin rows "|")))
        (assert (stringContains? (optionOr (listHead rows) "") "lowerScaleTest.asl\" :kind suite :exit 1 :executed 7 :ms 31000") (str "the journal row is whole too: " (optionOr (listHead rows) "")))
        (assert afterKill "a killed train (no receipt) leaves the last base-red receipt")
        (refute afterGreen "a train whose receipt names no base red removes it")
        (assert mainRed "main health ledger")
        true))
