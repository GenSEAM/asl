(module asl-target-llvm/tests/nativeGlobalsTest
  :x [runTests]
  :i [(tools/nativeTest :a nt)
      (asl-target-llvm/ssa :a llvm)])

fn libSource name: String -> String
  (str "(module " name "\n  :x [spawnEcho]\n  :i [])\n\n"
       "(println \"libA loaded\")\n\n"
       "fn ! spawnEcho word: String -> (Result Int64 String)\n  (processSpawn (str \"echo \" word))\n")

fn mainSource name: String libName: String -> String
  (str "(module " name "\n  :x [main]\n  :i [(" libName " :a a)])\n\n"
       "fn ! main -> (Result Int64 String)\n"
       "  (mt (a/spawnEcho \"shared\")\n"
       "    ((err e) (err e))\n"
       "    ((ok h) (mt (processWait h 5000)\n"
       "              ((err e) (err e))\n"
       "              ((ok out) (do (print out.stdout) (ok 0))))))\n")

fn ! testLinkInits -> Bool
  (let [(entryIr "define i32 @main() {\nbb.entry:\n  call void @rterr.reportInit()\n  call void @init.e()\n  ret i32 0\n}\ndefine void @init.e() {\nbb.entry:\n  ret void\n}\n")
        (linked (llvm/linkInits entryIr (list "prelude" "libA" "e")))
        (text (resultOr linked ""))
        (calls (stringIndexOf text "call void @init.prelude()\n  call void @init.libA()\n  call void @init.e()"))]
    (do (assert (ok? linked) "linkInits accepts an entry IR with one @main report anchor")
        (assert (some? calls) "linked inits run in dependency order before the entry's own init")
        (assert (stringContains? text "declare void @init.libA()\n") "a linked module's init is declared")
        (refute (stringContains? text "declare void @init.e()") "the entry's own init is not redeclared")
        (assert (err? (llvm/linkInits "define void @f() {\nbb.entry:\n  ret void\n}\n" (list "libA"))) "an IR without @main cannot take linked inits")
        (assert (llvm/definesInit? (llvm/ensureInit "" "prelude") "prelude") "ensureInit defines an empty init")
        (assert (= (llvm/ensureInit entryIr "e") entryIr) "ensureInit keeps an existing init")
        true))

; (:m :ref HL-E-LLVM :do "HL-E-LLVM (asl-host deleted): libA/mainB is a fixed, deterministic fixture (only its generated path varies), so hostRun below is a one-time recorded capture of asl-host's own output for this exact fixture, taken before HL-DELETE removed the binary. The native side already builds through tools/nativeTest's own prepareRunIn, so it cannot also serve as this suite's independent oracle without comparing native against itself; the recorded capture is used instead")

fn recordedHostRun -> nt/ProcOut
  (nt/ProcOut :exitCode 0 :stdout "libA loaded\nshared\n" :stderr "")

fn ! testSeparateModules -> Bool
  (let [(workDir (str ".asl/cache/nativeGlobalsTest-" (monotonicNs)))
        (pkg (str workDir "/pkg"))
        (_ (dirCreate pkg))
        (libPath (str pkg "/libA.asl"))
        (mainPath (str pkg "/mainB.asl"))
        (libName (nt/importPathOf libPath))
        (_ (fileWrite libPath (libSource libName)))
        (_ (fileWrite mainPath (mainSource (nt/importPathOf mainPath) libName)))
        (hostRun (recordedHostRun))
        (built (nt/prepareRunIn (str workDir "/cache") mainPath "fp_native_globals"))
        (bin (optionOr built.binary ""))
        (nativeRun (if (stringEmpty? bin) (nt/ProcOut :exitCode 127 :stdout "" :stderr built.reason) (nt/runProc (list bin) (none))))
        (_ (pathRemove workDir))]
    (do (assert (= hostRun.exitCode 0) "recorded asl-host output exits 0")
        (assert (= hostRun.stdout "libA loaded\nshared\n") "recorded asl-host output prints the imported module's top-level line and the spawned output")
        (assert (some? built.binary) (str "per-module native build links: " built.reason))
        (assert (= nativeRun.exitCode hostRun.exitCode) (str "native exit equals the recorded asl-host output: " nativeRun.stderr))
        (assert (= nativeRun.stdout hostRun.stdout) (str "native stdout equals the recorded asl-host output: " nativeRun.stdout))
        true))

fn ! runTests -> Bool
  (and (testLinkInits) (testSeparateModules))
