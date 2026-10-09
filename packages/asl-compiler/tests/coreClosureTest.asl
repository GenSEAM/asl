(module asl-compiler/coreClosureTest
  :x [loadClosureFor runTests]
  :i [(asl-parser/ast :a a) (asl-checker/resolve :a r)])

fn ! loadClosureFor entryFile: Str -> (Result (List r/ModuleSummary) Str)
  (mt (fileRead entryFile)
    ((err _) (err (str "Cannot read entry file: " entryFile)))
    ((ok src)
      (mt (a/parse src)
        ((err pe) (err (str "Parse error in " entryFile ": " pe.msg)))
        ((ok forms)
          (let [(entrySummary (r/collectSummary forms entryFile))
                (importPaths (r/mapValuesList entrySummary.imports))
                (roots (list (r/parentDirOf entryFile) "."))]
            (mt (r/loadModuleDeps! roots importPaths)
              ((err _) (err (str "Failed to load dependencies for " entryFile)))
              ((ok depsMap)
                (let [(depSummaries (mapValues depsMap))]
                  (ok (cons entrySummary depSummaries))))))))))

fn ! runTests -> Bool
  (mt (loadClosureFor "asl/packages/asl-compiler/src/asl1.asl")
    ((err msg) (do (assert false (str "closure must load: " msg)) false))
    ((ok summaries)
      (let [(names (map (fn [(s r/ModuleSummary)] -> Str s.name) summaries))
            (paths (map (fn [(s r/ModuleSummary)] -> Str s.path) summaries))
            (outsidePackages (filter (fn [(p Str)] -> Bool (not (stringContains? p "asl/packages/"))) paths))]
        (do
          (assert (> (listLength summaries) 15) "closure has substantial module count")
          (assert (listContains? names "asl-ir/lower") "closure contains asl-ir/lower")
          (assert (listContains? names "asl-target-llvm") "closure contains asl-target-llvm")
          (assert (listAny? (fn [(n Str)] -> Bool (stringStartsWith? n "asl-target-llvm")) names) "closure contains asl-target-llvm modules")
          (assert (listContains? names "asl-compiler/compiler") "closure contains asl-compiler/compiler")
          (assert (listContains? names "asl-checker/check") "closure contains asl-checker/check")
          (assert (listContains? names "asl-parser/ast") "closure contains asl-parser/ast")
          (refute (listContains? names "emitWat") "the WAT backend must not reach the self-hosting core")
          (refute (listContains? names "asl-target-swift/emitSwift") "swift backend must not reach the self-hosting core")
          (refute (listContains? names "asl-target-rs/emitRust") "rust backend must not reach the self-hosting core")
          (assert (listEmpty? outsidePackages) (str "closure contains no module outside asl/packages, but found: " (stringJoin outsidePackages ", ")))
          (refute (listContains? names "thisModuleDoesNotExist") "refutation: invented module is not in closure")
          true))))
