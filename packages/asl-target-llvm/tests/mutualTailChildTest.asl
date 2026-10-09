(module asl-target-llvm/tests/mutualTailChildTest
  :x [runTests]
  :i [(asl-target-llvm :a llvm)])

(schema SpawnedProc (:f pid Int64) (:f stdin Int64) (:f stdout Int64) (:f stderr Int64))

fn ! runTests -> Bool
  (let [(made (processRun "mktemp -d"))
        (work (stringTrim made.stdout))
        (source (str work "/mutual.asl"))
        (ll (str work "/mutual.ll"))
        (exe (str work "/mutual"))
        (src "(module mutual :x [even? odd? main])\n(fn even? [(n Int64)] -> Bool (if (= n 0) true (odd? (- n 1))))\n(fn odd? [(n Int64)] -> Bool (if (= n 0) false (even? (- n 1))))\n(fn main [] -> Int64 (if (even? 10000000) 0 1))\n")
        (written (fileWrite source src))
        (emitted (llvm/emitLlvmSource src "main"))
        (emitWrite (mt emitted ((ok code) (fileWrite ll code)) ((err _) (err "lower"))))
        (linked (processRun (str "/usr/bin/clang -Wno-override-module -x ir " ll " -x none asl/host/out/libaslrt.a -lm -o " exe)))
        (spawned (procSpawnv (list "/bin/sh" "-c" (str "ulimit -s 512; exec " exe)) (none) (none)))
        (spawn (mt spawned ((ok s) s) ((err _) (SpawnedProc :pid -1 :stdin -1 :stdout -1 :stderr -1))))
        (closed (list (if (> spawn.stdin 2) (fdClose spawn.stdin) (ok ()))
                      (if (> spawn.stdout 2) (fdClose spawn.stdout) (ok ()))
                      (if (> spawn.stderr 2) (fdClose spawn.stderr) (ok ()))))
        (waited (if (> spawn.pid 0) (procWaitPid spawn.pid false) (err "spawn")))
        (removed (processRun (str "rm -rf " work)))]
    (do
      (assert (= made.exitCode 0) "scratch directory created")
      (assert (= written (ok ())) "mutual-recursion source written")
      (assert (ok? emitted) (str "LLVM source lowering accepts mutual tail calls: " emitted))
      (assert (= emitWrite (ok ())) "LLVM emitted")
      (assert (= linked.exitCode 0) (str "clang links native mutual recursion: " linked.stderr))
      (assert (ok? spawned) (str "512 KiB-stack child spawned: " spawned))
      (assert (= closed (list (ok ()) (ok ()) (ok ()))) "child pipes closed")
      (assert (= waited (ok (some 0))) (str "ten million even?/odd? calls exit 0 on 512 KiB stack; got " waited))
      (assert (= removed.exitCode 0) "scratch directory removed")
      true))
