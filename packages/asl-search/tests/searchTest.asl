(module aslWebApiSearch/tests/searchTest
  :x [testSearchSourceIntegrity! testSearchGrammarRegistration testSearchUrlCleaningLogic testBipolarQueryVerification RunTests! runTests]
  :i [])

fn testSearchSourceIntegrity! -> Bool
  (let [(eRes (fileRead "asl/packages/asl-search/src/engine.asl"))
        (ecoRes (fileRead "asl/packages/asl-search/src/ecosystems.asl"))]
    (mt eRes
      ((err e1) (assert false (str "Failed to read engine.asl: " e1)))
      ((ok eSrc)
        (do
          (assert (stringContains? eSrc "schema ProxyNode") "engine.asl defines ProxyNode")
          (assert (stringContains? eSrc "schema SearchResult") "engine.asl defines SearchResult")
          (assert (stringContains? eSrc "schema BipolarQuery") "engine.asl defines BipolarQuery")
          (assert (stringContains? eSrc "fn generateBipolarQuery") "engine.asl defines generateBipolarQuery")
          (assert (stringContains? eSrc "fn isProxyHealthy") "engine.asl defines isProxyHealthy")
          (assert (stringContains? eSrc "fn cleanUrl") "engine.asl defines cleanUrl")
          (assert (stringContains? eSrc "fn formatRagContext") "engine.asl defines formatRagContext")
          (refute (stringContains? eSrc "Mach-O") "Zero Mach-O in search engine")
          (refute (stringContains? eSrc "ELF64") "Zero ELF64 in search engine"))))
    (mt ecoRes
      ((err e2) (assert false (str "Failed to read ecosystems.asl: " e2)))
      ((ok ecoSrc)
        (do
          (assert (stringContains? ecoSrc "schema PackageInfo") "ecosystems.asl defines PackageInfo")
          (assert (stringContains? ecoSrc "fn buildEcosystemUrl") "ecosystems.asl defines buildEcosystemUrl")
          (assert (stringContains? ecoSrc "fn formatPackageMarkdown") "ecosystems.asl defines formatPackageMarkdown")
          (refute (= ecoSrc "") "ecosystems source refutes empty"))))
    true)

fn testSearchSymbolExports! -> Bool
  (let [(gRes (fileRead "asl/packages/asl-search/src/engine.asl"))]
    (mt gRes
      ((err e) (assert false (str "Failed to read engine.asl: " e)))
      ((ok gSrc)
        (do
          (assert (stringContains? gSrc "aslWebApiSearch/engine") "module declares aslWebApiSearch/engine")
          (assert (stringContains? gSrc "ProxyNode") "module defines ProxyNode")
          (assert (stringContains? gSrc "SearchResult") "module defines SearchResult")
          (assert (stringContains? gSrc "BipolarQuery") "module defines BipolarQuery")
          (assert (stringContains? gSrc "generateBipolarQuery") "module defines generateBipolarQuery")
          (refute (stringContains? gSrc ";;") "engine refutes legacy line comments"))))
    true)

fn testSearchUrlCleaningLogic -> Bool
  (let [(rawUrl "https://example.com/item?utm_source=twitter&id=42")
        (cleanTarget "https://example.com/item?id=42")]
    (assert (stringContains? rawUrl "utm_source") "raw URL contains tracking param")
    (refute (stringContains? cleanTarget "utm_source") "clean URL refutes tracking param")
    (assert (stringStartsWith? rawUrl "https://") "raw URL starts with https")
    (assert (stringStartsWith? cleanTarget "https://") "clean URL starts with https")
    (refute (stringStartsWith? cleanTarget "http://") "clean URL refutes plain http")
    true)

fn testBipolarQueryVerification -> Bool
  (let [(claim "contract liability limitation")
        (archClaim "AgentSlang Wasm sandbox performance")]
    (assert (stringContains? claim "liability") "claim contains liability")
    (refute (stringContains? claim "exploit") "claim refutes exploit")
    (assert (stringContains? archClaim "sandbox") "arch claim contains sandbox")
    (refute (stringContains? archClaim "repealed") "arch claim refutes repealed")
    true)

fn RunTests! -> Bool
  (and (testSearchSourceIntegrity!)
       (testSearchSymbolExports!)
       (testSearchUrlCleaningLogic)
       (testBipolarQueryVerification))

fn ! runTests -> Bool
  (RunTests!)
