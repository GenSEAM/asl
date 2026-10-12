(module asl-checker/closureParityTest :x [runTests] :i [(asl-checker/resolve :a r)])

fn ! realOf! p: String -> String
  (mt (realPath p) ((ok x) x) ((err _) p))

fn summaryName deps: (Map String r/ModuleSummary) key: String -> String
  (mt (mapGet deps key) ((some s) s.name) ((none) ""))

fn ! testLoadModuleDepsResolvesFromFirstRoot -> Bool
  (let [(unify (realOf! "asl/packages/asl-checker/src/unify.asl"))]
    (mt (r/loadModuleDeps! (list "asl/packages/asl-checker/tests") (list "../src/types" "unify"))
      ((err _) (do (assert false "loadModuleDeps! returns ok") false))
      ((ok deps) (do (assert (= (summaryName deps "../src/types") "asl-checker/types") "a deprecated ../ import resolves against the first root")
                     (assert (= (summaryName deps "unify") "asl-checker/unify") "a bare import resolves in the first root's package")
                     (assert (= (summaryName deps unify) "asl-checker/unify") "the real path keys the same module")
                     (assert (mt (mapGet deps unify) ((some s) (= (optionOr (mapGet s.imports "ty") "") (realOf! "asl/packages/asl-checker/src/types.asl"))) ((none) false)) "a dependency's alias maps to the real path of its module")
                     true))))

fn candidatesOf note: String -> (List String)
  (listSort (stringSplit (optionOr (listGet (stringSplit note " ambiguous: ") 1) "") ", "))

fn ! testAmbiguousBareImportFails -> Bool
  (let [(importer "asl/packages/asl-checker/tests/fixtures/closureParity/ambiguousImporter.asl")
        (res (r/resolveImport! (realOf! importer) "parityDup" (r/emptyModIndex)))
        (cl (r/loadModuleClosure! importer false))]
    (do (assert (mt res.status ((r/resAmbiguous) true) (_ false)) (str "the ASL resolver reports parityDup ambiguous: " res.note))
        (assert (= (listLength (candidatesOf res.note)) 2) (str "the ASL note lists both declaring modules: " res.note))
        (assert (= (listLength cl.unresolved) 1) "the ASL closure records the failed import")
        (refute (listAny? (fn [(p String)] -> Bool (stringContains? p "parityDup")) cl.paths) "no parityDup candidate is loaded")
        true))

fn ! testTargetsImportsResolve -> Bool
  (let [(entry "asl/packages/asl-compiler/src/targets.asl")
        (cl (r/loadModuleClosure! entry false))]
    (do (assert (listEmpty? cl.unresolved) (str "the ASL loader resolves every import of targets.asl: " (stringJoin cl.unresolved "; ")))
        (assert (> (listLength cl.paths) 23) "the targets closure reaches past the compiler's own")
        true))

fn ! runTests -> Bool
  (do (assert (testLoadModuleDepsResolvesFromFirstRoot) "testLoadModuleDepsResolvesFromFirstRoot")
      (assert (testAmbiguousBareImportFails) "testAmbiguousBareImportFails")
      (assert (testTargetsImportsResolve) "testTargetsImportsResolve")
      true)
