(module aslGateway/tests/rateLearnTest
  :x [runTests]
  :i [(rateLearn :a rl)])

; (:m :ref GW-RPM-AIMD :do "throttled-only windows raise the learned rpm, a real 429 window lowers it, min and max clamp, a provider total bounds the sum, rows the gateway answered itself are no calls, and the store round-trips through an explicit scratch path")

fn row at: Int64 alias: String outcome: String -> String
  (str "(:call :at " (stringFromInt64 at) " :profile \"p\" :intent \"any\" :alias \"" alias "\" :provider \"prov\" :model \"m\" :in 1 :out 1 :ms 5 :outcome \"" outcome "\" :charge 0)")

fn many n: Int64 at: Int64 alias: String outcome: String -> (List String)
  (map (fn [(i Int64)] -> String (row (+ at i) alias outcome)) (range 0 n))

fn near a: Float64 b: Float64 -> Bool
  (< (abs (- a b)) 0.001)

fn spec alias: String max: Float64 -> rl/Spec
  (rl/Spec :alias alias :provider "prov" :start 20.0 :max max)

fn scratchPath -> String
  ".asl/cache/rateLearnTest/rateLearn.asn"

fn ! runTests -> Bool
  (let [(thr (many 10 1000 "a" "throttled"))
        (r429 (listAppend (many 10 2000 "a" "ok") (many 2 3000 "a" "429")))
        (noise (listAppend (many 5 4000 "a" "breaker 589s") (listAppend (many 5 4100 "a" "skipped") (many 5 4200 "a" "daily"))))
        (cThr (rl/countsOf thr "a" 0 100000))
        (cR (rl/countsOf r429 "a" 0 100000))
        (cN (rl/countsOf noise "a" 0 100000))
        (cWin (rl/countsOf (listAppend thr (many 3 900000 "a" "throttled")) "a" 0 5000))
        (cOther (rl/countsOf thr "b" 0 100000))
        (up (rl/nextRpm 20.0 20.0 0.0 cThr))
        (down (rl/nextRpm 20.0 20.0 0.0 cR))
        (mixed (rl/nextRpm 20.0 20.0 0.0 (rl/Counts :calls 100 :throttled 10 :real429 1)))
        (idle (rl/nextRpm 30.0 20.0 0.0 (rl/Counts :calls 5 :throttled 0 :real429 0)))
        (cap (rl/nextRpm 38.0 20.0 40.0 cThr))
        (floor (rl/nextRpm 6.0 20.0 0.0 cR))
        (dir ".asl/cache/rateLearnTest")
        (made (dirCreate dir))
        (specs (list (spec "a" 0.0) (spec "b" 0.0)))
        (learned (rl/learnAll specs (mapEmpty) thr 0 100000 (mapFromPairs (list (pair "prov" 30.0)))))
        (free (rl/learnAll specs (mapEmpty) thr 0 100000 (mapEmpty)))
        (wrote (rl/writeStore! (scratchPath) learned))
        (back (rl/readStore! (scratchPath)))]
    (do
      (assert (ok? made) "the scratch dir exists")
      (assert (and (= cThr.calls 10) (= cThr.throttled 10) (= cThr.real429 0)) (str "ten throttled rows are ten calls, ten throttled: " (stringFromInt64 cThr.calls)))
      (assert (and (= cR.calls 12) (= cR.real429 2) (= cR.throttled 0)) "a 429 row is a call and a real 429")
      (assert (= cN.calls 0) (str "breaker, skipped and daily rows are no calls: " (stringFromInt64 cN.calls)))
      (assert (= cWin.calls 10) "rows outside the window do not count")
      (assert (= cOther.calls 0) "rows of another alias do not count")
      (assert (near up 24.0) (str "throttled with no 429 adds 20 percent of the start: " (stringFromFloat64 up)))
      (assert (near down 14.0) (str "a 429 share above the threshold multiplies by 0.7: " (stringFromFloat64 down)))
      (assert (near mixed 20.0) "a 429 share under the threshold with throttling holds, it is not a clean window")
      (assert (near idle 30.0) "a window with nothing throttled holds")
      (assert (near cap 40.0) (str "the rate never exceeds rpmMax: " (stringFromFloat64 cap)))
      (assert (near floor 5.0) (str "the rate never falls below start/4: " (stringFromFloat64 floor)))
      (assert (near (mapGetOr free "a" 0.0) 24.0) "learnAll raises a throttled alias from its start")
      (assert (near (mapGetOr free "b" 0.0) 20.0) "an alias without calls keeps its start")
      (assert (near (mapGetOr learned "a" 0.0) 16.3636) (str "the provider total 30 scales 24 and 20 by 30/44: " (stringFromFloat64 (mapGetOr learned "a" 0.0))))
      (assert (near (+ (mapGetOr learned "a" 0.0) (mapGetOr learned "b" 0.0)) 30.0) "the clamped sum equals the provider total")
      (assert (ok? wrote) "the store is written")
      (assert (and (near (mapGetOr back "a" 0.0) (mapGetOr learned "a" 0.0)) (near (mapGetOr back "b" 0.0) (mapGetOr learned "b" 0.0)) (= (mapSize back) 2)) "the store round-trips")
      (assert (= (mapSize (rl/readStore! ".asl/cache/rateLearnTest/absent.asn")) 0) "a missing store is empty")
      (assert (ok? (pathRemove (scratchPath))) "the scratch store is removed")
      true))
