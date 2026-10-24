(module asl-target-llvm/tests/strContainsTest
  :x [runTests]
  :i [(asl-ir/link :a lk)
      (asl-target-llvm :a llvm)
      (asl-target-llvm/tests/rcTest :a rc)])

fn fixture -> String
  "asl/packages/asl-target-llvm/tests/fixtures/strContains/strContains.asl"

; (:m :ref STRRT-CONTAINS-MEMMEM :do "oracle for the 25 (haystack needle) cases of the fixture, derived from the String semantics and equal to what the pre-memmem memcmp loop printed on base 24b712c16: empty needle true, longer needle false, start/end/absent, repeated prefix, NUL bytes, UTF-8")
fn caseWant -> String
  "1100111100101101001011000"

fn bigWant -> String
  "len 33554432\nabsent 0\nabsentLong 0\natEnd 20\natStart 20\nnearEnd 0\n"

fn ! build! libs: rc/Libs dir: String mode: String -> (Result String String)
  (match (lk/linkEntry! (fixture))
    ((err ds) (err (str "fixture links: " (rc/diagText ds))))
    ((ok m) (match (llvm/emitLlvmProgramNativeWith! m (str m.name ".main") mode)
              ((err ds) (err (str "fixture emits in mode " mode ": " (rc/diagText ds))))
              ((ok code)
                (let [(ll (str dir "/strContains." mode ".ll")) (exe (str dir "/strContains." mode))]
                  (match (fileWrite ll code)
                    ((err e) (err (str "cannot write " ll ": " e)))
                    ((ok _) (let [(linked (rc/sh (rc/linkCmd libs mode ll exe)))]
                              (if (!= linked.exitCode 0) (err (str "fixture " mode " links: " linked.stderr)) (ok exe))))))))))

; (:m :ref STRCONTAINS-TEST-NOWALL :do "the emitted program routes @strrt.contains through libc memmem; asserted on the .ll text instead of a wall-clock bound, which flaked under load")
fn memmemCall -> String
  "call ptr @memmem(ptr %xText, i64 %x.len, ptr %yText, i64 %y.len)"

fn ! testMode libs: rc/Libs dir: String mode: String -> Bool
  (match (build! libs dir mode)
    ((err e) (do (assert false e) false))
    ((ok exe)
      (let [(small (rc/sh (rc/shellQuote exe)))
            (big (rc/sh (str (rc/shellQuote exe) " big")))
            (ll (resultOr (fileReadString (str dir "/strContains." mode ".ll")) ""))]
        (do (assert (= small.exitCode 0) (str mode " cases exit 0: " small.stderr))
            (assert (= small.stdout (str (caseWant) "\n")) (str mode " cases match the oracle: " small.stdout))
            (assert (= big.exitCode 0) (str mode " big scan exit 0: " big.stderr))
            (assert (= big.stdout (bigWant)) (str mode " big scan answers: " big.stdout))
            (assert (stringContains? ll (memmemCall)) (str mode " strrt.contains calls memmem in the emitted program"))
            true))))

fn ! clean dir: String -> Bool
  (let [(names (resultOr (dirList dir) (list)))]
    (do (fold (fn [(acc Bool) (n String)] -> Bool (and (ok? (pathRemove (str dir "/" n))) acc)) true names)
        (ok? (pathRemove dir))))

fn ! runTests -> Bool
  (let [(dir (str (optionOr (envGet "TMPDIR") "/tmp") "/strContainsTest." (procSelf) "." (monotonicNs)))
        (made (dirCreate dir))]
    (do (assert (ok? made) "work directory created")
        (match (rc/runtimes!)
          ((err e) (assert false (str "runtimes: " e)))
          ((ok libs) (do (assert (testMode libs dir "0") "tracing build")
                         (assert (testMode libs dir "notrace") "untraced RC build"))))
        (assert (clean dir) "work directory removed")
        true))
