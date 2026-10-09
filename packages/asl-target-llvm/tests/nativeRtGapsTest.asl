(module asl-target-llvm/tests/nativeRtGapsTest
  :x [runTests]
  :i [(asl-ir/link :a lk) (asl-ir/types :a irTy) (asl-proc/coreProcess :a proc) (asl-target-llvm :a llvm)])

fn host -> String
  "asl/host/out/asl-host"

fn fixtureSource -> String
  (str "(module nativeRtInstallerFixture :x [main] :i [(aslWeb/installer :a web)])\n"
       "fn ! main -> (Result Int64 String)\n"
       "  (let [(cfg (web/installerConfig))]\n"
       "    (if (and (= cfg.cli_name \"asl\") (= cfg.repo_url \"https://github.com/GenSEAM/asl.git\"))\n"
       "      (do (println cfg.cli_name) (println cfg.repo_url) (ok 0))\n"
       "      (err \"installer schema values mismatch\")))\n")

fn formatDiags ds: (List irTy/IrDiag) -> String
  (stringJoin (map (fn [(d irTy/IrDiag)] -> String
                       (str d.locus ": [" d.code "] " d.message)) ds) "; ")


fn ! compileNative path: String moduleName: String llPath: String exePath: String -> proc/ProcessOutput
  (mt (lk/linkEntry! path)
    ((err ds) (proc/ProcessOutput :exitCode 1 :stdout "" :stderr (str "link failed: " (formatDiags ds)) :durationMs 0))
    ((ok m)
      (mt (llvm/emitLlvmProgramNative! m (str moduleName ".main"))
        ((err ds) (proc/ProcessOutput :exitCode 1 :stdout "" :stderr (str "LLVM emission failed: " (formatDiags ds)) :durationMs 0))
        ((ok code)
          (do
            (fileWrite llPath code)
            (processRun (str "/usr/bin/clang -Wno-override-module -x ir " llPath
                            " -x none asl/host/out/libaslrt.a -lm -o " exePath)))))))

fn ! testInstallerSchemaParity -> Bool
  (let [(dir (str "asl/packages/asl-target-llvm/tests/.nativeRt-installer-" (stringFromInt64 (monotonicNs))))
        (made (dirCreate dir))
        (path (str dir "/nativeRtInstallerFixture.asl"))
        (llPath (str dir "/nativeRtInstallerFixture.ll"))
        (exePath (str dir "/nativeRtInstallerFixture"))
        (written (fileWrite path (fixtureSource)))
        (native (if (and (ok? made) (ok? written)) (compileNative path "nativeRtInstallerFixture" llPath exePath)
                    (proc/ProcessOutput :exitCode 1 :stdout "" :stderr "fixture setup failed" :durationMs 0)))
        (interp (processRun (str (host) " run " path)))
        (ran (if (= native.exitCode 0) (processRun exePath)
                 (proc/ProcessOutput :exitCode 1 :stdout "" :stderr native.stderr :durationMs 0)))
        (removedExe (if (fileExists? exePath) (pathRemove exePath) (ok ())))
        (removedLl (if (fileExists? llPath) (pathRemove llPath) (ok ())))
        (removedSrc (if (fileExists? path) (pathRemove path) (ok ())))
        (removedDir (if (fileExists? dir) (pathRemove dir) (ok ())))]
    (do
      (assert (ok? made) "temporary fixture directory is created")
      (assert (ok? written) "fixture source is written")
      (assert (= native.exitCode 0) (str "LLVM fixture links with libaslrt.a: " native.stderr))
      (assert (= interp.exitCode 0) (str "asl-host run exits 0: " interp.stderr))
      (assert (= ran.exitCode interp.exitCode) "native exit matches asl-host run")
      (assert (= ran.stdout interp.stdout) "native stdout matches asl-host run for installer schema fields")
      (assert (= ran.exitCode 0) (str "native installer schema fixture passes: " ran.stderr))
      (assert (ok? removedExe) "native executable is removed")
      (assert (ok? removedLl) "LLVM file is removed")
      (assert (ok? removedSrc) "fixture source is removed")
      (assert (ok? removedDir) "temporary directory is removed")
      true))

fn ! runTests -> Bool
  (do
    (assert (testInstallerSchemaParity) "native installer schema fixture matches the interpreter")
    true)
