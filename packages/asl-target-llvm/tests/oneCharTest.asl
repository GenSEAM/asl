(module asl-target-llvm/tests/oneCharTest
  :x [runTests]
  :i [(asl-ir/link :a lk)
      (asl-target-llvm :a llvm)
      (asl-target-llvm/tests/rcTest :a rc)])

fn fixture -> String
  "asl/packages/asl-target-llvm/tests/fixtures/oneChar/oneChar.asl"

fn want -> String
  "100000 100000 ab0cdefg\n"

fn table -> String
  "@strrt.one = internal global [6144 x i8]"

fn cellHead -> String
  "define internal %Val @listrt.cell("

fn consCall -> String
  "call ptr @aslRc.allocFastCons("

fn genericCall -> String
  "call ptr @aslRc.alloc("

; (:m :ref QW-ALLOC :do "the body of listrt.cell, the runtime cell of a list literal, from its head to the closing brace")
fn cellBody code: String -> String
  (optionOr (listHead (stringSplit (optionOr (listGet (stringSplit code (cellHead)) 1) "") "\n}")) "")

fn sliceHead -> String
  "define internal %Val @strrt.slice("

; (:m :ref QW-ALLOC :do "the body of strrt.slice, the unfused Option-returning slice")
fn sliceBody code: String -> String
  (optionOr (listHead (stringSplit (optionOr (listGet (stringSplit code (sliceHead)) 1) "") "\n}")) "")

fn literalData -> String
  "c\"define internal ptr @strrt.single(ptr %src) {"

fn singleCall -> String
  "call ptr @strrt.single("

; (:m :ref QW-ALLOC :do "built like listReverseTest: the fixture slices one byte 150000 times per run and joins, maps and folds the pieces; the oracle is the byte length of the joins")
fn ! build! libs: rc/Libs dir: String mode: String -> (Result (Pair String rc/Captured) String)
  (match (lk/linkEntry! (fixture))
    ((err ds) (err (str "fixture links: " (rc/diagText ds))))
    ((ok m) (match (llvm/emitLlvmProgramNativeWith! m (str m.name ".main") mode)
              ((err ds) (err (str "fixture emits in mode " mode ": " (rc/diagText ds))))
              ((ok code)
                (let [(ll (str dir "/oneChar." mode ".ll")) (exe (str dir "/oneChar." mode))]
                  (match (fileWrite ll code)
                    ((err e) (err (str "cannot write " ll ": " e)))
                    ((ok _) (let [(linked (rc/sh (rc/linkCmd libs mode ll exe)))]
                              (if (!= linked.exitCode 0)
                                (err (str "fixture " mode " links: " linked.stderr))
                                (ok (pair code (rc/sh (rc/shellQuote exe)))))))))))))

fn ! outputLines run: rc/Captured -> (List String)
  (stringLines run.stdout)

fn ! testMode libs: rc/Libs dir: String mode: String tabled: Bool -> Bool
  (match (build! libs dir mode)
    ((err e) (do (assert false e) false))
    ((ok built)
      (let [(code (pairFirst built)) (run (pairSecond built)) (lines (outputLines run))]
        (do (assert (= run.exitCode 0) (str mode " exits 0: " run.stderr))
            (assert (= (optionOr (listHead lines) "") (stringTrim (want))) (str mode " joins the one-byte pieces: " run.stdout))
            (assert (= (optionOr (listGet lines 2) "") "100000 100000") (str mode " keeps all pieces after the churn: " run.stdout))
            (assert (stringContains? (optionOr (listGet lines 1) "") "true 0") (str mode " compares equal pieces and reads one back: " run.stdout))
            (assert (= (optionOr (listGet lines 3) "") "3") (str mode " builds a literal list of three: " run.stdout))
            (assert (= (optionOr (listGet lines 4) "") "ef? 45 (some \"define\")") (str mode " slices without fusing and keeps a literal holding the define line: " run.stdout))
            (refute (stringContains? run.stderr "Sanitizer") (str mode " touches no released cell: " run.stderr))
            (assert (stringContains? code (singleCall)) (str mode " slices of length one go through strrt.single"))
            (if tabled
              (do (assert (stringContains? (cellBody code) (consCall)) (str mode " allocates a literal list cell from the cons pool: " (cellBody code)))
                  (refute (stringContains? (cellBody code) (genericCall)) (str mode " keeps the sized allocator out of the list cell")))
              ())
            (assert (stringContains? (sliceBody code) (singleCall)) (str mode " the unfused slice calls strrt.single in its own body"))
            (assert (stringContains? code (literalData)) (str mode " keeps the user literal that holds the define line"))
            (if tabled
              (assert (stringContains? code (table)) (str mode " carries the static one-byte table"))
              (refute (stringContains? code (table)) (str mode " keeps allocating one-byte cells")))
            true))))

; (:m :ref QW-ALLOC :do "allocations under notraceStats, fresh plus reused: 2318763 when every one-byte slice allocates a cell, 1818760 with the table (500000 slices, 2026-10-26), so the bound sits between")
fn ! testCounts libs: rc/Libs dir: String -> Bool
  (match (build! libs dir "notraceStats")
    ((err e) (do (assert false e) false))
    ((ok built)
      (let [(run (pairSecond built)) (total (+ (rc/statOf run.stderr "fresh") (rc/statOf run.stderr "reused")))]
        (do (assert (= (optionOr (listHead (outputLines run)) "") (stringTrim (want))) (str "notraceStats prints the oracle: " run.stdout))
            (assert (and (> total 0) (< total 2000000)) (str "one-byte slices allocate no string cell: fresh + reused " total " in " run.stderr))
            true))))

fn ! clean dir: String -> Bool
  (let [(names (resultOr (dirList dir) (list)))]
    (do (fold (fn [(acc Bool) (n String)] -> Bool (and (ok? (pathRemove (str dir "/" n))) acc)) true names)
        (ok? (pathRemove dir))))

fn ! runTests -> Bool
  (let [(dir (str (optionOr (envGet "TMPDIR") "/tmp") "/oneCharTest." (procSelf) "." (monotonicNs)))
        (made (dirCreate dir))]
    (do (assert (ok? made) "work directory created")
        (match (rc/runtimes!)
          ((err e) (assert false (str "runtimes: " e)))
          ((ok libs) (do (assert (testMode libs dir "0" false) "tracing build")
                         (assert (testMode libs dir "notrace" true) "untraced RC build")
                         (assert (testMode libs dir "asanNotrace" true) "untraced RC build under ASan")
                         (assert (testCounts libs dir) "untraced RC allocates no cell for a one-byte slice"))))
        (assert (clean dir) "work directory removed")
        true))
