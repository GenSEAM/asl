(module aslPack/standaloneTest :x [runTests] :i [(standalone :a s) (platform :a plat)])

fn testFooterConstants -> Bool
  (do (assert (= (s/magicFooter) "ASLPACK!") "Magic footer must equal ASLPACK!") (assert (= (s/footerSizeBytes) 16) "Footer size bytes must equal 16") true)

fn testCodesignEvaluation -> Bool
  (let [(pMac (plat/makePlatform (plat/osMacos) (plat/archArm64))) (pLin (plat/makePlatform (plat/osLinux) (plat/archX64))) (pWin (plat/makePlatform (plat/osWindows) (plat/archX64)))] (assert (s/requiresCodesign? pMac) "macOS platform must require codesigning") (assert (not (s/requiresCodesign? pLin)) "Linux platform must not require codesigning") (assert (not (s/requiresCodesign? pWin)) "Windows platform must not require codesigning") true)

fn testBundleManifestPlanning -> Bool
  (let [(pMac (plat/makePlatform (plat/osMacos) (plat/archArm64))) (cfg (s/StandaloneBundleConfig :runnerStubPath "templates/runner" :wasmPayloadPath "dist/app.wasm" :manifestHeader "pack:{v1}" :outputBinaryPath "dist/app-bin" :platform pMac)) (manifest (s/planStandaloneBundle cfg 4096))] (assert (= manifest.payloadSize 4096) "Payload size must equal 4096") (assert (= manifest.footerMagic "ASLPACK!") "Footer magic must equal ASLPACK!") (assert manifest.requiresCodesign "Manifest must require codesign") true)

fn testFormatFunctions -> Bool
  (do (assert (= (s/formatFooterManifest 123 "TEST") "pack-foot:{123|TEST}") "Footer manifest format") (assert (= (s/formatCodesignCommand "/path/to/bin") "codesign -s - --force \"/path/to/bin\"") "Codesign format") true)

fn runTests -> Bool
  (do (assert (testFooterConstants) "test-footer-constants must pass") (assert (testCodesignEvaluation) "test-codesign-evaluation must pass") (assert (testBundleManifestPlanning) "test-bundle-manifest-planning must pass") (assert (testFormatFunctions) "test-format-functions must pass") true)
