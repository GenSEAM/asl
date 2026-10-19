(module asl-target-llvm/tests/stdioFlushTest
  :x [runTests]
  :i [(tools/fleet/run :a run) (asl-target-llvm/rtAbi :a rtAbi) (asl-cli/asl1Cache :a cache) (asl-cli/system :a sys)])

; (:m :ref NATIVE-STDIO-FLUSH :do "native stdio is unbuffered for print/println (raw write(2) in rtFormat.asl), but a native process can still hold buffered libc stdio open across a fork/exec or exit if something upstream (a linked C library, or future code) ever buffers through FILE*; this matches the already-established fflush-before-fork/fflush-before-exit convention in parallel.asl's own native worker pool. Checked structurally against the generated LLVM IR text rather than by chasing a live repro, since every buffered-I/O path this codebase currently owns (print/println, processRun's open_memstream capture) was independently confirmed already correct; the fix is defensive parity with host semantics and with parallel.asl's own precedent for every other fork/exit site: rtAbi.asl's asl_rt_main body thread, processRunFn's shell-exec fork, and processSpawnFn's fork")

(schema Captured
  (:f exitCode Int64)
  (:f stdout String)
  (:f stderr String))

fn ! sh cmd: String -> Captured
  (let [(base (str (optionOr (envGet "TMPDIR") "/tmp") "/stdioFlushTest." (monotonicNs)))
        (outPath (str base ".out"))
        (errPath (str base ".err"))
        (done (run/runOneLimited (run/job (list "sh" "-c" (str "(" cmd ") > " outPath " 2> " errPath)) "." (run/childEnv (list)))
                                 (run/limits 120 32)))
        (outText (resultOr (fileReadString outPath) ""))
        (errText (resultOr (fileReadString errPath) ""))
        (_ (pathRemove outPath))
        (_ (pathRemove errPath))]
    (Captured :exitCode done.exit :stdout outText :stderr (if (= done.verdict "exit") errText (str errText done.out))))

; (:m :ref HL-E-LLVM :do "HL-E-LLVM (asl-host deleted): regenRtAbi! used to shell out to asl-host to interpret rtAbi.asl as a CLI script (its own fn ! main, writing the generated .ll to the given path); this is not a host-vs-native parity check, just a CLI wrapper around rtAbi/abiText, so it now calls rtAbi/main directly in-process (the exact same exported entry point) instead of spawning anything. buildProcFixture! used to run asl1.asl's build command interpreted by asl-host; it now uses the cached native asl1 compiler (asl-cli/asl1Cache nativeAsl1!), the same replacement used by deepStackTest")

fn ! nativeAsl1Bin! -> (Result String String)
  (mt (sys/context!)
    ((err e) (err e))
    ((ok ctx) (cache/nativeAsl1! ctx (str ctx.root "/asl/host/out/libaslrt.a") "/usr/bin/clang")))

fn ! regenRtAbi! out: String -> Bool
  (let [(res (rtAbi/main (list out)))]
    (do (assert (ok? res) (str "rtAbi/main regenerates its .ll: " res))
        true))

fn procFixtureSource -> String
  (stringJoin (list
    "(module procFlushFixture :x [main] :i [])"
    ""
    "fn ! main args: (List String) -> (Result Int64 String)"
    "  (let [(a (processRun \"echo a\"))"
    "        (b (processSpawn \"echo b\"))]"
    "    (ok a.exitCode))") "\n")

fn ! buildProcFixture! work: String -> Bool
  (let [(src (str work "/procFlushFixture.asl"))
        (ll (str work "/procFlushFixture.ll"))
        (wrote (ok? (fileWrite src (procFixtureSource))))
        (compiler (nativeAsl1Bin!))]
    (mt compiler
      ((err e) (do (assert false (str "procFlushFixture: native asl1 compiler: " e)) false))
      ((ok nativeAsl1)
        (let [(built (sh (str nativeAsl1 " build " src " -o " ll)))]
          (do (assert wrote "procFlushFixture: source written")
              (assert (= built.exitCode 0) (str "procFlushFixture: asl1 builds it natively; exit " built.exitCode "; stderr " built.stderr))
              true)))))

fn ! textOf path: String -> String
  (mt (fileReadString path)
    ((ok t) t)
    ((err e) (str "unreadable " path ": " e)))

fn ! testMainThreadFlushesBeforeExit work: String -> Bool
  (let [(out (str work "/rtAbi.ll"))
        (_ (regenRtAbi! out))
        (text (textOf out))]
    (do
      (assert (stringContains? text "define internal ptr @rtAbi.mainThread(") "rtAbi: mainThread is defined")
      (assert (stringContains? text "call i32 @fflush(ptr null)\n  call void @exit(i32 %code)")
              "rtAbi.mainThread: fflush(NULL) runs as the immediately preceding instruction before the body thread's final exit")
      true))

fn ! testProcessRunFlushesBeforeFork work: String -> Bool
  (let [(_ (buildProcFixture! work))
        (text (textOf (str work "/procFlushFixture.ll")))]
    (do
      (assert (stringContains? text "@fork()") "procFlushFixture: .ll calls fork()")
      (assert (stringContains? text "call i32 (ptr) @fflush(ptr %runFlushNull)\n  %forked = call i32 () @fork()")
              "processRunFn's shell-exec child: fflush(NULL) runs as the immediately preceding instruction before the fork() that follows it")
      true))

fn ! testProcessSpawnFlushesBeforeFork work: String -> Bool
  (let [(text (textOf (str work "/procFlushFixture.ll")))]
    (do
      (assert (stringContains? text "call i32 (ptr) @fflush(ptr %spawnFlushNull)\n  %pid = call i32 () @fork()")
              "processSpawnFn's fork: fflush(NULL) runs as the immediately preceding instruction before the fork() that follows it")
      true))

fn ! runTests -> Bool
  (let [(made (sh "mktemp -d"))
        (work (stringReplace made.stdout "\n" ""))]
    (do
      (assert (= made.exitCode 0) "mktemp -d makes a work directory")
      (testMainThreadFlushesBeforeExit work)
      (testProcessRunFlushesBeforeFork work)
      (testProcessSpawnFlushesBeforeFork work)
      true))
