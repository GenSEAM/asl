(module asl-tools/tests/nativeSuiteWallTest
  :x [runTests]
  :i [(asl-tools/nativeTest :a nt) (asl-tools/fleet/run :a fr) (asl-parser/ast :a ast)])

fn decl n: String -> String
  (str "(module m :x [runTests] :i [])\n\nfn suiteWallS -> Int64\n  " n "\n\nfn runTests -> Bool\n  true\n")

; (:m :ref NATIVETEST-PER-SUITE-WALL :do "the declared wall is read from the suite source and clamped: absent or malformed is the 1800 s default, below it is raised to it, above 7200 s is capped; then bin/asl test and nativeTest's own runner (waiting for the native CLI, so the fixture never runs on asl-host) runs a fixture declaring 2400 s, and the fixture prints the wall its own lease shows: 2460 s under bin/asl test, whose runner kills at the 2400 s wall and leases the group 60 s past it as the backstop (TEST-RUNNER-SELECT a55bb308c), and 2400 s under nativeTest's own runner, where fr/runGuarded kills at the lease deadline")
; (:m :ref SUITEWALL-DECL-PARSE :do "a source whose only suiteWallS text sits inside a multi-line string literal")
fn quoted -> String
  (str "(module m :x [runTests] :i [])\n\nfn note -> String\n  \"x\nfn suiteWallS -> Int64\n  6000\n\"\n\nfn runTests -> Bool\n  true\n")

fn ! runTests -> Bool
  (let [(root (resultOr (realPath ".") "."))
        (fixture "asl/tools/tests/fixtures/suiteWall/wallProbeTest.asl")
        (run (fr/runOneLimited (fr/job (list (str root "/bin/asl") "test" fixture) root (fr/childEnv (list "ASL_NATIVE_CLI_WAIT=1"))) (fr/limits 1200 32)))
        (own (fr/runOneLimited (fr/job (list (str root "/bin/asl") "run" "asl/tools/nativeTest.asl" fixture) root (fr/childEnv (list "ASL_NATIVE_CLI_WAIT=1"))) (fr/limits 1200 32)))]
    (do (assert (= (nt/declaredWallS (decl "3600")) (some 3600)) "a declared suiteWallS is read")
        (assert (= (nt/declaredWallS "(module m :x [] :i [])\n") (none)) "no declaration is none")
        (assert (= (nt/declaredWallS (decl "soon")) (none)) "a body that is not an integer is none")
        (assert (ok? (ast/parse (quoted))) "the quoted-declaration source parses")
        (assert (= (nt/declaredWallS (quoted)) (none)) "declaration text inside a string literal is no declaration")
        (assert (= (nt/declaredWallS "(module m :x [runTests] :i [])\n\nfn otherWallS -> Int64\n  3000\n") (none)) "an integer fn under another name is no declaration")
        (assert (= (nt/declaredWallS "fn suiteWallS -> Int64\n  2400\n\nfn runTests -> Bool\n  true\n") (some 2400)) "a headerless script's top-level suiteWallS is read")
        (assert (= (nt/suiteWall (decl "3600")) 3600) "a declared 3600 s wall is used")
        (assert (= (nt/suiteWall "(module m :x [] :i [])\n") 1800) "an absent declaration keeps the 1800 s default")
        (assert (= (nt/suiteWall (decl "60")) 1800) "a declaration below the default is raised to it")
        (assert (= (nt/suiteWall (decl "99999")) 7200) "a declaration over the cap is capped at 7200 s")
        (assert (= run.exit 0) (str "bin/asl test runs the 2400 s fixture under its declared wall: " run.out))
        (assert (stringContains? run.out "wallProbeTest.asl: 2 assertion(s) executed") (str "the fixture's lease assertions ran: " run.out))
        (assert (stringContains? run.out "wallProbe leaseWallS 2460\n") (str "under bin/asl test the runner kills at the declared 2400 s wall and the lease is the backstop 60 s past it: " run.out))
        (assert (and (= own.exit 0) (stringContains? own.out "wallProbeTest.asl: 2 assertion(s) executed")) (str "nativeTest's own runner (runOne) runs the fixture under its declared wall too: " own.out))
        (assert (stringContains? own.out "wallProbe leaseWallS 2400\n") (str "under nativeTest's own runner the lease deadline is the declared 2400 s wall itself: " own.out))
        true))
