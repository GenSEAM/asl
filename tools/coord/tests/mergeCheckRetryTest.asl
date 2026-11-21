(module asl-tools/coord/tests/mergeCheckRetryTest
  :x [runTests]
  :i [(asl-tools/coord/conductor :a cd) (asl-tools/coord/store :a st) (asl-tools/coord/tests/fixtures/pipeFix :a pf)])

; (:m :ref MERGECHECK-HOLD-TIMEOUT :do "a merge check cut off by timeouts or deadlines only is unverified, retry once per head: the unit stays merging with a (:retry) journal row and no failure count, the second timeout at the same head holds it blocked, a new head or a non-timeout unverified step behaves as named, and the conductor's check asks for --reuse-head")
fn timeoutReceipt head: String items: String -> String
  (str "(:mergeCheck :verdict unverified :mode cheap :base \"b0\" :head \"" head "\" :headCheckout true :unverified (" items ") :planRows ())")

fn resOf verdict: String sig: String -> cd/Res
  (cd/Res :ok 0 :wt "" :branch "" :model "" :tokens 0 :costMicro 0 :claimedGreen 0 :sig sig :ms 0 :exit 1 :asserts 0 :verdict verdict :tiers "")

fn vOf r: (Option cd/Res) -> String
  (match r ((some x) x.verdict) ((none) "none"))

fn ! journalOf root: String -> String
  (resultOr (fileReadString (cd/journalPath (str root "/store"))) "")

fn ! runTests -> Bool
  (let [(root (pf/scratch "mcRetry" "w"))
        (_ (pf/cleanup root))
        (store (str root "/store"))
        (u (pf/unitIn "R1" "sh check.sh impl.txt"))
        (_ (st/put! store u))
        (_ (cd/writeCUnit! store (pf/cuIn "R1" "merging" "" "sh/R1")))
        (tmo "\"consistencyHead:timeout consistency\" \"gatesHead:deadline\"")
        (r1 (cd/mergeVerdictRes! store u (pair 3 (timeoutReceipt "h1" tmo))))
        (r2 (cd/mergeVerdictRes! store u (pair 3 (timeoutReceipt "h1" tmo))))
        (r3 (cd/mergeVerdictRes! store u (pair 3 (timeoutReceipt "h2" tmo))))
        (rNo (cd/mergeVerdictRes! store u (pair 3 (timeoutReceipt "h3" "\"noMergeBase\""))))
        (rMix (cd/mergeVerdictRes! store u (pair 3 (timeoutReceipt "h4" "\"gatesHead:deadline\" \"suite:x.asl:unverified\""))))
        (rEx2 (cd/mergeVerdictRes! store u (pair 2 "(:mergeCheck :verdict block :error \"cannot check out base and head\")")))
        (journal (journalOf root))
        (retries (listLength (filter (fn [(l String)] -> Bool (stringStartsWith? l "(:retry :unit \"R1\"")) (stringLines journal))))
        (ctx (cd/Ctx :dir store :holder "mcRetry" :ttlMs 3600000 :maxWait 5 :maxSame 3 :stageSec 60 :maxDesc 50
                     :launch (fn [(stage String) (x st/Task) (c cd/CUnit)] -> (List String) (list "/usr/bin/true")) :pace (cd/fixedPace 4 4)))
        (c0 (optionOr (listFind (fn [(x cd/CUnit)] -> Bool (= x.id "R1")) (cd/readCUnits! store)) (pf/cuIn "R1" "absent" "" "")))
        (_ (cd/finish! ctx u c0 (optionOr r1 (resOf "none" "none"))))
        (afterRetry (optionOr (listFind (fn [(x cd/CUnit)] -> Bool (= x.id "R1")) (cd/readCUnits! store)) (pf/cuIn "R1" "absent" "" "")))
        (markerKept (fileExists? (cd/mergeRetryPath store "R1")))
        (longTmo (str (stringJoin (map (fn [(k Int64)] -> String "\"consistencyHead:timeout consistency\"") (range 0 12)) " ") " \"suite:t.asl:unverified\""))
        (rLong (cd/mergeVerdictRes! store u (pair 3 (timeoutReceipt "h5" longTmo))))
        (rSub (cd/mergeVerdictRes! store u (pair 3 (timeoutReceipt "h6" "\"suite:timeoutTest.asl:unverified\""))))
        (rHold (cd/mergeVerdictRes! store u (pair 3 (timeoutReceipt "h2" tmo))))
        (cH (optionOr (listFind (fn [(x cd/CUnit)] -> Bool (= x.id "R1")) (cd/readCUnits! store)) (pf/cuIn "R1" "absent" "" "")))
        (_ (cd/finish! ctx u cH (optionOr rHold (resOf "none" "none"))))
        (markerGone (not (fileExists? (cd/mergeRetryPath store "R1"))))
        (rc (cd/realCfg (list "--repo" "/r" "--dev-repo" "/r" "--dev" "dev" "--home" (str root "/home")) store))
        (o (cd/mergeCheckOpts rc (pf/cuIn "R1" "merging" "" "sh/R1") "base0"))
        (_ (pf/cleanup root))]
    (do (assert (and (= (vOf r1) "recheck") (= retries 2)) (str "the first timeout-only check is a recheck with one (:retry) row, and the next head gets its own: " (vOf r1) " " (stringFromInt64 retries)))
        (assert (and (= (vOf r2) "hold") (= (vOf r3) "recheck")) (str "a second timeout at the same head holds, a new head is checked again: " (vOf r2) " " (vOf r3)))
        (assert (= (vOf rNo) "hold") (str "an unverified step that is no timeout (noMergeBase) holds at once: " (vOf rNo)))
        (assert (= (vOf rMix) "hold") (str "a timeout beside another unverified step holds: " (vOf rMix)))
        (assert (= (vOf rEx2) "hold") "a check that could not run (exit 2) holds")
        (assert (and (= afterRetry.st "merging") (= afterRetry.fails 0) (stringEmpty? afterRetry.await)) (str "finish! keeps a recheck merging, no failure, no hold mark: " afterRetry.st " " afterRetry.await))
        (assert o.reuseHead "the conductor's merge check takes the head consistency rows a train saved (--reuse-head)")
        (assert markerKept "the retry mark lives in runs/ under runPath")
        (assert (and (= (vOf rLong) "hold") (cd/mergeTimeoutOnly? (timeoutReceipt "h" tmo)) (not (cd/mergeTimeoutOnly? (timeoutReceipt "h" longTmo)))) (str "a non-timeout item past 300 chars still holds: " (vOf rLong)))
        (assert (= (vOf rSub) "hold") (str "an item that only contains the word timeout is no timeout: " (vOf rSub)))
        (assert (and (= (vOf rHold) "hold") markerGone) "a unit that blocks drops its retry mark")
        true))
