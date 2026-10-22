; (:m :ref ORGPREMOVE-GCPOLICYLOCK :do "testLock/adopted/baselinePath moved to tools/tests/privateGroundingTest.asl: they check that the shipped defaultMinMib matches an 'adopted' row in .asl/mem/bench/perfBaseline.asn, a private, machine-specific measurement ledger (its :host field literally records this machine's load average at measurement time) that never ships with the published GenSEAM/asl repo; the check itself is unchanged, just relocated")
(module asl-target-llvm/tests/gcPolicyTest
  :x [runTests]
  :i [(asl-ir/link :a lk) (asl-ir/types :a ty) (asl-target-llvm :a llvm) (asl-target-llvm/gcAsl :a gc) (asl-tools/fleet/run :a run)])

fn clangLink -> String
  "/usr/bin/clang -O2 -Wno-override-module -x ir "

fn lib -> String
  " -x none asl/host/out/libaslrt.a -lm -o "

(schema Captured
  (:f exitCode Int64)
  (:f stdout String)
  (:f stderr String))

fn ! sh cmd: String -> Captured
  (let [(root (resultOr (realPath ".") "."))
        (prelude (optionOr (envGet "ASL_PRELUDE") (str root "/asl/prelude/prelude.asl")))
        (path (optionOr (envGet "PATH") "/usr/bin:/bin"))
        (base (str (optionOr (envGet "TMPDIR") "/tmp") "/gcPolicyTest." (monotonicNs)))
        (outPath (str base ".out"))
        (errPath (str base ".err"))
        (done (run/runOneLimited (run/job (list "sh" "-c" (str "(cd '" root "' && (" cmd ")) > " outPath " 2> " errPath)) root
                                         (run/childEnv (list (str "ASL_ROOT=" root) (str "ASL_PRELUDE=" prelude) (str "PATH=" path))))
                                 (run/limits 1200 32)))
        (outText (resultOr (fileReadString outPath) ""))
        (errText (resultOr (fileReadString errPath) ""))
        (_ (pathRemove outPath))
        (_ (pathRemove errPath))]
    (Captured :exitCode done.exit :stdout outText :stderr (if (= done.verdict "exit") errText (str errText done.out))))

fn formatDiags ds: (List ty/IrDiag) -> String
  (stringJoin (map (fn [(d ty/IrDiag)] -> String (str d.locus ": [" d.code "] " d.message)) ds) "; ")

fn statsLine text: String -> String
  (optionOr (listHead (filter (fn [(l String)] -> Bool (stringStartsWith? l "(:gcStats ")) (stringLines text))) "")

fn policyPart line: String -> String
  (stringJoin (filter (fn [(f String)] -> Bool (not (stringStartsWith? f "totalGCNs "))) (stringSplit line ":")) ":")

fn ! emitted path: String -> String
  (match (lk/linkEntry! path)
    ((err ds) (do (assert false (str path ": links; " (formatDiags ds))) ""))
    ((ok m) (match (llvm/emitLlvmProgramNative! m (str m.name ".main"))
              ((err ds) (do (assert false (str path ": emits; " (formatDiags ds))) ""))
              ((ok code) code))))

fn ! testEffective work: String -> Bool
  (let [(ll (str work "/list.ll"))
        (bin (str work "/list"))
        (mib (stringFromInt64 (gc/defaultMinMib)))]
    (do (assert (ok? (fileWrite ll (emitted "bench/native/list.asl"))) "list: .ll written")
        (let [(linked (sh (str (clangLink) ll (lib) bin)))]
          (assert (= linked.exitCode 0) (str "list: links against libaslrt.a; " linked.stderr)))
        (let [(plain (sh (str "ASL_GC_STATS=1 " bin " 3000000")))
              (set (sh (str "ASL_GC_STATS=1 ASL_GC_MIN_MIB=" mib " " bin " 3000000")))
              (small (sh (str "ASL_GC_STATS=1 ASL_GC_MIN_MIB=1 " bin " 3000000")))]
          (do (assert (= plain.exitCode 0) (str "list: exits 0 with no setting; " plain.stderr))
              (assert (stringContains? (statsLine plain.stderr) ":collections ") (str "list: prints its collector stats; " plain.stderr))
              (refute (stringContains? (statsLine plain.stderr) ":collections 0 ") (str "list: collects with no setting; " (statsLine plain.stderr)))
              (assert (= (policyPart (statsLine plain.stderr)) (policyPart (statsLine set.stderr)))
                      (str "list: no setting collects as ASL_GC_MIN_MIB=" mib "; unset " (statsLine plain.stderr) " set " (statsLine set.stderr)))
              (refute (= (policyPart (statsLine plain.stderr)) (policyPart (statsLine small.stderr)))
                      (str "list: no setting collects unlike ASL_GC_MIN_MIB=1, so the setting is read; unset " (statsLine plain.stderr) " 1 MiB " (statsLine small.stderr)))
              true))))

fn ! runTests -> Bool
  (let [(made (sh "mktemp -d"))
        (work (stringReplace made.stdout "\n" ""))]
    (do (assert (= made.exitCode 0) "mktemp -d makes a work directory")
        (testEffective work)
        (assert (= (sh (str "rm -rf " work)).exitCode 0) "work directory removed")
        true))
