(module asl-cli/tests/packageResolveTest
  :x [runTests]
  :i [(asl-tools/fleet/run :a fr)])

; (:m :ref PKGRESOLVE :do "CASE-PKG-INSIDE-WS and OUTSIDE-STAGE-AMBIGUOUS: a package with its own manifest placed under the workspace's dot directory (.asl/tmp, never indexed by the workspace walk) resolves its own qualified imports as its package root, and an outside package that carries a module named like a first-party one stages exactly one copy of it, so the import is not ambiguous; each asl test child runs through run.asl with a timeout and descendant limit")

fn ! repoRoot! -> String
  (resultOr (realPath ".") ".")

fn ! stamp! -> String
  (stringFromInt64 (monotonicNs))

fn ! writeAll! files: (List (Pair String String)) -> (Result Unit String)
  (match (listHead files)
    ((none) (ok ()))
    ((some f)
      (match (dirCreate (parentOf (pairFirst f)))
        ((err e) (err (str "cannot create " (parentOf (pairFirst f)) ": " e)))
        ((ok _)
          (match (fileWrite (pairFirst f) (pairSecond f))
            ((err e) (err (str "cannot write " (pairFirst f) ": " e)))
            ((ok _) (writeAll! (optionOr (listTail files) (list)))))))))

fn parentOf p: String -> String
  (let [(parts (stringSplit p "/"))]
    (stringJoin (listTake parts (- (listLength parts) 1)) "/"))

fn ! makeDirs! dirs: (List String) -> Bool
  (listAll? (fn [(d String)] -> Bool (ok? (dirCreate d))) dirs)

fn ! runAslTest! cwd: String path: String -> fr/Done
  (fr/runOneLimited (fr/job (list (str (repoRoot!) "/bin/asl") "test" path) cwd (fr/childEnv (list))) (fr/limits 900 64))

; (:m :ref PKGRESOLVE :do "case 1: the package lives in .asl/tmp of the workspace and has a manifest, src/ and tests/")
fn ! insideWorkspaceFiles! dir: String -> (List (Pair String String))
  (list
    (pair (str dir "/manifest.asn") "(:package pkgresolveinside\n :version \"0.1.0\"\n :entry \"src/a.asl\"\n :dependencies [])\n")
    (pair (str dir "/src/a.asl") "(module pkgresolveinside/a\n  :x [valueA]\n  :i [])\n\nfn valueA -> Int64\n  7\n")
    (pair (str dir "/src/b.asl") "(module pkgresolveinside/b\n  :x [valueB]\n  :i [(pkgresolveinside/a :a oa)])\n\nfn valueB -> Int64\n  (* (oa/valueA) 5)\n")
    (pair (str dir "/tests/aTest.asl") "(module pkgresolveinside/aTest\n  :x [runTests]\n  :i [(pkgresolveinside/b :a ob)])\n\nfn ! runTests -> Bool\n  (do\n    (assert (= (ob/valueB) 35) \"a package under the workspace dot directory resolves its transitive qualified imports\")\n    true)\n"))

fn ! testPackageInsideWorkspaceResolves! -> Bool
  (let [(root (repoRoot!))
        (rel (str ".asl/tmp/pkgResolveInside_" (stamp!)))
        (dir (str root "/" rel))
        (wrote (writeAll! (insideWorkspaceFiles! dir)))]
    (match wrote
      ((err e) (assert false (str "fixture setup failed: " e)))
      ((ok _)
        (let [(result (runAslTest! root (str rel "/tests/aTest.asl")))
              (removed (pathRemove dir))]
          (do
            (assert (= result.exit 0) (str "asl test of a package under .asl/tmp exits 0: " result.out))
            (assert (stringContains? result.out "assertion(s) executed") "the suite reports executed assertions")
            (assert (not (stringContains? result.out "ERR_UNRESOLVED_IMPORT")) "no unresolved-import error")
            (assert (ok? removed) "fixture directory is removed")
            true)))))

; (:m :ref PKGRESOLVE :do "case 2: an outside package that carries its own copy of the module asl-csv/csv; the first-party mirror must not stage a second one")
fn ! duplicateFiles! dir: String -> (List (Pair String String))
  (list
    (pair (str dir "/.asl.config.asn") "(:asl-config :workspace \"pkgresolveoutside\")\n")
    (pair (str dir "/packages/asl-csv/manifest.asn") "(:package asl-csv\n :version \"0.1.0\"\n :entry \"src/csv.asl\"\n :dependencies [])\n")
    (pair (str dir "/packages/asl-csv/src/csv.asl") "(module asl-csv/csv\n  :x [ownMarker]\n  :i [])\n\nfn ownMarker -> Int64\n  41\n")
    (pair (str dir "/tests/dupTest.asl") "(module pkgresolveoutside/dupTest\n  :x [runTests]\n  :i [(asl-csv/csv :a oc)])\n\nfn ! runTests -> Bool\n  (do\n    (assert (= (oc/ownMarker) 41) \"the outside package's own module is the one imported, with no ambiguity against the first-party copy\")\n    true)\n"))

fn ! testOutsideDuplicateModuleNotAmbiguous! -> Bool
  (let [(dir (str "/tmp/aslPkgResolveOutside_" (stamp!)))
        (wrote (writeAll! (duplicateFiles! dir)))
        (git (fr/runOneLimited (fr/job (list "git" "init" "-q") dir (fr/childEnv (list))) (fr/limits 60 8)))]
    (match wrote
      ((err e) (assert false (str "fixture setup failed: " e)))
      ((ok _)
        (let [(result (runAslTest! (repoRoot!) (str dir "/tests/dupTest.asl")))
              (removed (pathRemove dir))]
          (do
            (assert (= git.exit 0) "the fixture is a git work tree")
            (assert (not (stringContains? result.out "ambiguous")) (str "the staged mirror holds one copy of the duplicated module: " result.out))
            (assert (= result.exit 0) (str "asl test of an outside package with a first-party-named module exits 0: " result.out))
            (assert (stringContains? result.out "assertion(s) executed") "the suite reports executed assertions")
            (assert (ok? removed) "fixture directory is removed")
            true)))))

; (:m :ref PKGRESOLVE :do "case 3: asl build from a directory outside the workspace with an empty asl1 cache (a fresh HOME's) must stage the native asl1 from the seed and compile; the seed and the compiler read the prelude relative to their cwd, which was the caller's")
fn ! helloSource -> String
  "(module pkgresolvehello/main\n  :x [main]\n  :i [])\n\nfn main -> (Result Int String)\n  (ok 0)\n"

fn ! testBuildOutsideWorkspaceFreshCache! -> Bool
  (let [(dir (str "/tmp/aslPkgResolveBuild_" (stamp!)))
        (cache (str dir "/asl1cache"))
        (made (makeDirs! (list dir cache)))
        (wrote (fileWrite (str dir "/hello.asl") (helloSource)))
        (built (fr/runOneLimited (fr/job (list (str (repoRoot!) "/bin/asl") "build" "hello.asl" "-o" "hello.bin") dir (fr/childEnv (list (str "ASL_NATIVE_ASL1_CACHE=" cache)))) (fr/limits 3000 64)))
        (ran (fr/runOneLimited (fr/job (list (str dir "/hello.bin")) dir (fr/childEnv (list))) (fr/limits 60 8)))
        (removed (pathRemove dir))]
    (do
      (assert (and made (ok? wrote)) "fixture directory is made")
      (assert (= built.exit 0) (str "asl build outside the workspace with an empty asl1 cache exits 0 (was 127): " built.out))
      (assert (not (stringContains? built.out "ERR_LINK_PRELUDE")) "the prelude is found from the workspace root, not the caller's cwd")
      (assert (= ran.exit 0) (str "the built program runs and exits 0: " ran.out))
      (assert (ok? removed) "fixture directory is removed")
      true))

fn ! runTests -> Bool
  (and (and (testPackageInsideWorkspaceResolves!) (testOutsideDuplicateModuleNotAmbiguous!)) (testBuildOutsideWorkspaceFreshCache!))
