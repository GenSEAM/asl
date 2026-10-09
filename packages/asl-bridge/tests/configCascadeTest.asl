(module asl-bridge/configCascadeTest :x [testCascadeEntryCreation testPrecedenceHierarchy testCascadeMerge testSecretEnvResolution testSecretMasking runTests] :i [(configCascade :a cc)])

fn testCascadeEntryCreation -> Bool
  (let [(entry (cc/makeCascadeEntry "/app/.asl.local.config.asn" "local" (mapEmpty)))] (assert (= entry.path "/app/.asl.local.config.asn") "Entry path must match") (assert (= entry.level "local") "Entry level must match") true)

fn testPrecedenceHierarchy -> Bool
  (do (assert (cc/isLevelHigher? "local" "workspace") "local > workspace") (assert (cc/isLevelHigher? "local" "subproject") "local > subproject") (assert (cc/isLevelHigher? "subproject" "workspace") "subproject > workspace") (assert (cc/isLevelHigher? "workspace" "user") "workspace > user") (assert (not (cc/isLevelHigher? "user" "local")) "user not > local") true)

fn testCascadeMerge -> Bool
  (let [(parent (mapSet (mapSet (mapEmpty) "host" "localhost") "port" "3000")) (leaf (mapSet (mapSet (mapEmpty) "path" "/api") "port" "8080")) (merged (cc/cascadeMerge parent leaf))] (assert (= (optionOr (mapGet merged "host") "") "localhost") "Parent-only host must be preserved") (assert (= (optionOr (mapGet merged "path") "") "/api") "Leaf-only path must be preserved") (assert (= (optionOr (mapGet merged "port") "") "8080") "Merged leaf port must be 8080") (assert (not (= (optionOr (mapGet merged "port") "") "3000")) "Merged leaf port must not be parent 3000") true)

fn testSecretEnvResolution -> Bool
  (let [(mockEnv (mapSet (mapEmpty) "GITHUB_TOKEN" "ghp_live_secret")) (found (cc/resolveSecretValue "env" "GITHUB_TOKEN" "fallback_val" mockEnv)) (missing (cc/resolveSecretValue "env" "MISSING_VAR" "fallback_val" mockEnv)) (literal (cc/resolveSecretValue "literal" "const_key" "" mockEnv))] (assert (= found "ghp_live_secret") "Live secret found") (assert (= missing "fallback_val") "Missing fallback resolved") (assert (= literal "const_key") "Literal key resolved") true)

fn testSecretMasking -> Bool
  (let [(masked (cc/maskSecret "ghp_1234567890abcdef")) (emptyMasked (cc/maskSecret ""))] (assert (= masked "[REDACTED]") "Masked credential must be [REDACTED]") (assert (= emptyMasked "") "Empty secret must be empty string") true)

fn runTests -> Bool
  (do (assert (testCascadeEntryCreation) "test-cascade-entry-creation must pass") (assert (testPrecedenceHierarchy) "test-precedence-hierarchy must pass") (assert (testCascadeMerge) "test-cascade-merge must pass") (assert (testSecretEnvResolution) "test-secret-env-resolution must pass") (assert (testSecretMasking) "test-secret-masking must pass") true)
