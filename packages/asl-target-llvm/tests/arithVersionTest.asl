(module asl-target-llvm/tests/arithVersionTest
  :x [runTests]
  :i [(asl-ir/link :a lk)
      (asl-ir/types :a ty)
      (asl-target-llvm :a llvm)
      (asl-target-llvm/ssaOpt :a opt)
      (asl-target-llvm/sysRoute :a rt)
      (asl-target-llvm/parRoute :a par)
      (asl-target-llvm/arrayRoute :a ar)
      (asl-target-llvm/loopGuard :a lg)
      (asl-target-llvm/tests/rcTest :a rc)])

fn fixture -> String
  "asl/packages/asl-target-llvm/tests/fixtures/arithVersion/arithVersion.asl"

; (:m :ref ARITHVER :do "oracle from checked Int64 semantics, computed outside ASL: the affine sums, a hash loop under mod, a squares loop, a loop stepping by 2, sums near the int64 edge that must take the checked loop, and the fused ring rounds; tripOver passes every bound but the trip limit (2^61 / (3*7e6 + 2^40) < 7e6 steps) and backward starts past n (5 > 3), so each reaches its overflow only through the checked loop; failing runs are bounded by a 60 s alarm")
fn okExpected -> String
  (stringJoin (list "affine 15000550000" "affineNeg -1050005" "affineEmpty 3" "affineBigAcc 4611686018428887404" "hash 282060600"
                    "hashBigStart 400849221" "squares 1525" "stepTwo 2499950000" "accUnder -9223372036854760950" "ring 4999950000" "")
              "\n")

fn failures -> (List (Pair String String))
  (list (pair "accOver" "ERR_INT_OVERFLOW: Int + leaves int64")
        (pair "termOver" "ERR_INT_OVERFLOW: Int + leaves int64")
        (pair "squareOver" "ERR_INT_OVERFLOW: Int * leaves int64")
        (pair "tripOver" "ERR_INT_OVERFLOW: Int + leaves int64")
        (pair "backward" "ERR_INT_OVERFLOW: Int + leaves int64"))

fn ! optimized! m: ty/SsaModule -> (Result ty/SsaModule String)
  (match (rt/routeHostLinked! (opt/nativePrelude m))
    ((err ds) (err (str "system route: " (rc/diagText ds))))
    ((ok r) (match (par/routeHostLinked! r.result)
              ((err ds) (err (str "parallel route: " (rc/diagText ds))))
              ((ok r2) (match (ar/routeLinked r2.result)
                         ((err ds) (err (str "array route: " (rc/diagText ds))))
                         ((ok r3) (ok (opt/hoistConstants r3.result))))))))

fn named m: ty/SsaModule name: String -> (Option ty/SsaFunction)
  (listHead (filter (fn [(f ty/SsaFunction)] -> Bool (= f.name name)) m.functions))

fn instrsOf f: ty/SsaFunction -> (List ty/SsaInstr)
  (listFlatMap (fn [(b ty/SsaBlock)] -> (List ty/SsaInstr) b.instrs) f.blocks)

fn callees f: ty/SsaFunction -> (List String)
  (listFlatMap (fn [(i ty/SsaInstr)] -> (List String) (match i.op ((ty/opCall c _) (list c)) (_ (list)))) (instrsOf f))

fn primCount f: ty/SsaFunction name: String -> Int64
  (listCount (fn [(i ty/SsaInstr)] -> Bool (match i.op ((ty/opPrim n _) (= n name)) (_ false))) (instrsOf f))

fn checkedCount f: ty/SsaFunction -> Int64
  (+ (primCount f "addIntHost") (+ (primCount f "subIntHost") (primCount f "mulIntHost")))

fn empty -> ty/SsaFunction
  (ty/ssaFunction "" (list) (list) (ty/tyI64) (list))

; (:m :do "a versioned loop: the entry no longer calls itself and branches on its check to the fast loop or the checked one; the fast loop is called only from that entry and itself, keeps `checked` checked operations, and the checked loop keeps every one of the original's")
fn ! versioned m: ty/SsaModule name: String checked: Int64 original: Int64 -> Bool
  (let [(f (optionOr (named m name) (empty)))
        (fast (optionOr (named m (lg/fastName name)) (empty)))
        (slow (optionOr (named m (lg/slowName name)) (empty)))
        (entry (optionOr (listHead f.blocks) (ty/ssaBlock "" (list) (list) (ty/termUnreachable))))
        (callers (filter (fn [(g ty/SsaFunction)] -> Bool (listContains? (callees g) (lg/fastName name))) m.functions))]
    (do (assert (!= f.name "") (str name " is in the module"))
        (refute (listContains? (callees f) name) (str name ": the entry no longer calls itself"))
        (assert (match entry.term
                  ((ty/termBranch _ a b) (and (= a.target "av.fast") (= b.target "av.slow")))
                  (_ false))
                (str name ": the entry branches on its check to the fast or the checked loop"))
        (assert (= (map (fn [(g ty/SsaFunction)] -> String g.name) callers) (list name (lg/fastName name))) (str name ": only the checked entry and the fast loop itself call the fast loop: " (stringJoin (map (fn [(g ty/SsaFunction)] -> String g.name) callers) " ")))
        (assert (= (checkedCount fast) checked) (str name ": the fast loop keeps " checked " checked operations, has " (checkedCount fast)))
        (assert (> (primCount fast "rawAddI64") 0) (str name ": the fast loop adds raw"))
        (assert (= (checkedCount slow) original) (str name ": the checked loop keeps the original's " original " checked operations, has " (checkedCount slow)))
        (assert (= (primCount slow "rawAddI64") 0) (str name ": the checked loop has no raw add"))
        true))

fn ! testShape -> Bool
  (match (lk/linkEntry! (fixture))
    ((err ds) (do (assert false (str "fixture links: " (rc/diagText ds))) false))
    ((ok m0) (match (optimized! m0)
               ((err e) (do (assert false e) false))
               ((ok m) (let [(fused (filter (fn [(f ty/SsaFunction)] -> Bool (and (stringContains? f.name "$fuse") (not (stringContains? f.name "$av")))) m.functions))]
                         (do (assert (versioned m "arithVersion.sumAffine" 0 4) "the affine sum runs with no checked operation behind its check")
                             (assert (versioned m "arithVersion.hashLoop" 0 3) "the hash loop's adds and multiply are bounded by its mod")
                             (assert (none? (named m (lg/fastName "arithVersion.squares"))) "the squares loop, where only i+1 could run raw and acc*acc+i stays checked, is not versioned")
                             (assert (listContains? (callees (optionOr (named m "arithVersion.squares") (empty))) "arithVersion.squares") "the squares loop still calls itself")
                             (assert (none? (named m (lg/fastName "arithVersion.stepTwo"))) "a loop stepping by 2 is not versioned")
                             (assert (listContains? (callees (optionOr (named m "arithVersion.stepTwo") (empty))) "arithVersion.stepTwo") "a loop stepping by 2 still calls itself")
                             (assert (= (listLength fused) 1) (str "the ring rounds fuse into one loop: " (stringJoin (map (fn [(f ty/SsaFunction)] -> String f.name) fused) " ")))
                             (assert (versioned m (optionOr (optionMap (fn [(f ty/SsaFunction)] -> String f.name) (listHead fused)) "") 0 3) "the fused ring loop runs unchecked behind its check")
                             (assert (= (lg/guardLoops m) m) "guardLoops is idempotent")
                             true))))))

fn ! buildExe! libs: rc/Libs dir: String mode: String -> (Result String String)
  (match (lk/linkEntry! (fixture))
    ((err ds) (err (str "fixture links: " (rc/diagText ds))))
    ((ok m) (match (llvm/emitLlvmProgramNativeWith! m (str m.name ".main") mode)
              ((err ds) (err (str "fixture emits in mode " mode ": " (rc/diagText ds))))
              ((ok code)
                (let [(ll (str dir "/arithVersion." mode ".ll")) (exe (str dir "/arithVersion." mode))]
                  (match (fileWrite ll code)
                    ((err e) (err (str "cannot write " ll ": " e)))
                    ((ok _) (let [(linked (rc/sh (rc/linkCmd libs mode ll exe)))]
                              (if (!= linked.exitCode 0) (err (str "fixture " mode " links: " linked.stderr)) (ok exe))))))))))

; (:m :do "every mode prints the oracle, and every overflowing run exits 1 with the checked loop's error line and no sanitizer report")
fn ! testRun libs: rc/Libs dir: String mode: String -> Bool
  (match (buildExe! libs dir mode)
    ((err e) (do (assert false e) false))
    ((ok exe)
      (let [(okRun (rc/sh (str (rc/shellQuote exe) " ok")))]
        (do (assert (= okRun.exitCode 0) (str mode " ok run exits 0: " okRun.stderr))
            (assert (= okRun.stdout (okExpected)) (str mode " ok run prints the checked sums: " okRun.stdout))
            (refute (stringContains? okRun.stderr "Sanitizer") (str mode " ok run has no sanitizer report: " okRun.stderr))
            (fold (fn [(acc Bool) (c (Pair String String))] -> Bool
                    (let [(r (rc/sh (str "/usr/bin/perl -e 'alarm 60; exec @ARGV' " (rc/shellQuote exe) " " (pairFirst c))))]
                      (do (assert (= r.exitCode 1) (str mode " " (pairFirst c) " exits 1, got " r.exitCode))
                          (assert (= r.stdout "") (str mode " " (pairFirst c) " prints no sum: " r.stdout))
                          (assert (= (optionOr (listHead (stringLines r.stderr)) "") (pairSecond c)) (str mode " " (pairFirst c) " fails as the checked loop does: " r.stderr))
                          acc)))
                  true (failures))))))

fn ! clean dir: String -> Bool
  (let [(names (resultOr (dirList dir) (list)))]
    (do (fold (fn [(acc Bool) (n String)] -> Bool (and (ok? (pathRemove (str dir "/" n))) acc)) true names)
        (ok? (pathRemove dir))))

fn ! runTests -> Bool
  (let [(dir (str (optionOr (envGet "TMPDIR") "/tmp") "/arithVersionTest." (procSelf) "." (monotonicNs)))
        (made (dirCreate dir))]
    (do (assert (ok? made) "work directory created")
        (assert (testShape) "the bounded loops are versioned and the others are not")
        (match (rc/runtimes!)
          ((err e) (assert false (str "runtimes: " e)))
          ((ok libs) (do (assert (testRun libs dir "0") "tracing build")
                         (assert (testRun libs dir "notrace") "untraced RC build")
                         (assert (testRun libs dir "asanNotrace") "untraced RC build under ASan"))))
        (assert (clean dir) "work directory removed")
        true))
