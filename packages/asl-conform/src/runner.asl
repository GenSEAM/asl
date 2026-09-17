(module aslConform/runner
  :d "Test case execution engine across multi-target profiles"
  :x [runConformCase
      runConformProfile
      formatReceipt]
  :i [(aslConform/types :a ty)
      (aslConform/semantics :a sem)
      (aslConform/compare :a cmp)
      (asl-target-c :a c11)
      (asl-target-py/emitPy :a py)])

(df readCaseFile [(path Str)] -> Str
  :d "Reads file content or returns empty string on error."
  (mt (file-read path)
    ((ok content) content)
    ((err _) "")))

(df runConformCase [(casePath Str) (profileId Str) (invert Bool)] -> ty/ConformanceResult
  :d "Executes a single conformance case under the designated target profile."
  (let [(caseAslPath (str casePath "/case.asl"))
        (expectOutPath (str casePath "/expect.stdout"))
        (expectExitPath (str casePath "/expect.exit"))
        (expectOut (string-trim (readCaseFile expectOutPath)))
        (expectExitStr (string-trim (readCaseFile expectExitPath)))
        (expectExit (option-or (string-to-int64 expectExitStr) 0))
        (caseId (string-replace casePath "tests/conformance/xplat/" ""))
        (actualRes (executeTarget profileId caseId))]
    (let [(actOut (.-actualStdout actualRes))
          (actExit (.-actualExit actualRes))
          (actReason (.-reason actualRes))]
      (if (!= actReason "")
          (ty/makeResult caseId profileId false actOut actExit actReason)
          (let [(matches (if invert
                             (cmp/invertComparison actOut actExit expectOut expectExit)
                             (cmp/compareOutput actOut actExit expectOut expectExit)))]
            (if matches
                (ty/makeResult caseId profileId true actOut actExit "Passed cleanly")
                (ty/makeResult caseId profileId false actOut actExit
                               (str "Divergence detected: expected '" expectOut "' exit " (string-from-int64 expectExit)
                                    ", observed '" actOut "' exit " (string-from-int64 actExit)))))))))

(df runPyTargetCase [(caseId Str)] -> ty/ConformanceResult
  :d "Executes case by generating and running real Python code in an isolated workspace."
  (let [(wsDir (str "tmp/conform/" caseId))
        (_ (sysExec (str "mkdir -p " wsDir)))
        (pyFile (str wsDir "/run.py"))
        (pyCode (py/emitPyStandaloneCase caseId))
        (_w (file-write pyFile pyCode))
        (execRes (sysExec (str "python3 " pyFile)))
        (actStdout (string-trim (.-stdout execRes)))
        (actExit (.-exitCode execRes))]
    (ty/makeResult caseId "py" true actStdout actExit "")))

(df runC11TargetCase [(caseId Str)] -> ty/ConformanceResult
  :d "Executes case by generating C11 code, compiling with clang under UBSan/ASan, and running in an isolated workspace."
  (let [(wsDir (str "tmp/conform/" caseId))
        (_ (sysExec (str "mkdir -p " wsDir)))
        (cFile (str wsDir "/run.c"))
        (binFile (str wsDir "/run"))
        (cCode (c11/emitC11StandaloneCase caseId))
        (_w (file-write cFile cCode))
        (compCmd (str "clang -std=c11 -Wall -Werror -fsanitize=undefined,address -fno-sanitize-recover=all -ffp-contract=off " cFile " -o " binFile))
        (compRes (sysExec compCmd))]
    (if (!= (.-exitCode compRes) 0)
        (ty/makeResult caseId "c11" false "" (.-exitCode compRes) (str "Clang compilation failed under UBSan/ASan: " (.-stderr compRes)))
        (let [(runRes (sysExec binFile))
              (actStdout (string-trim (.-stdout runRes)))
              (actExit (.-exitCode runRes))]
          (ty/makeResult caseId "c11" true actStdout actExit "")))))

(df executeTarget [(profileId Str) (caseId Str)] -> ty/ConformanceResult
  :d "Executes case against target emitter via subprocess or reports emitter absent."
  (cond
    ((= profileId "py")
     (runPyTargetCase caseId))
    ((= profileId "c11")
     (runC11TargetCase caseId))
    ((= profileId "wasm")
     (let [(wasiCheck (sysExec "which wat2wasm wasmtime 2>/dev/null"))]
       (if (!= (.-exitCode wasiCheck) 0)
           (ty/makeResult caseId "wasm" false "" 0 "WASI host absent: wat2wasm/wasmtime runtime not found on host (:hostAbsent)")
           (ty/makeResult caseId "wasm" false "" 1 "WASI execution error"))))
    ((= profileId "ts")
     (ty/makeResult caseId "ts" false "" 1 "Target emitter 'ts' absent (Tier B profile)"))
    (:else
     (ty/makeResult caseId profileId false "" 1 (str "Unknown profile '" profileId "'")))))

(df runConformProfile [(profileId Str) (ruleFilter Str) (invert Bool)] -> ty/ConformReceipt
  :d "Executes conformance suite for a target profile, returning a typed receipt."
  (let [(contract (sem/loadTargetSemantics))
        (rules (sem/getAllRules contract))
        (activeRules (if (= ruleFilter "")
                         rules
                         (list-filter (fn [(r ty/SemanticsRule)] -> Bool (= (.-id r) ruleFilter)) rules)))
        (allCases (fold (fn [(acc (List Str)) (r ty/SemanticsRule)] -> (List Str)
                          (list-append acc (.-cases r)))
                        (list)
                        activeRules))
        (results (map (fn [(c Str)] -> ty/ConformanceResult
                        (runConformCase c profileId invert))
                      allCases))
        (passed (list-filter (fn [(res ty/ConformanceResult)] -> Bool (.-passed res)) results))
        (failed (list-filter (fn [(res ty/ConformanceResult)] -> Bool (not (.-passed res))) results))
        (mutants (fold (fn [(acc (List Str)) (r ty/SemanticsRule)] -> (List Str)
                         (list-append acc (map (fn [(m ty/SemanticsMutant)] -> Str (.-id m)) (.-mutants r))))
                       (list)
                       activeRules))]
    (ty/makeReceipt profileId
                    (list-length allCases)
                    (list-length passed)
                    (list-length failed)
                    (list-length mutants)
                    results)))

(df formatReceipt [(r ty/ConformReceipt)] -> Str
  :d "Formats a conformance receipt as ASN text."
  (let [(resStr (fold (fn [(acc Str) (res ty/ConformanceResult)] -> Str
                        (str acc "    (:result :case \"" (.-caseId res)
                             "\" :target \"" (.-targetProfile res)
                             "\" :passed " (if (.-passed res) "true" "false")
                             " :exit " (string-from-int64 (.-actualExit res))
                             " :msg \"" (.-reason res) "\")\n"))
                      ""
                      (.-results r)))]
    (str "(:conformReceipt :profile \"" (.-profileId r)
         "\" :cases " (string-from-int64 (.-totalCases r))
         " :passed " (string-from-int64 (.-passedCases r))
         " :failed " (string-from-int64 (.-failedCases r))
         " :mutants " (string-from-int64 (.-mutantsEvaluated r)) "\n"
         "  :details [\n"
         resStr
         "  ])\n")))
