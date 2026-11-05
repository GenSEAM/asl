(module asl-tools/coord/tests/tickReadsTest
  :x [runTests]
  :i [(asl-tools/coord/conductor :a cd) (asl-tools/coord/store :a st) (asl-tools/fleet/run :a fr) (asl-tools/coord/tests/fixtures/pipeFix :a pf)])

; (:m :ref COND-TICK-READS :do "a store read error is never an empty store: a corrupt conductor state row and an unreadable store directory each raise a lead-stream warn from the tick (deduped to one row with a count), the unreadable store shows in status! and is never settled even with no conductor rows, while a store directory that does not exist yet stays an empty settled store")
fn ctxOf dir: String -> cd/Ctx
  (cd/Ctx :dir dir :holder "tickReadsTest" :ttlMs 600000 :maxWait 0 :maxSame 3 :stageSec 60 :maxDesc 50
          :launch (fn [(stage String) (u st/Task) (c cd/CUnit)] -> (List String) (list "true")) :pace (cd/fixedPace 4 4))

fn leadText root: String -> String
  (resultOr (fileReadString (str root "/lead/stream.asn")) "")

fn countIn text: String needle: String -> Int64
  (- (listLength (stringSplit text needle)) 1)

fn ! runTests -> Bool
  (let [(root (pf/scratch "tickReads" "t"))
        (_ (pf/cleanup root))
        (dir (str root "/store"))
        (_ (st/put! dir (pf/unitIn "U1" "true")))
        (_ (st/put! dir (pf/unitIn "U2" "true")))
        (_ (cd/writeCUnit! dir (pf/cuIn "U1" "merged" "" "")))
        (_ (cd/writeCUnit! dir (pf/cuIn "U2" "merged" "" "")))
        (ctx (ctxOf dir))
        (clean (cd/surfaceReads! ctx))
        (leadClean (leadText root))
        (_ (fileWrite (cd/cuPath dir "U2") "(:cu :id \"U2\" :st merged :lane\n"))
        (_ (cd/tick! ctx))
        (leadOne (leadText root))
        (_ (fileWrite (cd/cuPath dir "U2") "(:cu :id \"U2\" :st merged :lane\n"))
        (_ (cd/surfaceReads! ctx))
        (leadRow (leadText root))
        (statusRow (cd/status! ctx))
        (_ (cd/writeCUnit! dir (pf/cuIn "U2" "merged" "" "")))
        (_ (pathRemove (str dir "/units")))
        (_ (fileWrite (str dir "/units") "not a directory"))
        (_ (pathRemove (cd/cuPath dir "U1")))
        (_ (pathRemove (cd/cuPath dir "U2")))
        (storeSettled (cd/settled? ctx))
        (storeStatus (cd/status! ctx))
        (storeRaised (cd/surfaceReads! ctx))
        (leadStore (leadText root))
        (fresh (ctxOf (str root "/never")))
        (freshSettled (cd/settled? fresh))
        (freshRaised (cd/surfaceReads! fresh))
        (_ (pf/cleanup root))]
    (do (assert (and (= clean 0) (stringEmpty? leadClean)) (str "control: healthy rows raise nothing: " (stringFromInt64 clean) " " leadClean))
        (assert (and (= (countIn leadOne "cuUnreadable") 1) (stringContains? leadOne "\"U2\"")) (str "one tick over a corrupt state row raises one cuUnreadable lead row for its unit: " leadOne))
        (assert (= (countIn leadRow "cuUnreadable") 1) (str "a repeat is still one row: " leadRow))
        (assert (stringContains? leadRow ":count 2") (str "the repeat bumped the count instead of adding a row: " leadRow))
        (assert (stringContains? statusRow ":id \"U2\" :st unreadable") (str "status! lists the unreadable row: " statusRow))
        (assert (not storeSettled) "an unreadable store is not settled even with no conductor rows")
        (assert (stringContains? storeStatus "(:store :unreadable") (str "status! names the unreadable store: " storeStatus))
        (assert (and (>= storeRaised 1) (stringContains? leadStore "storeUnreadable")) (str "the tick raises storeUnreadable: " leadStore))
        (assert (and freshSettled (= freshRaised 0)) "a store directory that does not exist yet is an empty settled store, not an error")
        true))
