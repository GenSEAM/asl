(module asl-target-llvm/tests/regionInferTest
  :x [runTests]
  :i [(asl-ir/link :a lk)
      (asl-ir/types :a ty)
      (asl-target-llvm :a llvm)
      (asl-target-llvm/ssaOpt :a opt)
      (asl-target-llvm/sysRoute :a rt)
      (asl-target-llvm/parRoute :a par)
      (asl-target-llvm/arrayRoute :a ar)
      (asl-target-llvm/tests/rcTest :a rc)])

fn fixture -> String
  "asl/packages/asl-target-llvm/tests/fixtures/regionInfer/regionInfer.asl"

fn tailFixture -> String
  "asl/packages/asl-target-llvm/tests/fixtures/regionInfer/regionTail.asl"

; (:m :ref SOAREGION :do "oracle: each of the 1000001 drive rounds adds the sum of 3i for i below 10, 135; nested 10 adds 135 over 11 rounds plus 1 for each of 10 returns (1495); tailRec 10 adds 1 ten times then 135 (145)")
fn tailWant -> String
  "135000135\n1495\n145\n"

; (:m :ref SOAREGION :do "oracle from the List semantics: b is 3i for i below n, so a sum is 3n(n-1)/2 (1498500 at n 1000); rounds sums it for n 100..149 (1168800); then the list length, sum plus length, sum plus one closure, the logged sum, the sum over the list built onto a 3-cell base (+9) and the base length")
fn want -> String
  "1498500 1498500 1168800\nlog\n1000 1499500 1498501 1498500 1498509 3\n"

fn ! optimized! m: ty/SsaModule -> (Result ty/SsaModule String)
  (match (rt/routeHostLinked! (opt/nativePrelude m))
    ((err ds) (err (str "system route: " (rc/diagText ds))))
    ((ok r) (match (par/routeHostLinked! r.result)
              ((err ds) (err (str "parallel route: " (rc/diagText ds))))
              ((ok r2) (match (ar/routeLinked r2.result)
                         ((err ds) (err (str "array route: " (rc/diagText ds))))
                         ((ok r3) (ok (opt/hoistConstants r3.result))))))))

fn instrsOf f: ty/SsaFunction -> (List ty/SsaInstr)
  (listFlatMap (fn [(b ty/SsaBlock)] -> (List ty/SsaInstr) b.instrs) f.blocks)

fn callees f: ty/SsaFunction -> (List String)
  (listFlatMap (fn [(ins ty/SsaInstr)] -> (List String) (match ins.op ((ty/opCall c _) (list c)) (_ (list)))) (instrsOf f))

fn exactly m: ty/SsaModule name: String -> (Option ty/SsaFunction)
  (listHead (filter (fn [(f ty/SsaFunction)] -> Bool (= f.name name)) m.functions))

fn thunksOf m: ty/SsaModule f: ty/SsaFunction -> (List ty/SsaFunction)
  (filter (fn [(g ty/SsaFunction)] -> Bool (stringStartsWith? g.name (str f.name "@region"))) m.functions)

fn flat -> String
  "prelude.arenaRunFlat"

; (:m :do "a regioned function calls arenaRunFlat instead of the producer; its one thunk calls the producer and opens no region of its own")
fn ! regionShape m: ty/SsaModule short: String producer: String -> Bool
  (match (exactly m (str m.name "." short))
    ((none) (do (assert false (str short " is in the optimized module")) false))
    ((some f)
      (let [(cs (callees f)) (ts (thunksOf m f)) (p (str m.name "." producer))]
        (do (assert (listContains? cs (flat)) (str short " calls arenaRunFlat: " (stringJoin cs " ")))
            (refute (listContains? cs p) (str short " no longer calls the producer itself: " (stringJoin cs " ")))
            (assert (= (listLength ts) 1) (str short " has one region thunk, found " (listLength ts)))
            (match (listHead ts)
              ((none) false)
              ((some t) (do (assert (listContains? (callees t) p) (str "the thunk " t.name " calls the producer: " (stringJoin (callees t) " ")))
                            (refute (listContains? (callees t) (flat)) (str "the thunk " t.name " opens no region of its own"))
                            true)))))))

; (:m :do "a function whose list escapes or whose region would see unknown code keeps its producer call and gets no thunk")
fn ! keptShape m: ty/SsaModule short: String producer: String -> Bool
  (match (exactly m (str m.name "." short))
    ((none) (do (assert false (str short " is in the optimized module")) false))
    ((some f)
      (let [(cs (callees f))]
        (do (assert (listContains? cs (str m.name "." producer)) (str short " still calls the producer " producer ": " (stringJoin cs " ")))
            (refute (listContains? cs (flat)) (str short " calls no arenaRunFlat: " (stringJoin cs " ")))
            (assert (listEmpty? (thunksOf m f)) (str short " has no region thunk"))
            true))))

fn ! testShapes -> Bool
  (match (lk/linkEntry! (fixture))
    ((err ds) (do (assert false (str "fixture links: " (rc/diagText ds))) false))
    ((ok m0) (match (optimized! m0)
               ((err e) (do (assert false e) false))
               ((ok m) (do (assert (regionShape m "regionSum" "build") "a fold over a built list runs in a region")
                           (assert (regionShape m "regionRaw" "build") "a raw sum over a built list runs in a region")
                           (assert (keptShape m "keepReturn" "build") "a returned list is not regioned")
                           (assert (keptShape m "keepStore" "build") "a list stored in a record the consumer returns is not regioned")
                           (assert (keptShape m "keepClosure" "build") "a list a closure captures is not regioned")
                           (assert (keptShape m "keepUnknown" "build") "a list passed to a consumer with an effectful builtin is not regioned")
                           (assert (keptShape m "keepOuter" "build") "a list built onto an outer list is not regioned")
                           (assert (listAny? (fn [(f ty/SsaFunction)] -> Bool (= f.name (flat))) m.functions) "the module defines arenaRunFlat for the traced builds")
                           true)))))

fn ! build! libs: rc/Libs dir: String mode: String -> (Result (Pair String rc/Captured) String)
  (buildFrom! libs dir (fixture) "regionInfer" mode)

fn ! buildFrom! libs: rc/Libs dir: String path: String stem: String mode: String -> (Result (Pair String rc/Captured) String)
  (match (lk/linkEntry! path)
    ((err ds) (err (str "fixture links: " (rc/diagText ds))))
    ((ok m) (match (llvm/emitLlvmProgramNativeWith! m (str m.name ".main") mode)
              ((err ds) (err (str "fixture emits in mode " mode ": " (rc/diagText ds))))
              ((ok code)
                (let [(ll (str dir "/" stem "." mode ".ll")) (exe (str dir "/" stem "." mode))]
                  (match (fileWrite ll code)
                    ((err e) (err (str "cannot write " ll ": " e)))
                    ((ok _) (let [(linked (rc/sh (rc/linkCmd libs mode ll exe)))]
                              (if (!= linked.exitCode 0)
                                (err (str "fixture " mode " links: " linked.stderr))
                                (ok (pair code (rc/sh (str "/usr/bin/perl -e 'alarm 60; exec @ARGV' " (rc/shellQuote exe))))))))))))))

fn ! testMode libs: rc/Libs dir: String mode: String -> Bool
  (match (build! libs dir mode)
    ((err e) (do (assert false e) false))
    ((ok built)
      (let [(code (pairFirst built)) (run (pairSecond built)) (traced (= mode "0"))]
        (do (assert (= run.exitCode 0) (str mode " exits 0: " run.stderr))
            (assert (= run.stdout (want)) (str mode " prints what the List semantics give: " run.stdout))
            (refute (stringContains? run.stderr "Sanitizer") (str mode " reads no released cell: " run.stderr))
            (if traced
              (do (assert (stringContains? code "call tailcc %Val @prelude$2EarenaRunFlat(") "the tracing build calls arenaRunFlat as a plain function")
                  (refute (stringContains? code "@aslRc.arenaRunFlat(") "the tracing build has no region runtime"))
              (do (assert (stringContains? code "call tailcc %Val @aslRc.arenaRunFlat(") (str mode " routes the regions to the flat region entry"))
                  (assert (stringContains? code "define internal void @aslRc.arenaRelease(ptr %a)") (str mode " links the flat release"))))
            true))))

; (:m :do "the counted untraced build: every region opens an arena, none is retained, and the regioned lists are cut from arenas rather than freed cell by cell")
fn ! testStats libs: rc/Libs dir: String -> Bool
  (match (build! libs dir "notraceStats")
    ((err e) (do (assert false e) false))
    ((ok built)
      (let [(run (pairSecond built)) (stats run.stderr)]
        (do (assert (= run.stdout (want)) (str "notraceStats prints what the List semantics give: " run.stdout))
            (assert (= (rc/statOf stats "arenas") 53) (str "regionSum, regionRaw, 50 rounds and the keepReturn length in main each open an arena: " stats))
            (assert (= (rc/statOf stats "retained") 0) (str "no region value escapes, so no arena is retained: " stats))
            (assert (= (rc/statOf stats "promoted") 0) (str "a region hands back a scalar, so nothing is copied out: " stats))
            (assert (= (rc/statOf stats "arenaCells") 0) (str "a flat release frees chunks without visiting a cell: " stats))
            (assert (and (> (rc/statOf stats "freed") 0) (< (rc/statOf stats "freed") 10000)) (str "the 2000 + 2000 + 12450 + 2000 regioned cells are not freed one by one, only the kept rows are: " stats))
            true))))

; (:m :ref SOAREGION :do "tail guard: drive is a region candidate whose slice reaches drive itself through step, so it keeps its producer call and gets no thunk")
fn ! testTailShape -> Bool
  (match (lk/linkEntry! (tailFixture))
    ((err ds) (do (assert false (str "tail fixture links: " (rc/diagText ds))) false))
    ((ok m0) (match (optimized! m0)
               ((err e) (do (assert false e) false))
               ((ok m) (do (assert (keptShape m "drive" "build") "a slice that reaches its owner is not regioned")
                           (assert (keptShape m "nested" "build") "a slice that reaches its owner outside tail position is not regioned")
                           (assert (keptShape m "tailRec" "build") "a consumer in tail position of a recursive function is not regioned")
                           true)))))

; (:m :ref SOAREGION :do "a million rounds through the tail call run in constant stack in every mode; a nested arena per round would end in ERR_STACK_DEPTH")
fn ! testTailMode libs: rc/Libs dir: String mode: String -> Bool
  (match (buildFrom! libs dir (tailFixture) "regionTail" mode)
    ((err e) (do (assert false e) false))
    ((ok built)
      (let [(run (pairSecond built))]
        (do (assert (= run.exitCode 0) (str "tail " mode " exits 0: " (optionOr (stringSlice run.stderr 0 300) run.stderr)))
            (assert (= run.stdout (tailWant)) (str "tail " mode " prints 135 per round: " run.stdout))
            true))))

fn ! clean dir: String -> Bool
  (let [(names (resultOr (dirList dir) (list)))]
    (do (fold (fn [(acc Bool) (n String)] -> Bool (and (ok? (pathRemove (str dir "/" n))) acc)) true names)
        (ok? (pathRemove dir))))

fn ! runTests -> Bool
  (let [(dir (str (optionOr (envGet "TMPDIR") "/tmp") "/regionInferTest." (procSelf) "." (monotonicNs)))
        (made (dirCreate dir))]
    (do (assert (ok? made) "work directory created")
        (assert (testShapes) "regionable sites run in a region and the others keep their calls")
        (assert (testTailShape) "a slice reaching its owner keeps its call")
        (match (rc/runtimes!)
          ((err e) (assert false (str "runtimes: " e)))
          ((ok libs) (do (assert (testMode libs dir "0") "tracing build")
                         (assert (testMode libs dir "notrace") "untraced RC build")
                         (assert (testMode libs dir "asanNotrace") "untraced RC build under ASan")
                         (assert (testStats libs dir) "counted untraced RC build")
                         (assert (testTailMode libs dir "0") "tail rounds, tracing")
                         (assert (testTailMode libs dir "notrace") "tail rounds, untraced RC")
                         (assert (testTailMode libs dir "asanNotrace") "tail rounds, untraced RC under ASan"))))
        (assert (clean dir) "work directory removed")
        true))
