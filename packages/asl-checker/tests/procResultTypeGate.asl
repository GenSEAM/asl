(module asl-checker/tests/procResultTypeGate
  :x [targetPaths checkerRoots diagMessages runTests]
  :i [(asl-parser/ast :a a) (asl-checker/resolve :a r) (asl-checker/check :a chk) (asl-checker/types :a ty)])

fn targetPaths -> (List Str)
  (list "asl/packages/asl-gates/src/gateRunner.asl" "asl/packages/asl-engine/src/engine.asl" "asl/packages/asl-engine/src/main.asl" "asl/packages/asl-engine/src/transport.asl" "asl/packages/asl-cli/tests/argvParityTest.asl" "tests/host/genInventoryTest.asl")

fn checkerRoots -> (List Str)
  (list "asl/packages/asl-cli/src" "." "asl/packages/asl-parser/src" "asl/packages/asl-checker/src" "asl/packages/asl-compiler/src" "asl/packages/asl-eval/src" "asl/packages/asl-codegen/src" "asl/packages/asl-text/src" "asl/packages" "asl")

fn ! diagMessagesForParsed path: Str forms: (List a/TopForm) -> (Result (List Str) Str)
  (let [(summary (r/collectSummary forms path))
        (importPaths (r/mapValuesList summary.imports))
        (depsRes (r/loadModuleDeps! (cons (r/parentDirOf path) (checkerRoots)) importPaths))]
    (mt depsRes
      ((err e) (err (str path ": imports do not load: " e)))
      ((ok deps) (ok (map (fn [(d ty/Diagnostic)] -> Str (str path ": " d.code ": " d.message)) (chk/checkModule forms deps path))))))

fn ! diagMessagesForPath path: Str -> (Result (List Str) Str)
  (mt (fileRead path)
    ((err _) (err (str path ": unreadable")))
    ((ok src) (mt (a/parse src) ((err e) (err (str path ": does not parse: " e.msg))) ((ok forms) (diagMessagesForParsed path forms)))))

fn ! diagMessages -> (List (Result (List Str) Str))
  (map diagMessagesForPath (targetPaths))

fn ! testNoProcessResultAnnotationRemains -> Bool
  (let [(outcomes (diagMessages))
        (failures (fold (fn [(acc (List Str)) (o (Result (List Str) Str))] -> (List Str) (mt o ((err e) (listAppend acc (list e))) ((ok _) acc))) (list) outcomes))
        (msgs (fold (fn [(acc (List Str)) (o (Result (List Str) Str))] -> (List Str) (mt o ((err _) acc) ((ok ms) (listAppend acc ms)))) (list) outcomes))
        (hits (filter (fn [(m Str)] -> Bool (stringContains? m "ProcessResult")) msgs))]
    (do
      (assert (= (listLength outcomes) 6) "the gate covers the six target files")
      (assert (listEmpty? failures) (str "each target file reads, parses and loads its imports, so the check below runs on real diagnostics: " (stringJoin failures "; ")))
      (assert (listEmpty? hits) (str "the undefined ProcessResult annotation must not reappear: " (stringJoin hits "; ")))
      true))

fn ! runTests -> Bool
  (do (assert (testNoProcessResultAnnotationRemains) "testNoProcessResultAnnotationRemains") true)
