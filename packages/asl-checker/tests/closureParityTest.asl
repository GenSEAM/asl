(module asl-checker/closureParityTest :x [runTests] :i [(asl-checker/resolve :a r)])

fn hostBin -> String
  "asl/host/out/asl-host"

fn ! workspaceRoot! -> String
  (mt (realPath ".") ((ok p) p) ((err _) "."))

fn ! realOf! p: String -> String
  (mt (realPath p) ((ok x) x) ((err _) p))

fn ! hostBuildLines! entry: String -> (List String)
  (let [(cmd (str "d=$(mktemp -d) && " (hostBin) " build " entry " -o \"$d/m\" 2>/dev/null && LC_ALL=C grep -ao '" (workspaceRoot!) "/[[:print:]]*[.]asl' \"$d/m\" | sort -u; rc=$?; rm -rf \"$d\"; exit $rc"))
        (res (processRun cmd))]
    (do (assert (= res.exitCode 0) (str "asl-host build " entry " exits 0: " res.stderr))
        (filter (fn [(l String)] -> Bool (not (stringEmpty? l))) (stringLines res.stdout))))

fn builtCount lines: (List String) -> Int64
  (fold (fn [(acc Int64) (l String)] -> Int64 (if (stringStartsWith? l "built ") (optionOr (stringToInt64 (optionOr (listGet (stringSplit (optionOr (listGet (stringSplit l ": ") 1) "") " ") 0) "")) -1) acc)) -1 lines)

fn distinctSorted xs: (List String) -> (List String)
  (listSort (fold (fn [(acc (List String)) (x String)] -> (List String) (if (listContains? acc x) acc (cons x acc))) (list) xs))

fn ! assertSameClosure! entry: String want: Int64 -> Bool
  (let [(lines (hostBuildLines! entry))
        (count (builtCount lines))
        (envPrelude (optionOr (envGet "ASL_PRELUDE") ""))
        (prelude (realOf! (if (stringEmpty? envPrelude) "asl/host/out/prelude.asl" envPrelude)))
        (entryReal (realOf! entry))
        (hostSet (distinctSorted (filter (fn [(l String)] -> Bool (and (not (stringStartsWith? l "built ")) (!= l prelude))) lines)))
        (cl (r/loadModuleClosure! entry false))
        (aslSet (distinctSorted (cons entryReal cl.paths)))]
    (do (assert (listEmpty? cl.unresolved) (str entry ": the ASL loader resolves every import: " (stringJoin cl.unresolved "; ")))
        (assert (= (listLength aslSet) (+ want 1)) (str entry ": the ASL closure holds " (stringFromInt64 want) " modules besides the entry, got " (stringFromInt64 (- (listLength aslSet) 1))))
        (assert (= (+ (listLength hostSet) 1) count) (str entry ": the paths grepped from the host build are all " (stringFromInt64 count) " modules it embeds, prelude included"))
        (assert (= aslSet hostSet) (str entry ": ASL and host module sets agree; ASL " (stringJoin aslSet " ") " host " (stringJoin hostSet " ")))
        true))

fn ! testCompilerClosureMatchesHost -> Bool
  (assertSameClosure! "asl/packages/asl-compiler/src/compiler.asl" 45)

fn ! testDeprecatedPathClosureMatchesHost -> Bool
  (assertSameClosure! "asl/packages/asl-checker/tests/boundedSubstitutionTest.asl" 2)

fn ! testSymlinkIsNotASecondDeclaration -> Bool
  (assertSameClosure! "asl/packages/asl-checker/tests/fixtures/closureParity/symlinkImporter.asl" 10)

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

fn ! testAmbiguousBareImportFailsInBoth -> Bool
  (let [(importer "asl/packages/asl-checker/tests/fixtures/closureParity/ambiguousImporter.asl")
        (host (processRun (str (hostBin) " check " importer " 2>&1")))
        (hostLine (optionOr (listHead (filter (fn [(l String)] -> Bool (stringContains? l "ERR_UNRESOLVED_IMPORT parityDup")) (stringLines host.stdout))) ""))
        (res (r/resolveImport! (realOf! importer) "parityDup" (r/emptyModIndex)))
        (cl (r/loadModuleClosure! importer false))]
    (do (assert (= host.exitCode 1) "asl-host check rejects the ambiguous bare import")
        (assert (stringContains? hostLine "parityDup ambiguous: ") (str "the host names the ambiguity: " host.stdout))
        (assert (mt res.status ((r/resAmbiguous) true) (_ false)) (str "the ASL resolver reports parityDup ambiguous: " res.note))
        (assert (= (listLength (candidatesOf res.note)) 2) (str "the ASL note lists both declaring modules: " res.note))
        (assert (= (candidatesOf res.note) (candidatesOf hostLine)) (str "ASL and host name the same candidates: " res.note " vs " hostLine))
        (assert (= (listLength cl.unresolved) 1) "the ASL closure records the failed import")
        (refute (listAny? (fn [(p String)] -> Bool (stringContains? p "parityDup")) cl.paths) "no parityDup candidate is loaded")
        true))

fn ! testTargetsImportsResolveInBoth -> Bool
  (let [(entry "asl/packages/asl-compiler/src/targets.asl")
        (host (processRun (str (hostBin) " check " entry " 2>&1")))
        (cl (r/loadModuleClosure! entry false))]
    (do (refute (stringContains? host.stdout "ERR_UNRESOLVED_IMPORT") (str "asl-host resolves every import of targets.asl: " host.stdout))
        (assert (listEmpty? cl.unresolved) (str "the ASL loader resolves every import of targets.asl: " (stringJoin cl.unresolved "; ")))
        (assert (> (listLength cl.paths) 23) "the targets closure reaches past the compiler's own")
        true))

fn ! runTests -> Bool
  (do (assert (testCompilerClosureMatchesHost) "testCompilerClosureMatchesHost")
      (assert (testDeprecatedPathClosureMatchesHost) "testDeprecatedPathClosureMatchesHost")
      (assert (testSymlinkIsNotASecondDeclaration) "testSymlinkIsNotASecondDeclaration")
      (assert (testLoadModuleDepsResolvesFromFirstRoot) "testLoadModuleDepsResolvesFromFirstRoot")
      (assert (testAmbiguousBareImportFailsInBoth) "testAmbiguousBareImportFailsInBoth")
      (assert (testTargetsImportsResolveInBoth) "testTargetsImportsResolveInBoth")
      true)
