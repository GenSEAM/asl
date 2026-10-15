(module aslConform/runner :x [runConformCase! runConformProfile! formatReceipt] :i [(aslConform/types :a ty) (aslConform/semantics :a sem) (aslConform/compare :a cmp) (asl-target-c :a c11) (asl-target-py :a py) (asl-proc/coreProcess :a proc) (asl-proc/pool :a pool)])

fn readCaseFile! path: Str -> Str
  (mt (fileRead path) ((ok content) content) ((err _) ""))

fn runConformCase! casePath: Str profileId: Str invert: Bool -> ty/ConformanceResult
  (let [(caseAslPath (str casePath "/case.asl")) (expectOutPath (str casePath "/expect.stdout")) (expectExitPath (str casePath "/expect.exit")) (expectOut (stringTrim (readCaseFile! expectOutPath))) (expectExitStr (stringTrim (readCaseFile! expectExitPath))) (expectExit (optionOr (stringToInt64 expectExitStr) 0)) (caseId (stringReplace casePath "tests/conformance/xplat/" "")) (actualRes (executeTarget! profileId caseId))] (let [(actOut actualRes.actualStdout) (actExit actualRes.actualExit) (actReason actualRes.reason)] (if (!= actReason "") (ty/makeResult caseId profileId false actOut actExit actReason) (let [(matches (if invert (cmp/invertComparison actOut actExit expectOut expectExit) (cmp/compareOutput actOut actExit expectOut expectExit)))] (if matches (ty/makeResult caseId profileId true actOut actExit "Passed cleanly") (ty/makeResult caseId profileId false actOut actExit (str "Divergence detected: expected '" expectOut "' exit " (stringFromInt64 expectExit) ", observed '" actOut "' exit " (stringFromInt64 actExit))))))))

fn ! runArgv! bin: Str args: (List Str) -> proc/ProcessOutput
  (mt (pool/runPool! (list (listAppend (list bin) args)) 1)
    ((err message) (proc/ProcessOutput :exitCode 127 :stdout "" :stderr (str "process spawn failed: " message) :durationMs 0))
    ((ok rows)
      (mt (listHead rows)
        ((none) (proc/ProcessOutput :exitCode 127 :stdout "" :stderr "process returned no result" :durationMs 0))
        ((some row)
          (mt row.spawnError
            ((some message) (proc/ProcessOutput :exitCode (if (= message "permission") 126 127) :stdout "" :stderr (str "sh: " bin ": " (if (= message "permission") "Permission denied" "command not found")) :durationMs 0))
            ((none) (proc/ProcessOutput :exitCode row.exitCode :stdout row.stdout :stderr row.stderr :durationMs row.durationMs)))))))

fn pyQuoted s: Str -> Str
  (str "\"" (stringReplace (stringReplace (stringReplace s "\\" "\\\\") "\"" "\\\"") "\n" "\\n") "\"")

fn ! pyCaseSource! casePath: Str -> Str
  (mt (py/compileEntry! (str casePath "/case.asl"))
    ((ok code) code)
    ((err ds) (str "import sys\nsys.exit(" (pyQuoted (py/diagText ds)) ")\n")))

fn ! runPyTargetCase! caseId: Str -> ty/ConformanceResult
  (let [(wsDir (str "tmp/conform/" caseId)) (_ (runArgv! "mkdir" (list "-p" wsDir))) (pyFile (str wsDir "/run.py")) (pyCode (pyCaseSource! (str "tests/conformance/xplat/" caseId))) (_w (fileWrite pyFile pyCode)) (execRes (runArgv! "python3" (list pyFile))) (actStdout (stringTrim execRes.stdout)) (actExit execRes.exitCode)] (ty/makeResult caseId "py" true actStdout actExit ""))

fn ! runC11TargetCase! caseId: Str -> ty/ConformanceResult
  (let [(wsDir (str "tmp/conform/" caseId)) (_ (runArgv! "mkdir" (list "-p" wsDir))) (cFile (str wsDir "/run.c")) (binFile (str wsDir "/run")) (cCode (c11/emitC11StandaloneCase caseId)) (_w (fileWrite cFile cCode)) (compRes (runArgv! "clang" (list "-std=c11" "-Wall" "-Werror" "-fsanitize=undefined,address" "-fno-sanitize-recover=all" "-ffp-contract=off" cFile "-o" binFile)))] (if (!= compRes.exitCode 0) (ty/makeResult caseId "c11" false "" compRes.exitCode (str "Clang compilation failed under UBSan/ASan: " compRes.stderr)) (let [(runRes (runArgv! binFile (list))) (actStdout (stringTrim runRes.stdout)) (actExit runRes.exitCode)] (ty/makeResult caseId "c11" true actStdout actExit ""))))

fn executeTarget! profileId: Str caseId: Str -> ty/ConformanceResult
  (cond ((= profileId "py") (runPyTargetCase! caseId)) ((= profileId "c11") (ty/makeResult caseId "c11" false "" 1 "Target emitter 'c11' absent (Tier B profile)")) ((= profileId "wasm") (let [(wasiCheck (runArgv! "which" (list "wat2wasm" "wasmtime")))] (if (!= wasiCheck.exitCode 0) (ty/makeResult caseId "wasm" false "" 0 "WASI host absent: wat2wasm/wasmtime runtime not found on host (:hostAbsent)") (ty/makeResult caseId "wasm" false "" 1 "WASI execution error")))) ((= profileId "ts") (ty/makeResult caseId "ts" false "" 1 "Target emitter 'ts' absent (Tier B profile)")) (else (ty/makeResult caseId profileId false "" 1 (str "Unknown profile '" profileId "'"))))

fn runConformProfile! profileId: Str ruleFilter: Str invert: Bool -> ty/ConformReceipt
  (let [(contract (sem/loadTargetSemantics)) (rules (sem/getAllRules contract)) (activeRules (if (= ruleFilter "") rules (filter (fn [(r ty/SemanticsRule)] -> Bool (= r.id ruleFilter)) rules))) (allCases (fold (fn [(acc (List Str)) (r ty/SemanticsRule)] -> (List Str) (listAppend acc r.cases)) (list) activeRules)) (results (map (fn [(c Str)] -> ty/ConformanceResult (runConformCase! c profileId invert)) allCases)) (passed (filter (fn [(res ty/ConformanceResult)] -> Bool res.passed) results)) (failed (filter (fn [(res ty/ConformanceResult)] -> Bool (not res.passed)) results)) (mutants (fold (fn [(acc (List Str)) (r ty/SemanticsRule)] -> (List Str) (listAppend acc (map (fn [(m ty/SemanticsMutant)] -> Str m.id) r.mutants))) (list) activeRules))] (ty/makeReceipt profileId (listLength allCases) (listLength passed) (listLength failed) results mutants invert))

fn formatReceipt r: ty/ConformReceipt -> Str
  (let [(status (if (> r.failedCases 0) ":failed" ":passed")) (resStr (fold (fn [(acc Str) (res ty/ConformanceResult)] -> Str (str acc "    (:result :case \"" res.caseId "\" :target \"" res.profile "\" :passed " (if res.passed "true" "false") " :exit " (stringFromInt64 res.actualExit) " :msg \"" res.reason "\")\n")) "" r.results))] (str "(:conformReceipt :profile \"" r.profile "\" :status " status " :cases " (stringFromInt64 r.totalCases) " :passed " (stringFromInt64 r.passedCases) " :failed " (stringFromInt64 r.failedCases) " :mutants " (stringFromInt64 (listLength r.mutantsChecked)) "\n" "  :details [\n" resStr "  ])\n"))
