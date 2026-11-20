(module asl-cli/tests/buildOwnerGoneTest
  :x [runTests]
  :i [(asl-tools/fleet/run :a fr)])

; (:m :ref BUILD-DETACHED-ESCAPE :do "a cold native CLI build in a scratch cache is owned by the bin/asl that started it: once that bin/asl is killed while a clang of the build runs, no process of its tree is left 5 s later, and a second bin/asl waiting on the same cache still finishes the build and answers")
fn ! treeOf! root: Int64 -> (List Int64)
  (fr/descendantsOf (fr/psSnapshot) root)

fn ! clangIn? pids: (List Int64) -> Bool
  (if (listEmpty? pids) false
    (stringContains? (resultOr (fr/shellOut (str "ps -o comm= -p " (stringJoin (map stringFromInt64 pids) ",")) 10000) "") "clang"))

fn ! waitClang! root: Int64 tries: Int64 -> (List Int64)
  (let [(tree (treeOf! root))]
    (cond
      ((clangIn? tree) tree)
      ((<= tries 0) (list))
      (else (do (sleepMs 500) (waitClang! root (- tries 1))))))

fn ! finish! g: fr/Guarded -> fr/ProcOut
  (fr/guardLoop g)

fn ! alive pids: (List Int64) -> (List Int64)
  (filter (fn [(p Int64)] -> Bool (resultOr (procAlive? p) false)) pids)

fn ! runTests -> Bool
  (let [(root (resultOr (realPath ".") "."))
        (cache (str "/tmp/buildOwnerGoneTest." (stringFromInt64 (procSelf))))
        (_ (dirCreate cache))
        (env (fr/childEnv (list (str "ASL_NATIVE_CLI_CACHE=" cache))))
        (argv (list (str root "/bin/asl") "version"))
        (first (fr/guardStart! argv root env (fr/limits 1800 400)))]
    (match first
      ((err _) (do (assert false "the first bin/asl started") false))
      ((ok a)
        (let [(tree (waitClang! a.run.pid 1200))
              (second (fr/guardStart! argv root env (fr/limits 1800 400)))
              (_ (sleepMs 1000))
              (_ (procKill a.run.pid "SIGKILL"))
              (reaped (ok? (procWaitPid a.run.pid false)))
              (_ (sleepMs 5000))
              (left (alive tree))
              (_ (map (fn [(p Int64)] -> Int64 (fr/killTree! p)) left))
              (b (match second ((ok g) (some (finish! g))) ((err _) (none))))
              (head (fileExists? (str cache "/head" (stringReplace root "/" "_"))))
              (cleaned (fr/runShell! (str "rm -rf \"" cache "\"") "/" (fr/childEnv (list)) (fr/limits 120 4)))]
          (do (assert (not (listEmpty? tree)) "a clang of the cold build ran under the first bin/asl")
              (assert reaped "the killed bin/asl was reaped")
              (assert (listEmpty? left) (str "5 s after its bin/asl was killed no process of that build is left: " (stringJoin (map stringFromInt64 left) " ")))
              (assert (match b ((some o) (= o.exitCode 0)) ((none) false)) (str "the second bin/asl finished the build and answered: " (match b ((some o) (str (stringFromInt64 o.exitCode) " " (optionOr (stringSlice o.stderr 0 600) ""))) ((none) "did not start"))))
              (assert head "the second caller left a head for the scratch cache")
              (assert (= cleaned.exit 0) "the scratch cache was removed")
              true)))))
