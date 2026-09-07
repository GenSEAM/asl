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
    (and (= (.-path entry) "/app/.asl.local.config.asn")
         (= (.-level entry) "local"))))

(df test-precedence-hierarchy [] -> Bool
  :d "Verifies precedence ordering between configuration levels."
  (and (cc/is-level-higher? "local" "workspace")
       (and (cc/is-level-higher? "local" "subproject")
            (and (cc/is-level-higher? "subproject" "workspace")
                 (and (cc/is-level-higher? "workspace" "user")
                      (not (cc/is-level-higher? "user" "local")))))))

(df test-cascade-merge [] -> Bool
  :d "Verifies map merging with leaf precedence."
  (let [(parent (map-set (map-empty) "port" "3000"))
        (leaf (map-set (map-empty) "port" "8080"))
        (merged (cc/cascade-merge parent leaf))]
    (= (map-get merged "port") "8080")))

(df test-secret-env-resolution [] -> Bool
  :d "Verifies dynamic resolution from environment map with fallbacks."
  (let [(mock-env (map-set (map-empty) "GITHUB_TOKEN" "ghp_live_secret"))
        (found (cc/resolve-secret-value "env" "GITHUB_TOKEN" "fallback_val" mock-env))
        (missing (cc/resolve-secret-value "env" "MISSING_VAR" "fallback_val" mock-env))
        (literal (cc/resolve-secret-value "literal" "const_key" "" mock-env))]
    (and (= found "ghp_live_secret")
         (and (= missing "fallback_val")
              (= literal "const_key")))))

(df test-secret-masking [] -> Bool
  :d "Verifies that masking returns [REDACTED] for non-empty credentials."
  (let [(masked (cc/mask-secret "ghp_1234567890abcdef"))
        (empty-masked (cc/mask-secret ""))]
    (and (= masked "[REDACTED]")
         (= empty-masked ""))))

(df run-tests [] -> Bool
  :d "Executes test suite."
  (and (test-cascade-entry-creation)
       (and (test-precedence-hierarchy)
            (and (test-cascade-merge)
                 (and (test-secret-env-resolution)
                      (test-secret-masking))))))
