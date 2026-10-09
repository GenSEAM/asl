(module asl-checker/resolveIoTest :x [runTests] :i [(resolve :a r)])

fn ! sh cmd: String -> ProcessOutput
  (processRun cmd)

fn ! workDir! -> String
  (let [(made (sh "d=$(mktemp -d) && cd \"$d\" && pwd -P"))]
    (do (assert (= made.exitCode 0) "mktemp -d makes a work directory")
        (stringReplace made.stdout "\n" "")))

fn moduleSource name: String imports: String -> String
  (str "(module " name " :x [f] :i [" imports "])\n\nfn f -> Int64\n  1\n")

fn ! writeFixture! dir: String name: String imports: String -> Bool
  (let [(res (fileWrite (str dir "/" name ".asl") (moduleSource name imports)))]
    (do (assert (ok? res) (str "fixture " name ".asl written")) true))

fn ! fixtureDir! -> String
  (let [(dir (workDir!))
        (cfg (fileWrite (str dir "/.asl.config.asn") "(:aslConfig :workspace \"fx\")\n"))]
    (do (assert (ok? cfg) "fixture workspace config written")
        (writeFixture! dir "ioA" "(ioB :a b)")
        (writeFixture! dir "ioB" "")
        (writeFixture! dir "ioC" "(ioNope :a n)")
        (writeFixture! dir "ioD" "(ioBad :a x)")
        (assert (ok? (fileWrite (str dir "/ioBad.asl") "(module ioBad :x [] :i [])\n\nfn -> Int64\n  1\n")) "unparsable fixture written")
        dir))

fn hasLine lines: (List String) needle: String -> Bool
  (listAny? (fn [(l String)] -> Bool (stringContains? l needle)) lines)

fn ! testUnreadableDependencyIsAnIoLine dir: String -> Bool
  (let [(locked (sh (str "chmod 000 " dir "/ioB.asl")))
        (cl (r/loadModuleClosure! (str dir "/ioA.asl") false))
        (restored (sh (str "chmod 644 " dir "/ioB.asl")))]
    (do (assert (= locked.exitCode 0) "ioB.asl made unreadable")
        (assert (= restored.exitCode 0) "ioB.asl made readable again")
        (assert (hasLine cl.errors (str dir "/ioB.asl: ERR_IO ")) (str "an unreadable dependency is an ERR_IO line: " (stringJoin cl.errors "; ")))
        (assert (hasLine cl.errors "permission denied") (str "the line names the IoError case: " (stringJoin cl.errors "; ")))
        (refute (listContains? cl.paths (str dir "/ioB.asl")) "the unreadable dependency is not loaded")
        true))

fn ! testUnreadableEntryIsAnIoLine dir: String -> Bool
  (let [(locked (sh (str "chmod 000 " dir "/ioA.asl")))
        (cl (r/loadModuleClosure! (str dir "/ioA.asl") false))
        (restored (sh (str "chmod 644 " dir "/ioA.asl")))]
    (do (assert (= locked.exitCode 0) "ioA.asl made unreadable")
        (assert (= restored.exitCode 0) "ioA.asl made readable again")
        (assert (= (listLength cl.errors) 1) (str "an unreadable entry is one error line: " (stringJoin cl.errors "; ")))
        (assert (hasLine cl.errors (str dir "/ioA.asl: ERR_IO permission denied")) (str "the entry line names the file and the case: " (stringJoin cl.errors "; ")))
        (assert (listEmpty? cl.paths) "nothing is loaded from an unreadable entry")
        true))

fn ! testLoadModuleDepsOkOnGoodImports dir: String -> Bool
  (mt (r/loadModuleDeps! (list dir) (list "ioA"))
    ((err _) (do (assert false "loadModuleDeps! is ok when every import loads") false))
    ((ok deps) (do (assert (mt (mapGet deps "ioA") ((some s) (= s.name "ioA")) ((none) false)) "the import path keys its summary") true)))

fn ! testLoadModuleDepsErrOnMissingImport dir: String -> Bool
  (let [(direct (r/loadModuleDeps! (list dir) (list "ioNope")))
        (transitive (r/loadModuleDeps! (list dir) (list "ioC")))]
    (do (assert (err? direct) "loadModuleDeps! is err when an import resolves to no module")
        (assert (err? transitive) "loadModuleDeps! is err when a dependency's import resolves to no module")
        true))

fn ! testLoadModuleDepsErrOnUnreadableOrUnparsable dir: String -> Bool
  (let [(locked (sh (str "chmod 000 " dir "/ioB.asl")))
        (unreadable (r/loadModuleDeps! (list dir) (list "ioA")))
        (restored (sh (str "chmod 644 " dir "/ioB.asl")))
        (unparsable (r/loadModuleDeps! (list dir) (list "ioD")))]
    (do (assert (= locked.exitCode 0) "ioB.asl made unreadable")
        (assert (= restored.exitCode 0) "ioB.asl made readable again")
        (assert (err? unreadable) "loadModuleDeps! is err when a dependency cannot be read")
        (assert (err? unparsable) "loadModuleDeps! is err when a dependency does not parse")
        true))

fn ! testAsl1ReportsTransitiveMissingImport dir: String -> Bool
  (let [(entry (str dir "/ioMain.asl"))
        (written (fileWrite entry "(module ioMain :x [main] :i [(ioC :a c)])\n\nfn ! main args: (List String) -> (Result Int64 String)\n  (ok (c/f))\n"))
        (driver (str "asl/host/out/asl-host run asl/packages/asl-compiler/src/asl1.asl "))
        (checked (sh (str driver "check " entry)))
        (built (sh (str driver "build " entry " -o " dir "/ioMain.ll")))]
    (do (assert (ok? written) "ioMain.asl fixture written")
        (assert (= checked.exitCode 1) (str "asl1 check exits 1 when a dependency's import is missing, got " checked.exitCode "; stderr: " checked.stderr))
        (assert (stringContains? checked.stderr (str dir "/ioC.asl: ERR_UNRESOLVED_IMPORT ioNope")) (str "asl1 check names the missing import: " checked.stderr))
        (assert (stringContains? checked.stderr "[ERR_LOAD]") (str "asl1 check reports the failed load: " checked.stderr))
        (assert (= built.exitCode 1) (str "asl1 build exits 1 when a dependency's import is missing, got " built.exitCode))
        (assert (stringContains? built.stderr (str dir "/ioC.asl: ERR_UNRESOLVED_IMPORT ioNope")) (str "asl1 build names the missing import: " built.stderr))
        (assert (stringContains? built.stderr "Failed to load package dependencies of ") (str "asl1 build stops at the load, before linking: " built.stderr))
        (assert (err? (fileRead (str dir "/ioMain.ll"))) "asl1 build writes no .ll")
        true))

fn ! testSysImportShortcuts dir: String -> Bool
  (let [(top (writeFixture! dir "ioSysTop" "(sys :a s)"))
        (leaf (writeFixture! dir "ioSysLeaf" "(sys :a s)"))
        (root (writeFixture! dir "ioSysRoot" "(ioSysLeaf :a leaf)"))
        (topCl (r/loadModuleClosure! (str dir "/ioSysTop.asl") false))
        (nestedCl (r/loadModuleClosure! (str dir "/ioSysRoot.asl") false))
        (leafPath (optionOr (listHead nestedCl.paths) ""))
        (leafSummary (mapGet nestedCl.deps leafPath))]
    (do (assert top "top-level sys fixture written")
        (assert leaf "transitive sys fixture written")
        (assert root "transitive root fixture written")
        (assert (listEmpty? topCl.unresolved) (str "top-level sys import is a built-in, not an unresolved file: " (stringJoin topCl.unresolved "; ")))
        (assert (listEmpty? topCl.paths) (str "top-level sys import creates no module path: " (stringJoin topCl.paths "; ")))
        (assert (listEmpty? topCl.errors) (str "top-level sys import does not try to read a fake module: " (stringJoin topCl.errors "; ")))
        (assert (listEmpty? nestedCl.unresolved) (str "a dependency's sys import is built-in, not unresolved: " (stringJoin nestedCl.unresolved "; ")))
        (assert (listEmpty? nestedCl.errors) (str "a dependency's sys import does not try to read a fake module: " (stringJoin nestedCl.errors "; ")))
        (assert (= (listLength nestedCl.paths) 1) (str "nested sys import retains only the real dependency: " (stringJoin nestedCl.paths "; ")))
        (assert (listAny? (fn [(p String)] -> Bool (stringEndsWith? p "/ioSysLeaf.asl")) nestedCl.paths) "nested sys import does not hide the real dependency")
        (assert (mt leafSummary ((some summary) (mt (r/modImport summary "s") ((some path) (= path "sys")) ((none) false))) ((none) false)) "the sys import alias remains bound to the builtin module")
        true))

fn testParentDirOf -> Bool
  (do (assert (= (r/parentDirOf "/a/b.asl") "/a") "parent of an absolute file")
      (assert (= (r/parentDirOf "/b.asl") "/") "parent of a top-level file is /")
      (assert (= (r/parentDirOf "/") "/") "parent of / is /")
      (assert (= (r/parentDirOf "sub/b.asl") "sub") "parent of a relative file")
      (assert (= (r/parentDirOf "b.asl") ".") (str "parent of a slashless path is ., got " (r/parentDirOf "b.asl")))
      (assert (= (r/parentDirOf "sub") ".") "parent of a relative directory is .")
      (assert (= (r/parentDirOf ".") ".") "parent of . is .")
      (assert (= (r/parentDirOf "") ".") "parent of the empty path is .")
      true)

fn ! testResolveImportFromRelativeImporter -> Bool
  (let [(bare (r/resolveImport! "resolveIoTestImporter.asl" "asl-checker/unify" (r/emptyModIndex)))
        (nested (r/resolveImport! "asl/packages/asl-checker/tests/resolveIoTest.asl" "unify" (r/emptyModIndex)))]
    (do (assert (mt bare.status ((r/resOk) true) (_ false)) (str "a slashless importer resolves against the working directory: " bare.note))
        (assert (stringEndsWith? bare.path "/asl/packages/asl-checker/src/unify.asl") (str "to the unify module: " bare.path))
        (assert (mt nested.status ((r/resOk) true) (_ false)) (str "a relative importer path resolves: " nested.note))
        (assert (= nested.path bare.path) "both reach the same module")
        true))

fn ! runTests -> Bool
  (let [(dir (fixtureDir!))]
    (do (assert (testSysImportShortcuts dir) "testSysImportShortcuts")
        (assert (testParentDirOf) "testParentDirOf")
        (assert (testResolveImportFromRelativeImporter) "testResolveImportFromRelativeImporter")
        (assert (testUnreadableDependencyIsAnIoLine dir) "testUnreadableDependencyIsAnIoLine")
        (assert (testUnreadableEntryIsAnIoLine dir) "testUnreadableEntryIsAnIoLine")
        (assert (testLoadModuleDepsOkOnGoodImports dir) "testLoadModuleDepsOkOnGoodImports")
        (assert (testLoadModuleDepsErrOnMissingImport dir) "testLoadModuleDepsErrOnMissingImport")
        (assert (testLoadModuleDepsErrOnUnreadableOrUnparsable dir) "testLoadModuleDepsErrOnUnreadableOrUnparsable")
        (assert (testAsl1ReportsTransitiveMissingImport dir) "testAsl1ReportsTransitiveMissingImport")
        (assert (= (sh (str "rm -rf " dir)).exitCode 0) "work directory removed")
        true))
