(module asl-target-llvm/tests/linuxLayoutGateTest
  :x [runTests]
  :i [(asl-target-llvm/libc :a lc)])

fn ! sh cmd: String -> ProcessOutput
  (processRun cmd)

fn tripleStrategy unameS: String unameM: String platform: String dockerUp: Bool -> String
  (let [(hostPlatform
          (if (= unameS "Linux")
            (cond
              ((or (= unameM "x86_64") (= unameM "amd64")) "linux/amd64")
              ((or (= unameM "aarch64") (= unameM "arm64")) "linux/arm64")
              (else ""))
            ""))]
    (cond
      ((= hostPlatform platform) "native")
      (dockerUp "docker")
      (else "missingDocker")))


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

fn ! dockerDaemonUp? -> Bool
  (= (sh "docker info").exitCode 0)

fn ! hostUnameS -> String
  (stringTrim (sh "uname -s").stdout)

fn ! hostUnameM -> String
  (stringTrim (sh "uname -m").stdout)

fn ! probeSrcAbs -> String
  (str (stringTrim (sh "pwd").stdout) "/" (probeSrc))

fn ! probeNative -> ProcessOutput
  (sh (str "cc -std=c11 -Wall -Wextra -o /tmp/linuxLayoutGateNativeProbe " (probeSrcAbs) " && /tmp/linuxLayoutGateNativeProbe"))

fn ! probeInDocker platform: String -> ProcessOutput
  (sh (str "docker run --rm --platform " platform " -v \"" (probeSrcAbs) ":/src/libcProbe.c:ro\" -w /tmp gcc:14 sh -c \"cp /src/libcProbe.c . && gcc -std=c11 -Wall -Wextra -o probe libcProbe.c && ./probe\""))

fn ! runOneTriple platform: String facts: lc/TripleFacts strategy: String -> Int64
  (if (= strategy "missingDocker")
    (do (assert false (str facts.triple ": docker is required (host is not this triple) but `docker info` failed: is Docker running?"))
        -1)
    (let [(label facts.triple)
          (t0 (monotonicNs))
          (out (if (= strategy "native") (probeNative) (probeInDocker platform)))
          (elapsedSec (/ (- (monotonicNs) t0) 1000000000))]
      (do (assert (= out.exitCode 0)
            (str label ": " strategy " build+run of libcProbe.c; stderr: " out.stderr))
          (let [(probed (parseProbeOutput out.stdout))]
            (do (assert (> (listLength probed) 0) (str label ": probe produced output"))
                (assertOneConst probed "errnoAccessorMatchesMacro" 1)
                (assertConstsMatch probed facts.consts)
                (assertStructsMatch probed facts.structs)))
          elapsedSec)))

fn ! runTests -> Bool
  (let [(hostS (hostUnameS))
        (hostM (hostUnameM))
        (dockerUp (dockerDaemonUp?))
        (arm64Strategy (tripleStrategy hostS hostM "linux/arm64" dockerUp))
        (amd64Strategy (tripleStrategy hostS hostM "linux/amd64" dockerUp))
        (arm64Sec (runOneTriple "linux/arm64" (lc/linuxAarch64Facts) arm64Strategy))
        (amd64Sec (runOneTriple "linux/amd64" (lc/linuxX8664Facts) amd64Strategy))]
    (do (assert (>= arm64Sec 0) (str "linux-aarch64 (" arm64Strategy "): " (stringFromInt64 arm64Sec) "s"))
        (assert (>= amd64Sec 0) (str "linux-x86_64 (" amd64Strategy "): " (stringFromInt64 amd64Sec) "s"))
        true))
