(module asl-target-llvm/tests/closedFdsTest
  :x [runTests]
  :i [(asl-ir/link :a lk)
      (asl-target-llvm :a llvm)
      (asl-target-llvm/tests/rcTest :a rc)])

; (:m :ref PROCSPAWN-CLOSED-FDS :do "a program started with fds 0-2 closed gets the runtime's temp files and pipes on 0, 1 and 2; dup2 onto the same number is a no-op and the following close then destroys the child's stdout, so output is lost; the exe prints nothing (stdout is closed) and reports through its exit code: 0 = the child's /bin/echo x came back whole")
fn ! buildExe! libs: rc/Libs dir: String -> (Result String String)
  (match (lk/linkEntry! "asl/packages/asl-target-llvm/tests/fixtures/rc/rcClosedFds.asl")
    ((err ds) (err (str "rcClosedFds links: " (rc/diagText ds))))
    ((ok m)
      (match (llvm/emitLlvmProgramNativeWith! m (str m.name ".main") "0")
        ((err ds) (err (str "rcClosedFds emits: " (rc/diagText ds))))
        ((ok code)
          (let [(ll (str dir "/rcClosedFds.ll"))
                (exe (str dir "/rcClosedFds"))]
            (match (fileWrite ll code)
              ((err e) (err (str "cannot write " ll ": " e)))
              ((ok _)
                (let [(linked (rc/sh (rc/linkCmd libs "0" ll exe)))]
                  (if (!= linked.exitCode 0) (err (str "rcClosedFds links: " linked.stderr)) (ok exe))))))))))

fn ! closedRun exe: String mode: String closed: String -> Int64
  (let [(r (rc/sh (str (rc/shellQuote exe) " " mode " " closed)))
        (_ (if (= r.exitCode 0) true (do (eprintln (str "closedFds " mode " [" closed "] exit " r.exitCode " stderr " r.stderr)) true)))]
    r.exitCode)

fn ! reportCases exe: String -> Bool
  (let [(rows (map (fn [(c (Pair String String))] -> String (str (pairFirst c) " [" (pairSecond c) "] exit " (closedRun exe (pairFirst c) (pairSecond c))))
                   (list (pair "spawn" "") (pair "run" "") (pair "spawn" "0<&- 1>&- 2>&-") (pair "run" "0<&- 1>&- 2>&-") (pair "spawn" "0<&-") (pair "spawn" "1>&-"))))]
    (do (eprintln (str "closedFds cases: " (stringJoin rows "; "))) true))

fn ! runTests -> Bool
  (match (rc/runtimes!)
    ((err e) (do (assert false (str "closedFdsTest runtimes: " e)) false))
    ((ok libs)
      (let [(dir (str (optionOr (envGet "TMPDIR") "/tmp") "/closedFdsTest." (procSelf) "." (monotonicNs)))
            (made (dirCreate dir))]
        (do (assert (ok? made) "work directory created")
            (match (buildExe! libs dir)
              ((err e) (do (assert false (str "build: " e)) false))
              ((ok exe)
                (do (reportCases exe)
                    (let [(code (closedRun exe "spawn" ""))] (assert (= code 0) (str "processSpawn with open fds returns the child's output: exit " code)))
                    (let [(code (closedRun exe "run" ""))] (assert (= code 0) (str "processRun with open fds returns the child's output: exit " code)))
                    (let [(code (closedRun exe "spawn" "0<&- 1>&- 2>&-"))] (assert (= code 0) (str "processSpawn with fds 0-2 closed returns the child's output: exit " code)))
                    (let [(code (closedRun exe "run" "0<&- 1>&- 2>&-"))] (assert (= code 0) (str "processRun with fds 0-2 closed returns the child's output: exit " code)))
                    (let [(code (closedRun exe "spawn" "0<&-"))] (assert (= code 0) (str "behaviour pin (guards no single line of the fix): processSpawn with only stdin closed returns the child's output: exit " code)))
                    (let [(code (closedRun exe "spawn" "1>&-"))] (assert (= code 0) (str "behaviour pin (guards no single line of the fix): processSpawn with only stdout closed returns the child's output: exit " code)))
                    true)))
            (let [(gone (rc/sh (str "rm -rf " (rc/shellQuote dir))))]
              (assert (= gone.exitCode 0) "work directory removed"))
            true))))
