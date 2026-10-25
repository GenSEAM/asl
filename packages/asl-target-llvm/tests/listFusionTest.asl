(module asl-target-llvm/tests/listFusionTest
  :x [runTests]
  :i [(asl-ir/link :a lk)
      (asl-ir/types :a ty)
      (asl-target-llvm :a llvm)
      (asl-target-llvm/ssaOpt :a opt)
      (asl-target-llvm/sysRoute :a rt)
      (asl-target-llvm/parRoute :a par)
      (asl-target-llvm/arrayRoute :a ar)
      (asl-target-llvm/listFusion :a lf)
      (asl-target-llvm/tests/rcTest :a rc)])

fn fixture -> String
  "asl/packages/asl-target-llvm/tests/fixtures/listFusion/listFusion.asl"

; (:m :ref FUSION :do "oracle from the List semantics: the ring rounds sum 0..99999, the max of 3i over even i up to 100000, the last of 7..100006 in reversed order, the empty batch leaves 42; then 500500+1000, 500500+1 (the unreversed list ends in 1), the sum of 1000000/v for v in 1..1000, the last of the unreversed list (7) and the first element above 5; then the guard rows: a seeded accumulator (5 + 500500), producer and consumer calls (500500, 500500 + 1000), a division between the calls (d 0), a skipping producer under a trapping fold (3 times the evens), two-code division on both sides (10^18 over 62 125 250 500 1000), an accumulator read by the step and one passed on")
fn want -> String
  "4999950000 300000 100006 42\n501500 500501 7485017 7 6\n500505 500500 501500 500500 748500 1032258 500500 499500\n"

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

fn conses f: ty/SsaFunction -> Int64
  (listCount (fn [(ins ty/SsaInstr)] -> Bool (match ins.op ((ty/opEntry n _) (= n "cons")) (_ false))) (instrsOf f))

fn fusedCallee? name: String -> Bool
  (stringContains? name "$fuse")

fn exactly m: ty/SsaModule name: String -> (Option ty/SsaFunction)
  (listHead (filter (fn [(f ty/SsaFunction)] -> Bool (= f.name name)) m.functions))

; (:m :ref ARITHVER :do "a caller that is itself a counted loop is versioned by loopGuard after fusion; its fast loop is the body that holds the fused call")
fn named m: ty/SsaModule short: String -> (Option ty/SsaFunction)
  (match (exactly m (str m.name "." short "$avFast"))
    ((some f) (some f))
    ((none) (exactly m (str m.name "." short))))

; (:m :do "a fused caller calls neither the producer nor listReverse but one fused loop, and that loop conses nothing")
fn ! fusedShape m: ty/SsaModule short: String producer: String -> Bool
  (match (named m short)
    ((none) (do (assert false (str short " is in the optimized module")) false))
    ((some f)
      (let [(cs (callees f))
            (loops (filter fusedCallee? cs))]
        (do (refute (listContains? cs "prelude.listReverse") (str short " no longer reverses a list: " (stringJoin cs " ")))
            (refute (listContains? cs (str m.name "." producer)) (str short " no longer calls the producer " producer ": " (stringJoin cs " ")))
            (assert (= (listLength loops) 1) (str short " calls one fused loop: " (stringJoin cs " ")))
            (match (listHead loops)
              ((none) false)
              ((some l) (match (match (exactly m (str l "$avFast")) ((some g) (some g)) ((none) (exactly m l)))
                          ((none) (do (assert false (str "the fused loop " l " is defined")) false))
                          ((some g) (do (assert (= (conses g) 0) (str "the fused loop " l " builds no cons cell, found " (conses g)))
                                        (assert (listContains? (callees g) g.name) (str "the fused loop " g.name " calls itself"))
                                        true)))))))))

; (:m :do "a caller whose list escapes, is read twice, is consumed by a fold that may raise another error or stop early, or is not reversed keeps its producer call and gets no fused loop; a region thunk (SOAREGION) that now holds the producer call counts as the caller")
fn ! keptShape m: ty/SsaModule short: String producer: String reversed: Bool -> Bool
  (match (named m short)
    ((none) (do (assert false (str short " is in the optimized module")) false))
    ((some f)
      (let [(cs (listAppend (callees f) (listFlatMap callees (filter (fn [(g ty/SsaFunction)] -> Bool (stringStartsWith? g.name (str f.name "@region"))) m.functions))))]
        (do (assert (listContains? cs (str m.name "." producer)) (str short " still calls the producer " producer ": " (stringJoin cs " ")))
            (assert (= (listContains? cs "prelude.listReverse") reversed) (str short " keeps its listReverse call as written: " (stringJoin cs " ")))
            (refute (listAny? fusedCallee? cs) (str short " calls no fused loop: " (stringJoin cs " ")))
            true))))

fn ! testShapes -> Bool
  (match (lk/linkEntry! (fixture))
    ((err ds) (do (assert false (str "fixture links: " (rc/diagText ds))) false))
    ((ok m0) (match (optimized! m0)
               ((err e) (do (assert false e) false))
               ((ok m) (do (assert (fusedShape m "fuseRing" "pushBatch") "ring rounds fuse")
                           (assert (fusedShape m "fuseEvens" "pushEvens") "a producer that skips fuses with a branching fold")
                           (assert (fusedShape m "fuseLast" "pushBatch") "an order-sensitive fold fuses")
                           (assert (fusedShape m "fuseEmpty" "pushBatch") "an empty batch fuses")
                           (assert (fusedShape m "fuseEndless" "forever") "an endless producer that conses at every step fuses (accepted divergence)")
                           (assert (= (listLength (filter (fn [(f ty/SsaFunction)] -> Bool (and (fusedCallee? f.name) (not (stringContains? f.name "$av")))) m.functions)) 4) "one fused loop per producer and consumer pair")
                           (assert (keptShape m "keepTwice" "pushBatch" true) "a reversed list read twice is built")
                           (assert (keptShape m "keepBuilt" "pushBatch" true) "a built list read again is built")
                           (assert (keptShape m "keepTrap" "pushBatch" true) "a fold that may divide by zero is not moved before the producer's adds")
                           (assert (keptShape m "keepNoReverse" "pushBatch" false) "an unreversed list is built")
                           (assert (keptShape m "keepEarly" "pushBatch" true) "a fold that may stop early is not fused")
                           (assert (keptShape m "keepSeeded" "pushBatch" true) "an accumulator seeded with a non-empty list is built")
                           (assert (keptShape m "keepCallP" "pushCall" true) "a producer that calls a function is not fused")
                           (assert (keptShape m "keepCallC" "pushBatch" true) "a fold that calls a function is not fused")
                           (assert (keptShape m "keepBetween" "pushBatch" true) "a trapping division between the producer and the fold keeps the order")
                           (assert (keptShape m "keepSkipTrap" "pushEvens" true) "a skipping producer under a trapping fold is not fused")
                           (assert (keptShape m "keepTwoCodes" "gen" true) "a division on both sides can raise two errors and is not fused")
                           (assert (keptShape m "keepAccUsed" "pushWrap" true) "an accumulator the step reads is not fused")
                           (assert (keptShape m "keepAccOther" "pushDup" true) "an accumulator passed on in another argument is not fused")
                           true)))))

fn renameIn m: ty/SsaModule from: String to: String -> ty/SsaModule
  (with m :functions (map (fn [(f ty/SsaFunction)] -> ty/SsaFunction
                            (ty/ssaFunction (if (= f.name from) to f.name) f.captures f.params f.retTy
                              (map (fn [(b ty/SsaBlock)] -> ty/SsaBlock
                                     (ty/ssaBlock b.label b.params
                                       (map (fn [(i ty/SsaInstr)] -> ty/SsaInstr (match i.op ((ty/opCall c args) (if (= c from) (ty/ssaInstr i.dest i.ty (ty/opCall to args)) i)) (_ i))) b.instrs)
                                       b.term))
                                   f.blocks)))
                          m.functions))

; (:m :do "a producer under the arrays prefix is opaque to the RC pass, so a loop built from it would go uncounted: the linked fixture with pushBatch renamed there keeps the ring rounds' list, while the unrenamed one fuses")
fn ! testOpaque -> Bool
  (match (lk/linkEntry! (fixture))
    ((err ds) (do (assert false (str "fixture links: " (rc/diagText ds))) false))
    ((ok m0) (let [(moved (renameIn m0 (str m0.name ".pushBatch") "asl-target-llvm/arrays.pushBatch"))
                   (plain (lf/fuseLists m0)) (opaque (lf/fuseLists moved))
                   (ring (fn [(m ty/SsaModule)] -> (List String) (callees (optionOr (named m "fuseRing") (ty/ssaFunction "" (list) (list) (ty/tyVal) (list))))))]
               (do (assert (listAny? fusedCallee? (ring plain)) (str "the ring rounds fuse in the linked module: " (stringJoin (ring plain) " ")))
                   (assert (listContains? (ring opaque) "asl-target-llvm/arrays.pushBatch") (str "an arrays-prefixed producer is still called: " (stringJoin (ring opaque) " ")))
                   (refute (listAny? fusedCallee? (ring opaque)) (str "an arrays-prefixed producer is not fused: " (stringJoin (ring opaque) " ")))
                   true))))

fn ! build! libs: rc/Libs dir: String mode: String -> (Result (Pair String rc/Captured) String)
  (match (lk/linkEntry! (fixture))
    ((err ds) (err (str "fixture links: " (rc/diagText ds))))
    ((ok m) (match (llvm/emitLlvmProgramNativeWith! m (str m.name ".main") mode)
              ((err ds) (err (str "fixture emits in mode " mode ": " (rc/diagText ds))))
              ((ok code)
                (let [(ll (str dir "/listFusion." mode ".ll")) (exe (str dir "/listFusion." mode))]
                  (match (fileWrite ll code)
                    ((err e) (err (str "cannot write " ll ": " e)))
                    ((ok _) (let [(linked (rc/sh (rc/linkCmd libs mode ll exe)))]
                              (if (!= linked.exitCode 0)
                                (err (str "fixture " mode " links: " linked.stderr))
                                (ok (pair code (rc/sh (rc/shellQuote exe)))))))))))))

fn ! testMode libs: rc/Libs dir: String mode: String -> Bool
  (match (build! libs dir mode)
    ((err e) (do (assert false e) false))
    ((ok built)
      (let [(code (pairFirst built)) (run (pairSecond built))]
        (do (assert (= run.exitCode 0) (str mode " exits 0: " run.stderr))
            (assert (= run.stdout (want)) (str mode " prints what the List semantics give: " run.stdout))
            (refute (stringContains? run.stderr "Sanitizer") (str mode " reads no released cell: " run.stderr))
            (assert (stringContains? code "fuse") (str mode " emits the fused loops"))
            (let [(endless (rc/sh (str "/usr/bin/perl -e 'alarm 20; exec @ARGV' " (rc/shellQuote (str dir "/listFusion." mode)) " endless")))]
              (do (assert (= endless.exitCode 1) (str mode " the fused endless producer stops at the fold's first overflow, exit " endless.exitCode))
                  (assert (= (optionOr (listHead (stringLines endless.stderr)) "") "ERR_INT_OVERFLOW: Int + leaves int64") (str mode " the endless run fails with the fold's error: " endless.stderr))
                  (assert (= endless.stdout "") (str mode " the endless run prints nothing: " endless.stdout))))
            true))))

fn ! clean dir: String -> Bool
  (let [(names (resultOr (dirList dir) (list)))]
    (do (fold (fn [(acc Bool) (n String)] -> Bool (and (ok? (pathRemove (str dir "/" n))) acc)) true names)
        (ok? (pathRemove dir))))

fn ! runTests -> Bool
  (let [(dir (str (optionOr (envGet "TMPDIR") "/tmp") "/listFusionTest." (procSelf) "." (monotonicNs)))
        (made (dirCreate dir))]
    (do (assert (ok? made) "work directory created")
        (assert (testShapes) "fusable sites fuse and the others keep their lists")
        (assert (testOpaque) "an opaque producer is not fused")
        (match (rc/runtimes!)
          ((err e) (assert false (str "runtimes: " e)))
          ((ok libs) (do (assert (testMode libs dir "0") "tracing build")
                         (assert (testMode libs dir "notrace") "untraced RC build")
                         (assert (testMode libs dir "asanNotrace") "untraced RC build under ASan"))))
        (assert (clean dir) "work directory removed")
        true))
