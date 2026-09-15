(module aslPack/standaloneTest
  :d "Unit tests for standalone binary packaging, footer layouts, and codesigning invariants."
  :x [runTests]
  :i [(standalone :a s)
      (platform :a plat)])

(df testFooterConstants [] -> Bool
  :d "Verifies fixed 16-byte footer and magic identifier."
  (do
    (assert (= (s/magicFooter) "ASLPACK!") "Magic footer must equal ASLPACK!")
    (assert (= (s/footerSizeBytes) 16) "Footer size bytes must equal 16")
    true))

(df testCodesignEvaluation [] -> Bool
  :d "Verifies that macOS targets require codesigning while Linux/Windows do not."
  (let [(pMac (plat/makePlatform (plat/osMacos) (plat/archArm64)))
        (pLin (plat/makePlatform (plat/osLinux) (plat/archX64)))
        (pWin (plat/makePlatform (plat/osWindows) (plat/archX64)))]
    (assert (s/requiresCodesign? pMac) "macOS platform must require codesigning")
    (assert (not (s/requiresCodesign? pLin)) "Linux platform must not require codesigning")
    (assert (not (s/requiresCodesign? pWin)) "Windows platform must not require codesigning")
    true))

(df testBundleManifestPlanning [] -> Bool
  :d "Verifies standalone bundle planning across target descriptors."
  (let [(pMac (plat/makePlatform (plat/osMacos) (plat/archArm64)))
        (cfg (s/StandaloneBundleConfig
               :runnerStubPath "templates/runner"
               :wasmPayloadPath "dist/app.wasm"
               :manifestHeader "pack:{v1}"
               :outputBinaryPath "dist/app-bin"
               :platform pMac))
        (manifest (s/planStandaloneBundle cfg 4096))]
    (assert (= (.-payloadSize manifest) 4096) "Payload size must equal 4096")
    (assert (= (.-footerMagic manifest) "ASLPACK!") "Footer magic must equal ASLPACK!")
    (assert (.-requiresCodesign manifest) "Manifest must require codesign")
    true))

(df testFormatFunctions [] -> Bool
  :d "Verifies format-footer-manifest and format-codesign-command."
  (do
    (assert (= (s/formatFooterManifest 123 "TEST") "pack-foot:{123|TEST}") "Footer manifest format")
    (assert (= (s/formatCodesignCommand "/path/to/bin") "codesign -s - --force \"/path/to/bin\"") "Codesign format")
    true))

(df runTests [] -> Bool
  :d "Executes standalone packaging test suites."
  (do
    (assert (testFooterConstants) "test-footer-constants must pass")
    (assert (testCodesignEvaluation) "test-codesign-evaluation must pass")
    (assert (testBundleManifestPlanning) "test-bundle-manifest-planning must pass")
    (assert (testFormatFunctions) "test-format-functions must pass")
    true))
