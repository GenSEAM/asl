(module asl-cli/tests/moduleResolutionTest :x [runTests] :i [(asl-cli/tests/resolutionSample :a smp) (asl-text/escape :a esc)])

fn testDeclaredModuleResolution -> Bool
  (let [(val (smp/sampleIdentityValue))] (assert (= val "sample-manifest-resolution-success") "declared module must resolve and return sample token") true)

fn testPackageModuleResolution -> Bool
  (let [(val (esc/escapeAsnStr "hello \"world\""))] (assert (= val "hello \\\"world\\\"") "package module function must return escaped ASN string") true)

fn runTests -> Bool
  (do (assert (testDeclaredModuleResolution) "test-declared-module-resolution must pass") (assert (testPackageModuleResolution) "test-package-module-resolution must pass") true)
