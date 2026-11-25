(module asl-cli/tests/buildOwnerGoneTest
  :x [runTests]
  :i [(asl-tools/fleet/run :a fr) (asl/packages/asl-cli/tests/nativeColdFixture :a nf)])

; (:m :ref BUILD-DETACHED-ESCAPE :do "a native CLI build in a scratch cache (seed, asl1 and cli copied from the run store, the notrace runtime stage built cold; the runtime is added to the take once its clang runs so the second caller finishes by adoption) is owned by the bin/asl that started it: once that bin/asl is killed while a clang of the build runs, no process of its tree is left 5 s later, and a second bin/asl waiting on the same cache still finishes the build and answers")
fn ! treeOf! root: Int64 -> (List Int64)
  (fr/descendantsOf (fr/psSnapshot) root)

fn ! clangIn? pids: (List Int64) -> Bool
  (if (listEmpty? pids) false
    (stringContains? (resultOr (fr/shellOut (str "ps -o comm= -p " (stringJoin (map stringFromInt64 pids) ",")) 10000) "") "clang"))

fn ! waitClang! root: Int64 tries: Int64 floor: Int64 -> (List Int64)
  (let [(tree (treeOf! root))]
    (cond
      ((clangIn? tree) tree)
      ((<= tries 0) (list))
      ((and (listEmpty? tree) (<= tries floor)) (list))
      (else (do (sleepMs 500) (waitClang! root (- tries 1) floor)))))

fn ! finish! g: fr/Guarded -> fr/ProcOut
  (fr/guardLoop g)

fn ! alive pids: (List Int64) -> (List Int64)
  (filter (fn [(p Int64)] -> Bool (resultOr (procAlive? p) false)) pids)

; (:m :ref BUILD-OWNER-GONE-CLI-STAGE :do "tree is empty and the first caller's start is 20 s old: the build spawns children at once (clang --version), so no child by then means the build ended without any clang and the wait stops with a red verdict instead of the whole bound")
fn ! runCase! root: String label: String take: (List String) widen: Bool waitTries: Int64 -> Bool
  (let [(cache (str "/tmp/buildOwnerGoneTest." label "." (stringFromInt64 (procSelf))))
        (upstream (nf/adoptFrom! cache take))
        (env (fr/childEnv (list (str "ASL_NATIVE_CLI_CACHE=" cache))))
        (argv (list (str root "/bin/asl") "version"))
        (first (fr/guardStart! argv root env (fr/limits 1800 400)))]
    (match first
      ((err _) (do (assert false (str label ": the first bin/asl started")) false))
      ((ok a)
        (let [(tree (waitClang! a.run.pid waitTries (- waitTries 40)))
              (second (fr/guardStart! argv root env (fr/limits 1800 400)))
              (_ (sleepMs 1000))
              (widened (if widen (ok? (fileWrite (str cache "/upstream.asn") (nf/upstreamText (nf/sharedCliCache!) (list "seed" "rt" "asl1" "cli")))) true))
              (_ (procKill a.run.pid "SIGKILL"))
              (reaped (ok? (procWaitPid a.run.pid false)))
              (_ (sleepMs 5000))
              (left (alive tree))
              (_ (map (fn [(p Int64)] -> Int64 (fr/killTree! p)) left))
              (b (match second ((ok g) (some (finish! g))) ((err _) (none))))
              (head (fileExists? (str cache "/head" (stringReplace root "/" "_"))))
              (cleaned (fr/runShell! (str "rm -rf \"" cache "\"") "/" (fr/childEnv (list)) (fr/limits 120 4)))]
          (do (assert upstream (str label ": the scratch cache copies " (stringJoin take " ") " from the run's store, so only the stage the claim is about is built cold"))
              (assert widened (str label ": once a clang of the cold build ran, the scratch cache also took the runtime from the run's store, so the second bin/asl finishes by adoption instead of lowering it again"))
              (assert (not (listEmpty? tree)) (str label ": a clang of the cold build ran under the first bin/asl"))
              (assert reaped (str label ": the killed bin/asl was reaped"))
              (assert (listEmpty? left) (str label ": 5 s after its bin/asl was killed no process of that build is left: " (stringJoin (map stringFromInt64 left) " ")))
              (assert (match b ((some o) (= o.exitCode 0)) ((none) false)) (str label ": the second bin/asl finished the build and answered: " (match b ((some o) (str (stringFromInt64 o.exitCode) " " (optionOr (stringSlice o.stderr 0 600) ""))) ((none) "did not start"))))
              (assert head (str label ": the second caller left a head for the scratch cache"))
              (assert (= cleaned.exit 0) (str label ": the scratch cache was removed"))
              true)))))

; (:m :ref BUILD-OWNER-GONE-CLI-STAGE :do "two cases of one claim: the runtime stage (seed asl1 cli adopted, the second caller finishes by adoption) is the fast one, the cli stage (seed rt asl1 adopted, the cli lowered cold by both callers) is the one a long asl1 emit and a whole-module link run in and stays slow but bounded")
fn ! runTests -> Bool
  (let [(root (resultOr (realPath ".") "."))
        (fast (runCase! root "rt" (list "seed" "asl1" "cli") true 1200))
        (cold (if (not fast) false (runCase! root "cli" (list "seed" "rt" "asl1") false 3000)))]
    (and fast cold))
