(module asl-cli/tests/rootDiscoveryTest
  :x [runTests]
  :i [(asl/packages/asl-cli/src/system :a sys)])

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

fn ! writeProbe! root: String -> (Result String String)
  (let [(dir (str root "/.asl/tmp"))
        (made (dirCreate dir))]
    (match made
      ((err e) (err e))
      ((ok _)
        (let [(path (str dir "/rootDiscoveryProbe_" (stringFromInt64 (monotonicNs)) ".asl"))
              (written (fileWrite path (probeSource)))]
          (match written
            ((err e) (err e))
            ((ok _) (ok path)))))))

fn ! makeDir! path: String -> (Result String String)
  (match (dirCreate path) ((err e) (err e)) ((ok _) (ok path)))

; (:m :ref MAINRED-ROOTDISCOVERY :do "HL-DELETE retired asl/host/out/asl-host, the runner these cases used; the probe is built once with bin/asl build into a fresh dir under <root>/.asl/tmp, so its own exe sits inside the workspace and every case starts that binary directly, with no ASL_CLI_ variable inherited")
fn ! buildProbe! ctx: sys/Context probePath: String -> (Result String String)
  (match (makeDir! (str ctx.root "/.asl/tmp/rootDiscoveryExe_" (stringFromInt64 (monotonicNs))))
    ((err e) (err e))
    ((ok dir)
      (let [(exe (str dir "/rootDiscoveryProbe"))
            (builtR (sys/capture! (list (str ctx.root "/bin/asl") "build" probePath "-o" exe) (some ctx.root)))]
        (match builtR
          ((err e) (do (pathRemove dir) (err e)))
          ((ok built)
            (if (and (= built.exitCode 0) (sys/isFile? exe))
              (ok exe)
              (do (pathRemove dir) (err (str "asl build exited " (stringFromInt64 built.exitCode) ": " built.stdout built.stderr)))))))))

fn ! makeTempCwd! root: String -> (Result String String)
  (makeDir! (str root "/.asl/tmp/rootDiscoveryCwd_" (stringFromInt64 (monotonicNs))))

fn ! makeOutsideCwd! -> (Result String String)
  (makeDir! (str "/tmp/rootDiscoveryOutside_" (stringFromInt64 (monotonicNs))))

fn ! makePathDir! probeExe: String -> (Result String String)
  (let [(dir (str "/tmp/rootDiscoveryPath_" (stringFromInt64 (monotonicNs))))
        (made (dirCreate dir))]
    (match made
      ((err e) (err e))
      ((ok _)
        (let [(linked (pathSymlink probeExe (str dir "/asl-host")))]
          (match linked
            ((err e) (err e))
            ((ok _) (ok dir)))))))

fn ! makeOutsideExeCopy! probeExe: String -> (Result String String)
  (let [(dir (str "/tmp/rootDiscoveryExeCopy_" (stringFromInt64 (monotonicNs))))
        (made (dirCreate dir))]
    (match made
      ((err e) (err e))
      ((ok _)
        (let [(path (str dir "/decoy-exe"))
              (bytesR (fileReadBytes probeExe))]
          (match bytesR
            ((err e) (err e))
            ((ok bytes)
              (let [(writtenR (fileWrite path bytes))]
                (match writtenR
                  ((err e) (err e))
                  ((ok _) (ok path))))))))))

fn ! makeDeniedCandidate! -> (Result String String)
  (let [(base (str "/tmp/rootDiscoveryDenied_" (stringFromInt64 (monotonicNs))))
        (sub (str base "/sub"))
        (madeBase (dirCreate base))]
    (match madeBase
      ((err e) (err e))
      ((ok _)
        (let [(madeSub (dirCreate sub))]
          (match madeSub
            ((err e) (err e))
            ((ok _)
              (let [(file (str sub "/decoy-exe"))
                    (writtenR (fileWrite file "x"))]
                (match writtenR
                  ((err e) (err e))
                  ((ok _)
                    (let [(chmodR (fileChmod sub 0))]
                      (match chmodR
                        ((err e) (err e))
                        ((ok _) (ok file)))))))))))))

fn ! removeDeniedCandidate! file: String -> Bool
  (do
    (fileChmod (sys/parentOf file) 448)
    (pathRemove (sys/parentOf (sys/parentOf file)))
    true)

fn okOrFailed captured: sys/Captured -> (Result String String)
  (if (= captured.exitCode 0)
    (ok (sys/stripTrailingNewlines captured.stdout))
    (err (str "probe exited " (stringFromInt64 captured.exitCode) ": " captured.stderr)))

fn ! runProbeEnv! probeExe: String cwd: String extra: (List String) -> (Result String String)
  (let [(captureR (sys/captureWith! (list probeExe) (some cwd) extra))]
    (match captureR
      ((err e) (err e))
      ((ok captured) (okOrFailed captured))))

fn ! runProbe! probeExe: String cwd: String -> (Result String String)
  (runProbeEnv! probeExe cwd (list))

fn ! gitBin! -> String
  (optionOr (sys/onPath! "git") "/usr/bin/git")

fn ! expectedRoot! -> (Result String String)
  (let [(captureR (sys/capture! (list (gitBin!) "rev-parse" "--show-toplevel") (none)))]
    (match captureR
      ((err e) (err e))
      ((ok captured)
        (if (= captured.exitCode 0)
          (ok (sys/stripTrailingNewlines captured.stdout))
          (err (str "git rev-parse --show-toplevel failed: " captured.stderr))))))

fn ! checkDiscovered r: (Result String String) expected: String label: String -> Bool
  (do
    (match r
      ((ok found) (assert (= found expected) (str label ": expected " expected " got " found)))
      ((err e) (assert false (str label " failed: " e))))
    true)

fn ! checkCwdCases! probeExe: String root: String expected: String -> Bool
  (let [(nestedR (makeTempCwd! root))]
    (match nestedR
      ((err e) (assert false (str "temp cwd setup failed: " e)))
      ((ok nestedCwd)
        (let [(fromRoot (runProbe! probeExe root))
              (fromNested (runProbe! probeExe nestedCwd))
              (_ (pathRemove nestedCwd))]
          (and (checkDiscovered fromRoot expected "from repo root")
               (checkDiscovered fromNested expected "from a nested cwd"))))))

fn ! checkSelfExeCase! probeExe: String expected: String -> Bool
  (let [(outsideR (makeOutsideCwd!))]
    (match outsideR
      ((err e) (assert false (str "outside cwd setup failed: " e)))
      ((ok outside)
        (let [(found (runProbeEnv! probeExe outside (list "PATH=/rootDiscoveryTest-no-such-path")))
              (_ (pathRemove outside))]
          (checkDiscovered found expected "from outside the repo via the running exe")))))

fn ! makeOutsideHost! probeExe: String -> (Result String String)
  (match (makeOutsideExeCopy! probeExe)
    ((err e) (err e))
    ((ok path) (match (fileChmod path 493) ((err e) (err e)) ((ok _) (ok path)))))

fn ! checkArgv0Case! runner: String pre: (List String) probeExe: String expected: String -> Bool
  (let [(outsideR (makeOutsideCwd!))]
    (match outsideR
      ((err e) (assert false (str "outside cwd setup failed: " e)))
      ((ok outside)
        (let [(found (runProbeEnv! runner outside (listAppend pre (list (str "ASL_CLI_ARGV0=" probeExe)))))
              (_ (pathRemove outside))]
          (checkDiscovered found expected "from outside the repo via ASL_CLI_ARGV0")))))

fn ! checkPathCase! runner: String pre: (List String) probeExe: String expected: String -> Bool
  (let [(outsideR (makeOutsideCwd!))]
    (match outsideR
      ((err e) (assert false (str "outside cwd setup failed: " e)))
      ((ok outside)
        (let [(dirR (makePathDir! probeExe))]
          (match dirR
            ((err e) (do (pathRemove outside) (assert false (str "PATH dir setup failed: " e))))
            ((ok pathDir)
              (let [(found (runProbeEnv! runner outside (listAppend pre (list (str "PATH=" pathDir)))))
                    (_ (pathRemove outside))
                    (_ (pathRemove pathDir))]
                (checkDiscovered found expected "from outside the repo via PATH"))))))))

fn ! checkArgv0OutsidePathInRepoCase! runner: String pre: (List String) probeExe: String expected: String -> Bool
  (let [(outsideR (makeOutsideCwd!))]
    (match outsideR
      ((err e) (assert false (str "outside cwd setup failed: " e)))
      ((ok outside)
        (let [(exeR (makeOutsideExeCopy! probeExe))]
          (match exeR
            ((err e) (do (pathRemove outside) (assert false (str "decoy exe setup failed: " e))))
            ((ok decoyExe)
              (let [(dirR (makePathDir! probeExe))]
                (match dirR
                  ((err e) (do (pathRemove outside) (pathRemove (sys/parentOf decoyExe)) (assert false (str "PATH dir setup failed: " e))))
                  ((ok pathDir)
                    (let [(found (runProbeEnv! runner outside (listAppend pre (list (str "ASL_CLI_ARGV0=" decoyExe) (str "PATH=" pathDir)))))
                          (_ (pathRemove outside))
                          (_ (pathRemove (sys/parentOf decoyExe)))
                          (_ (pathRemove pathDir))]
                      (checkDiscovered found expected "ASL_CLI_ARGV0 outside the repo, PATH holding the real one")))))))))))

fn ! checkPermissionDeniedCase! runner: String pre: (List String) -> Bool
  (let [(outsideR (makeOutsideCwd!))]
    (match outsideR
      ((err e) (assert false (str "outside cwd setup failed: " e)))
      ((ok outside)
        (let [(deniedR (makeDeniedCandidate!))]
          (match deniedR
            ((err e) (do (pathRemove outside) (assert false (str "denied candidate setup failed: " e))))
            ((ok deniedFile)
              (let [(found (runProbeEnv! runner outside (listAppend pre (list (str "ASL_CLI_ARGV0=" deniedFile) "PATH=/rootDiscoveryTest-no-such-path"))))
                    (_ (removeDeniedCandidate! deniedFile))
                    (_ (pathRemove outside))]
                (do
                  (match found
                    ((ok r) (assert false (str "permissionDenied case: expected an error, found root " r)))
                    ((err e) (assert (stringContains? e "permissionDenied") (str "permissionDenied case: expected error to mention permissionDenied, got " e))))
                  true))))))))

fn ! checkGiveUpMessageCase! runner: String pre: (List String) -> Bool
  (let [(marker (str "giveup" (stringFromInt64 (monotonicNs))))
        (outside (str "/tmp/rootDiscoveryOutside_" marker))
        (madeR (makeDir! outside))]
    (match madeR
      ((err e) (assert false (str "outside cwd setup failed: " e)))
      ((ok _)
        (let [(found (runProbeEnv! runner outside (listAppend pre (list "PATH=/rootDiscoveryTest-no-such-path"))))
              (_ (pathRemove outside))]
          (do
            (match found
              ((ok r) (assert false (str "give-up case: expected an error, found root " r)))
              ((err e) (do
                (assert (stringContains? e marker) (str "give-up case: expected error to mention cwd marker " marker ", got " e))
                (assert (stringContains? e "ASL_CLI_ARGV0") (str "give-up case: expected error to mention ASL_CLI_ARGV0, got " e)))))
            true)))))

fn ! runProbeCases! ctx: sys/Context probeExe: String expected: String -> Bool
  (let [(pre (list (str "ASL_PRELUDE=" ctx.root "/asl/prelude/prelude.asl")))]
    (and (checkCwdCases! probeExe ctx.root expected)
         (and (checkSelfExeCase! probeExe expected)
              (match (makeOutsideHost! probeExe)
                ((err e) (assert false (str "outside host copy failed: " e)))
                ((ok runner)
                  (let [(passed (and (checkArgv0Case! runner pre probeExe expected)
                                     (and (checkPathCase! runner pre probeExe expected)
                                          (and (checkArgv0OutsidePathInRepoCase! runner pre probeExe expected)
                                               (and (checkPermissionDeniedCase! runner pre)
                                                    (checkGiveUpMessageCase! runner pre))))))
                        (_ (pathRemove (sys/parentOf runner)))]
                    passed))))))

fn ! testDiscoversRootWithoutEnv -> Bool
  (let [(ctxR (sys/context!))]
    (match ctxR
      ((err e) (assert false (str "current context! failed: " e)))
      ((ok ctx)
        (let [(expectedR (expectedRoot!))]
          (match expectedR
            ((err e) (assert false (str "independent expected root (git) failed: " e)))
            ((ok expected)
              (let [(probeR (writeProbe! ctx.root))]
                (match probeR
                  ((err e) (assert false (str "probe setup failed: " e)))
                  ((ok probePath)
                    (let [(exeR (buildProbe! ctx probePath))
                          (_ (pathRemove probePath))]
                      (match exeR
                        ((err e) (assert false (str "probe build failed: " e)))
                        ((ok probeExe)
                          (let [(result (runProbeCases! ctx probeExe expected))
                                (_ (pathRemove (sys/parentOf probeExe)))]
                            result)))))))))))))

fn ! runTests -> Bool
  (testDiscoversRootWithoutEnv)
