(module aslConform/mutant :x [applyMutant verifyMutantKilled getMutantTarget getMutantKilledCase runIsolatedMutantTrial!] :i [(aslConform/types :a ty) (asl-target-c :a c11) (asl-target-py/emitPy :a py) (asl-proc/coreProcess :a proc)])

fn applyMutant m: ty/SemanticsMutant originalCode: Str -> Str
  (let [(mid m.id)] (cond ((= mid "divModFloorOmitMutant") (stringReplace originalCode "//" "/")) ((= mid "divModTruncOmitMutant") (stringReplace originalCode "asl_floor_div(" "(-7 / 3) + 0 * asl_floor_div(")) ((= mid "shiftMaskOmitMutant") (stringReplace originalCode "& 63" "& 255")) ((= mid "intWrapSignedMutant") (stringReplace originalCode "(uint64_t)" "")) ((= mid "floatFormatLossyMutant") (stringReplace (stringReplace originalCode "%.17g" "%.6f") "%.16g" "%.6f")) ((= mid "optionUnitNullMutant") (stringReplace originalCode "AslSome(None)" "None")) (else originalCode)))

fn verifyMutantKilled m: ty/SemanticsMutant mutatedStdout: Str expectedStdout: Str -> Bool
  (!= (stringTrim mutatedStdout) (stringTrim expectedStdout))

fn getMutantTarget m: ty/SemanticsMutant -> Str
  m.target

fn getMutantKilledCase m: ty/SemanticsMutant -> Str
  m.kills

fn mutantProcessError e: proc/ProcessError -> Str
  (mt e
    ((proc/notFound bin) (str "sh: " bin ": command not found"))
    ((proc/timeout ms) (str "process timed out after " (stringFromInt64 ms) "ms"))
    ((proc/permissionDenied path) (str "sh: " path ": Permission denied"))
    ((proc/executionFailed code msg) (str "process failed (" (stringFromInt64 code) "): " msg)))

fn ! runArgv! bin: Str args: (List Str) -> proc/ProcessOutput
  (mt (proc/exec! (proc/cmd bin args))
    ((ok output) output)
    ((err e) (proc/ProcessOutput :exitCode 127 :stdout "" :stderr (mutantProcessError e) :durationMs 0)))

fn runIsolatedMutantTrial! m: ty/SemanticsMutant casePath: Str -> ty/ConformanceResult
  (let [(mid m.id) (target m.target) (wsDir (str "tmp/conform/mutants/" mid)) (_ (runArgv! "mkdir" (list "-p" wsDir))) (expectOutPath (str casePath "/expect.stdout")) (expOut (stringTrim (mt (fileRead expectOutPath) ((ok s) s) ((err _) ""))))] (if (= target "asl-target-c") (let [(caseId (stringReplace casePath "tests/conformance/xplat/" "")) (baseCCode (c11/emitC11StandaloneCase caseId)) (mutCCode (applyMutant m baseCCode)) (cPath (str wsDir "/run.c")) (binPath (str wsDir "/run")) (_w (fileWrite cPath mutCCode)) (compRes (runArgv! "clang" (list "-std=c11" "-Wall" "-Werror" "-fsanitize=undefined,address" "-fno-sanitize-recover=all" "-ffp-contract=off" cPath "-o" binPath)))] (if (!= compRes.exitCode 0) (ty/makeResult (str "mutant:" mid) target true compRes.stderr compRes.exitCode (str "Mutant '" mid "' killed at compilation stage under Address/Undefined Sanitizer flags")) (let [(runRes (runArgv! binPath (list))) (mutStdout (stringTrim runRes.stdout)) (runExit runRes.exitCode) (killed (or (!= runExit 0) (verifyMutantKilled m mutStdout expOut)))] (ty/makeResult (str "mutant:" mid) target killed mutStdout runExit (if killed (str "Mutant '" mid "' successfully killed under C11 runtime sanitizer trap or output divergence") (str "Mutant '" mid "' survived: output matched expected")))))) (let [(caseId (stringReplace casePath "tests/conformance/xplat/" "")) (basePy (py/emitPyStandaloneCase caseId)) (mutatedPy (applyMutant m basePy)) (pyPath (str wsDir "/run.py")) (_wp (fileWrite pyPath mutatedPy)) (res (runArgv! "python3" (list pyPath))) (mutStdout (stringTrim res.stdout)) (killed (verifyMutantKilled m mutStdout expOut))] (ty/makeResult (str "mutant:" mid) target killed mutStdout res.exitCode (if killed (str "Mutant '" mid "' successfully killed in isolated workspace: output diverged") (str "Mutant '" mid "' survived: output matched expected"))))))
