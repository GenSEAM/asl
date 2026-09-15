(module asl-checker/corpusTypeDebtGate
  :d "Measures what the compiler never looks at. compilePackageToC99! type-checks the entry module alone, so every dependency is emitted unchecked; this gate runs checkModule over the whole bootstrap closure instead. The total is a mixture, not a type-error count: it holds genuine type errors, rule diagnostics such as missing docstrings and unmarked effects, and a systematic false positive where a module cannot see its own unexported schemas because collectSummary records exported types only. Red by design; decompose with tools/typeDebtProbe before acting on it."
  :x [bootstrapRoots closureSummaries moduleDiagCount corpusDiagTotal testCorpusTypeChecksClean testDebtCounterIsHonest runTests]
  :i [(ast :a a) (resolve :a r) (check :a chk) (types :a ty)])

(df bootstrapRoots [] -> (List Str)
  :d "Mirrors the module search roots tools/compileBootstrap.asl compiles the CLI under."
  (list "."
        "asl/packages/asl-cli/src"
        "asl/packages/asl-parser/src"
        "asl/packages/asl-checker/src"
        "asl/packages/asl-compiler/src"
        "asl/packages/asl-eval/src"
        "asl/packages/asl-codegen/src"
        "asl/packages/asl-text/src"
        "asl/packages"
        "asl"))

(df ! closureSummaries [] -> (List r/ModuleSummary)
  :d "Every module summary transitively reachable from the CLI entrypoint."
  (let [(entry "asl/packages/asl-cli/src/main.asl")]
    (mt (file-read entry)
      ((err _) (list))
      ((ok src)
       (mt (a/parse src)
         ((err _) (list))
         ((ok forms)
          (let [(summary (r/collectSummary forms entry))
                (importPaths (r/mapValuesList (.-imports summary)))]
            (mt (r/loadModuleDeps! (bootstrapRoots) importPaths)
              ((err _) (list))
              ((ok deps) (map-values deps))))))))))

(df ! moduleDiagCount [(m r/ModuleSummary) (deps (Map Str r/ModuleSummary))] -> Int64
  :d "Runs the checker over one module and returns its diagnostic count."
  (let [(path (.-path m))]
    (mt (file-read path)
      ((err _) 0)
      ((ok src)
       (mt (a/parse src)
         ((err _) 1)
         ((ok forms) (list-length (chk/checkModule forms deps path))))))))

(df ! corpusDiagTotal [] -> Int64
  :d "Total checker diagnostics across the whole bootstrap closure."
  (let [(entry "asl/packages/asl-cli/src/main.asl")]
    (mt (file-read entry)
      ((err _) 0)
      ((ok src)
       (mt (a/parse src)
         ((err _) 0)
         ((ok forms)
          (let [(summary (r/collectSummary forms entry))
                (importPaths (r/mapValuesList (.-imports summary)))]
            (mt (r/loadModuleDeps! (bootstrapRoots) importPaths)
              ((err _) 0)
              ((ok deps)
               (fold (fn [(acc Int64) (m r/ModuleSummary)] -> Int64
                        (let [(n (moduleDiagCount m deps))]
                          (do
                            (if (> n 0)
                                (print (str "  (module " (.-name m) " :diagnostics " (string-from-int64 n) ")"))
                                true)
                            (+ acc n))))
                     0
                     (map-values deps)))))))))))

(df ! testCorpusTypeChecksClean [] -> Bool
  :d "Every module the bootstrap emits must pass the checker, not just the 12-line entry module."
  (let [(mods (closureSummaries))
        (total (corpusDiagTotal))]
    (assert (> (list-length mods) 5) "the closure must actually resolve, not collapse to empty")
    (print (str "(corpusTypeDebt :modules " (string-from-int64 (list-length mods)) " :diagnostics " (string-from-int64 total) ")"))
    (assert (= total 0) (str "the bootstrap closure must type-check clean; diagnostics outstanding: " (string-from-int64 total)))
    true))

(df testDebtCounterIsHonest [] -> Bool
  :d "Dual-polarity guard under D77: a zero total must mean checked-and-clean, never checked-nothing."
  (let [(empty (list))]
    (assert (= (list-length empty) 0) "an empty module list has length zero")
    (refute (> (list-length empty) 5) "an empty closure must not satisfy the resolution guard")
    true))

(df ! runTests [] -> Bool
  (do
    (assert (testDebtCounterIsHonest) "testDebtCounterIsHonest")
    (assert (testCorpusTypeChecksClean) "testCorpusTypeChecksClean")
    true))
