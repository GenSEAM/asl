(module asl-cli/tests/manifestResolutionTest :x [runTests testDeclaredManifestResolution testWorkspaceModuleResolution] :i [(asl-cli/tests/resolutionSample :a smp) (aslMem/math :a mmath)])

fn testDeclaredManifestResolution -> Bool
  (let [(token (smp/sampleIdentityValue))] (assert (= token "sample-manifest-resolution-success") "module must resolve and execute via declared name") true)

fn testWorkspaceModuleResolution -> Bool
  (let [(dot (mmath/vectorDot (list 1.0 2.0) (list 3.0 4.0)))] (assert (= dot 11.0) "vector-dot must evaluate correctly on resolved module") true)

fn runTests -> Bool
  (do (assert (testDeclaredManifestResolution) "test-declared-manifest-resolution must pass") (assert (testWorkspaceModuleResolution) "test-workspace-module-resolution must pass") true)
