(module asl/tools/tests/prepareAllTest
  :x [runTests]
  :i [(asl-tools/nativeTest :a nt)
      (asl-tools/fleet/run :a run)])

fn suites -> (List String)
  (map (fn [(s String)] -> String (str "asl/tools/tests/fixtures/prepareAll/suite" s ".asl")) (list "A" "B" "C" "D"))

fn binariesOf bs: (List nt/Built) -> (List String)
  (map (fn [(b nt/Built)] -> String (optionOr b.binary "")) bs)

fn relativeTo bs: (List nt/Built) cache: String -> (List String)
  (map (fn [(b String)] -> String (stringReplace b cache "")) (binariesOf bs))

fn reasonsOf bs: (List nt/Built) -> String
  (stringJoin (map (fn [(b nt/Built)] -> String (str "[" b.cache " " b.reason "]")) bs) " ")

fn allBuilt? bs: (List nt/Built) -> Bool
  (listAll? (fn [(b nt/Built)] -> Bool (and (some? b.binary) (fileExists? (optionOr b.binary "")))) bs)

fn ! exitOf bin: String -> Int64
  (run/runOne (run/Job :argv (list (resultOr (realPath bin) bin)) :cwd "." :env (list))).exit

fn ! freshCache! root: String name: String -> String
  (let [(d (str root "/" name))
        (_ (dirCreate d))]
    (resultOr (realPath d) d))

fn ! markerCache! root: String name: String -> String
  (let [(d (str root "/" name))
        (_ (dirCreate d))]
    d)

fn ! swept? d: String -> Bool
  (do (nt/sweepStore! d) (fileExists? (str d "/swept")))

fn ! markersHold? ign: String -> Bool
  (let [(rootRaw (str (optionOr (envGet "TMPDIR") "/tmp") "/prepareAllMarkers-" (stringFromInt64 (procSelf)) "-" (stringFromInt64 (nowNs))))
        (_ (dirCreate rootRaw))
        (root (resultOr (realPath rootRaw) rootRaw))
        (me (stringFromInt64 (procSelf)))
        (live1 (str "building." me))
        (live2 (str "building." me ".b"))
        (dead "building.999999")
        (a (markerCache! root "mkLive"))
        (_ (fileWrite (str a "/" live1) ""))
        (heldLive (not (swept? a)))
        (b (markerCache! root "mkDead"))
        (_ (fileWrite (str b "/" dead) ""))
        (sweptDead (swept? b))
        (deadGone (not (fileExists? (str b "/" dead))))
        (c (markerCache! root "mkTwo"))
        (_ (fileWrite (str c "/" live1) ""))
        (_ (fileWrite (str c "/" live2) ""))
        (_ (pathRemove (str c "/" live1)))
        (heldOne (not (swept? c)))
        (_ (pathRemove (str c "/" live2)))
        (sweptNone (swept? c))
        (d (markerCache! root "mkNone"))
        (sweptEmpty (swept? d))
        (_ (pathRemove root))]
    (and heldLive (and sweptDead (and deadGone (and heldOne (and sweptNone sweptEmpty))))))

fn ! runTests -> Bool
  (let [(rootRaw (str (optionOr (envGet "TMPDIR") "/tmp") "/prepareAllTest-" (stringFromInt64 (procSelf)) "-" (stringFromInt64 (nowNs))))
        (made (dirCreate rootRaw))
        (root (resultOr (realPath rootRaw) rootRaw))
        (fp (nt/fingerprint))
        (cachePar (freshCache! root "par"))
        (cacheSeq (freshCache! root "seq"))
        (cold (nt/prepareAllIn cachePar (suites) fp 4))
        (warm (nt/prepareAllIn cachePar (suites) fp 4))
        (seq (nt/prepareAllIn cacheSeq (suites) fp 1))
        (exits (map (fn [(b String)] -> Int64 (exitOf b)) (binariesOf cold)))
        (recompiledWarm (fold (fn [(n Int64) (b nt/Built)] -> Int64 (+ n (listLength b.recompiled))) 0 warm))
        (coldBuilt (allBuilt? cold))
        (warmBuilt (allBuilt? warm))
        (seqBuilt (allBuilt? seq))
        (removed (pathRemove root))]
    (do
      (assert (ok? made) (str "a fresh temp dir " rootRaw))
      (assert (= (listLength cold) 4) (str "one Built per suite on a cold cache with 4 workers: " (stringFromInt64 (listLength cold))))
      (assert coldBuilt (str "four suites sharing one helper build cold in parallel: " (reasonsOf cold)))
      (assert (listAll? (fn [(e Int64)] -> Bool (= e 0)) exits) (str "every parallel-built binary exits 0: " (stringJoin (map stringFromInt64 exits) ",")))
      (assert (= (relativeTo cold cachePar) (relativeTo seq cacheSeq))
              (str "parallel and sequential prepareAll give the same slots in input order: " (stringJoin (relativeTo cold cachePar) " ")))
      (assert (and warmBuilt (= (binariesOf warm) (binariesOf cold))) (str "the warm parallel pass returns the cold binaries: " (reasonsOf warm)))
      (assert (= recompiledWarm 0) (str "the warm pass recompiles nothing: " (stringFromInt64 recompiledWarm)))
      (assert seqBuilt (str "the sequential pass builds every suite: " (reasonsOf seq)))
      (assert (markersHold? root) "building.PID markers: live holds the sweep, dead is ignored and removed, two live keep the hold until both go")
      (assert (ok? removed) (str "remove " root))
      (assert (= (nt/suiteWorkersFor 10 10) 4) (str "10 jobs on 10 cpus give 4 suite workers, not 10: " (stringFromInt64 (nt/suiteWorkersFor 10 10))))
      (assert (= (nt/suiteWorkersFor 2 10) 2) "the asked k caps the workers")
      (assert (= (nt/suiteWorkersFor 10 3) 1) "a small machine builds one suite at a time")
      true))
