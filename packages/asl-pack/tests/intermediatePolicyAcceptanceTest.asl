(module asl-pack/tests/intermediatePolicyAcceptanceTest
  :x [testIntermediatePolicySchema testConfigDeclaration testGitignoreAndAslignoreIsolation testWorkspaceCleanStatus runTests]
  :i [(asl-tools/fleet/run :a run)])

fn ! testIntermediatePolicySchema -> Bool
  (let [(unitTestRes (run/runOneLimited (run/job (list "./bin/asl" "test" "asl/packages/asl-pack/tests/intermediatePolicyTest.asl") "." (run/childEnv (list))) (run/limits 180 8)))
        (mRes (fileReadString "asl/packages/asl-pack/manifest.asn"))
        (codeRes (fileReadString "asl/packages/asl-pack/src/intermediatePolicy.asl"))]
    (do
      (assert (= unitTestRes.exit 0) "asl-pack intermediatePolicy unit test passed")
      (refute (!= unitTestRes.exit 0) "refutes unit test failure")
      (match mRes
        ((err _) false)
        ((ok mSrc)
          (do
            (assert (stringContains? mSrc "aslPack/intermediatePolicy") "manifest registers intermediate-policy")
            (refute (not (stringContains? mSrc "aslPack/intermediatePolicy")) "refutes missing registration")
            (match codeRes
              ((err _) false)
              ((ok code)
                (do
                  (assert (stringContains? code "IntermediatePolicy") "defines IntermediatePolicy schema")
                  (assert (stringContains? code "makeDefaultIntermediatePolicy") "defines makeDefaultIntermediatePolicy")
                  (assert (stringContains? code "resolveIntermediatePath") "defines resolveIntermediatePath")
                  (assert (stringContains? code "shouldCleanIntermediates?") "defines shouldCleanIntermediates?")
                  (assert (stringContains? code "cleanIntermediateFile!") "defines cleanIntermediateFile!")
                  true))))))))

fn ! testConfigDeclaration -> Bool
  (let [(cfgRes (fileReadString ".asl.config.asn"))]
    (match cfgRes
      ((err _) false)
      ((ok cfg)
        (do
          (assert (stringContains? cfg ":intermediatePolicy") "config declares :intermediatePolicy")
          (assert (stringContains? cfg ":cleanIntermediates true") "config declares :cleanIntermediates true")
          (assert (stringContains? cfg ":buildDir \"target\"") "config declares :buildDir target")
          (refute (stringContains? cfg "\"bootstrap.c\"") "config contains zero bootstrap.c references")
          true))))

fn ! testGitignoreAndAslignoreIsolation -> Bool
  (let [(giRes (fileReadString ".gitignore"))
        (aiRes (fileReadString ".aslignore"))]
    (match giRes
      ((err _) false)
      ((ok gi)
        (do
          (assert (stringContains? gi "target/") ".gitignore ignores target/")
          (assert (stringContains? gi "*.ll") ".gitignore ignores *.ll")
          (assert (stringContains? gi "asl.ll") ".gitignore ignores asl.ll")
          (assert (stringContains? gi ".asl/build/") ".gitignore ignores .asl/build/")
          (match aiRes
            ((err _) false)
            ((ok ai)
              (do
                (assert (stringContains? ai "target/") ".aslignore ignores target/")
                (assert (stringContains? ai "*.ll") ".aslignore ignores *.ll")
                (assert (stringContains? ai "asl.ll") ".aslignore ignores asl.ll")
                (assert (stringContains? ai ".asl/build/") ".aslignore ignores .asl/build/")
                true)))))))

fn ! testWorkspaceCleanStatus -> Bool
  (let [(statusRes (run/runOneLimited (run/job (list "git" "status" "--porcelain") "." (run/childEnv (list))) (run/limits 180 8)))
        (remoteRes (run/runOneLimited (run/job (list "git" "remote") "." (run/childEnv (list))) (run/limits 180 8)))
        (remoteOutput (stringReplace remoteRes.out "nice: setpriority: Operation not permitted\n" ""))
        (remoteCount (listLength (filter (fn [(line String)] -> Bool (not (stringEmpty? line))) (stringLines remoteOutput))))]
    (do
      (assert (and (= remoteRes.exit 0) (= remoteCount 0)) "workspace has zero git remotes")
      (refute (or (!= remoteRes.exit 0) (!= remoteCount 0)) "refutes non-zero git remotes")
      (assert (not (stringContains? statusRes.out "?? asl.ll")) "root asl.ll is not untracked in git")
      (refute (stringContains? statusRes.out "?? asl.ll") "refutes untracked root asl.ll")
      true))

fn ! runTests -> Bool
  (do
    (assert (testIntermediatePolicySchema) "testIntermediatePolicySchema")
    (assert (testConfigDeclaration) "testConfigDeclaration")
    (assert (testGitignoreAndAslignoreIsolation) "testGitignoreAndAslignoreIsolation")
    (assert (testWorkspaceCleanStatus) "testWorkspaceCleanStatus")
    true)
