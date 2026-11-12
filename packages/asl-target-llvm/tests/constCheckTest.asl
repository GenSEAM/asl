(module asl-target-llvm/tests/constCheckTest
  :x [runTests]
  :i [(asl-ir/link :a lk)
      (asl-target-llvm :a llvm)
      (asl-target-llvm/tests/rcTest :a rc)])

fn fixture -> String
  "asl/packages/asl-target-llvm/tests/fixtures/constCheck/constCheck.asl"
; (:m :ref PERF-CHECKS :do "the oracle at n 0: every loop counter steps exactly onto an int64 edge without trapping, and a shift by 64 is masked to a shift by 0 as mathrt.shiftLeft does")
fn okExpected -> String
  (stringJoin (list "upLoop 9223372036854775807" "leftLoop 9223372036854775807" "downLoop -9223372036854775808" "addNegLoop -9223372036854775808"
                    "subNegLoop 9223372036854775807" "zeroLoop 7" "varLoop 9223372036854775807" "nonStep 9223372036854775807" "subVar -9223372036854775808"
                    "shiftConst 24576" "shiftVar 3" "")
              "\n")

; (:m :ref PERF-CHECKS :do "one step past each edge traps with the checked error line: + for adds, - for subs, literal or variable step")
fn failures -> (List (Pair String String))
  (list (pair "upOver" "ERR_INT_OVERFLOW: Int + leaves int64")
        (pair "leftOver" "ERR_INT_OVERFLOW: Int + leaves int64")
        (pair "downOver" "ERR_INT_OVERFLOW: Int - leaves int64")
        (pair "addNegOver" "ERR_INT_OVERFLOW: Int + leaves int64")
        (pair "subNegOver" "ERR_INT_OVERFLOW: Int - leaves int64")
        (pair "varOver" "ERR_INT_OVERFLOW: Int + leaves int64")
        (pair "nonStepOver" "ERR_INT_OVERFLOW: Int + leaves int64")
        (pair "subVarOver" "ERR_INT_OVERFLOW: Int - leaves int64"))

fn ! emitted! -> (Result String String)
  (match (lk/linkEntry! (fixture))
    ((err ds) (err (str "fixture links: " (rc/diagText ds))))
    ((ok m) (match (llvm/emitLlvmProgramNativeWith! m (str m.name ".main") "notrace")
              ((err ds) (err (str "fixture emits: " (rc/diagText ds))))
              ((ok code) (ok code)))))

; (:m :do "the bodies of every define ... @constCheck$2Ename( or of its loop-guard variants @constCheck$2Ename$..., each up to its closing brace; empty when absent")
fn defines? l: String name: String -> Bool
  (and (stringStartsWith? l "define")
       (or (stringContains? l (str "@constCheck$2E" name "(")) (stringContains? l (str "@constCheck$2E" name "$"))))

fn bodiesFrom lines: (List String) name: String inBody: Bool acc: (List String) -> (List String)
  (match (listHead lines)
    ((none) (listReverse acc))
    ((some l) (let [(rest (listDrop lines 1))]
                (cond (inBody (if (= l "}") (bodiesFrom rest name false acc) (bodiesFrom rest name true (cons l acc))))
                      ((defines? l name) (bodiesFrom rest name true (cons l acc)))
                      (else (bodiesFrom rest name false acc))))))

fn bodyOf code: String name: String -> String
  (stringJoin (bodiesFrom (stringLines code) name false (list)) "\n")

fn ! checkBound code: String name: String cmp: String -> Bool
  (let [(b (bodyOf code name))]
    (do (assert (!= b "") (str name ": its body is emitted"))
        (assert (stringContains? b cmp) (str name ": the counter step compares against the constant bound `" cmp "`: " b))
        (refute (stringContains? b "with.overflow") (str name ": no with.overflow call for a literal counter step: " b))
        (assert (stringContains? b "nsw i64 %i, ") (str name ": the step is nsw: " b))
        (assert (stringContains? b "@rterr.int(i32 ") (str name ": the bound still traps through rterr.int: " b))
        true))

fn ! testShape code: String -> Bool
  (do (assert (checkBound code "upLoop" "icmp sgt i64 %i, 9223372036854775806") "i + 1 traps above MAX - 1")
      (assert (checkBound code "leftLoop" "icmp sgt i64 %i, 9223372036854775802") "5 + i traps above MAX - 5")
      (assert (checkBound code "downLoop" "icmp slt i64 %i, -9223372036854775805") "i - 3 traps below MIN + 3")
      (assert (checkBound code "addNegLoop" "icmp slt i64 %i, -9223372036854775804") "i + -4 traps below MIN + 4")
      (assert (checkBound code "subNegLoop" "icmp sgt i64 %i, 9223372036854775805") "i - -2 traps above MAX - 2")
      (let [(z (bodyOf code "zeroLoop"))]
        (do (assert (stringContains? z "add nsw i64 %i, 0") (str "i + 0 is a plain nsw add: " z))
            (assert (stringContains? z "= icmp ne i64 0, 0") (str "i + 0 checks a constant false, which LLVM drops: " z))
            (assert (stringContains? z "icmp slt i64 %k, -9223372036854775807") (str "k - 1 traps below MIN + 1: " z))
            (refute (stringContains? z "with.overflow") (str "zeroLoop has no with.overflow call: " z))))
      (let [(v (bodyOf code "varLoop")) (x (bodyOf code "nonStep")) (s (bodyOf code "subVar"))]
        (do (assert (stringContains? v "@llvm.sadd.with.overflow.i64(i64 %i, i64 %d)") (str "a variable step i + d keeps with.overflow: " v))
            (assert (stringContains? x "@llvm.sadd.with.overflow.i64(i64 %x, ") (str "x + 1 outside a self call keeps with.overflow: " x))
            (refute (stringContains? x "icmp sgt") (str "x + 1 outside a self call has no bound compare: " x))
            (assert (stringContains? x "@rterr.int(i32 0)") (str "x + 1 traps through rterr.int: " x))
            (assert (stringContains? s "@llvm.ssub.with.overflow.i64(i64 %x, i64 %y)") (str "x - y keeps with.overflow: " s))))
      (let [(c (bodyOf code "shiftConst")) (k (bodyOf code "shiftVar"))]
        (do (assert (stringContains? c "shl i64 %x") (str "x << 13 is one shl: " c))
            (refute (stringContains? c "br i1") (str "x << 13 has no range-check branch: " c))
            (assert (stringContains? k "and i64 %k, 63") (str "x << k masks k to 0..63: " k))
            (refute (stringContains? k "br i1") (str "x << k masks rather than branches: " k))))
      true)

fn ! testRun libs: rc/Libs dir: String code: String -> Bool
  (let [(ll (str dir "/constCheck.ll")) (exe (str dir "/constCheck"))]
    (match (fileWrite ll code)
      ((err e) (do (assert false (str "cannot write " ll ": " e)) false))
      ((ok _)
        (let [(linked (rc/sh (rc/linkCmd libs "notrace" ll exe)))]
          (if (!= linked.exitCode 0)
            (do (assert false (str "fixture links: " linked.stderr)) false)
            (let [(okRun (rc/sh (str "/usr/bin/perl -e 'alarm 60; exec @ARGV' " (rc/shellQuote exe) " ok 0")))]
              (do (assert (= okRun.exitCode 0) (str "ok run exits 0: " okRun.stderr))
                  (assert (= okRun.stdout (okExpected)) (str "ok run reaches every edge: " okRun.stdout))
                  (fold (fn [(acc Bool) (c (Pair String String))] -> Bool
                          (let [(r (rc/sh (str "/usr/bin/perl -e 'alarm 60; exec @ARGV' " (rc/shellQuote exe) " " (pairFirst c) " 0")))]
                            (do (assert (= r.exitCode 1) (str (pairFirst c) " exits 1, got " r.exitCode ": " r.stdout))
                                (assert (= r.stdout "") (str (pairFirst c) " prints no value: " r.stdout))
                                (assert (= (optionOr (listHead (stringLines r.stderr)) "") (pairSecond c)) (str (pairFirst c) " fails as a checked op does: " r.stderr))
                                acc)))
                        true (failures)))))))))

fn ! clean dir: String -> Bool
  (let [(names (resultOr (dirList dir) (list)))]
    (do (fold (fn [(acc Bool) (n String)] -> Bool (and (ok? (pathRemove (str dir "/" n))) acc)) true names)
        (ok? (pathRemove dir))))

fn ! runTests -> Bool
  (let [(dir (str (optionOr (envGet "TMPDIR") "/tmp") "/constCheckTest." (procSelf) "." (monotonicNs)))
        (made (dirCreate dir))]
    (do (assert (ok? made) "work directory created")
        (match (emitted!)
          ((err e) (assert false e))
          ((ok code) (do (assert (testShape code) "literal counter steps check one bound, other adds keep with.overflow, shifts mask")
                         (match (rc/runtimes!)
                           ((err e) (assert false (str "runtimes: " e)))
                           ((ok libs) (assert (testRun libs dir code) "native run traps exactly past each edge"))))))
        (assert (clean dir) "work directory removed")
        true))
