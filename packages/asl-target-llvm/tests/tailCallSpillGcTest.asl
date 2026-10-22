(module asl-target-llvm/tests/tailCallSpillGcTest
  :x [runTests]
  :i [(asl-ir/link :a lk)
      (asl-ir/types :a irTy)
      (asl-target-llvm :a llvm)
      (tools/fleet/run :a run)
      (asl/packages/asl-cli/src/system :a sys)
      (asl/packages/asl-cli/src/asl1Cache :a cache)
      (asl/packages/asl-cli/src/nativeBuild :a nb)])

fn clangLink -> String
  "/usr/bin/clang -Wno-override-module -x ir "

fn lib -> String
  " -x none asl/host/out/libaslrt.a -lm -o "

fn asanLink -> String
  "/usr/bin/clang -Wno-override-module -fsanitize=address,undefined -x ir "

; (:m :ref FROZEN-HOSTLESS :do "the ASan runtime is the native variant build nativeBuild.asanRuntime! makes from the runtime sources (cached under .asl/cache/rcRuntime, shared with rcSelfCompileTest), not the retired host build.sh --sanitize")
fn ! asanRuntime! -> (Result String String)
  (let [(r (resultOr (realPath ".") "."))
        (plain (str r "/asl/host/out/libaslrt.a"))
        (cacheDir (str r "/.asl/cache/rcRuntime"))
        (_ (dirCreate (str r "/.asl/cache")))
        (_ (dirCreate cacheDir))
        (ctx (sys/Context :root r :scriptDir "" :argv0 "" :hostBin ""))
        (b (nb/Build :root r :cache cacheDir :tmp cacheDir :lib plain :base "" :clangVersion "" :owner ""
                     :deadlineNs (+ (monotonicNs) 900000000000) :maxDesc 16))]
    (match (cache/nativeAsl1! ctx plain (optionOr (envGet "CLANG") "clang"))
      ((err e) (err (str "native asl1: " e)))
      ((ok asl1) (nb/asanRuntime! b asl1 (str r "/asl/packages")))))

fn asanLib asan: String -> String
  (str " -x none " asan " -lm -o ")

fn asanStress -> String
  "ASAN_OPTIONS=detect_stack_use_after_return=1 ASL_GC_STRESS=1 "

(schema Ran
  (:f exitCode Int64)
  (:f stdout String)
  (:f stderr String))

fn ! shWithin cmd: String timeoutS: Int64 -> Ran
  (let [(base (str (optionOr (envGet "TMPDIR") "/tmp") "/tailCallSpillGcTest." (monotonicNs)))
        (outPath (str base ".out"))
        (errPath (str base ".err"))
        (done (run/runOneLimited (run/job (list "sh" "-c" (str "(" cmd ") > " outPath " 2> " errPath)) "." (run/childEnv (list))) (run/limits timeoutS 32)))
        (outText (resultOr (fileReadString outPath) ""))
        (errText (resultOr (fileReadString errPath) ""))
        (_ (pathRemove outPath))
        (_ (pathRemove errPath))]
    (Ran :exitCode done.exit :stdout outText :stderr (if (= done.verdict "exit") errText (str errText done.out))))

fn ! sh cmd: String -> Ran
  (shWithin cmd 1200)

fn fixtureSource -> String
  (stringJoin (list
    "(module tailSpillMod"
    "  :x [main]"
    "  :i [])"
    ""
    "(schema Boxed (:f payload String))"
    ""
    "fn finish extra: Int64 b: Boxed -> Boxed"
    "  (Boxed :payload (str b.payload \"+\" (stringFromInt64 extra)))"
    ""
    "fn ! tailInto f: T b: Boxed -> Boxed"
    "  (f b)"
    ""
    "fn ! main args: (List String) -> (Result Int64 String)"
    "  (let [(pf (partial finish 7))"
    "        (fresh (Boxed :payload (stringJoin (list \"frag-a\" \"frag-b\" \"frag-c\") \"-\")))"
    "        (result (tailInto pf fresh))]"
    "    (do (println result.payload)"
    "        (ok 0)))")
    "\n")

fn wantOutput -> String
  "frag-a-frag-b-frag-c+7\n"

fn formatDiags ds: (List irTy/IrDiag) -> String
  (stringJoin (map (fn [(d irTy/IrDiag)] -> String (str d.locus ": [" d.code "] " d.message)) ds) "; ")

fn ! compiledText path: String -> (Result String String)
  (match (lk/linkEntry! path)
    ((err ds) (err (formatDiags ds)))
    ((ok m) (match (llvm/emitLlvmProgramNative! m (str m.name ".main"))
              ((err ds) (err (formatDiags ds)))
              ((ok code) (ok code)))))

fn plantSlowAlloc ir: String -> (Option String)
  (let [(anchor "slow:\n  %slowResult = call %Val @objrt.call(%Val %fn, i64 %argc, ptr %argv)")
        (replacement "slow:\n  store i64 -1, ptr @asl_rt_spill\n  %slowResult = call %Val @objrt.call(%Val %fn, i64 %argc, ptr %argv)")]
    (if (stringContains? ir anchor) (some (stringReplace ir anchor replacement)) (none)))

fn notRun why: String -> Ran
  (Ran :exitCode -1 :stdout "" :stderr (str "not run: " why))

(schema StressRuns
  (:f plain Ran)
  (:f stressed Ran))

(schema AsanRuns
  (:f linked Ran)
  (:f run Ran))

fn ! underStress bin: String -> StressRuns
  (StressRuns :plain (sh bin) :stressed (sh (str "ASL_GC_STRESS=1 " bin)))

fn ! underAsanStress ll: String bin: String asan: String -> AsanRuns
  (let [(linked (sh (str (asanLink) ll (asanLib asan) bin)))]
    (AsanRuns :linked linked :run (if (= linked.exitCode 0) (sh (str (asanStress) bin)) (notRun "ASan link failed"))))

fn sameUnderStress label: String r: StressRuns -> Bool
  (do (assert (= r.plain.exitCode 0) (str label ": plain exit 0, got " r.plain.exitCode "; " r.plain.stderr))
      (assert (= r.plain.stdout (wantOutput)) (str label ": plain output; got " r.plain.stdout))
      (assert (= r.stressed.exitCode 0) (str label ": exit under ASL_GC_STRESS=1 " r.stressed.exitCode "; " r.stressed.stderr))
      (assert (= r.stressed.stdout (wantOutput)) (str label ": the fresh record's content (built only through the unrooted spill/slow path) survives collect-on-every-alloc; got " r.stressed.stdout))
      true)

fn sameUnderAsanStress label: String r: AsanRuns -> Bool
  (do (assert (= r.linked.exitCode 0) (str label ": links against the ASan library; " r.linked.stderr))
      (assert (= r.run.exitCode 0) (str label ": exit under ASan fake stacks and ASL_GC_STRESS=1 " r.run.exitCode "; " r.run.stderr))
      (assert (= r.run.stdout (wantOutput)) (str label ": same output under ASan fake stacks and stress; got " r.run.stdout))
      true)

(schema SpillRuns
  (:f sourceWritten Bool)
  (:f code (Result String String))
  (:f llWritten Bool)
  (:f linked Ran)
  (:f stress StressRuns)
  (:f asan AsanRuns))

(schema MutantRuns
  (:f sourceWritten Bool)
  (:f code (Result String String))
  (:f mutated (Option String))
  (:f llWritten Bool)
  (:f linked Ran)
  (:f run Ran))

fn ! spillRuns work: String asan: String -> SpillRuns
  (let [(src (str work "/tailSpillMod.asl"))
        (ll (str work "/tailSpillMod.ll"))
        (bin (str work "/tailSpillMod"))
        (sourceWritten (ok? (fileWrite src (fixtureSource))))
        (code (compiledText src))
        (llWritten (and (ok? code) (ok? (fileWrite ll (resultOr code "")))))
        (linked (if llWritten (sh (str (clangLink) ll (lib) bin)) (notRun "no .ll")))
        (linkedOk (= linked.exitCode 0))]
    (SpillRuns :sourceWritten sourceWritten :code code :llWritten llWritten :linked linked
               :stress (if linkedOk (underStress bin) (StressRuns :plain (notRun "link failed") :stressed (notRun "link failed")))
               :asan (if llWritten (underAsanStress ll (str bin ".asan") asan) (AsanRuns :linked (notRun "no .ll") :run (notRun "no .ll")))))

fn testSpillSurvivesStress r: SpillRuns -> Bool
  (do (assert r.sourceWritten "tailSpillMod: source written")
      (match r.code
        ((err e) (assert false (str "tailSpillMod: links and emits; " e)))
        ((ok code)
          (do (assert r.llWritten "tailSpillMod: .ll written")
              (assert (= r.linked.exitCode 0) (str "tailSpillMod: links; " r.linked.stderr))
              (assert (stringContains? code "musttail call tailcc %Val @tailrt.closure(") "tailInto's (f b) is a musttail closure call spilling through @asl_rt_spill")
              (sameUnderStress "tailSpillMod" r.stress)
              (sameUnderAsanStress "tailSpillMod" r.asan)
              true)))
      true)

fn ! mutantRuns work: String asan: String -> MutantRuns
  (let [(src (str work "/tailSpillMutant.asl"))
        (ll (str work "/tailSpillMutant.ll"))
        (bin (str work "/tailSpillMutant.asan"))
        (sourceWritten (ok? (fileWrite src (fixtureSource))))
        (code (compiledText src))
        (mutated (match code ((ok c) (plantSlowAlloc c)) ((err _) (none))))
        (llWritten (match mutated ((some m) (ok? (fileWrite ll m))) ((none) false)))
        (linked (if llWritten (sh (str (asanLink) ll (asanLib asan) bin)) (notRun "no mutated .ll")))]
    (MutantRuns :sourceWritten sourceWritten :code code :mutated mutated :llWritten llWritten :linked linked
                :run (if (= linked.exitCode 0) (sh (str (asanStress) bin)) (notRun "mutant link failed"))))

fn testMutantIsCaught r: MutantRuns -> Bool
  (do (assert r.sourceWritten "tailSpillMutant: source written")
      (match r.code
        ((err e) (assert false (str "tailSpillMutant: links and emits; " e)))
        ((ok _)
          (match r.mutated
            ((none) (assert false "tailrt.closure's slow: anchor text found in the emitted IR (codegen shape changed; update the anchor)"))
            ((some _)
              (do (assert r.llWritten "tailSpillMutant: mutated .ll written")
                  (assert (= r.linked.exitCode 0) (str "tailSpillMutant: links; " r.linked.stderr))
                  (refute (and (= r.run.exitCode 0) (= r.run.stdout (wantOutput)))
                          (str "tailSpillMutant: clobbering @asl_rt_spill ahead of objrt.call in tailrt.closure's slow label is caught (wrong content or a crash) under stress; got exit " r.run.exitCode " stdout " r.run.stdout " stderr " r.run.stderr))
                  true)))))
      true)

fn ! testChildrenSupervised -> Bool
  (let [(hung (shWithin "sleep 30" 1))]
    (do (assert (= hung.exitCode 124) (str "a child outliving its limit is killed with exit 124, got " hung.exitCode))
        (assert (stringContains? hung.stderr ":timeout") (str "the kill verdict reaches the caller's stderr; got " hung.stderr))
        true))

fn ! runTests -> Bool
  (let [(work (str (optionOr (envGet "TMPDIR") "/tmp") "/tailCallSpillGcTest." (monotonicNs)))
        (made (ok? (dirCreate work)))
        (built (asanRuntime!))
        (asan (resultOr built ""))
        (spill (spillRuns work asan))
        (mutant (mutantRuns work asan))
        (removed (ok? (pathRemove work)))]
    (do (assert made "a fresh work directory is created")
        (assert (ok? built) (str "the native ASan runtime builds: " built))
        (testSpillSurvivesStress spill)
        (testMutantIsCaught mutant)
        (testChildrenSupervised)
        (assert removed "work directory removed")
        true))
