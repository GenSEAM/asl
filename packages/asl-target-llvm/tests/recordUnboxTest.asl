(module asl-target-llvm/tests/recordUnboxTest
  :x [runTests]
  :i [(asl-ir/link :a lk)
      (asl-target-llvm :a llvm)
      (asl-target-llvm/tests/rcTest :a rct)])

(schema Run
  (:f code String)
  (:f out rct/Captured))

fn fixture name: String -> String
  (str "asl/packages/asl-target-llvm/tests/fixtures/recordUnbox/" name ".asl")

; (:m :ref UNBOXFIELDS :do "outputs of the fixtures as bin/asl run prints them on the base tree (0646a6d62, boxed records); the native builds must print the same bytes")
fn wantSoa -> String
  (str "sums 31495500 121483500\n"
       "first {:a 8998 :b 20995 :c 32992 :d 38991}\n"
       "eq true true\n")

fn wantMixed -> String
  (str "ids 15\n"
       "ratios 3.75\n"
       "oks 2\n"
       "1|m1|0.25|t,1|false 2|m2|0.5|t,2|true 3|m3|0.75|t,3|false 4|m4|1.0|t,4|true 5|m5|1.25|t,5|false\n"
       "record {:id 3 :name \"m3\" :ratio 0.75 :tags (\"t\" \"3\") :ok false}\n"
       "permuted {:id 21 :name \"p\" :ratio 2.5 :tags () :ok true} 21|p|2.5||true\n"
       "with 42|m3|0.75|t,3|false 3|renamed|0.75|t,3|false {:id 42 :name \"m3\" :ratio 0.75 :tags (\"t\" \"3\") :ok false}\n"
       "dyn 11|dyn|1.5||true {:id 11 :name \"dyn\" :ratio 1.5 :tags () :ok true}\n"
       "fallback {:id \"not an int\" :name \"fb\" :ratio 0.5 :tags (\"x\") :ok false} not an int fb 0.5 false\n"
       "fallback typed 0.5 0.75 fb x\n"
       "generic 3 21\n"
       "eq true false true true\n"
       "floats {:x nan :y -0.0 :b true} nan -0.0 true true false 0.0 -0.0\n")

fn wantPar -> String
  (str "par {:x 2 :label \"p1+\" :w 2.0 :on true} {:x 3 :label \"p2+\" :w 4.0 :on false} {:x 4 :label \"p3+\" :w 6.0 :on true} {:x 5 :label \"p4+\" :w 8.0 :on false}\n"
       "fields 14 20.0 2\n"
       "typed 20,3,40,5\n"
       "eq true\n")

fn emitted name: String mode: String -> (Result String String)
  (match (lk/linkEntry! (fixture name))
    ((err ds) (err (str name " links: " (rct/diagText ds))))
    ((ok m) (match (llvm/emitLlvmProgramNativeWith! m (str m.name ".main") mode)
              ((err ds) (err (str name " emits in mode " mode ": " (rct/diagText ds))))
              ((ok code) (ok code)))))

fn lines text: String -> (List String)
  (stringSplit text "\n")

; (:m :do "the i32 stored to +12 right after the first allocation of the given size: the slot count the rc and gc kid scans read")
fn storedCount text: String alloc: String -> Int64
  (let [(ls (lines text))
        (at (listFind (fn [(e (Pair Int64 String))] -> Bool (stringContains? (pairSecond e) alloc)) (enumerate ls)))]
    (match at
      ((none) -1)
      ((some e) (let [(after (listTake (listDrop ls (+ (pairFirst e) 1)) 8))
                      (np (listFind (fn [(l String)] -> Bool (and (stringStartsWith? l "  store i32 ") (stringEndsWith? l ".np"))) after))]
                  (match np
                    ((none) -1)
                    ((some l) (optionOr (stringToInt64 (stringReplace (optionOr (listGet (stringSplit l " ") 4) "") "," "")) -1)))))))

; (:m :do "the lines of the first define whose header names the function")
fn body text: String name: String -> String
  (let [(ls (lines text))
        (at (listFind (fn [(e (Pair Int64 String))] -> Bool (and (stringStartsWith? (pairSecond e) "define ") (stringContains? (pairSecond e) (str name "(")))) (enumerate ls)))]
    (match at
      ((none) "")
      ((some e) (let [(rest (stringJoin (listDrop ls (pairFirst e)) "\n"))]
                  (match (stringIndexOf rest "\n}\n") ((none) rest) ((some j) (optionOr (stringSlice rest 0 j) "")))))))

fn descSym text: String schema: String -> String
  (let [(marker (str schema " = internal global <{"))
        (line (optionOr (listFind (fn [(l String)] -> Bool (and (stringStartsWith? l "@keyIds.") (stringContains? l marker))) (lines text)) ""))]
    (optionOr (listHead (stringSplit line " ")) ""))

fn ! testShape -> Bool
  (match (emitted "soa" "0")
    ((err e) (do (assert false e) false))
    ((ok soa) (match (emitted "mixed" "0")
      ((err e) (do (assert false e) false))
      ((ok mixed)
        (let [(rec (descSym soa "Rec"))
              (mix (descSym mixed "Mix"))
              (permuted (body mixed "fixtures$2FrecordUnbox$2Fmixed$2Epermuted"))
              (lambda (body soa "fixtures$2FrecordUnbox$2Fsoa$2Emain$40lambda0"))]
          (do (assert (stringContains? soa "Rec = internal global <{ i32, i32, [4 x i32], [4 x i32] }> zeroinitializer, align 8") "Rec, four Int64 fields, has a descriptor global")
              (assert (stringContains? soa "(i32 2, i64 56)") "a Rec literal allocates 24 + 4 x 8 = 56 bytes")
              (refute (stringContains? soa "(i32 2, i64 88)") "no Rec literal allocates the boxed 88 bytes")
              (assert (= (storedCount soa "(i32 2, i64 56)") 0) (str "a Rec literal writes nb = 0 boxed slots to +12, got " (storedCount soa "(i32 2, i64 56)")))
              (assert (stringContains? soa (str "store ptr getelementptr inbounds (i8, ptr " rec ", i64 9), ptr ")) "a Rec literal stores its tagged descriptor keys word")
              (assert (stringContains? soa (str "icmp eq ptr ")) "typed Rec reads compare the keys word")
              (assert (stringContains? lambda (str ".g0.is = icmp eq ptr ")) "the fold lambda's untyped r.b read first compares the keys word with a guessed descriptor")
              (assert (stringContains? lambda (str ", " (descTaggedText rec) "\n")) "the guess is the Rec descriptor, the only descriptor schema declaring b")
              (assert (listAny? (fn [(l String)] -> Bool (and (stringContains? l ".g0.valp = getelementptr") (stringEndsWith? l ", i64 32"))) (lines lambda)) "on a hit r.b is one load of the raw word at 24 + 8")
              (assert (hitPathClean lambda) "the hit path of r.b goes from the guess to the join with no key scan and no field-id resolve")
              (assert (stringContains? soa "store i32 33554464, ptr %desc.loc1") "Rec's descriptor init stores loc b = Int tag 2 << 24 | 32")
              (assert (stringContains? mixed "Mix = internal global <{ i32, i32, [5 x i32], [5 x i32] }> zeroinitializer, align 8") "Mix has a descriptor global")
              (assert (stringContains? mixed "(i32 2, i64 80)") "a full Mix literal allocates 24 + 2 x 16 + 3 x 8 = 80 bytes")
              (assert (= (storedCount mixed "(i32 2, i64 80)") 2) (str "a Mix literal writes nb = 2 (name, tags) to +12, got " (storedCount mixed "(i32 2, i64 80)")))
              (assert (stringContains? mixed "store i32 33554488, ptr %desc.loc0") "Mix loc id: Int raw word after both slots at 56")
              (assert (stringContains? mixed "store i32 4278190104, ptr %desc.loc1") "Mix loc name: boxed slot 0 at 24")
              (assert (stringContains? mixed "store i32 50331712, ptr %desc.loc2") "Mix loc ratio: Float raw word at 64")
              (assert (stringContains? mixed "store i32 4278190120, ptr %desc.loc3") "Mix loc tags: boxed slot 1 at 40")
              (assert (stringContains? mixed "store i32 16777288, ptr %desc.loc4") "Mix loc ok: Bool raw word at 72")
              (assert (stringContains? mixed "store i32 2, ptr %desc.nbp") "Mix descriptor nb = 2")
              (assert (offsetOf permuted 0 56) "the permuted literal (lowered to declared order) puts :id, a raw word, after both boxed slots at 56")
              (assert (offsetOf permuted 1 24) "the permuted literal puts :name in boxed slot 0 at 24")
              (assert (offsetOf permuted 2 64) "the permuted literal puts :ratio at 64")
              (assert (offsetOf permuted 3 40) "the permuted literal puts :tags in boxed slot 1 at 40")
              (assert (offsetOf permuted 4 72) "the permuted literal puts :ok at 72")
              (assert (stringContains? mixed ".boxed:\n") "a literal whose Int64 field comes from an Any source has a boxed fallback branch")
              (assert (stringContains? mixed (str "getelementptr inbounds (i8, ptr " mix ", i64 8)")) "the fallback stores the untagged declared keys of the descriptor")
              (assert (stringContains? mixed "(i32 2, i64 104)") "the fallback of a full literal allocates today's 24 + 5 x 16 bytes")
              true))))))

fn offsetOf text: String i: Int64 off: Int64 -> Bool
  (listAny? (fn [(l String)] -> Bool (and (stringContains? l (str ".f" i "p = getelementptr inbounds i8, ptr ")) (stringEndsWith? l (str ", i64 " off)))) (lines text))

; (:m :do "the lines from the first guess label to the first guessed value's branch: they hold no key loop and no field-id load")
fn hitPathClean text: String -> Bool
  (match (stringIndexOf text ".g0:\n")
    ((none) false)
    ((some i) (let [(rest (optionOr (stringSlice text i (stringLength text)) ""))
                    (upto (match (stringIndexOf rest ".g0.v = ") ((none) rest) ((some j) (optionOr (stringSlice rest 0 j) ""))))]
                (and (stringContains? rest ".g0.v = ")
                     (and (not (stringContains? upto "@fieldId")) (not (stringContains? upto ".keyp")))))))

fn descTaggedText sym: String -> String
  (str "getelementptr inbounds (i8, ptr " sym ", i64 9)")

fn ! runLinked libs: rct/Libs dir: String name: String mode: String env: String -> (Result Run String)
  (match (emitted name (if (= mode "stress") "0" mode))
    ((err e) (err e))
    ((ok code)
      (let [(ll (str dir "/" name "." mode ".ll"))
            (exe (str dir "/" name "." mode))]
        (match (fileWrite ll code)
          ((err e) (err (str "cannot write " ll ": " e)))
          ((ok _) (let [(linked (rct/sh (rct/linkCmd libs (if (= mode "stress") "0" mode) ll exe)))]
                    (if (!= linked.exitCode 0)
                      (err (str name " " mode " links: " linked.stderr))
                      (ok (Run :code code :out (rct/sh (str env (rct/shellQuote exe))))))))))))

fn ! checkRun name: String mode: String r: (Result Run String) want: String -> Bool
  (match r
    ((err e) (do (assert false (str name " " mode " build: " e)) false))
    ((ok x) (do (assert (= x.out.exitCode 0) (str name " " mode " exits 0: " x.out.stderr))
                (assert (= x.out.stdout want) (str name " " mode " prints what bin/asl run prints on base; got\n" x.out.stdout))
                (refute (stringContains? x.out.stderr "Sanitizer") (str name " " mode " reports no sanitizer error: " x.out.stderr))
                true)))

; (:m :do "cells held at exit = fresh + reused - freed (reused cells come off the free chain and are freed too) of the RC build on main 6e2c5f45f (boxed records, --rc 1, ASL_RC_STATS=1); the raw layout must not hold more")
fn baseHeld name: String -> Int64
  (cond ((= name "soa") 11) ((= name "mixed") 44) ((= name "par") 46) (else 0))

fn ! checkNative libs: rct/Libs dir: String name: String want: String -> Bool
  (let [(counted (runLinked libs dir name "1" ""))
        (stats (match counted ((ok c) c.out.stderr) ((err _) "")))
        (fresh (rct/statOf stats "fresh")) (reused (rct/statOf stats "reused"))
        (freed (rct/statOf stats "freed"))
        (stuck (rct/statOf stats "stuck"))
        (a (checkRun name "tracing" (runLinked libs dir name "0" "") want))
        (b (checkRun name "rc" counted want))
        (c (checkRun name "asan" (runLinked libs dir name "asan" "") want))
        (d (checkRun name "gcStress" (runLinked libs dir name "stress" "ASL_GC_STRESS=1 ") want))]
    (do (assert (and (> fresh 0) (<= (- (+ fresh reused) freed) (baseHeld name))) (str name " RC holds at most the " (baseHeld name) " cells the boxed layout held at exit: " stats))
        (assert (= stuck 0) (str name " RC leaves no freed cell sticky: " stats))
        (and a (and b (and c d)))))

fn errText r: (Result Run String) -> String
  (match r ((ok _) "ok") ((err e) e))

fn ! runTests -> Bool
  (and (testShape)
       (match (rct/runtimes!)
         ((err e) (do (assert false (str "runtimes: " e)) false))
         ((ok libs) (let [(dir (str (optionOr (envGet "TMPDIR") "/tmp") "/recordUnboxTest." (procSelf) "." (monotonicNs)))
                          (made (dirCreate dir))
                          (soa (checkNative libs dir "soa" (wantSoa)))
                          (mixed (checkNative libs dir "mixed" (wantMixed)))
                          (par (checkNative libs dir "par" (wantPar)))
                          (gone (rct/sh (str "rm -rf " (rct/shellQuote dir))))]
                      (do (assert (ok? made) "work directory created")
                          (assert (= gone.exitCode 0) "work directory removed")
                          (and soa (and mixed par)))))))
