(module asl-pack/tests/packUnitSuitesTest :x [testPackUnitSuites! testResolvedSymbolInvariants! testDualPolarityRefutations! runTests] :i [(asl-tools/fleet/run :a run)])

fn runSuite! path: Str -> Bool
  (let [(done (run/runOneLimited (run/job (list "./bin/asl" "test" path) "." (run/childEnv (list))) (run/limits 180 8)))] (= done.exit 0))

fn testPackUnitSuites! -> Bool
  (let [(mOk (runSuite! "asl/packages/asl-pack/tests/mobileTest.asl")) (sOk (runSuite! "asl/packages/asl-pack/tests/standaloneTest.asl")) (rOk (runSuite! "asl/packages/asl-pack/tests/releaseTest.asl")) (dOk (runSuite! "asl/packages/asl-pack/tests/distTest.asl")) (fOk (runSuite! "asl/packages/asl-pack/tests/ffiTest.asl")) (iOk (runSuite! "asl/packages/asl-pack/tests/installerTest.asl")) (pOk (runSuite! "asl/packages/asl-pack/tests/packTest.asl")) (plOk (runSuite! "asl/packages/asl-pack/tests/platformTest.asl")) (rtOk (runSuite! "asl/packages/asl-pack/tests/runtimeTest.asl"))] (assert mOk "mobileTest.asl must pass") (assert sOk "standaloneTest.asl must pass") (assert rOk "releaseTest.asl must pass") (assert dOk "distTest.asl must pass") (assert fOk "ffiTest.asl must pass") (assert iOk "installerTest.asl must pass") (assert pOk "packTest.asl must pass") (assert plOk "platformTest.asl must pass") (assert rtOk "runtimeTest.asl must pass") true)

fn testResolvedSymbolInvariants! -> Bool
  (let [(pRes (run/runOneLimited (run/job (list "cat" "asl/packages/asl-pack/src/targets/previewServer.asl") "." (run/childEnv (list))) (run/limits 180 8))) (pText pRes.out) (sRes (run/runOneLimited (run/job (list "cat" "asl/packages/asl-pack/src/standalone.asl") "." (run/childEnv (list))) (run/limits 180 8))) (sText sRes.out)] (assert (stringContains? pText "(asl-transpile/asn :a asn)") "previewServer.asl must import asl-transpile/asn") (refute (stringContains? pText "asl-codec/core/asn") "previewServer.asl must not import asl-codec/core/asn") (assert (stringContains? sText "asn/AsnEntry") "standalone.asl must call constructor AsnEntry") (refute (stringContains? sText "asn/asnEntry") "standalone.asl must not call lowercase constructor asnEntry") true)

fn testDualPolarityRefutations! -> Bool
  (let [(pRes (run/runOneLimited (run/job (list "cat" "asl/packages/asl-pack/src/targets/previewServer.asl") "." (run/childEnv (list))) (run/limits 180 8))) (pText pRes.out) (sRes (run/runOneLimited (run/job (list "cat" "asl/packages/asl-pack/src/standalone.asl") "." (run/childEnv (list))) (run/limits 180 8))) (sText sRes.out)] (refute (stringContains? pText "core/asn") "previewServer must refute obsolete core/asn path") (refute (stringContains? sText "asnEntry") "standalone must refute lowercase constructor") true)

fn ! runTests -> Bool
  (do (assert (testResolvedSymbolInvariants!) "testResolvedSymbolInvariants must pass") (assert (testDualPolarityRefutations!) "testDualPolarityRefutations must pass") (assert (testPackUnitSuites!) "testPackUnitSuites must pass") true)
