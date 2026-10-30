(module asl-target-llvm/tests/closureSpecTest
  :x [runTests]
  :i [(asl-ir/link :a lk)
      (asl-target-llvm :a llvm)
      (asl-target-llvm/ssa :a ssa)
      (asl-target-llvm/tests/rcTest :a rc)])

fn fixture -> String
  "asl/packages/asl-target-llvm/tests/fixtures/closureSpec/closureSpec.asl"

; (:m :ref CLOSPEC :do "worked out by hand from the fixture, so it does not depend on either build; the unspecialised build prints the same")
fn expected -> String
  (stringJoin (list "foldCap 135" "foldHeapCap 38" "mapCap 10,11,12,13,14" "filterCap 7,8,9" "nested 10,20,30"
                    "e0" "e1" "e2" "effects 3" "heapList a!3,bb!3,ccc!3" "applyN 63" "stored 42" "picked -6" "pickFold 594" "shared 19" "long 100000"
                    "genPlain 55" "genCap 510" "genHeapCap 14" "g0" "g1" "g2" "genEffects 3" "arrFold 30" "arrScan 20" "rounds 160" "roundsLoop 160"
                    "loops 135 10,11,12,13,14 7,8,9 510 30 20" "")
              "\n")

fn sym name: String -> String
  (str "@" (ssa/llvmName name))

; (:m :do "the lines of the function the text defines under symbol s, from its define line to its closing brace")
fn bodyOf text: String s: String -> (List String)
  (pairSecond
    (fold (fn [(acc (Pair Int64 (List String))) (l String)] -> (Pair Int64 (List String))
            (cond
              ((= (pairFirst acc) 2) acc)
              ((= (pairFirst acc) 1) (if (= l "}") (pair 2 (pairSecond acc)) (pair 1 (listAppend (pairSecond acc) (list l)))))
              ((and (stringStartsWith? l "define ") (stringContains? l (str s "("))) (pair 1 (list l)))
              (else acc)))
          (pair 0 (list)) (stringLines text)))

fn symbolsIn line: String -> (List String)
  (map (fn [(part String)] -> String (str "@" (optionOr (listHead (stringSplit part "(")) "")))
       (optionOr (listTail (stringSplit line "@")) (list)))

fn calleesOf body: (List String) -> (List String)
  (listFlatMap (fn [(l String)] -> (List String) (if (stringContains? l " call ") (symbolsIn l) (list))) (optionOr (listTail body) (list)))

; (:m :do "the module functions a loop reaches from the function under s through calls, a few levels deep, the runtime's own helpers aside")
fn reach text: String names: (List String) depth: Int64 -> (List String)
  (if (<= depth 0)
    names
    (let [(more (fold (fn [(acc (List String)) (n String)] -> (List String)
                        (fold (fn [(a (List String)) (c String)] -> (List String)
                                (if (or (listContains? a c) (listEmpty? (bodyOf text c))) a (listAppend a (list c))))
                              acc (calleesOf (bodyOf text n))))
                      names names))]
      (if (= (listLength more) (listLength names)) names (reach text more (- depth 1)))))

fn closureCall? l: String -> Bool
  (or (stringContains? l "@objrt.call(") (stringContains? l "@aslRcCallOwned"))

fn ! loopFree text: String mode: String name: String -> Bool
  (let [(root (sym (str "closureSpec." name)))
        (fns (reach text (list root) 3))
        (calling (filter (fn [(s String)] -> Bool (listAny? closureCall? (bodyOf text s))) fns))]
    (do (assert (> (listLength (bodyOf text root)) 0) (str mode " " name ": the fixture function is emitted"))
        (assert (> (listLength fns) 1) (str mode " " name ": the loop calls a module function"))
        (assert (listEmpty? calling) (str mode " " name ": no function the loop reaches calls a closure through objrt.call or aslRcCallOwned: " (stringJoin calling " ")))
        true))

fn loops -> (List String)
  (list "foldLoop" "genLoop" "arrFoldLoop" "scanLoop")

fn ! emitted mode: String -> (Result String String)
  (match (lk/linkEntry! (fixture))
    ((err ds) (err (str "fixture links: " (rc/diagText ds))))
    ((ok m) (match (llvm/emitLlvmProgramNativeWith! m (str m.name ".main") mode)
              ((err ds) (err (str "fixture emits in mode " mode ": " (rc/diagText ds))))
              ((ok code) (ok code)))))

; (:m :ref CLOSPEC :do "the fold, Generate, Fold and Scan loops of the fixture call their lambda directly under tracing and under RC: none of the functions they reach makes a closure call")
fn ! testIr -> Bool
  (fold (fn [(acc Bool) (mode String)] -> Bool
          (match (emitted mode)
            ((err e) (do (assert false e) false))
            ((ok text) (and acc (listAll? (fn [(n String)] -> Bool (loopFree text mode n)) (loops))))))
        true (list "0" "notrace"))

fn ! buildExe! libs: rc/Libs dir: String mode: String -> (Result String String)
  (match (emitted mode)
    ((err e) (err e))
    ((ok code)
      (let [(ll (str dir "/closureSpec." mode ".ll"))
            (exe (str dir "/closureSpec." mode))]
        (match (fileWrite ll code)
          ((err e) (err (str "cannot write " ll ": " e)))
          ((ok _) (let [(linked (rc/sh (rc/linkCmd libs mode ll exe)))]
                    (if (!= linked.exitCode 0) (err (str "fixture " mode " links: " linked.stderr)) (ok exe))))))))

; (:m :ref LLVM-NODE2-REDS-B :do "the three arrays Fold and Scan pin are never freed and the run asserts that count itself (large - largeFreed = 3, pinned = 3); LeakSanitizer is on by default on Linux and not on macOS arm64, so under ASan the exit-time leak report is switched off there while address and undefined-behaviour errors still report")
fn leakEnv mode: String -> String
  (if (= mode "asanNotrace") "ASAN_OPTIONS=detect_leaks=0 " "")

; (:m :ref CLOSPEC :do "specialised calls compute what the closure calls computed, captures, nested lambdas and effects in order included, under tracing, RC and RC with ASan")
fn ! testRun libs: rc/Libs dir: String -> Bool
  (fold (fn [(acc Bool) (mode String)] -> Bool
          (match (buildExe! libs dir mode)
            ((err e) (do (assert false e) false))
            ((ok exe) (let [(r (rc/sh (str (leakEnv mode) (rc/shellQuote exe))))]
                        (do (assert (= r.exitCode 0) (str mode " exits 0: " r.stderr))
                            (assert (= r.stdout (expected)) (str mode " output: " r.stdout))
                            (refute (stringContains? r.stderr "Sanitizer") (str mode " ASan reports nothing: " r.stderr))
                            (if (= mode "0") true
                              (do (assert (= (- (rc/statOf r.stderr "large") (rc/statOf r.stderr "largeFreed")) 3) (str mode ": every generated array is freed, only the three arrays Fold and Scan pin (as before) stay: " r.stderr))
                                  (assert (= (rc/statOf r.stderr "pinned") 3) (str mode ": nothing else is pinned: " r.stderr))
                                  true))
                            acc)))))
        true (list "0" "notrace" "asanNotrace"))

fn ! clean dir: String -> Bool
  (do (map (fn [(e String)] -> Bool (ok? (pathRemove (str dir "/" e)))) (resultOr (dirList dir) (list)))
      (ok? (pathRemove dir)))

fn ! runTests -> Bool
  (let [(dir (str (optionOr (envGet "TMPDIR") "/tmp") "/closureSpecTest." (procSelf) "." (monotonicNs)))
        (made (dirCreate dir))]
    (do (assert (ok? made) "work directory created")
        (assert (testIr) "the fixture loops call their lambdas directly")
        (match (rc/runtimes!)
          ((err e) (assert false (str "runtimes: " e)))
          ((ok libs) (assert (testRun libs dir) "specialised loops print what the closure calls printed")))
        (clean dir)
        true))
