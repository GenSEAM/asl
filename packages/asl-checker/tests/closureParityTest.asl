(module asl-checker/closureParityTest :x [runTests] :i [(asl-checker/resolve :a r)])

fn ! realOf! p: String -> String
  (match (realPath p) ((ok x) x) ((err _) p))

fn summaryName deps: (Map String r/ModuleSummary) key: String -> String
  (match (mapGet deps key) ((some s) s.name) ((none) ""))

fn ! testLoadModuleDepsResolvesFromFirstRoot -> Bool
  (let [(unify (realOf! "asl/packages/asl-checker/src/unify.asl"))]
    (match (r/loadModuleDeps! (list "asl/packages/asl-checker/tests") (list "asl-checker/types" "unify"))
      ((err _) (do (assert false "loadModuleDeps! returns ok") false))
      ((ok deps) (do (assert (= (summaryName deps "asl-checker/types") "asl-checker/types") "a named import resolves against the first root")
                     (assert (= (summaryName deps "unify") "asl-checker/unify") "a bare import resolves in the first root's package")
                     (assert (= (summaryName deps unify) "asl-checker/unify") "the real path keys the same module")
                     (assert (match (mapGet deps unify) ((some s) (= (optionOr (mapGet s.imports "ty") "") (realOf! "asl/packages/asl-checker/src/types.asl"))) ((none) false)) "a dependency's alias maps to the real path of its module")
                     true))))

fn ! testRelativeImportRetired -> Bool
  (let [(cl (r/loadModuleDepsFrom! (list "asl/packages/asl-checker/tests") (list "../src/types") (mapEmpty) (r/emptyModIndex)))
        (text (stringJoin (listAppend cl.unresolved cl.errors) "; "))]
    (do (assert (not (listEmpty? cl.unresolved)) "a leading ../ import is unresolved, not resolved")
        (assert (stringContains? text "is a relative import, which is retired: import the module by the name its header declares") (str "the error names the new spelling: " text))
        true))

fn candidatesOf note: String -> (List String)
  (listSort (stringSplit (optionOr (listGet (stringSplit note " ambiguous: ") 1) "") ", "))

fn ! testAmbiguousBareImportFails -> Bool
  (let [(importer "asl/packages/asl-checker/tests/fixtures/closureParity/ambiguousImporter.asl")
        (res (r/resolveImport! (realOf! importer) "parityDup" (r/emptyModIndex)))
        (cl (r/loadModuleClosure! importer false))]
    (do (assert (match res.status ((r/resAmbiguous) true) (_ false)) (str "the ASL resolver reports parityDup ambiguous: " res.note))
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
      (assert (testRelativeImportRetired) "testRelativeImportRetired")
      (assert (testAmbiguousBareImportFails) "testAmbiguousBareImportFails")
      (assert (testTargetsImportsResolve) "testTargetsImportsResolve")
      true)
