(module asl-target-llvm/tests/deepStackTest
  :x [runTests]
  :i [(tools/fleet/run :a run)])

(schema Captured
  (:f exitCode Int64)
  (:f stdout String)
  (:f stderr String))

fn ! shWithin cmd: String timeoutS: Int64 -> Captured
  (let [(base (str (optionOr (envGet "TMPDIR") "/tmp") "/deepStackTest." (monotonicNs)))
        (outPath (str base ".out"))
        (errPath (str base ".err"))
        (done (run/runOneLimited (run/job (list "sh" "-c" (str "(" cmd ") > " outPath " 2> " errPath)) "." (run/childEnv (list)))
                                 (run/limits timeoutS 32)))
        (outText (resultOr (fileReadString outPath) ""))
        (errText (resultOr (fileReadString errPath) ""))
        (_ (pathRemove outPath))
        (_ (pathRemove errPath))]
    (Captured :exitCode done.exit :stdout outText :stderr (if (= done.verdict "exit") errText (str errText done.out))))

fn ! sh cmd: String -> Captured
  (shWithin cmd 120)

; (:m :ref NATIVE-STACK-GUARD :do "beyond-limit case: recursion deep enough to exceed both host's MAX_FRAMES (1048576, asl/host/src/value.h) and native's 1 GiB body-thread stack (rtAbi mainText). Runs as a real subprocess on each side since a stack overflow cannot safely let the same process keep asserting afterward. Before NATIVE-STACK-GUARD: native died raw (SIGBUS/SIGSEGV, exit 128+signal, no message). After: rtAbi's guard-page sigaltstack handler (rtAbi.asl#locateDarwinText) reports ERR_STACK_DEPTH and exits 1, matching the host's own ERR_STACK_DEPTH text and exit 1 for the identical source")

fn hostBin -> String
  "asl/host/out/asl-host"

fn clangBin -> String
  "/usr/bin/clang -Wno-override-module"

fn rtLib -> String
  "asl/host/out/libaslrt.a"

fn beyondLimitSource -> String
  (stringJoin (list
    "(module gapfx/beyondLimit :x [main] :i [])"
    ""
    "fn goDeep n: Int64 -> Int64"
    "  (if (<= n 0) 0 (+ 1 (goDeep (- n 1))))"
    ""
    "fn ! main args: (List String) -> (Result Int64 String)"
    "  (do (print (stringFromInt64 (goDeep 50000000)))"
    "      (ok 0))") "\n")

fn ! expectExit! label: String cmd: String want: Int64 -> Bool
  (let [(out (sh cmd))]
    (do (assert (= out.exitCode want) (str label ": exit " out.exitCode ", want " want "; stdout: " out.stdout "; stderr: " out.stderr))
        true))

fn ! stderrHolds! label: String cmd: String needle: String -> Bool
  (let [(out (sh cmd))]
    (do (assert (stringContains? out.stderr needle) (str label ": stderr holds '" needle "': " out.stderr))
        true))

fn ! testBeyondStackLimit base: String -> Bool
  (let [(src (str base "/beyondLimit.asl"))
        (ll (str base "/beyondLimit.ll"))
        (bin (str base "/beyondLimit"))
        (wrote (fileWrite src (beyondLimitSource)))
        (built (expectExit! "beyondLimit: asl1 builds it" (str (hostBin) " run asl/packages/asl-compiler/src/asl1.asl build " src " -o " ll) 0))
        (linked (expectExit! "beyondLimit: clang links it" (str (clangBin) " -x ir " ll " -x none " (rtLib) " -lm -o " bin) 0))
        (hostOk (stderrHolds! "beyondLimit host" (str (hostBin) " run " src) "ERR_STACK_DEPTH"))
        (nativeExit (expectExit! "beyondLimit native: guard catches the overflow loudly" bin 1))
        (nativeMsg (stderrHolds! "beyondLimit native" bin "ERR_STACK_DEPTH"))]
    (and (ok? wrote) (and built (and linked (and hostOk (and nativeExit nativeMsg))))))

fn depth -> Int64
  400000

fn opens n: Int64 -> String
  (stringRepeat "(" n)

fn closes n: Int64 -> String
  (stringRepeat ")" n)

fn group bs: Bytes n: Int64 p: Int64 -> Int64
  (if (and (< p n) (= (bytesGet bs p) 40))
    (let [(q (group bs n (+ p 1)))]
      (if (and (>= q 0) (and (< q n) (= (bytesGet bs q) 41))) (+ q 1) -1))
    p)

fn keep k: Int64 -> Int64
  (if (= k 0)
    0
    (let [(mine (stringRepeat "x" (+ 200 (mod k 7))))
          (spent (stringLength (stringRepeat "y" (+ 40 (mod k 5)))))
          (below (keep (- k 1)))]
      (+ below (+ (stringLength mine) spent))))

fn kept k: Int64 -> Int64
  (if (= k 0) 0 (+ (+ (+ 200 (mod k 7)) (+ 40 (mod k 5))) (kept (- k 1))))

fn ! scratchBase! -> String
  (str (optionOr (envGet "TMPDIR") "/tmp") "/deepStackTest-" (stringFromInt64 (procSelf)) "-" (stringFromInt64 (nowNs)))

fn ! runTests -> Bool
  (let [(text (str (opens (depth)) (closes (depth))))
        (bs (stringToBytes text))
        (n (bytesLength bs))
        (end (group bs n 0))
        (total (keep (depth)))
        (base (scratchBase!))
        (madeBase (dirCreate base))
        (guardOk (testBeyondStackLimit base))
        (cleaned (pathRemove base))]
    (do
      (assert (= n (* 2 (depth))) "the probe text holds every bracket")
      (assert (= end n) (str "a 400000-deep group parses to the end: " end))
      (assert (= total (kept (depth))) (str "strings held only by deep frames survive collections: " total))
      (assert (ok? madeBase) "the stack-guard scratch directory is created")
      (assert (ok? cleaned) "the stack-guard scratch directory is removed")
      guardOk))
