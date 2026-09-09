(module asl-bridge/config-cascade-test
  :d "Unit tests for Hierarchical Configuration Cascading and Secret Resolution."
  :x [test-cascade-entry-creation
      test-precedence-hierarchy
      test-cascade-merge
      test-secret-env-resolution
      test-secret-masking
      run-tests]
  :i [(config_cascade :a cc)])

(df test-cascade-entry-creation [] -> Bool
  :d "Verifies config cascade entry constructor."
  (let [(entry (cc/make-cascade-entry "/app/.asl.local.config.asn" "local" (map-empty)))]
    (assert (= (.-path entry) "/app/.asl.local.config.asn") "Entry path must match")
    (assert (= (.-level entry) "local") "Entry level must match")
    true))

(df test-precedence-hierarchy [] -> Bool
  :d "Verifies precedence ordering between configuration levels."
  (do
    (assert (cc/is-level-higher? "local" "workspace") "local > workspace")
    (assert (cc/is-level-higher? "local" "subproject") "local > subproject")
    (assert (cc/is-level-higher? "subproject" "workspace") "subproject > workspace")
    (assert (cc/is-level-higher? "workspace" "user") "workspace > user")
    (assert (not (cc/is-level-higher? "user" "local")) "user not > local")
    true))

(df test-cascade-merge [] -> Bool
  :d "Verifies map merging with leaf precedence."
  (let [(parent (map-set (map-empty) "port" "3000"))
        (leaf (map-set (map-empty) "port" "8080"))
        (merged (cc/cascade-merge parent leaf))]
    (assert (= (map-get merged "port") "8080") "Merged leaf port must be 8080")
    (assert (not (= (map-get merged "port") "3000")) "Merged leaf port must not be parent 3000")
    true))

(df test-secret-env-resolution [] -> Bool
  :d "Verifies dynamic resolution from environment map with fallbacks."
  (let [(mock-env (map-set (map-empty) "GITHUB_TOKEN" "ghp_live_secret"))
        (found (cc/resolve-secret-value "env" "GITHUB_TOKEN" "fallback_val" mock-env))
        (missing (cc/resolve-secret-value "env" "MISSING_VAR" "fallback_val" mock-env))
        (literal (cc/resolve-secret-value "literal" "const_key" "" mock-env))]
    (assert (= found "ghp_live_secret") "Live secret found")
    (assert (= missing "fallback_val") "Missing fallback resolved")
    (assert (= literal "const_key") "Literal key resolved")
    true))

(df test-secret-masking [] -> Bool
  :d "Verifies that masking returns [REDACTED] for non-empty credentials."
  (let [(masked (cc/mask-secret "ghp_1234567890abcdef"))
        (empty-masked (cc/mask-secret ""))]
    (assert (= masked "[REDACTED]") "Masked credential must be [REDACTED]")
    (assert (= empty-masked "") "Empty secret must be empty string")
    true))

(df run-tests [] -> Bool
  :d "Executes test suite."
  (do
    (assert (test-cascade-entry-creation) "test-cascade-entry-creation must pass")
    (assert (test-precedence-hierarchy) "test-precedence-hierarchy must pass")
    (assert (test-cascade-merge) "test-cascade-merge must pass")
    (assert (test-secret-env-resolution) "test-secret-env-resolution must pass")
    (assert (test-secret-masking) "test-secret-masking must pass")
    true))
