(module aslPack/tests/intermediatePolicyTest
  :x [testDefaultPolicy testPathResolution testIsIntermediate testCleanIntermediates testGitignoreChecking runTests]
  :i [(intermediatePolicy :a ip)])

fn testDefaultPolicy -> Bool
  (let [(p (ip/makeDefaultIntermediatePolicy))]
    (do
      (assert p.cleanIntermediates "default policy has cleanIntermediates true")
      (refute (not p.cleanIntermediates) "refutes false cleanIntermediates")
      (assert (= p.buildDir "target") "default build directory is target")
      (assert (= p.keepFlag "--keep-intermediates") "default keepFlag is --keep-intermediates")
      (assert (listContains? p.ignoredExtensions ".ll") "ignoredExtensions contains .ll")
      (assert (listContains? p.ignoredDirectories "target") "ignoredDirectories contains target")
      true))

fn testPathResolution -> Bool
  (let [(p (ip/makeDefaultIntermediatePolicy))
        (path (ip/resolveIntermediatePath p "asl" ".ll"))]
    (do
      (assert (= path "target/asl.ll") "resolves target/asl.ll")
      (refute (!= path "target/asl.ll") "refutes wrong path")
      true))

fn testIsIntermediate -> Bool
  (let [(p (ip/makeDefaultIntermediatePolicy))]
    (do
      (assert (ip/isIntermediateFile? p "foo.ll") "foo.ll is intermediate")
      (assert (ip/isIntermediateFile? p "target/bin") "target/bin is intermediate")
      (assert (ip/isIntermediateFile? p ".asl/build/out.bc") ".asl/build/out.bc is intermediate")
      (refute (ip/isIntermediateFile? p "src/main.asl") "src/main.asl is not intermediate")
      true))

fn testCleanIntermediates -> Bool
  (let [(p (ip/makeDefaultIntermediatePolicy))]
    (do
      (assert (ip/shouldCleanIntermediates? p false) "should clean when keepIntermediates is false")
      (refute (ip/shouldCleanIntermediates? p true) "should not clean when keepIntermediates is true")
      true))

fn testGitignoreChecking -> Bool
  (let [(giContent "target/\n*.ll\n.asl/build/\nbuild/\n")]
    (do
      (assert (ip/isPathGitIgnored? "target/asl.ll" giContent) "target/asl.ll is gitignored")
      (assert (ip/isPathGitIgnored? "asl.ll" giContent) "asl.ll is gitignored via *.ll")
      (assert (ip/isPathGitIgnored? ".asl/build/cache" giContent) ".asl/build/cache is gitignored")
      (refute (ip/isPathGitIgnored? "asl/packages/main.asl" giContent) "main.asl is not gitignored")
      true))

fn runTests -> Bool
  (do
    (assert (testDefaultPolicy) "testDefaultPolicy")
    (assert (testPathResolution) "testPathResolution")
    (assert (testIsIntermediate) "testIsIntermediate")
    (assert (testCleanIntermediates) "testCleanIntermediates")
    (assert (testGitignoreChecking) "testGitignoreChecking")
    true)
