(module asl-target-llvm/tests/nativeRtGapsTest
  :x [runTests]
  :i [(asl-ir/link :a lk) (asl-ir/types :a irTy) (asl-proc/coreProcess :a proc) (asl-target-llvm :a llvm)])

; (:m :ref HL-E-LLVM :do "HL-E-LLVM (asl-host deleted): the parity oracle used to be a live asl-host interpreting fixtureSource over aslWeb/installer's InstallerConfig (cli_name/repo_url). 3e490cac6 (WEB-ASL-NATIVE, the aslang.dev rebuild) deleted asl/web/src/scripts/installer.asl and its installerConfig entirely, with no successor of that exact shape anywhere in the tree; the nearest live schema-record generator serving the same NATIVE-RT purpose (a schema-record flowing through link+LLVM emission+native run, replacing an invalid keyword-headed value) is aslPack/dist's DistConfig/makeDistConfig, so the fixture now exercises that real, still-live module instead. makeDistConfig's repoUrl and npmPackageName fields are literal constants in asl/packages/asl-pack/src/dist.asl, so the expected value below is read straight from that source, not a recorded host run")

fn interpExpected -> proc/ProcessOutput
  (proc/ProcessOutput :exitCode 0 :stdout "asl\nhttps://github.com/GenSEAM/asl.git\n" :stderr "" :durationMs 0)

fn fixtureSource -> String
  (str "(module nativeRtInstallerFixture :x [main] :i [(aslPack/dist :a dist)])\n"
       "fn ! main -> (Result Int64 String)\n"
       "  (let [(cfg (dist/makeDistConfig \"0.0.0\"))]\n"
       "    (if (and (= cfg.npmPackageName \"asl\") (= cfg.repoUrl \"https://github.com/GenSEAM/asl.git\"))\n"
       "      (do (println cfg.npmPackageName) (println cfg.repoUrl) (ok 0))\n"
       "      (err \"dist schema values mismatch\")))\n")

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
        (interp (interpExpected))
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
      (assert (= interp.exitCode 0) "expected dist-schema output exits 0")
      (assert (= ran.exitCode interp.exitCode) "native exit matches the expected dist-schema output")
      (assert (= ran.stdout interp.stdout) "native stdout matches the expected dist-schema fields")
      (assert (= ran.exitCode 0) (str "native dist-schema fixture passes: " ran.stderr))
      (assert (ok? removedExe) "native executable is removed")
      (assert (ok? removedLl) "LLVM file is removed")
      (assert (ok? removedSrc) "fixture source is removed")
      (assert (ok? removedDir) "temporary directory is removed")
      true))

fn ! runTests -> Bool
  (do
    (assert (testInstallerSchemaParity) "native dist-schema fixture matches the expected literal values")
    true)
