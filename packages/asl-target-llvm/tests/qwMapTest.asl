(module asl-target-llvm/tests/qwMapTest
  :x [runTests]
  :i [(asl-ir/link :a lk)
      (asl-target-llvm :a llvm)
      (asl-target-llvm/tests/rcTest :a rc)])

; (:m :ref QW-MAP :do "the ordered Map path of the untraced build: a field read in the arm of its own match is a plain slot load (no objrt.variantField call in the treap walks), optionOr over mapGet is mapGetOr (no Option box in the loop), no key or field name is interned per node, and the output equals the tracing build's")
fn fixturePath -> String
  "asl/packages/asl-target-llvm/tests/fixtures/qwMap/mapLoop.asl"

fn defineOf code: String head: String -> String
  (match (stringIndexOf code head)
    ((none) "")
    ((some at) (let [(rest (optionOr (stringSlice code at (stringLength code)) ""))]
                 (match (stringIndexOf rest "\n}\n")
                   ((none) rest)
                   ((some end) (optionOr (stringSlice rest 0 end) ""))))))

fn ! build! libs: rc/Libs dir: String mode: String -> (Result (Pair String rc/Captured) String)
  (match (lk/linkEntry! (fixturePath))
    ((err ds) (err (str "links: " (rc/diagText ds))))
    ((ok m) (match (llvm/emitLlvmProgramNativeWith! m (str m.name ".main") mode)
              ((err ds) (err (str "emits in mode " mode ": " (rc/diagText ds))))
              ((ok code)
                (let [(ll (str dir "/mapLoop." mode ".ll")) (exe (str dir "/mapLoop." mode))]
                  (match (fileWrite ll code)
                    ((err e) (err (str "cannot write " ll ": " e)))
                    ((ok _) (let [(linked (rc/sh (rc/linkCmd libs mode ll exe)))]
                              (if (!= linked.exitCode 0)
                                (err (str mode " links: " linked.stderr))
                                (ok (pair code (rc/sh (str (rc/shellQuote exe) " 20000")))))))))))))

fn ! clean dir: String -> Bool
  (let [(names (resultOr (dirList dir) (list)))]
    (do (fold (fn [(acc Bool) (n String)] -> Bool (and (ok? (pathRemove (str dir "/" n))) acc)) true names)
        (ok? (pathRemove dir))))

fn ! checkIr code: String -> Bool
  (let [(get (defineOf code "define tailcc %Val @prelude$2EpreludeTreeGet("))
        (has (defineOf code "define tailcc i1 @prelude$2EpreludeTreeHas$3F("))
        (churn (defineOf code "define tailcc %Val @mapLoop$2Echurn("))]
    (do (assert (!= get "") "the Get walk is in the program")
        (assert (!= has "") "the Has walk is in the program")
        (assert (!= churn "") "the churn loop is in the program")
        (refute (stringContains? get "@objrt.variantField") "Get reads its node fields with no slow call")
        (refute (stringContains? has "@objrt.variantField") "Has reads its node fields with no slow call")
        (refute (stringContains? code "call %Val @objrt.variantField") "no match arm of the program calls objrt.variantField")
        (assert (stringContains? churn "@prelude$2EmapGetOr(") "churn reads with mapGetOr")
        (refute (stringContains? churn "@prelude$2EmapGet(") "churn builds no Option from mapGet")
        (refute (stringContains? churn "@prelude$2EoptionOr(") "churn calls no optionOr")
        (refute (stringContains? get "call i32 @aslInternShared") "Get interns nothing per node")
        (refute (stringContains? has "call i32 @aslInternShared") "Has interns nothing per node")
        (refute (stringContains? churn "call i32 @aslInternShared") "churn interns nothing per element")
        (assert (stringContains? code "define internal %Val @opsrt.keyCmpSlow(") "String and mixed keys keep one slow compare")
        true))

fn ! runTests -> Bool
  (let [(dir (str (optionOr (envGet "TMPDIR") "/tmp") "/qwMapTest." (procSelf) "." (monotonicNs)))
        (made (dirCreate dir))]
    (do (assert (ok? made) "work directory created")
        (match (rc/runtimes!)
          ((err e) (assert false (str "runtimes: " e)))
          ((ok libs)
            (match (build! libs dir "0")
              ((err e) (assert false e))
              ((ok traced)
                (let [(oracle (pairSecond traced).stdout)]
                  (do (assert (= (pairSecond traced).exitCode 0) (str "tracing exits 0: " (pairSecond traced).stderr))
                      (assert (stringContains? oracle "16 ") (str "tracing prints the map row: " oracle))
                      (fold (fn [(acc Bool) (mode String)] -> Bool
                              (match (build! libs dir mode)
                                ((err e) (do (assert false e) false))
                                ((ok built)
                                  (let [(run (pairSecond built))]
                                    (do (assert (= run.exitCode 0) (str mode " exits 0: " run.stderr))
                                        (assert (= run.stdout oracle) (str mode " prints what tracing prints: " run.stdout " want " oracle))
                                        (refute (stringContains? run.stderr "Sanitizer") (str mode " reads no released node: " run.stderr))
                                        (assert (checkIr (pairFirst built)) (str mode " IR"))
                                        acc)))))
                            true (list "notrace" "asanNotrace"))))))))
        (assert (clean dir) "work directory removed")
        true))
