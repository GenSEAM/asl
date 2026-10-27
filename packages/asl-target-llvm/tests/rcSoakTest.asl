(module asl-target-llvm/tests/rcSoakTest
  :x [runTests]
  :i [(asl-ir/link :a lk)
      (asl-target-llvm :a llvm)
      (asl-target-llvm/gcRoute :a gr)
      (asl-target-llvm/target :a target)
      (asl-target-llvm/libc :a libc)
      (asl-target-llvm/tests/rcTest :a rc)])

(schema Soak
  (:f name String)
  (:f size Int64))

fn soaks -> (List Soak)
  (list (Soak :name "list" :size 20000)
        (Soak :name "str" :size 20000)
        (Soak :name "record" :size 200000)
        (Soak :name "map" :size 5000)
        (Soak :name "mapGrow" :size 500)
        (Soak :name "ring" :size 20000)
        (Soak :name "bitset" :size 1000)
        (Soak :name "flatmap" :size 5000)
        (Soak :name "soa" :size 5000)
        (Soak :name "allocMix" :size 20000))

; (:m :ref RECSROA :do "recordScalar removes bench/native/record.asl per-step Body, so the record soak runs its escaping copy")
; (:m :ref SLICEVIEW :do "a slice read only by readers is fused, so the slice soak runs a copy whose view crosses a call")
; (:m :ref WAVE6 :do "listFusion makes bench/native/ring allocate O(1) cells, so the ring soak runs a copy whose batch fusion rejects, and testRingFused checks the bench itself")
; (:m :ref WAVE6 :do "regionInfer runs bench/native/soa's record list in one flat arena under untraced RC, so the soa soak runs a copy whose list is read after its sum, and testSoaRegion checks the bench itself")
fn benchPath name: String -> String
  (if (= name "ring") "asl/packages/asl-target-llvm/tests/fixtures/listFusion/alloc/ring.asl" (if (= name "soa") "asl/packages/asl-target-llvm/tests/fixtures/regionInfer/alloc/soa.asl" (if (= name "record") "asl/packages/asl-target-llvm/tests/fixtures/recordScalar/alloc/record.asl" (if (= name "slice") "asl/packages/asl-target-llvm/tests/fixtures/sliceView/alloc/slice.asl" (str "bench/native/" name ".asl")))))

fn ! buildExe! libs: rc/Libs dir: String name: String mode: String -> (Result String String)
  (match (lk/linkEntry! (benchPath name))
    ((err ds) (err (str name " links: " (rc/diagText ds))))
    ((ok m)
     (match (llvm/emitLlvmProgramNativeWith! m (str m.name ".main") mode)
       ((err ds) (err (str name " emits in mode " mode ": " (rc/diagText ds))))
       ((ok code)
        (let [(ll (str dir "/" name "." mode ".ll"))
              (exe (str dir "/" name "." mode))]
          (match (fileWrite ll code)
            ((err e) (err (str "cannot write " ll ": " e)))
            ((ok _)
             (let [(linked (rc/sh (rc/linkCmd libs mode ll exe)))]
               (if (!= linked.exitCode 0) (err (str name " " mode " links: " linked.stderr)) (ok exe))))))))))

fn ! runAt exe: String n: Int64 -> rc/Captured
  (rc/sh (str (rc/shellQuote exe) " " n))

fn live stats: String -> Int64
  (- (+ (rc/statOf stats "fresh") (rc/statOf stats "reused")) (rc/statOf stats "freed"))

fn largeLive stats: String -> Int64
  (- (rc/statOf stats "large") (rc/statOf stats "largeFreed"))

fn collector notrace: Bool -> String
  (match (libc/libcFacts "darwin-arm64")
    ((none) "")
    ((some facts) (match (gr/collectorTextWith facts (target/nativeTargetFacts "arm64-apple-darwin") notrace) ((ok text) text) ((err _) ""))))

fn testUntracedCollector -> Bool
  (let [(traced (collector false))
        (untraced (collector true))
        (mark "@asl$2Dtarget$2Dllvm$2FgcAsl$2EmarkPhase(")
        (sweep "@asl$2Dtarget$2Dllvm$2FgcAsl$2EsweepPhase(")]
    (do (assert (and (stringContains? traced (str "define internal tailcc i64 " mark)) (stringContains? traced (str "define internal tailcc i64 " sweep)))
                "the tracing collector defines its mark and sweep phases")
        (assert (stringContains? traced "call void @gcMutatorRoots(") "the tracing collector scans mutator roots")
        (assert (stringContains? untraced "define ptr @asl_alloc(i32 %t, i64 %n) {") "the untraced collector still provides asl_alloc")
        (assert (stringContains? untraced "define void @asl_gc_collect() {\n  ret void\n}") "the untraced asl_gc_collect does nothing")
        (refute (stringContains? untraced mark) "the untraced collector links no mark phase")
        (refute (stringContains? untraced sweep) "the untraced collector links no sweep phase")
        (refute (stringContains? untraced "@gcMutatorRoots(") "the untraced collector scans no roots")
        (refute (stringContains? untraced "call tailcc i64 @gcAslCollect(") "no untraced allocation path triggers a collection")
        true))

fn ! checkRuns s: Soak t: String c: String a: String -> Bool
  (let [(big (* s.size 4))
        (t1 (runAt t s.size))
        (t4 (runAt t big))
        (c1 (runAt c s.size))
        (c4 (runAt c big))
        (a4 (runAt a big))
        (n s.name)]
    (do (assert (= t1.exitCode 0) (str n " tracing exits 0 at " s.size ", got " t1.exitCode ": " t1.stderr))
        (assert (= t4.exitCode 0) (str n " tracing exits 0 at " big ", got " t4.exitCode ": " t4.stderr))
        (assert (= c1.exitCode 0) (str n " RC exits 0 at " s.size ", got " c1.exitCode ": " c1.stderr))
        (assert (= c4.exitCode 0) (str n " RC exits 0 at " big ", got " c4.exitCode ": " c4.stderr))
        (assert (= a4.exitCode 0) (str n " RC under ASan exits 0 at " big ", got " a4.exitCode ": " a4.stderr))
        (assert (and (!= t1.stdout "") (= c1.stdout t1.stdout)) (str n " RC prints what tracing prints at " s.size ": " c1.stdout " vs " t1.stdout))
        (assert (and (!= t4.stdout "") (= c4.stdout t4.stdout)) (str n " RC prints what tracing prints at " big ": " c4.stdout " vs " t4.stdout))
        (assert (= a4.stdout t4.stdout) (str n " RC under ASan prints what tracing prints at " big ": " a4.stdout))
        (refute (stringContains? a4.stderr "Sanitizer") (str n " ASan reports nothing at " big ": " a4.stderr))
        (assert (= (rc/statOf c1.stderr "stuck") 0) (str n " RC leaves no freed cell sticky at " s.size ": " c1.stderr))
        (assert (= (rc/statOf c4.stderr "stuck") 0) (str n " RC leaves no freed cell sticky at " big ": " c4.stderr))
        ; (:m :ref QW-MAP :do "garbage is reclaimed either by a free or by an in-place reset reuse (fbip): the map loop reads with mapGetOr, so no Option box is freed per element and the reclaiming work shows as resets; the claim is that the sum scales with the workload")
        (assert (> (+ (rc/statOf c4.stderr "freed") (rc/statOf c4.stderr "fbip")) (* 3 (+ (rc/statOf c1.stderr "freed") (rc/statOf c1.stderr "fbip")))) (str n " RC frees or in-place reuses scale with the workload: " c1.stderr " then " c4.stderr))
        (assert (= (live c4.stderr) (live c1.stderr)) (str n " pooled cells live at exit do not grow with the workload: " (live c1.stderr) " at " s.size ", " (live c4.stderr) " at " big " (" c1.stderr " then " c4.stderr ")"))
        (assert (= (rc/statOf c4.stderr "pinned") (rc/statOf c1.stderr "pinned")) (str n " pinned cells do not grow with the workload: " c1.stderr " then " c4.stderr))
        (assert (= (rc/statOf a4.stderr "freed") (rc/statOf c4.stderr "freed")) (str n " ASan-mode RC frees the same cells as RC mode"))
        true))

fn ! checkUntraced s: Soak t: String u: String -> Bool
  (let [(big (* s.size 4))
        (t1 (runAt t s.size))
        (t4 (runAt t big))
        (u1 (runAt u s.size))
        (u4 (runAt u big))
        (n s.name)]
    (do (assert (= u1.exitCode 0) (str n " untraced RC exits 0 at " s.size ", got " u1.exitCode ": " u1.stderr))
        (assert (= u4.exitCode 0) (str n " untraced RC exits 0 at " big ", got " u4.exitCode ": " u4.stderr))
        (assert (and (!= t1.stdout "") (= u1.stdout t1.stdout)) (str n " untraced RC prints what tracing prints at " s.size ": " u1.stdout " vs " t1.stdout))
        (assert (= u4.stdout t4.stdout) (str n " untraced RC prints what tracing prints at " big ": " u4.stdout " vs " t4.stdout))
        (assert (= (rc/statOf u4.stderr "stuck") 0) (str n " untraced RC leaves no freed cell sticky: " u4.stderr))
        (assert (> (+ (rc/statOf u4.stderr "freed") (+ (rc/statOf u4.stderr "largeFreed") (rc/statOf u4.stderr "fbip"))) (* 3 (+ (rc/statOf u1.stderr "freed") (+ (rc/statOf u1.stderr "largeFreed") (rc/statOf u1.stderr "fbip")))))
                (str n " untraced RC frees or in-place reuses scale with the workload: " u1.stderr " then " u4.stderr))
        (assert (= (live u4.stderr) (live u1.stderr)) (str n " untraced pooled cells live at exit do not grow: " u1.stderr " then " u4.stderr))
        (assert (= (largeLive u4.stderr) (largeLive u1.stderr)) (str n " untraced unpooled objects (arrays, bytes, over 512 B) live at exit do not grow: " u1.stderr " then " u4.stderr))
        (assert (= (rc/statOf u4.stderr "pinned") (rc/statOf u1.stderr "pinned")) (str n " untraced pinned cells do not grow: " u1.stderr " then " u4.stderr))
        true))

fn allocs stats: String -> Int64
  (+ (+ (rc/statOf stats "fresh") (rc/statOf stats "reused")) (rc/statOf stats "large"))

; (:m :ref WAVE6 :do "bench/native/ring fused: its allocation count is the same at n and 4n, while the unfused soak copy allocates per element")
fn ! testRingFused libs: rc/Libs dir: String -> Bool
  (match (lk/linkEntry! "bench/native/ring.asl")
    ((err ds) (do (assert false (str "ring links: " (rc/diagText ds))) false))
    ((ok m) (match (llvm/emitLlvmProgramNativeWith! m (str m.name ".main") "1")
              ((err ds) (do (assert false (str "ring emits under RC: " (rc/diagText ds))) false))
              ((ok code)
                (let [(ll (str dir "/ringFused.1.ll")) (exe (str dir "/ringFused.1"))]
                  (match (fileWrite ll code)
                    ((err e) (do (assert false (str "cannot write " ll ": " e)) false))
                    ((ok _) (let [(linked (rc/sh (rc/linkCmd libs "1" ll exe)))
                                  (c1 (runAt exe 20000))
                                  (c4 (runAt exe 80000))]
                              (do (assert (= linked.exitCode 0) (str "ring RC links: " linked.stderr))
                                  (assert (= c1.exitCode 0) (str "fused ring exits 0 at 20000: " c1.stderr))
                                  (assert (= c4.exitCode 0) (str "fused ring exits 0 at 80000: " c4.stderr))
                                  (assert (= (stringTrim c4.stdout) "3189728256") (str "fused ring prints its sum at 80000: " c4.stdout))
                                  (assert (> (allocs c1.stderr) 0) (str "fused ring reports its allocations: " c1.stderr))
                                  (assert (= (allocs c4.stderr) (allocs c1.stderr)) (str "fused ring allocates O(1) cells: " c1.stderr " then " c4.stderr))
                                  true)))))))))

; (:m :ref WAVE6 :do "bench/native/soa under untraced RC: its records come from a flat arena released whole, so it opens an arena and its per-cell frees are the same at n and 4n")
fn ! testSoaRegion libs: rc/Libs dir: String -> Bool
  (match (lk/linkEntry! "bench/native/soa.asl")
    ((err ds) (do (assert false (str "soa links: " (rc/diagText ds))) false))
    ((ok m) (match (llvm/emitLlvmProgramNativeWith! m (str m.name ".main") "notraceStats")
              ((err ds) (do (assert false (str "soa emits untraced: " (rc/diagText ds))) false))
              ((ok code)
                (let [(ll (str dir "/soaRegion.nt.ll")) (exe (str dir "/soaRegion.nt"))]
                  (match (fileWrite ll code)
                    ((err e) (do (assert false (str "cannot write " ll ": " e)) false))
                    ((ok _) (let [(linked (rc/sh (rc/linkCmd libs "notraceStats" ll exe)))
                                  (u1 (runAt exe 5000))
                                  (u4 (runAt exe 20000))]
                              (do (assert (= linked.exitCode 0) (str "soa untraced links: " linked.stderr))
                                  (assert (= u1.exitCode 0) (str "region soa exits 0 at 5000: " u1.stderr))
                                  (assert (= u4.exitCode 0) (str "region soa exits 0 at 20000: " u4.stderr))
                                  (assert (= (stringTrim u4.stdout) "1399970000 1399970000") (str "region soa prints its sums at 20000: " u4.stdout))
                                  (assert (> (rc/statOf u4.stderr "arenas") 0) (str "region soa runs its records in an arena: " u4.stderr))
                                  (assert (= (rc/statOf u4.stderr "freed") (rc/statOf u1.stderr "freed")) (str "region soa frees no cell one by one per record: " u1.stderr " then " u4.stderr))
                                  true)))))))))

fn untracedSoaks -> (List Soak)
  (list (Soak :name "slice" :size 1000))

fn ! checkUntracedOnly libs: rc/Libs dir: String s: Soak -> Bool
  (match (buildExe! libs dir s.name "0")
    ((err e) (do (assert false (str "tracing build: " e)) false))
    ((ok t) (match (buildExe! libs dir s.name "notraceStats")
              ((err e) (do (assert false (str "untraced RC build: " e)) false))
              ((ok u) (checkUntraced s t u)))))

fn ! checkSoak libs: rc/Libs dir: String s: Soak -> Bool
  (match (buildExe! libs dir s.name "0")
    ((err e) (do (assert false (str "tracing build: " e)) false))
    ((ok t)
     (match (buildExe! libs dir s.name "1")
       ((err e) (do (assert false (str "RC build: " e)) false))
       ((ok c)
        (match (buildExe! libs dir s.name "asan")
          ((err e) (do (assert false (str "RC ASan build: " e)) false))
          ((ok a) (match (buildExe! libs dir s.name "notraceStats")
                    ((err e) (do (assert false (str "untraced RC build: " e)) false))
                    ((ok u) (and (checkRuns s t c a) (checkUntraced s t u))))))))))

fn ! runTests -> Bool
  (match (rc/runtimes!)
    ((err e) (do (assert false (str "rcSoakTest runtimes: " e)) false))
    ((ok libs)
     (let [(dir (str (optionOr (envGet "TMPDIR") "/tmp") "/rcSoakTest." (procSelf) "." (monotonicNs)))
           (made (dirCreate dir))]
       (do (assert (ok? made) "rcSoakTest work directory created")
           (assert (testUntracedCollector) "the untraced collector variant links no tracing")
           (assert (testRingFused libs dir) "the fused ring bench allocates O(1) cells")
           (assert (testSoaRegion libs dir) "the soa bench runs its records in an arena")
           (assert (fold (fn [(acc Bool) (s Soak)] -> Bool (and (checkSoak libs dir s) acc)) true (soaks)) "every bench in the soak sample holds under RC")
           (assert (fold (fn [(acc Bool) (s Soak)] -> Bool (and (checkUntracedOnly libs dir s) acc)) true (untracedSoaks)) "array views are freed without a collector")
           (assert (ok? (pathRemove dir)) "rcSoakTest work directory removed")
           true))))
