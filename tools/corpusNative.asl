(module asl-tools/corpusNative
  :x [main suitePath assertCount refuteCount passedCount summary nativeArgv clangArgv combineOutput interpreterText sh CorpusProcessOutput]
  :i [(asl-proc/coreProcess :a cp)])

(schema CorpusProcessOutput
  (:f exitCode Int64)
  (:f stdout String)
  (:f stderr String))

fn outDir -> String
  "asl/host/out/corpusNative"

fn binary -> String
  (str (outDir) "/corpusNativeMain")

fn suitePath name: String -> (Option String)
  (cond
    ((stringStartsWith? name "printReparseShard") (some (str "asl/packages/asl-parser/tests/" name ".asl")))
    ((stringStartsWith? name "layoutCorpusShard") (some (str "asl/packages/asl-syntax/tests/asl/" name ".asl")))
    ((= name "symbolsTest") (some "asl/packages/asl-syntax/tests/asl/symbolsTest.asl"))
    ((= name "liftLowerIdentityTest") (some "asl/packages/asl-parser/tests/liftLowerIdentityTest.asl"))
    ((= name "asnTest") (some "asl/packages/asl-syntax/tests/asl/asnTest.asl"))
    ((= name "corpusTest") (some "asl/packages/asl-syntax/tests/core/corpusTest.asl"))
    (else (none)))

fn allSuites -> (List String)
  (list "printReparseShard1Test" "printReparseShard2Test" "printReparseShard3Test" "printReparseShard4Test"
        "printReparseShard5Test" "printReparseShard6Test" "printReparseShard7Test" "printReparseShard8Test"
        "layoutCorpusShard1Test" "layoutCorpusShard2Test" "layoutCorpusShard3Test" "layoutCorpusShard4Test"
        "symbolsTest" "liftLowerIdentityTest" "asnTest" "corpusTest")

fn countLine text: String -> (Option String)
  (listHead (filter (fn [(l String)] -> Bool (stringContains? l " assertion(s) executed")) (stringLines text)))

fn countBefore text: String marker: String -> (Option Int64)
  (match (countLine text)
    ((none) (none))
    ((some l) (if (stringContains? l marker)
                (let [(words (stringSplit (optionOr (listHead (stringSplit l marker)) "") " "))]
                  (match (listGet words (- (listLength words) 1))
                    ((none) (none))
                    ((some w) (stringToInt64 w))))
                (none))))

fn assertCount text: String -> (Option Int64)
  (countBefore text " assertion(s) executed")

fn refuteCount text: String -> Int64
  (optionOr (countBefore text " refutation(s) executed") 0)

fn summary asserts: Int64 refutes: Int64 -> String
  (str asserts " assertion(s) executed" (if (> refutes 0) (str ", " refutes " refutation(s) executed") "") " (" (+ asserts refutes) " passed)")

fn passedCount text: String -> (Option Int64)
  (match (countLine text)
    ((none) (none))
    ((some l) (match (stringIndexOf l "executed (")
                ((none) (none))
                ((some i) (stringToInt64 (optionOr (listHead (stringSplit (optionOr (stringSlice l (+ i 10) (stringLength l)) "") " passed)")) ""))))))

fn seconds ns: Int64 -> String
  (let [(ms (/ ns 1000000))]
    (str (/ ms 1000) "." (/ (mod ms 1000) 100) "s"))

fn tailOf text: String -> String
  (let [(lines (stringLines text))
        (n (listLength lines))]
    (stringJoin (optionOr (listSlice lines (if (> n 6) (- n 6) 0) n) (list)) "\n"))

fn ! sh argv: (List String) -> CorpusProcessOutput
  (let [(bin (optionOr (listHead argv) ""))
        (args (optionOr (listTail argv) (list)))
        (cmd (cp/withTimeout (cp/cmd bin args) 1800000))]
    (match (cp/execRaw! cmd)
      ((err e) (CorpusProcessOutput :exitCode 127 :stdout "" :stderr (str e)))
      ((ok out) (CorpusProcessOutput :exitCode out.exitCode :stdout out.stdout :stderr out.stderr))))

fn clangArgv clang: String ll: String out: String -> (List String)
  (listAppend (listAppend (list "nice" "-n" "15") (filter (fn [(w String)] -> Bool (not (stringEmpty? w))) (stringSplit clang " ")))
              (list "-O2" "-Wno-override-module" "-x" "ir" ll "-x" "none" "asl/host/out/libaslrt.a" "-lm" "-o" out))

; (:m :ref HL-FIXWAVE :do "both spawns in this file used to hardcode asl/host/out/asl-host, the stage-0 interpreter HL-DELETE retired for good; bin/asl (the native CLI launcher) is the only thing left that can run asl1.asl or any other module, so this now compares native-vs-native rather than interpreter-vs-native -- the same substitution already made in frozen.asn's HL-DELETE note for resolveHost! across tests/host/parTest.asl and others")
fn ! build -> Bool
  (let [(clang (optionOr (envGet "CLANG") "clang"))
        (ll (str (outDir) "/corpusNativeMain.ll"))
        (made (sh (list "mkdir" "-p" (outDir))))
        (t0 (monotonicNs))
        (compiled (sh (list "nice" "-n" "15" "bin/asl" "run" "asl/packages/asl-compiler/src/asl1.asl" "build" "tools/corpusNativeMain.asl" "-o" ll)))
        (t1 (monotonicNs))]
    (cond
      ((!= made.exitCode 0) (do (eprintln (str "cannot create " (outDir) ": " made.stderr)) false))
      ((!= compiled.exitCode 0) (do (eprintln (str "asl1 build tools/corpusNativeMain.asl failed (exit " compiled.exitCode "):\n" compiled.stderr)) false))
      (else
        (let [(linked (sh (clangArgv clang ll (binary))))]
          (if (= linked.exitCode 0)
            (do (println (str "built " (binary) ": asl1 " (seconds (- t1 t0)) ", clang " (seconds (- (monotonicNs) t1)))) true)
            (do (eprintln (str "clang could not link " ll ":\n" linked.stderr)) false))))))

fn nativeArgv name: String -> (List String)
  (list "env" "ASL_ASSERT_REPORT=1" "ASL_PRELUDE=asl/host/out/prelude.asl" "nice" "-n" "15" (binary) name)

fn combineOutput stdout: String stderr: String -> String
  (if (stringEmpty? stderr) stdout (str stdout (if (stringEmpty? stdout) "" "\n") stderr))

fn interpreterText out: CorpusProcessOutput -> String
  (combineOutput out.stdout out.stderr)

fn ! runNative name: String -> (Option (Pair Int64 Int64))
  (let [(t0 (monotonicNs))
        (out (sh (nativeArgv name)))
        (took (seconds (- (monotonicNs) t0)))
        (n (assertCount out.stderr))
        (r (refuteCount out.stderr))]
    (if (and (= out.exitCode 0) (some? n))
      (do (println (str name ": " (summary (optionOr n 0) r) " native " took)) (some (pair (optionOr n 0) r)))
      (do (println (str "FAIL " name ": native exit " out.exitCode " after " took "\n" (tailOf out.stderr))) (none))))

fn ! runInterpreter name: String path: String native: (Pair Int64 Int64) -> Bool
  (let [(t0 (monotonicNs))
        (out (sh (list "nice" "-n" "15" "bin/asl" "test" path)))
        (took (seconds (- (monotonicNs) t0)))
        (text (interpreterText out))
        (n (assertCount text))
        (r (refuteCount text))
        (a (pairFirst native))
        (nr (pairSecond native))]
    (cond
      ((or (!= out.exitCode 0) (none? n)) (do (println (str "FAIL " name ": interpreter exit " out.exitCode " after " took "\n" (tailOf text))) false))
      ((and (= n (some a)) (and (= r nr) (= (passedCount text) (some (+ a nr))))) (do (println (str name ": interpreter " (summary a nr) " " took "; counts equal")) true))
      (else (do (println (str "FAIL " name ": interpreter " (optionOr n 0) " asserts, " r " refutes, " (optionOr (passedCount text) 0) " passed; native " (summary a nr))) false))))

fn ! runSuite compare: Bool name: String -> Bool
  (match (suitePath name)
    ((none) (do (println (str "FAIL " name ": not a native corpus suite")) false))
    ((some path) (match (runNative name)
                   ((none) false)
                   ((some n) (if compare (runInterpreter name path n) true)))))

fn ! main args: (List String) -> (Result Int64 String)
  (let [(compare (listContains? args "--compare"))
        (reuse (listContains? args "--reuse"))
        (named (filter (fn [(a String)] -> Bool (not (stringStartsWith? a "--"))) args))
        (names (if (listEmpty? named) (allSuites) named))
        (ready (if (and reuse (ok? (fileStat (binary)))) true (build)))]
    (if ready
      (let [(results (map (fn [(n String)] -> Bool (runSuite compare n)) names))]
        (ok (if (fold (fn [(acc Bool) (r Bool)] -> Bool (and acc r)) true results) 0 1)))
      (ok 1)))
