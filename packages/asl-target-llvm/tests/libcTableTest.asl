(module asl-target-llvm/tests/libcTableTest
  :x [runTests]
  :i [(asl-target-llvm/libc :a lc)])

fn clang -> String
  "/usr/bin/clang"

fn ! sh cmd: String -> ProcessOutput
  (processRun cmd)

fn probeSrc -> String
  "asl/packages/asl-target-llvm/tests/fixtures/libcProbe.c"

fn parseProbeLine line: String -> (Option (Pair String Int64))
  (let [(parts (stringSplit line "="))]
    (if (= (listLength parts) 2)
      (optionMap
        (fn [(v Int64)] -> (Pair String Int64) (pair (optionOr (listGet parts 0) "") v))
        (stringToInt64 (optionOr (listGet parts 1) "")))
      (none)))

fn parseProbeOutput out: String -> (List (Pair String Int64))
  (fold
    (fn [(acc (List (Pair String Int64))) (line String)] -> (List (Pair String Int64))
      (let [(parsed (parseProbeLine line))]
        (if (some? parsed) (cons (optionOr parsed (pair "" 0)) acc) acc)))
    (list)
    (stringLines out))

fn hexValue digits: (List String) acc: Int64 -> (Option Int64)
  (match (listHead digits)
    ((none) (some acc))
    ((some d) (match (stringIndexOf "0123456789abcdef" (stringLower d))
      ((none) (none))
      ((some k) (hexValue (optionOr (listTail digits) (list)) (+ (* acc 16) k))))))

fn macroValue text: String -> (Option Int64)
  (if (and (stringStartsWith? text "0x") (> (stringLength text) 2))
    (hexValue (stringChars (optionOr (stringSlice text 2 (stringLength text)) "")) 0)
    (stringToInt64 text))

fn parseMacroLine line: String -> (Option (Pair String Int64))
  (let [(parts (stringSplit line " "))]
    (if (and (= (listLength parts) 3) (= (optionOr (listHead parts) "") "#define"))
      (optionMap (fn [(v Int64)] -> (Pair String Int64) (pair (optionOr (listGet parts 1) "") v)) (macroValue (optionOr (listGet parts 2) "")))
      (none)))

; (:m :ref RETIRED-PROBES :do "table names by typedef whose layout clang reads from the headers, so no probe C grows for them")
fn headerRecords -> (List (Pair String String))
  (list (pair "struct __siginfo" "siginfo_t") (pair "struct __darwin_sigaltstack" "stack_t"))

fn layoutStep state: (Pair String (List (Pair String Int64))) line: String -> (Pair String (List (Pair String Int64)))
  (let [(cur (pairFirst state)) (acc (pairSecond state))]
    (match (stringIndexOf line "|")
      ((none) state)
      ((some k) (let [(left (stringTrim (optionOr (stringSlice line 0 k) "")))
                      (right (optionOr (stringSlice line (+ k 1) (stringLength line)) ""))
                      (body (stringTrim right))]
        (cond
          ((stringStartsWith? body "[sizeof=")
            (if (stringEmpty? cur) state
              (match (stringToInt64 (optionOr (listHead (stringSplit (optionOr (stringSlice body 8 (stringLength body)) "") ",")) ""))
                ((none) state)
                ((some n) (pair "" (cons (pair (str "sizeof_" cur) n) acc))))))
          ((and (stringStartsWith? right " ") (not (stringStartsWith? right "  ")))
            (pair (optionOr (lc/pairFind (headerRecords) body) "") acc))
          ((and (not (stringEmpty? cur)) (and (stringStartsWith? right "   ") (not (stringStartsWith? right "    "))))
            (match (stringToInt64 left)
              ((none) state)
              ((some off) (pair cur (cons (pair (str cur "." (optionOr (listLast (stringSplit body " ")) "")) off) acc)))))
          (else state))))))

; (:m :ref RETIRED-PROBES :do "signal.h constants and record layouts the stack guard needs, measured by clang itself: macros by -dM, layouts by -fdump-record-layouts-complete")
fn ! headerFacts! -> (List (Pair String Int64))
  (let [(macros (sh (str (clang) " -E -dM -x c -include signal.h /dev/null")))
        (layouts (sh (str (clang) " -x c -fsyntax-only -Xclang -fdump-record-layouts-complete -include signal.h /dev/null")))
        (defined (fold (fn [(acc (List (Pair String Int64))) (line String)] -> (List (Pair String Int64))
                         (match (parseMacroLine line) ((some p) (cons p acc)) ((none) acc)))
                       (list) (stringLines macros.stdout)))
        (laid (pairSecond (fold layoutStep (pair "" (list)) (stringLines layouts.stdout))))]
    (do (assert (= macros.exitCode 0) (str "clang -dM lists signal.h macros: " macros.stderr))
        (assert (= layouts.exitCode 0) (str "clang dumps signal.h record layouts: " layouts.stderr))
        (assert (some? (lc/pairFind laid "stack_t.ss_flags")) "the layout dump has stack_t's fields")
        (listAppend defined laid)))

fn assertOneConst probed: (List (Pair String Int64)) name: String want: Int64 -> Bool
  (let [(gotOpt (lc/pairFind probed name))]
    (assert (some? gotOpt) (str "probe reports " name))
    (assert (= (optionOr gotOpt -1) want)
      (str name ": table says " (stringFromInt64 want) ", probe says " (stringFromInt64 (optionOr gotOpt -1))))
    true)

fn assertConstsMatch probed: (List (Pair String Int64)) expected: (List (Pair String Int64)) -> Bool
  (fold
    (fn [(acc Bool) (p (Pair String Int64))] -> Bool
      (and acc (assertOneConst probed (pairFirst p) (pairSecond p))))
    true
    expected)

fn assertOneField probed: (List (Pair String Int64)) structName: String fieldPair: (Pair String Int64) -> Bool
  (let [(fieldName (str structName "." (pairFirst fieldPair))) (want (pairSecond fieldPair)) (gotOpt (lc/pairFind probed fieldName))]
    (assert (some? gotOpt) (str "probe reports " fieldName))
    (assert (= (optionOr gotOpt -1) want)
      (str fieldName ": table says " (stringFromInt64 want) ", probe says " (stringFromInt64 (optionOr gotOpt -1))))
    true)

fn assertStructMatch probed: (List (Pair String Int64)) structName: String sf: lc/StructFacts -> Bool
  (let [(sizeOk (assertOneConst probed (str "sizeof_" structName) sf.size))]
    (fold
      (fn [(acc Bool) (fp (Pair String Int64))] -> Bool
        (and acc (assertOneField probed structName fp)))
      sizeOk
      sf.fields))

fn assertStructsMatch probed: (List (Pair String Int64)) structs: (List (Pair String lc/StructFacts)) -> Bool
  (fold
    (fn [(acc Bool) (sp (Pair String lc/StructFacts))] -> Bool
      (and acc (assertStructMatch probed (pairFirst sp) (pairSecond sp))))
    true
    structs)

fn ! writeSnippet work: String name: String src: String -> Bool
  (ok? (fileWrite (str work "/" name ".c") src))

fn ! compiles? work: String name: String -> Bool
  (= (sh (str (clang) " -std=c11 -fsyntax-only " work "/" name ".c")).exitCode 0)

fn ! assertVariadicProbe facts: lc/TripleFacts work: String -> Bool
  (let [(openWant (optionOr (lc/pairFind facts.variadic "open") false))
        (flockWant (optionOr (lc/pairFind facts.variadic "flock") false))]
    (assert (= openWant true) "table says open is variadic (sanity: the probe below assumes this)")
    (assert (= flockWant false) "table says flock is not variadic (sanity: the probe below assumes this)")
    (assert (writeSnippet work "variadicOpen"
              "#include <fcntl.h>\nint main(void){ return open(\"/tmp/libcProbeVariadicCheck\", O_RDONLY, 0644, 0); }\n")
      "write variadicOpen.c")
    (assert (writeSnippet work "variadicFlock"
              "#include <sys/file.h>\nint main(void){ return flock(0, LOCK_SH, 0); }\n")
      "write variadicFlock.c")
    (assert (compiles? work "variadicOpen") "open(path, flags, ...) is variadic: an extra argument still compiles")
    (assert (not (compiles? work "variadicFlock")) "flock(fd, op) is fixed-arity: an extra argument is a compile error")
    true)

fn ! runTests -> Bool
  (let [(made (sh "mktemp -d"))]
    (assert (= made.exitCode 0) "mktemp -d makes a work directory")
    (let [(work (stringTrim made.stdout))]
      (let [(built (sh (str (clang) " -std=c11 -Wall -Wextra -o " work "/libcProbe " (probeSrc))))]
        (assert (= built.exitCode 0) (str "clang builds libcProbe: " built.stderr))
        (let [(ran (sh (str work "/libcProbe")))]
          (assert (= ran.exitCode 0) (str "libcProbe runs: " ran.stderr))
          (let [(probed (listAppend (headerFacts!) (parseProbeOutput ran.stdout))) (facts (lc/darwinArm64Facts))]
            (assert (> (listLength probed) 0) "probe produced output")
            (assert (lc/libcVerified "darwin-arm64") "darwin-arm64 is the measured row")
            (assert (= facts.triple "darwin-arm64") "darwinArm64Facts.triple")
            (assert (some? (lc/libcFacts "darwin-arm64")) "libcFacts resolves darwin-arm64")
            (assert (none? (lc/libcFacts "windows-x86_64")) "libcFacts has no row for an unsupported triple")
            (assert (assertConstsMatch probed facts.consts) "O_*/F_*/LOCK_*/errno/_SC_NPROCESSORS_ONLN constants match the probe")
            (assert (assertStructsMatch probed facts.structs) "struct sizes and field offsets match the probe")
            (assert (= facts.errnoAccessor "__error") "darwinArm64Facts.errnoAccessor is __error")
            (assert (= (optionOr (lc/pairFind probed "errnoAccessorMatchesMacro") 0) 1)
              "the probe's own __error() call reads the same storage as the errno macro after a real failure")
            (assertVariadicProbe facts work)
            (let [(x8664Dir (optionOr (lc/libcConst (lc/linuxX8664Facts) "O_DIRECTORY") -1))
                  (aarch64Dir (optionOr (lc/libcConst (lc/linuxAarch64Facts) "O_DIRECTORY") -1))]
              (assert (= x8664Dir 65536) "linux-x86_64 O_DIRECTORY is the asm-generic value 1<<16")
              (assert (= aarch64Dir 16384) "linux-aarch64 O_DIRECTORY is the arch/arm64 override 1<<14, not the generic value")
              (assert (not (= x8664Dir aarch64Dir)) "O_DIRECTORY must not come back from a value shared across both linux triples"))
            (assert (= (sh (str "rm -rf " work)).exitCode 0) "work directory removed")
            true)))))
