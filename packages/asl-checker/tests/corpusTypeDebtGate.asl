(module asl-checker/corpusTypeDebtGate :x [bootstrapRoots closureSummaries moduleDiagCount corpusDiagTotal typeDebtRatchet testCorpusTypeChecksClean runTests] :i [(ast :a a) (resolve :a r) (check :a chk) (types :a ty)])

fn bootstrapRoots -> (List Str)
  (list "asl/packages/asl-cli/src" "." "asl/packages/asl-parser/src" "asl/packages/asl-checker/src" "asl/packages/asl-compiler/src" "asl/packages/asl-eval/src" "asl/packages/asl-codegen/src" "asl/packages/asl-text/src" "asl/packages" "asl")

fn ! closureSummaries -> (List r/ModuleSummary)
  (let [(entry "asl/packages/asl-cli/src/main.asl")] (mt (fileRead entry) ((err _) (list)) ((ok src) (mt (a/parse src) ((err _) (list)) ((ok forms) (let [(summary (r/collectSummary forms entry)) (importPaths (r/mapValuesList summary.imports))] (mt (r/loadModuleDeps! (bootstrapRoots) importPaths) ((err _) (list)) ((ok deps) (mapValues deps)))))))))

fn ! moduleDiagCount m: r/ModuleSummary deps: (Map Str r/ModuleSummary) -> Int64
  (let [(path m.path)] (mt (fileRead path) ((err _) 0) ((ok src) (mt (a/parse src) ((err _) 1) ((ok forms) (listLength (chk/checkModule forms deps path)))))))

fn typeDebtRatchet -> Int64
  55

fn ! corpusDiagTotal -> Int64
  (let [(entry "asl/packages/asl-cli/src/main.asl")] (mt (fileRead entry) ((err _) 0) ((ok src) (mt (a/parse src) ((err _) 0) ((ok forms) (let [(summary (r/collectSummary forms entry)) (importPaths (r/mapValuesList summary.imports))] (mt (r/loadModuleDeps! (bootstrapRoots) importPaths) ((err _) 0) ((ok deps) (fold (fn [(acc Int64) (m r/ModuleSummary)] -> Int64 (let [(n (moduleDiagCount m deps))] (do (if (> n 0) (print (str "  (module " m.name " :diagnostics " (stringFromInt64 n) ")")) ()) (+ acc n)))) 0 (mapValues deps))))))))))

fn ! testCorpusTypeChecksClean -> Bool
  (let [(mods (closureSummaries))] (do (assert (> (listLength mods) 5) "the closure must actually resolve, not collapse to empty") (let [(total (corpusDiagTotal))] (do (print (str "(corpusTypeDebt :modules " (stringFromInt64 (listLength mods)) " :diagnostics " (stringFromInt64 total) ")")) (assert (= total (typeDebtRatchet)) (str "type debt must equal the ratchet: lower it when debt drops, fix code when it rises; outstanding: " (stringFromInt64 total))) true))))

fn ! runTests -> Bool
  (do (assert (testCorpusTypeChecksClean) "testCorpusTypeChecksClean") true)
