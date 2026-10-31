(module asl-target-llvm/tests/procSpawnLeakTest
  :x [runTests]
  :i [(asl-ir/link :a lk)
      (asl-target-llvm :a llvm)
      (asl-target-llvm/tests/rcTest :a rc)])

; (:m :ref PROCSPAWN-CSTR-LEAK :do "processSpawn made its /bin/sh, sh and -c C strings with valToCStr and freed none of them on any returning path, 24 bytes of heap per call; the ASan build of a program that spawns and waits once must exit 0 with LeakSanitizer on (linux; macOS has no LeakSanitizer so the run only proves the spawn works there)")
fn ! buildExe! libs: rc/Libs dir: String -> (Result String String)
  (match (lk/linkEntry! "asl/packages/asl-target-llvm/tests/fixtures/rc/rcSpawnLeak.asl")
    ((err ds) (err (str "rcSpawnLeak links: " (rc/diagText ds))))
    ((ok m)
      (match (llvm/emitLlvmProgramNativeWith! m (str m.name ".main") "asan")
        ((err ds) (err (str "rcSpawnLeak emits: " (rc/diagText ds))))
        ((ok code)
          (let [(ll (str dir "/rcSpawnLeak.ll"))
                (exe (str dir "/rcSpawnLeak"))]
            (match (fileWrite ll code)
              ((err e) (err (str "cannot write " ll ": " e)))
              ((ok _)
                (let [(linked (rc/sh (rc/linkCmd libs "asan" ll exe)))]
                  (if (!= linked.exitCode 0) (err (str "rcSpawnLeak links: " linked.stderr)) (ok exe))))))))))

fn ! runTests -> Bool
  (match (rc/runtimes!)
    ((err e) (do (assert false (str "procSpawnLeakTest runtimes: " e)) false))
    ((ok libs)
      (let [(dir (str (optionOr (envGet "TMPDIR") "/tmp") "/procSpawnLeakTest." (procSelf) "." (monotonicNs)))
            (made (dirCreate dir))]
        (do (assert (ok? made) "work directory created")
            (match (buildExe! libs dir)
              ((err e) (do (assert false (str "build: " e)) false))
              ((ok exe)
                (let [(r (rc/sh (rc/shellQuote exe)))]
                  (do (assert (= r.exitCode 0) (str "spawn then wait exits 0 under ASan with leak detection: " r.exitCode " " r.stderr))
                      (refute (stringContains? r.stderr "LeakSanitizer") (str "no leak report: " r.stderr))
                      true))))
            (let [(gone (rc/sh (str "rm -rf " (rc/shellQuote dir))))]
              (assert (= gone.exitCode 0) "work directory removed"))
            true))))
