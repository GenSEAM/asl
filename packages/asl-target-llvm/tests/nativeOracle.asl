(module asl-target-llvm/tests/nativeOracle
  :x [ProcOut independentRun! selfTestBinary!]
  :i [(tools/nativeTest :a nt)])

; (:m :ref HL-E-LLVM :do "HL-E-LLVM (asl-host deleted): several asl-target-llvm suites used asl-host to run a fixture's SOURCE as a parity oracle for a hand-built native binary (the suite's own direct asl-ir/lower + asl-target-llvm emit + clang link). With asl-host gone there is no interpreter left, so independentRun! below is the replacement oracle: it builds and runs the same source through tools/nativeTest's own prepareRun/runProc pipeline (full asl-parser + asl-checker + asl-ir/lower + its own build cache), a genuinely separate code path from each suite's manual backend calls and clang invocation, never the binary under test. Proven host-free even for brand-new, never-before-compiled fixtures: tools/nativeTest's in-process API (this module) has no host dependency; only going through it as a *subprocess* via (asl run tools/nativeTest.asl run ...) does, because that route also needs bin/asl's own nativeCli self-build cache to be warm for tools/nativeTest.asl, which a cold one can still resolve by falling back to a now-absent asl-host (confirmed: 'nativeTest: asl-host not found at asl/host/out/asl-host...'). selfTestBinary! below is for suites that genuinely need tools/nativeTest.asl itself as an external OS subprocess (cwd/env-var/ASL_ROOT routing tests that cannot be faked in-process): it calls nt/prepareRun on tools/nativeTest.asl's OWN source in-process (zero host dependency, confirmed on a cold cache) and returns the path to the resulting native binary, which behaves identically to the old 'asl-host run tools/nativeTest.asl run ...' when exec'd directly as '<binary> run <path> <args>' (confirmed: NATIVE-CACHE marker, matching stdout, exit 0, no stray fallback diagnostics)")

(schema ProcOut
  (:f exitCode Int64)
  (:f stdout String)
  (:f stderr String))

fn ! independentRun! src: String args: (List String) label: String -> ProcOut
  (let [(workDir (str "asl/tmp/nativeOracle-" label "-" (stringFromInt64 (monotonicNs))))
        (made (dirCreate workDir))
        (path (str workDir "/fixture.asl"))
        (written (if (ok? made) (fileWrite path src) (err "workDir not created")))]
    (if (not (ok? written))
      (let [(_ (pathRemove workDir))] (ProcOut :exitCode 127 :stdout "" :stderr (str "independentRun!: cannot write fixture: " written)))
      (let [(built (nt/prepareRun path label))
            (bin (optionOr built.binary ""))
            (out (if (stringEmpty? bin)
                   (ProcOut :exitCode 127 :stdout "" :stderr (str "independentRun!: " built.reason))
                   (let [(r (nt/runProc (listAppend (list bin) args) (none)))]
                     (ProcOut :exitCode r.exitCode :stdout r.stdout :stderr r.stderr))))
            (_ (pathRemove workDir))]
        out)))

fn ! selfTestBinary! -> (Result String String)
  (let [(built (nt/prepareRun "tools/nativeTest.asl" "selfBuild"))]
    (mt built.binary
      ((none) (err built.reason))
      ((some bin) (realPath bin))))
