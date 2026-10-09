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
    "  (mt (sys/context!)\n"
    "    ((ok c) (do (println c.root) (ok 0)))\n"
    "    ((err e) (do (eprintln e) (ok 1))))\n")

fn ! writeProbe! root: String -> (Result String String)
  (let [(dir (str root "/.asl/tmp"))
        (made (dirCreate dir))]
    (mt made
      ((err e) (err e))
      ((ok _)
        (let [(path (str dir "/rootDiscoveryProbe_" (stringFromInt64 (monotonicNs)) ".asl"))
              (written (fileWrite path (probeSource)))]
          (mt written
            ((err e) (err e))
            ((ok _) (ok path)))))))

fn ! makeDir! path: String -> (Result String String)
  (mt (dirCreate path) ((err e) (err e)) ((ok _) (ok path)))

fn ! makeTempCwd! root: String -> (Result String String)
  (makeDir! (str root "/.asl/tmp/rootDiscoveryCwd_" (stringFromInt64 (monotonicNs))))

fn ! makeOutsideCwd! -> (Result String String)
  (makeDir! (str "/tmp/rootDiscoveryOutside_" (stringFromInt64 (monotonicNs))))

fn ! makePathDir! hostBin: String -> (Result String String)
  (let [(dir (str "/tmp/rootDiscoveryPath_" (stringFromInt64 (monotonicNs))))
        (made (dirCreate dir))]
    (mt made
      ((err e) (err e))
      ((ok _)
        (let [(linked (pathSymlink hostBin (str dir "/asl-host")))]
          (mt linked
            ((err e) (err e))
            ((ok _) (ok dir)))))))

fn ! makeOutsideExeCopy! hostBin: String -> (Result String String)
  (let [(dir (str "/tmp/rootDiscoveryExeCopy_" (stringFromInt64 (monotonicNs))))
        (made (dirCreate dir))]
    (mt made
      ((err e) (err e))
      ((ok _)
        (let [(path (str dir "/decoy-exe"))
              (bytesR (fileReadBytes hostBin))]
          (mt bytesR
            ((err e) (err e))
            ((ok bytes)
              (let [(writtenR (fileWrite path bytes))]
                (mt writtenR
                  ((err e) (err e))
                  ((ok _) (ok path))))))))))

fn ! makeDeniedCandidate! -> (Result String String)
  (let [(base (str "/tmp/rootDiscoveryDenied_" (stringFromInt64 (monotonicNs))))
        (sub (str base "/sub"))
        (madeBase (dirCreate base))]
    (mt madeBase
      ((err e) (err e))
      ((ok _)
        (let [(madeSub (dirCreate sub))]
          (mt madeSub
            ((err e) (err e))
            ((ok _)
              (let [(file (str sub "/decoy-exe"))
                    (writtenR (fileWrite file "x"))]
                (mt writtenR
                  ((err e) (err e))
                  ((ok _)
                    (let [(chmodR (fileChmod sub 0))]
                      (mt chmodR
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

fn ! runProbeEnv! hostBin: String probePath: String cwd: String extra: (List String) -> (Result String String)
  (let [(captureR (sys/captureWith! (list hostBin "run" probePath) (some cwd) extra))]
    (mt captureR
      ((err e) (err e))
      ((ok captured) (okOrFailed captured))))

fn ! runProbe! hostBin: String probePath: String cwd: String -> (Result String String)
  (runProbeEnv! hostBin probePath cwd (list))

fn ! gitBin! -> String
  (optionOr (sys/onPath! "git") "/usr/bin/git")

fn ! expectedRoot! -> (Result String String)
  (let [(captureR (sys/capture! (list (gitBin!) "rev-parse" "--show-toplevel") (none)))]
    (mt captureR
      ((err e) (err e))
      ((ok captured)
        (if (= captured.exitCode 0)
          (ok (sys/stripTrailingNewlines captured.stdout))
          (err (str "git rev-parse --show-toplevel failed: " captured.stderr))))))

fn ! checkDiscovered r: (Result String String) expected: String label: String -> Bool
  (do
    (mt r
      ((ok found) (assert (= found expected) (str label ": expected " expected " got " found)))
      ((err e) (assert false (str label " failed: " e))))
    true)

fn ! resolveHostBin ctx: sys/Context -> String
  (optionOr (envGet "ASL_HOST") ctx.hostBin)

fn ! checkCwdCases! hostBin: String probePath: String root: String expected: String -> Bool
  (let [(nestedR (makeTempCwd! root))]
    (mt nestedR
      ((err e) (assert false (str "temp cwd setup failed: " e)))
      ((ok nestedCwd)
        (let [(fromRoot (runProbe! hostBin probePath root))
              (fromNested (runProbe! hostBin probePath nestedCwd))
              (_ (pathRemove nestedCwd))]
          (and (checkDiscovered fromRoot expected "from repo root")
               (checkDiscovered fromNested expected "from a nested cwd"))))))

fn ! checkSelfExeCase! hostBin: String probePath: String expected: String -> Bool
  (let [(outsideR (makeOutsideCwd!))]
    (mt outsideR
      ((err e) (assert false (str "outside cwd setup failed: " e)))
      ((ok outside)
        (let [(found (runProbeEnv! hostBin probePath outside (list "PATH=/rootDiscoveryTest-no-such-path")))
              (_ (pathRemove outside))]
          (checkDiscovered found expected "from outside the repo via the running exe")))))

fn ! makeOutsideHost! hostBin: String -> (Result String String)
  (mt (makeOutsideExeCopy! hostBin)
    ((err e) (err e))
    ((ok path) (mt (fileChmod path 493) ((err e) (err e)) ((ok _) (ok path)))))

fn ! checkArgv0Case! runner: String pre: (List String) hostBin: String probePath: String expected: String -> Bool
  (let [(outsideR (makeOutsideCwd!))]
    (mt outsideR
      ((err e) (assert false (str "outside cwd setup failed: " e)))
      ((ok outside)
        (let [(found (runProbeEnv! runner probePath outside (listAppend pre (list (str "ASL_CLI_ARGV0=" hostBin)))))
              (_ (pathRemove outside))]
          (checkDiscovered found expected "from outside the repo via ASL_CLI_ARGV0")))))

fn ! checkPathCase! runner: String pre: (List String) hostBin: String probePath: String expected: String -> Bool
  (let [(outsideR (makeOutsideCwd!))]
    (mt outsideR
      ((err e) (assert false (str "outside cwd setup failed: " e)))
      ((ok outside)
        (let [(dirR (makePathDir! hostBin))]
          (mt dirR
            ((err e) (do (pathRemove outside) (assert false (str "PATH dir setup failed: " e))))
            ((ok pathDir)
              (let [(found (runProbeEnv! runner probePath outside (listAppend pre (list (str "PATH=" pathDir)))))
                    (_ (pathRemove outside))
                    (_ (pathRemove pathDir))]
                (checkDiscovered found expected "from outside the repo via PATH"))))))))

fn ! checkArgv0OutsidePathInRepoCase! runner: String pre: (List String) hostBin: String probePath: String expected: String -> Bool
  (let [(outsideR (makeOutsideCwd!))]
    (mt outsideR
      ((err e) (assert false (str "outside cwd setup failed: " e)))
      ((ok outside)
        (let [(exeR (makeOutsideExeCopy! hostBin))]
          (mt exeR
            ((err e) (do (pathRemove outside) (assert false (str "decoy exe setup failed: " e))))
            ((ok decoyExe)
              (let [(dirR (makePathDir! hostBin))]
                (mt dirR
                  ((err e) (do (pathRemove outside) (pathRemove (sys/parentOf decoyExe)) (assert false (str "PATH dir setup failed: " e))))
                  ((ok pathDir)
                    (let [(found (runProbeEnv! runner probePath outside (listAppend pre (list (str "ASL_CLI_ARGV0=" decoyExe) (str "PATH=" pathDir)))))
                          (_ (pathRemove outside))
                          (_ (pathRemove (sys/parentOf decoyExe)))
                          (_ (pathRemove pathDir))]
                      (checkDiscovered found expected "ASL_CLI_ARGV0 outside the repo, PATH holding the real one")))))))))))

fn ! checkPermissionDeniedCase! runner: String pre: (List String) probePath: String -> Bool
  (let [(outsideR (makeOutsideCwd!))]
    (mt outsideR
      ((err e) (assert false (str "outside cwd setup failed: " e)))
      ((ok outside)
        (let [(deniedR (makeDeniedCandidate!))]
          (mt deniedR
            ((err e) (do (pathRemove outside) (assert false (str "denied candidate setup failed: " e))))
            ((ok deniedFile)
              (let [(found (runProbeEnv! runner probePath outside (listAppend pre (list (str "ASL_CLI_ARGV0=" deniedFile) "PATH=/rootDiscoveryTest-no-such-path"))))
                    (_ (removeDeniedCandidate! deniedFile))
                    (_ (pathRemove outside))]
                (do
                  (mt found
                    ((ok r) (assert false (str "permission-denied case: expected an error, found root " r)))
                    ((err e) (assert (stringContains? e "permissionDenied") (str "permission-denied case: expected error to mention permissionDenied, got " e))))
                  true))))))))

fn ! checkGiveUpMessageCase! runner: String pre: (List String) probePath: String -> Bool
  (let [(marker (str "giveup" (stringFromInt64 (monotonicNs))))
        (outside (str "/tmp/rootDiscoveryOutside_" marker))
        (madeR (makeDir! outside))]
    (mt madeR
      ((err e) (assert false (str "outside cwd setup failed: " e)))
      ((ok _)
        (let [(found (runProbeEnv! runner probePath outside (listAppend pre (list "PATH=/rootDiscoveryTest-no-such-path"))))
              (_ (pathRemove outside))]
          (do
            (mt found
              ((ok r) (assert false (str "give-up case: expected an error, found root " r)))
              ((err e) (do
                (assert (stringContains? e marker) (str "give-up case: expected error to mention cwd marker " marker ", got " e))
                (assert (stringContains? e "ASL_CLI_ARGV0") (str "give-up case: expected error to mention ASL_CLI_ARGV0, got " e)))))
            true)))))

fn ! runProbeCases! ctx: sys/Context probePath: String expected: String -> Bool
  (let [(hostBin (resolveHostBin ctx))
        (pre (list (str "ASL_PRELUDE=" ctx.root "/asl/prelude/prelude.asl")))]
    (and (checkCwdCases! hostBin probePath ctx.root expected)
         (and (checkSelfExeCase! hostBin probePath expected)
              (mt (makeOutsideHost! hostBin)
                ((err e) (assert false (str "outside host copy failed: " e)))
                ((ok runner)
                  (let [(passed (and (checkArgv0Case! runner pre hostBin probePath expected)
                                     (and (checkPathCase! runner pre hostBin probePath expected)
                                          (and (checkArgv0OutsidePathInRepoCase! runner pre hostBin probePath expected)
                                               (and (checkPermissionDeniedCase! runner pre probePath)
                                                    (checkGiveUpMessageCase! runner pre probePath))))))
                        (_ (pathRemove (sys/parentOf runner)))]
                    passed))))))

fn ! testDiscoversRootWithoutEnv -> Bool
  (let [(ctxR (sys/context!))]
    (mt ctxR
      ((err e) (assert false (str "current context! failed: " e)))
      ((ok ctx)
        (let [(expectedR (expectedRoot!))]
          (mt expectedR
            ((err e) (assert false (str "independent expected root (git) failed: " e)))
            ((ok expected)
              (let [(probeR (writeProbe! ctx.root))]
                (mt probeR
                  ((err e) (assert false (str "probe setup failed: " e)))
                  ((ok probePath)
                    (let [(result (runProbeCases! ctx probePath expected))
                          (_ (pathRemove probePath))]
                      result))))))))))

fn ! runTests -> Bool
  (testDiscoversRootWithoutEnv)
