(module asl/packages/asl-plugin/tests/artifactDigestTest :x [testLegitimateArtifactDigest! testTamperedArtifactDigest! testMissingArtifact! testShellInjectionResilience! testValidateManifestSecurity! testDualPolarityRefutations! runTests] :i [(asl-plugin/types :a t) (asl-plugin/security :a sec)])

fn ensureArtifactFixtures! -> Bool
  (if (and (fileExists? "tmp/sandbox_51302/valid.wasm") (fileExists? "tmp/sandbox_51302/plugin'quote;echo-inject.wasm")) true (let [(cmd "mkdir -p tmp/sandbox_51302 && echo 'valid-wasm' > tmp/sandbox_51302/valid.wasm && echo 'injection-safe' > \"tmp/sandbox_51302/plugin'quote;echo-inject.wasm\" 2>/dev/null") (res (processRun cmd))] (= res.exitCode 0)))

fn testLegitimateArtifactDigest! -> Bool
  (let [(validHash "6647aadc6af6d7d4788c9342f1c83915e50ea30bafe63dd857adc066efe3c0f2") (res (sec/verifyArtifactDigest! "tmp/sandbox_51302/valid.wasm" validHash))] (assert (ok? res) "Legitimate artifact hash must verify successfully") true)

fn testTamperedArtifactDigest! -> Bool
  (let [(tamperedHash "0000000000000000000000000000000000000000000000000000000000000000") (res (sec/verifyArtifactDigest! "tmp/sandbox_51302/valid.wasm" tamperedHash))] (assert (err? res) "Tampered artifact hash must fail verification") (mt res ((err e) (let [(isSigErr (mt e ((t/errInvalidSignature msg) (stringContains? msg "mismatch")) (else false)))] (assert isSigErr "Tampered hash must trigger errInvalidSignature mentioning mismatch") true)) ((ok _) false)))

fn testMissingArtifact! -> Bool
  (let [(validHash "6647aadc6af6d7d4788c9342f1c83915e50ea30bafe63dd857adc066efe3c0f2") (res (sec/verifyArtifactDigest! "tmp/sandbox_51302/nonexistent.wasm" validHash))] (assert (err? res) "Missing artifact must fail verification") (mt res ((err e) (let [(isNotFound (mt e ((t/errNotFound _) true) (else false)))] (assert isNotFound "Missing artifact must trigger errNotFound variant") true)) ((ok _) false)))

fn testShellInjectionResilience! -> Bool
  (let [(injectPath "tmp/sandbox_51302/plugin'quote;echo-inject.wasm") (injectHash "73040604420496feaaf407a41d20eee47a4152bacb24797405d6429e6431bdc7") (res (sec/verifyArtifactDigest! injectPath injectHash))] (assert (ok? res) "Special characters and single quotes must be safely escaped") true)

fn testValidateManifestSecurity! -> Bool
  (let [(validHash "6647aadc6af6d7d4788c9342f1c83915e50ea30bafe63dd857adc066efe3c0f2") (badHash "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff") (manifestOk (t/PluginManifest :id "p-valid" :name "Valid Plugin" :version "1.0.0" :kind (t/kindWasm) :capabilities (list) :exports (list) :entrypoint "valid.wasm" :integritySha256 validHash)) (manifestBad (t/PluginManifest :id "p-bad" :name "Bad Plugin" :version "1.0.0" :kind (t/kindWasm) :capabilities (list) :exports (list) :entrypoint "valid.wasm" :integritySha256 badHash)) (resOk (sec/validateManifestSecurity! manifestOk "tmp/sandbox_51302")) (resBad (sec/validateManifestSecurity! manifestBad "tmp/sandbox_51302"))] (assert (ok? resOk) "Valid manifest security check must pass") (assert (err? resBad) "Tampered manifest hash check must fail") true)

fn testDualPolarityRefutations! -> Bool
  (let [(validHash "6647aadc6af6d7d4788c9342f1c83915e50ea30bafe63dd857adc066efe3c0f2") (badHash "1111111111111111111111111111111111111111111111111111111111111111") (resOk (sec/verifyArtifactDigest! "tmp/sandbox_51302/valid.wasm" validHash)) (resBad (sec/verifyArtifactDigest! "tmp/sandbox_51302/valid.wasm" badHash)) (resMissing (sec/verifyArtifactDigest! "tmp/sandbox_51302/absent.wasm" validHash))] (refute (err? resOk) "Authentic artifact digest must not produce error") (refute (ok? resBad) "Mismatched artifact digest must not produce ok") (refute (ok? resMissing) "Absent artifact digest must not produce ok") true)

fn ! runTests -> Bool
  (do (assert (ensureArtifactFixtures!) "Fixtures must be created cleanly") (assert (testLegitimateArtifactDigest!) "testLegitimateArtifactDigest must pass") (assert (testTamperedArtifactDigest!) "testTamperedArtifactDigest must pass") (assert (testMissingArtifact!) "testMissingArtifact must pass") (assert (testShellInjectionResilience!) "testShellInjectionResilience must pass") (assert (testValidateManifestSecurity!) "testValidateManifestSecurity must pass") (assert (testDualPolarityRefutations!) "testDualPolarityRefutations must pass") true)
