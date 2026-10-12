(module asl-target-llvm/tests/stdioFlushTest
  :x [runTests]
  :i [(tools/fleet/run :a run)])

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

fn host -> String
  "asl/host/out/asl-host"

fn ! regenRtAbi! out: String -> Bool
  (let [(cmd (str (host) " run asl/packages/asl-target-llvm/src/rtAbi.asl " out))
        (res (sh cmd))]
    (do (assert (= res.exitCode 0) (str "rtAbi.asl: asl-host regenerates its .ll; exit " res.exitCode "; stderr " res.stderr))
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
        (built (sh (str (host) " run asl/packages/asl-compiler/src/asl1.asl build " src " -o " ll)))]
    (do (assert wrote "procFlushFixture: source written")
        (assert (= built.exitCode 0) (str "procFlushFixture: asl1 builds it; exit " built.exitCode "; stderr " built.stderr))
        true))

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
