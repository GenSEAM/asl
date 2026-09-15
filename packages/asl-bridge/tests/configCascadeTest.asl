(module asl-bridge/configCascadeTest
  :d "Unit tests for Hierarchical Configuration Cascading and Secret Resolution."
  :x [testCascadeEntryCreation
      testPrecedenceHierarchy
      testCascadeMerge
      testSecretEnvResolution
      testSecretMasking
      runTests]
  :i [(config_cascade :a cc)])

(df testCascadeEntryCreation [] -> Bool
  :d "Verifies config cascade entry constructor."
  (let [(entry (cc/makeCascadeEntry "/app/.asl.local.config.asn" "local" (map-empty)))]
    (assert (= (.-path entry) "/app/.asl.local.config.asn") "Entry path must match")
    (assert (= (.-level entry) "local") "Entry level must match")
    true))

(df testPrecedenceHierarchy [] -> Bool
  :d "Verifies precedence ordering between configuration levels."
  (do
    (assert (cc/isLevelHigher? "local" "workspace") "local > workspace")
    (assert (cc/isLevelHigher? "local" "subproject") "local > subproject")
    (assert (cc/isLevelHigher? "subproject" "workspace") "subproject > workspace")
    (assert (cc/isLevelHigher? "workspace" "user") "workspace > user")
    (assert (not (cc/isLevelHigher? "user" "local")) "user not > local")
    true))

(df testCascadeMerge [] -> Bool
  :d "Verifies map merging with leaf precedence."
  (let [(parent (map-set (map-empty) "port" "3000"))
        (leaf (map-set (map-empty) "port" "8080"))
        (merged (cc/cascadeMerge parent leaf))]
    (assert (= (option-or (map-get merged "port") "") "8080") "Merged leaf port must be 8080")
    (assert (not (= (map-get merged "port") "3000")) "Merged leaf port must not be parent 3000")
    true))

(df testSecretEnvResolution [] -> Bool
  :d "Verifies dynamic resolution from environment map with fallbacks."
  (let [(mockEnv (map-set (map-empty) "GITHUB_TOKEN" "ghp_live_secret"))
        (found (cc/resolveSecretValue "env" "GITHUB_TOKEN" "fallback_val" mockEnv))
        (missing (cc/resolveSecretValue "env" "MISSING_VAR" "fallback_val" mockEnv))
        (literal (cc/resolveSecretValue "literal" "const_key" "" mockEnv))]
    (assert (= found "ghp_live_secret") "Live secret found")
    (assert (= missing "fallback_val") "Missing fallback resolved")
    (assert (= literal "const_key") "Literal key resolved")
    true))

(df testSecretMasking [] -> Bool
  :d "Verifies that masking returns [REDACTED] for non-empty credentials."
  (let [(masked (cc/maskSecret "ghp_1234567890abcdef"))
        (emptyMasked (cc/maskSecret ""))]
    (assert (= masked "[REDACTED]") "Masked credential must be [REDACTED]")
    (assert (= emptyMasked "") "Empty secret must be empty string")
    true))

(df runTests [] -> Bool
  :d "Executes test suite."
  (do
    (assert (testCascadeEntryCreation) "test-cascade-entry-creation must pass")
    (assert (testPrecedenceHierarchy) "test-precedence-hierarchy must pass")
    (assert (testCascadeMerge) "test-cascade-merge must pass")
    (assert (testSecretEnvResolution) "test-secret-env-resolution must pass")
    (assert (testSecretMasking) "test-secret-masking must pass")
    true))
