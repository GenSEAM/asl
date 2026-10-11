(module asl-target-llvm/tests/lowerPairOptionTest
  :x [runTests]
  :i [(asl-ir/link :a lk) (asl-ir/types :a ty) (asl-target-llvm :a llvm) (tools/fleet/run :a run)])

(schema Captured
  (:f exitCode Int64)
  (:f stdout String)
  (:f stderr String))

fn shellQuote s: String -> String
  (str "'" (stringReplace s "'" "'\\''") "'")

fn ! shWithin cmd: String timeoutS: Int64 -> Captured
  (let [(root (optionOr (envGet "ASL_ROOT") "."))
        (prelude (optionOr (envGet "ASL_PRELUDE") (str root "/asl/prelude/prelude.asl")))
        (path (optionOr (envGet "PATH") "/usr/bin:/bin"))
        (base (str (optionOr (envGet "TMPDIR") "/tmp") "/lowerPairOptionTest." (monotonicNs)))
        (outPath (str base ".out"))
        (errPath (str base ".err"))
        (done (run/runOneLimited (run/job (list "sh" "-c" (str "(cd " (shellQuote root) " && (" cmd ")) > " (shellQuote outPath) " 2> " (shellQuote errPath))) root
                                         (run/childEnv (list (str "ASL_ROOT=" root) (str "ASL_PRELUDE=" prelude) (str "PATH=" path))))
                                 (run/limits timeoutS 32)))
        (outText (resultOr (fileReadString outPath) ""))
        (errText (resultOr (fileReadString errPath) ""))
        (_ (pathRemove outPath))
        (_ (pathRemove errPath))]
    (Captured :exitCode done.exit :stdout outText :stderr (if (= done.verdict "exit") errText (str errText done.out))))

fn ! sh cmd: String -> Captured
  (shWithin cmd 1200)

fn fixtureSource -> String
  (str "(module lowerPairOptionFixture :x [main] :i [(asl-ir/types :a ty)])\n"
       "fn ! main -> (Result Int64 String)\n"
       "  (let [(p (pair 20 22))\n"
       "        (someValue (optionOr (some 3) 0))\n"
       "        (noneValue (optionOr (none) 7))\n"
       "        (reversed (listReverse (list 1 2 3)))\n"
       "        (firstValue (optionOr (listHead reversed) 0))\n"
       "        (linked (ty/ssaModule \"lowerPairOptionFixture\" (list) (list) (list) (list) (list) (list)))]\n"
       "    (if (and (= (+ (pairFirst p) (pairSecond p)) 42)\n"
       "             (and (= someValue 3)\n"
       "                  (and (= noneValue 7)\n"
       "                       (and (= firstValue 3) (= linked.name \"lowerPairOptionFixture\")))))\n"
       "      (do (println (pairFirst p)) (println (pairSecond p))\n"
       "           (println someValue) (println noneValue) (println firstValue)\n"
       "           (println linked.name) (ok 0))\n"
       "      (err \"lowered builtin or imported call mismatch\")))\n")

fn formatDiags ds: (List ty/IrDiag) -> String
  (stringJoin (map (fn [(d ty/IrDiag)] -> String
                       (str d.locus ": [" d.code "] " d.message)) ds) "; ")

fn sourceFixture -> String
  (str "(module lowerPairOptionSource :x [main] :i [])\n"
       "fn ! main -> (Result Int64 String)\n"
       "  (let [(p (pair 20 22))\n"
       "        (reversed (listReverse (list 3 4)))\n"
       "        (firstValue (pairFirst p))\n"
       "        (secondValue (pairSecond p))\n"
       "        (headValue (optionOr (listHead reversed) 0))]\n"
       "    (do (println firstValue) (println secondValue) (println headValue) (ok 0)))\n")

fn ! testSourceBuiltinLowering -> Bool
  (let [(lowered (lk/lowerSourceLinked! (sourceFixture)))]
    (assert (ok? lowered) (str "lowerSourceLinked! handles pair, pair accessors, optionOr, and listReverse against the real prelude: " (mt lowered ((ok _) "ok") ((err ds) (formatDiags ds)))))
    true)

fn ! compileNative path: String llPath: String exePath: String -> Captured
  (mt (lk/linkEntry! path)
    ((err ds) (Captured :exitCode 1 :stdout "" :stderr (str "link failed: " (formatDiags ds))))
    ((ok m)
      (mt (llvm/emitLlvmProgramNative! m "lowerPairOptionFixture.main")
        ((err ds) (Captured :exitCode 1 :stdout "" :stderr (str "LLVM emission failed: " (formatDiags ds))))
        ((ok code)
          (do
            (fileWrite llPath code)
            (sh (str "/usr/bin/clang -Wno-override-module -x ir " (shellQuote llPath)
                    " -x none asl/host/out/libaslrt.a -lm -o " (shellQuote exePath))))))))

fn ! testNativeParity -> Bool
  (let [(dir (str "asl/packages/asl-target-llvm/tests/.tmp-lower-pair-option-" (stringFromInt64 (monotonicNs))))
        (made (dirCreate dir))
        (path (str dir "/lowerPairOptionFixture.asl"))
        (llPath (str dir "/lowerPairOptionFixture.ll"))
        (exePath (str dir "/lowerPairOptionFixture"))
        (written (fileWrite path (fixtureSource)))
        (native (if (and (ok? made) (ok? written)) (compileNative path llPath exePath)
                    (Captured :exitCode 1 :stdout "" :stderr "fixture setup failed")))
        (interp (sh (str (shellQuote (optionOr (envGet "ASL_HOST") "asl/host/out/asl-host")) " run " (shellQuote path))))
        (ran (if (= native.exitCode 0) (sh (shellQuote exePath))
                 (Captured :exitCode 1 :stdout "" :stderr native.stderr)))
        (removedExe (if (fileExists? exePath) (pathRemove exePath) (ok ())))
        (removedLl (if (fileExists? llPath) (pathRemove llPath) (ok ())))
        (removedSrc (if (fileExists? path) (pathRemove path) (ok ())))
        (removedDir (if (fileExists? dir) (pathRemove dir) (ok ())))]
    (do
      (assert (ok? made) "temporary fixture directory is created")
      (assert (ok? written) "fixture source is written")
      (assert (= native.exitCode 0) (str "linked native fixture builds: " native.stderr))
      (assert (= interp.exitCode 0) (str "asl-host run exits 0: " interp.stderr))
      (assert (= ran.exitCode interp.exitCode) "native exit matches asl-host run")
      (assert (= ran.stdout interp.stdout) "native stdout matches asl-host for optionOr, pair fields, listReverse, and an imported call")
      (assert (= ran.exitCode 0) (str "native fixture validates all lowered values: " ran.stderr))
      (assert (ok? removedExe) "native executable is removed")
      (assert (ok? removedLl) "LLVM file is removed")
      (assert (ok? removedSrc) "fixture source is removed")
      (assert (ok? removedDir) "temporary directory is removed")
      true))

fn ! compileViaEmitLlvmSource llPath: String exePath: String -> Captured
  (mt (llvm/emitLlvmSource (fixtureSource) "main")
    ((err ds) (Captured :exitCode 1 :stdout "" :stderr (str "emitLlvmSource failed: " (formatDiags ds))))
    ((ok code)
      (do
        (fileWrite llPath code)
        (sh (str "/usr/bin/clang -Wno-override-module -x ir " (shellQuote llPath)
                " -x none asl/host/out/libaslrt.a -lm -o " (shellQuote exePath))))))

fn ! testEmitLlvmSourceCliPath -> Bool

  (let [(dir (str "asl/packages/asl-target-llvm/tests/.tmp-emit-llvm-source-" (stringFromInt64 (monotonicNs))))
        (made (dirCreate dir))
        (path (str dir "/lowerPairOptionFixture.asl"))
        (llPath (str dir "/lowerPairOptionFixture.ll"))
        (exePath (str dir "/lowerPairOptionFixture"))
        (written (fileWrite path (fixtureSource)))
        (native (if (and (ok? made) (ok? written)) (compileViaEmitLlvmSource llPath exePath)
                    (Captured :exitCode 1 :stdout "" :stderr "fixture setup failed")))
        (interp (sh (str (shellQuote (optionOr (envGet "ASL_HOST") "asl/host/out/asl-host")) " run " (shellQuote path))))
        (ran (if (= native.exitCode 0) (sh (shellQuote exePath))
                 (Captured :exitCode 1 :stdout "" :stderr native.stderr)))
        (removedExe (if (fileExists? exePath) (pathRemove exePath) (ok ())))
        (removedLl (if (fileExists? llPath) (pathRemove llPath) (ok ())))
        (removedSrc (if (fileExists? path) (pathRemove path) (ok ())))
        (removedDir (if (fileExists? dir) (pathRemove dir) (ok ())))]
    (do
      (assert (ok? made) "temporary fixture directory is created")
      (assert (ok? written) "fixture source is written")
      (assert (= native.exitCode 0) (str "llvm/emitLlvmSource (the bare CLI entry, no path argument) builds and links: " native.stderr))
      (assert (= interp.exitCode 0) (str "asl-host run exits 0: " interp.stderr))
      (assert (= ran.exitCode interp.exitCode) "emitLlvmSource's native build exits like asl-host run")
      (assert (= ran.stdout interp.stdout) "emitLlvmSource's native build prints the same pair/optionOr/listReverse/imported-call values as asl-host run")
      (assert (= ran.exitCode 0) (str "emitLlvmSource's native fixture validates all lowered values: " ran.stderr))
      (assert (ok? removedExe) "native executable is removed")
      (assert (ok? removedLl) "LLVM file is removed")
      (assert (ok? removedSrc) "fixture source is removed")
      (assert (ok? removedDir) "temporary directory is removed")
      true))

fn ! runTests -> Bool
  (do
    (assert (testSourceBuiltinLowering) "linking a bare source file against the real prelude resolves pair/optionOr/pairFirst/pairSecond/listReverse")
    (assert (testNativeParity) "the linked module's builtin and imported calls agree between asl-host run and the native build")
    (assert (testEmitLlvmSourceCliPath) "the asl-target-llvm emitLlvmSource CLI entry (LOWERPQ) resolves the same prelude functions and imported call as linkEntry!, matching asl-host run")
    true)
