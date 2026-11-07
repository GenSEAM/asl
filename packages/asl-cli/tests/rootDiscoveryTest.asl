(module asl-cli/tests/rootDiscoveryTest
  :x [runTests]
  :i [(asl/packages/asl-cli/src/system :a sys) (asl/packages/asl-cli/src/asl1Cache :a cache) (asl/packages/asl-cli/src/nativeCli :a nc) (asl-tools/fleet/run :a fr)])

fn ! probeSource -> String
  (str
    "(module asl-cli/tests/rootDiscoveryProbe\n"
    "  :x [main]\n"
    "  :i [(asl/packages/asl-cli/src/system :a sys)])\n"
    "\n"
    "fn ! main -> (Result Int64 String)\n"
    "  (match (sys/context!)\n"
    "    ((ok c) (do (println c.root) (ok 0)))\n"
    "    ((err e) (do (eprintln e) (ok 1))))\n")

fn ! stamp -> String
  (stringFromInt64 (monotonicNs))

fn ! makeDir! path: String -> (Result String String)
  (match (dirCreate path) ((err e) (err e)) ((ok _) (ok path)))

; (:m :ref MAINRED-ROOTDISCOVERY :do "every child of this test (compiler, linker, git, the 8 probe runs) is a fleet runGuarded child: own process group, timeout, descendant limit and a tree kill on its verdict; the env is sys/childEnv! so no ASL_CLI_ variable reaches it")
fn ! guarded! argv: (List String) cwd: String extra: (List String) secs: Int64 -> fr/ProcOut
  (fr/runGuarded argv cwd (sys/childEnv! extra) (fr/limits secs 16))

fn ! drive! f: fr/Forked -> fr/ForkEnd
  (let [(s (fr/forkAdvance! f))]
    (match s.end
      ((some e) e)
      ((none) (do (sleepMs 50) (drive! s.fork)))))

fn ! clangOf! root: String -> String
  (let [(name (resultOr (nc/clangFor! root) "clang"))]
    (if (stringContains? name "/")
      name
      (optionOr (sys/onPath! name) name)))

fn ! toolchainText! ctx: sys/Context out: String -> Int64
  (let [(clang (clangOf! ctx.root))
        (lib (str ctx.root "/asl/host/out/libaslrt.a"))]
    (match (cache/nativeAsl1! ctx lib clang)
      ((ok asl1) (if (ok? (fileWrite out (str clang "\n" asl1))) 0 2))
      ((err e) (do (fileWrite out e) 1))))

; (:m :ref MAINRED-ROOTDISCOVERY :do "the cached native asl1 compiler and the clang it is keyed by are looked up in a forkLimited! child (own group, deadline, tree kill) that writes them to a file: a cold cache compiles asl1 there, inside the bound, and the running CLI is never started")
fn ! toolchain! ctx: sys/Context dir: String -> (Result (Pair String String) String)
  (let [(out (str dir "/toolchain.txt"))
        (log (str dir "/toolchain.log"))
        (forked (fr/forkLimited! log (fr/limits 900 32) (fn [] -> Int64 (toolchainText! ctx out))))]
    (match forked
      ((err e) (err (str "toolchain fork failed: " e)))
      ((ok f)
        (let [(end (drive! f))
              (lines (stringLines (resultOr (fileReadString out) "")))]
          (if (and (= end.exit 0) (= (listLength lines) 2))
            (ok (pair (optionOr (listGet lines 0) "") (optionOr (listGet lines 1) "")))
            (err (str "toolchain lookup exited " (stringFromInt64 end.exit) " " end.verdict ": " (stringJoin lines " ") " " (resultOr (fileReadString log) ""))))))))

fn failedStep label: String o: fr/ProcOut -> String
  (str label " exited " (stringFromInt64 o.exitCode) ": " o.stdout o.stderr)

; (:m :ref MAINRED-ROOTDISCOVERY :do "HL-DELETE retired asl/host/out/asl-host, the runner these cases used; the probe is compiled by the native asl1 to IR and linked by clang with libaslrt.a into a fresh dir under <root>/.asl/tmp, so its own exe sits inside the workspace and every case starts that binary directly")
fn ! buildProbe! ctx: sys/Context dir: String probePath: String -> (Result String String)
  (match (toolchain! ctx dir)
    ((err e) (err e))
    ((ok tools)
      (let [(ll (str dir "/rootDiscoveryProbe.ll"))
            (exe (str dir "/rootDiscoveryProbe"))
            (lib (str ctx.root "/asl/host/out/libaslrt.a"))
            (pre (list (str "ASL_PRELUDE=" ctx.root "/asl/prelude/prelude.asl")))
            (compiled (guarded! (list (pairSecond tools) "build" probePath "-o" ll) ctx.root pre 600))]
        (if (or (!= compiled.exitCode 0) (not (sys/isFile? ll)))
          (err (failedStep "asl1 build" compiled))
          (let [(linked (guarded! (list (pairFirst tools) "-O2" "-Wno-override-module" "-x" "ir" ll "-x" "none" lib "-lm" "-o" exe) ctx.root (list) 600))]
            (if (and (= linked.exitCode 0) (sys/isFile? exe))
              (ok exe)
              (err (failedStep "clang link" linked))))))))

fn okOrFailed o: fr/ProcOut -> (Result String String)
  (if (= o.exitCode 0)
    (ok (sys/stripTrailingNewlines o.stdout))
    (err (str "probe exited " (stringFromInt64 o.exitCode) ": " o.stderr)))

fn ! runProbeEnv! exe: String cwd: String extra: (List String) -> (Result String String)
  (okOrFailed (guarded! (list exe) cwd extra 60))

fn noEnv outside: String -> (Result (List String) String)
  (ok (list))

fn ! nothing -> Bool
  true

; (:m :ref MAINRED-ROOTDISCOVERY :do "each case makes its dirs, runs the probe, removes what it made and only then returns its result; assertions run after every case and the build dir are gone, so a red run leaves nothing behind")
fn ! inOutside! tag: String extra: (fn [String] -> (Result (List String) String)) run: (fn [String (List String)] -> (Result String String)) undo: (fn [] -> Bool) -> (Result String String)
  (match (makeDir! (str "/tmp/rootDiscoveryOutside_" tag))
    ((err e) (let [(_ (undo))] (err (str "outside cwd setup failed: " e))))
    ((ok outside)
      (let [(rows (extra outside))
            (found (match rows
                     ((err e) (err (str "setup failed: " e)))
                     ((ok more) (run outside more))))
            (_ (pathRemove outside))
            (_ (undo))]
        found)))

fn ! copyExe! exe: String -> (Result String String)
  (match (makeDir! (str "/tmp/rootDiscoveryExeCopy_" (stamp)))
    ((err e) (err e))
    ((ok dir)
      (let [(path (str dir "/decoy-exe"))
            (copied (match (fileReadBytes exe)
                      ((err e) (err e))
                      ((ok bytes) (match (fileWrite path bytes)
                                    ((err e) (err e))
                                    ((ok _) (fileChmod path 493))))))]
        (match copied
          ((err e) (let [(_ (pathRemove dir))] (err e)))
          ((ok _) (ok path))))))

fn ! pathDirFor! exe: String -> (Result String String)
  (match (makeDir! (str "/tmp/rootDiscoveryPath_" (stamp)))
    ((err e) (err e))
    ((ok dir)
      (match (pathSymlink exe (str dir "/asl-host"))
        ((err e) (let [(_ (pathRemove dir))] (err e)))
        ((ok _) (ok dir)))))

fn ! deniedFile! -> (Result String String)
  (let [(base (str "/tmp/rootDiscoveryDenied_" (stamp)))
        (sub (str base "/sub"))
        (file (str sub "/decoy-exe"))
        (made (match (dirCreate base)
                ((err e) (err e))
                ((ok _) (match (dirCreate sub)
                          ((err e) (err e))
                          ((ok _) (match (fileWrite file "x")
                                    ((err e) (err e))
                                    ((ok _) (fileChmod sub 0))))))))]
    (match made
      ((err e) (let [(_ (pathRemove base))] (err e)))
      ((ok _) (ok file))))

fn ! dropDenied! file: String -> Bool
  (let [(_ (fileChmod (sys/parentOf file) 448))
        (_ (pathRemove (sys/parentOf (sys/parentOf file))))]
    true)

fn ! dropParent! r: (Result String String) -> Bool
  (match r
    ((ok path) (ok? (pathRemove (sys/parentOf path))))
    ((err _) true))

fn ! dropDir! r: (Result String String) -> Bool
  (match r
    ((ok dir) (ok? (pathRemove dir)))
    ((err _) true))

fn ! viaRunner! runnerR: (Result String String) pre: (List String) rows: (List String) outside: String more: (List String) -> (Result String String)
  (match runnerR
    ((err e) (err (str "outside host copy failed: " e)))
    ((ok runner) (runProbeEnv! runner outside (listAppend pre (listAppend rows more)))))

fn ! nested! root: String exe: String -> (Result String String)
  (match (makeDir! (str root "/.asl/tmp/rootDiscoveryCwd_" (stamp)))
    ((err e) (err (str "temp cwd setup failed: " e)))
    ((ok dir)
      (let [(r (runProbeEnv! exe dir (list)))
            (_ (pathRemove dir))]
        r)))

; (:m :ref MAINRED-ROOTDISCOVERY :do "the 8 probe runs as (label result) rows in case order; the two cases that expect an error carry it as their result")
fn ! probeCases! ctx: sys/Context exe: String marker: String -> (List (Pair String (Result String String)))
  (let [(pre (list (str "ASL_PRELUDE=" ctx.root "/asl/prelude/prelude.asl")))
        (noPath "PATH=/rootDiscoveryTest-no-such-path")
        (fromRoot (runProbeEnv! exe ctx.root (list)))
        (fromNested (nested! ctx.root exe))
        (selfExe (inOutside! (stamp) noEnv (fn [(o String) (more (List String))] -> (Result String String) (runProbeEnv! exe o (list noPath))) nothing))
        (runnerR (copyExe! exe))
        (argv0 (inOutside! (stamp) noEnv (fn [(o String) (more (List String))] -> (Result String String) (viaRunner! runnerR pre (list (str "ASL_CLI_ARGV0=" exe)) o more)) nothing))
        (pathDirR (pathDirFor! exe))
        (pathRows (fn [(o String)] -> (Result (List String) String)
                    (match pathDirR
                      ((err e) (err (str "PATH dir setup failed: " e)))
                      ((ok d) (ok (list (str "PATH=" d)))))))
        (viaPath (inOutside! (stamp) pathRows (fn [(o String) (more (List String))] -> (Result String String) (viaRunner! runnerR pre (list) o more)) nothing))
        (decoyR (copyExe! exe))
        (decoyRows (fn [(o String)] -> (Result (List String) String)
                     (match decoyR
                       ((err e) (err (str "decoy exe setup failed: " e)))
                       ((ok decoy) (match pathDirR
                                     ((err e) (err (str "PATH dir setup failed: " e)))
                                     ((ok d) (ok (list (str "ASL_CLI_ARGV0=" decoy) (str "PATH=" d)))))))))
        (argv0Decoy (inOutside! (stamp) decoyRows (fn [(o String) (more (List String))] -> (Result String String) (viaRunner! runnerR pre (list) o more)) nothing))
        (_ (dropParent! decoyR))
        (_ (dropDir! pathDirR))
        (deniedR (deniedFile!))
        (deniedRows (fn [(o String)] -> (Result (List String) String)
                      (match deniedR
                        ((err e) (err (str "denied candidate setup failed: " e)))
                        ((ok f) (ok (list (str "ASL_CLI_ARGV0=" f) noPath))))))
        (denied (inOutside! (stamp) deniedRows (fn [(o String) (more (List String))] -> (Result String String) (viaRunner! runnerR pre (list) o more))
                            (fn [] -> Bool (match deniedR ((ok f) (dropDenied! f)) ((err _) true)))))
        (giveUp (inOutside! marker noEnv (fn [(o String) (more (List String))] -> (Result String String) (viaRunner! runnerR pre (list noPath) o more)) nothing))
        (_ (dropParent! runnerR))]
    (list (pair "from repo root" fromRoot)
          (pair "from a nested cwd" fromNested)
          (pair "from outside the repo via the running exe" selfExe)
          (pair "from outside the repo via ASL_CLI_ARGV0" argv0)
          (pair "from outside the repo via PATH" viaPath)
          (pair "ASL_CLI_ARGV0 outside the repo, PATH holding the real one" argv0Decoy)
          (pair "permissionDenied" denied)
          (pair "give-up" giveUp)))

fn rowAt rows: (List (Pair String (Result String String))) i: Int64 -> (Pair String (Result String String))
  (optionOr (listGet rows i) (pair (str "case " (stringFromInt64 i)) (err "missing case row")))

fn ! checkDiscovered row: (Pair String (Result String String)) expected: String -> Bool
  (do
    (match (pairSecond row)
      ((ok found) (assert (= found expected) (str (pairFirst row) ": expected " expected " got " found)))
      ((err e) (assert false (str (pairFirst row) " failed: " e))))
    true)

fn ! checkAll! rows: (List (Pair String (Result String String))) expected: String marker: String -> Bool
  (do
    (checkDiscovered (rowAt rows 0) expected)
    (checkDiscovered (rowAt rows 1) expected)
    (checkDiscovered (rowAt rows 2) expected)
    (checkDiscovered (rowAt rows 3) expected)
    (checkDiscovered (rowAt rows 4) expected)
    (checkDiscovered (rowAt rows 5) expected)
    (match (pairSecond (rowAt rows 6))
      ((ok r) (assert false (str "permissionDenied case: expected an error, found root " r)))
      ((err e) (assert (stringContains? e "permissionDenied") (str "permissionDenied case: expected error to mention permissionDenied, got " e))))
    (match (pairSecond (rowAt rows 7))
      ((ok r) (assert false (str "give-up case: expected an error, found root " r)))
      ((err e) (do
                 (assert (stringContains? e marker) (str "give-up case: expected error to mention cwd marker " marker ", got " e))
                 (assert (stringContains? e "ASL_CLI_ARGV0") (str "give-up case: expected error to mention ASL_CLI_ARGV0, got " e)))))
    true)

fn ! expectedRoot! cwd: String -> (Result String String)
  (let [(o (guarded! (list (optionOr (sys/onPath! "git") "/usr/bin/git") "rev-parse" "--show-toplevel") cwd (list) 60))]
    (if (= o.exitCode 0)
      (ok (sys/stripTrailingNewlines o.stdout))
      (err (str "git rev-parse --show-toplevel failed: " o.stderr))))

fn ! buildAndRun! ctx: sys/Context expected: String dir: String -> Bool
  (let [(probePath (str dir "/rootDiscoveryProbe.asl"))
        (written (fileWrite probePath (probeSource)))
        (exeR (match written
                ((err e) (err (str "probe write failed: " e)))
                ((ok _) (buildProbe! ctx dir probePath))))
        (marker (str "giveup" (stamp)))
        (rows (match exeR
                ((ok exe) (probeCases! ctx exe marker))
                ((err _) (list))))
        (_ (pathRemove dir))]
    (match exeR
      ((err e) (assert false (str "probe build failed: " e)))
      ((ok _) (checkAll! rows expected marker))))

fn ! testDiscoversRootWithoutEnv -> Bool
  (match (sys/context!)
    ((err e) (assert false (str "current context! failed: " e)))
    ((ok ctx)
      (match (expectedRoot! ".")
        ((err e) (assert false (str "independent expected root (git) failed: " e)))
        ((ok expected)
          (match (makeDir! (str ctx.root "/.asl/tmp/rootDiscoveryExe_" (stamp)))
            ((err e) (assert false (str "probe dir setup failed: " e)))
            ((ok dir) (buildAndRun! ctx expected dir)))))))

fn ! runTests -> Bool
  (testDiscoversRootWithoutEnv)
