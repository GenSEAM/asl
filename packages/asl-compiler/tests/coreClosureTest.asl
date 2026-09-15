(module asl-compiler/coreClosureTest
  :d "Guards the self-hosting core: the module closure reached from the CLI entrypoint must carry the language and its C99 backend only."
  :x [bootstrapRoots entryClosureModules testCoreClosureExcludesForeignBackends testCoreClosureKeepsLanguageCore testCoreClosureRefutations runTests]
  :i [(ast :a a) (resolve :a r)])

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

(df ! entryClosureModules [] -> (List Str)
  :d "Returns every module name transitively reachable from the CLI entrypoint."
  (let [(entry "asl/packages/asl-cli/src/main.asl")
        (srcRes (file-read entry))]
    (mt srcRes
      ((err _) (list))
      ((ok src)
       (mt (a/parse src)
         ((err _) (list))
         ((ok forms)
          (let [(summary (r/collectSummary forms entry))
                (importPaths (r/mapValuesList (.-imports summary)))
                (depsRes (r/loadModuleDeps! (bootstrapRoots) importPaths))]
            (mt depsRes
              ((err _) (list))
              ((ok deps) (map-keys deps))))))))))

(df ! testCoreClosureExcludesForeignBackends [] -> Bool
  :d "Every non-C99 backend must stay outside the bootstrap closure."
  (let [(mods (entryClosureModules))]
    (assert (> (list-length mods) 5) "the closure must actually resolve, not collapse to empty")
    (refute (list-contains? mods "emitWat") "the WAT backend must not reach the self-hosting core")
    (refute (list-contains? mods "emitGo") "the Go backend must not reach the self-hosting core")
    (refute (list-contains? mods "emit") "the Rust backend must not reach the self-hosting core")
    (refute (list-contains? mods "emitC") "the Arduino/legacy C backend must not reach the self-hosting core")
    (refute (list-contains? mods "wasm") "the WASM/WASI backend must not reach the self-hosting core")
    (refute (list-contains? mods "targets") "the multi-target dispatcher must not reach the self-hosting core")
    (refute (list-contains? mods "mangle") "the Rust identifier mangler must not reach the self-hosting core")
    (refute (list-contains? mods "expr") "the Rust expression lowerer must not reach the self-hosting core")
    (refute (list-contains? mods "rtypes") "the Rust type mapper must not reach the self-hosting core")
    true))

(df ! testCoreClosureKeepsLanguageCore [] -> Bool
  :d "The language core and its C99 backend must remain reachable."
  (let [(mods (entryClosureModules))]
    (assert (list-contains? mods "compiler") "the compiler core stays in the closure")
    (assert (list-contains? mods "c99Emit") "the C99 backend stays in the closure")
    (assert (list-contains? mods "check") "the type checker stays in the closure")
    (assert (list-contains? mods "reader") "the reader stays in the closure")
    true))

(df ! testCoreClosureRefutations [] -> Bool
  :d "Dual-polarity guard under D77: the membership test must be able to answer both ways."
  (let [(mods (entryClosureModules))]
    (assert (list-contains? mods "compiler") "a module that is present reads as present")
    (refute (list-contains? mods "emitPy") "a module that was never in the closure reads as absent")
    (refute (list-contains? mods "thisModuleDoesNotExist") "an invented name must not report as present")
    true))

(df ! runTests [] -> Bool
  (do
    (assert (testCoreClosureExcludesForeignBackends) "testCoreClosureExcludesForeignBackends")
    (assert (testCoreClosureKeepsLanguageCore) "testCoreClosureKeepsLanguageCore")
    (assert (testCoreClosureRefutations) "testCoreClosureRefutations")
    true))
