(module aslConform/mutant
  :d "Production code mutant application and verification under D77/D89 refutation"
  :x [applyMutant
      verifyMutantKilled
      getMutantTarget
      getMutantKilledCase
      runIsolatedMutantTrial]
  :i [(aslConform/types :a ty)
      (asl-target-c :a c11)
      (asl-target-py/emitPy :a py)])

(df applyMutant [(m ty/SemanticsMutant) (originalCode Str)] -> Str
  :d "Applies targeted structural mutation to test suite or emitter code."
  (let [(mid (.-id m))]
    (cond
      ((= mid "divModFloorOmitMutant")
       (string-replace originalCode "//" "/"))
      ((= mid "divModTruncOmitMutant")
       (string-replace originalCode "asl_floor_div(" "(-7 / 3) + 0 * asl_floor_div("))
      ((= mid "shiftMaskOmitMutant")
       (string-replace originalCode "& 63" "& 255"))
      ((= mid "intWrapSignedMutant")
       (string-replace originalCode "(uint64_t)" ""))
      ((= mid "floatFormatLossyMutant")
       (string-replace (string-replace originalCode "%.17g" "%.6f") "%.16g" "%.6f"))
      ((= mid "optionUnitNullMutant")
       (string-replace originalCode "AslSome(None)" "None"))
      (:else originalCode))))

(df verifyMutantKilled [(m ty/SemanticsMutant) (mutatedStdout Str) (expectedStdout Str)] -> Bool
  :d "Verifies that the applied mutant successfully diverges from expected output (i.e. is killed)."
  (!= (string-trim mutatedStdout) (string-trim expectedStdout)))

(df getMutantTarget [(m ty/SemanticsMutant)] -> Str
  :d "Returns the target package of the mutant."
  (.-target m))

(df getMutantKilledCase [(m ty/SemanticsMutant)] -> Str
  :d "Returns the test case expected to be killed by the mutant."
  (.-kills m))

(df runIsolatedMutantTrial [(m ty/SemanticsMutant) (casePath Str)] -> ty/ConformanceResult
  :d "Runs a mutant execution trial in an isolated workspace under tmp/conform/mutants/."
  (let [(mid (.-id m))
        (target (.-target m))
        (wsDir (str "tmp/conform/mutants/" mid))
        (_ (sysExec (str "mkdir -p " wsDir)))
        (expectOutPath (str casePath "/expect.stdout"))
        (expOut (string-trim (mt (file-read expectOutPath) ((ok s) s) ((err _) ""))))]
    (if (= target "asl-target-c")
        (let [(caseId (string-replace casePath "tests/conformance/xplat/" ""))
              (baseCCode (c11/emitC11StandaloneCase caseId))
              (mutCCode (applyMutant m baseCCode))
              (cPath (str wsDir "/run.c"))
              (binPath (str wsDir "/run"))
              (_w (file-write cPath mutCCode))
              (compRes (sysExec (str "clang -std=c11 -Wall -Werror -fsanitize=undefined,address -fno-sanitize-recover=all -ffp-contract=off " cPath " -o " binPath)))]
          (if (!= (.-exitCode compRes) 0)
              (ty/makeResult (str "mutant:" mid)
                             target
                             true
                             (.-stderr compRes)
                             (.-exitCode compRes)
                             (str "Mutant '" mid "' killed at compilation stage under Address/Undefined Sanitizer flags"))
              (let [(runRes (sysExec binPath))
                    (mutStdout (string-trim (.-stdout runRes)))
                    (runExit (.-exitCode runRes))
                    (killed (or (!= runExit 0) (verifyMutantKilled m mutStdout expOut)))]
                (ty/makeResult (str "mutant:" mid)
                               target
                               killed
                               mutStdout
                               runExit
                               (if killed
                                   (str "Mutant '" mid "' successfully killed under C11 runtime sanitizer trap or output divergence")
                                   (str "Mutant '" mid "' survived: output matched expected"))))))
        (let [(caseId (string-replace casePath "tests/conformance/xplat/" ""))
              (basePy (py/emitPyStandaloneCase caseId))
              (mutatedPy (applyMutant m basePy))
              (pyPath (str wsDir "/run.py"))
              (_wp (file-write pyPath mutatedPy))
              (res (sysExec (str "python3 " pyPath)))
              (mutStdout (string-trim (.-stdout res)))
              (killed (verifyMutantKilled m mutStdout expOut))]
          (ty/makeResult (str "mutant:" mid)
                         target
                         killed
                         mutStdout
                         (.-exitCode res)
                         (if killed
                             (str "Mutant '" mid "' successfully killed in isolated workspace: output diverged")
                             (str "Mutant '" mid "' survived: output matched expected")))))))
