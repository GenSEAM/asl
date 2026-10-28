(module asl-gates/tests/shebangDocWhitelistTest :x [testShebangDocAndConfigWhitelist testDualPolarityRefutations runTests] :i [(asl-gates/shebangAudit :a sa)])

fn testShebangDocAndConfigWhitelist -> Bool
  (let [(vReadme (sa/auditScriptFile "README.md" "# ASL Monorepo" false ".md" (list))) (vYaml (sa/auditScriptFile "pnpm-workspace.yaml" "packages:\n  - asl/*" false ".yaml" (list))) (vJson (sa/auditScriptFile "package.json" "{\"name\": \"asex\"}" false ".json" (list))) (vGitignore (sa/auditScriptFile ".gitignore" "node_modules/" false ".gitignore" (list))) (vUnknown (sa/auditScriptFile "unknown.xyz" "xyz binary" false ".xyz" (list)))] (assert vReadme.valid "README.md outside package tree must be accepted") (assert vYaml.valid "pnpm-workspace.yaml outside package tree must be accepted") (assert vJson.valid "package.json outside package tree must be accepted") (assert vGitignore.valid ".gitignore outside package tree must be accepted") (assert (not vUnknown.valid) "unknown.xyz outside package tree must be rejected") true)

fn testDualPolarityRefutations -> Bool
  (let [(vReadme (sa/auditScriptFile "README.md" "# ASL" false ".md" (list))) (vYaml (sa/auditScriptFile "pnpm-workspace.yaml" "packages: []" false ".yaml" (list))) (vBinary (sa/auditScriptFile "README.md" "\u007fELF..." false ".md" (list)))] (refute (not vReadme.valid) "Refute that README.md is rejected as an unapproved script") (refute (not vYaml.valid) "Refute that YAML configuration is rejected as an unapproved script") (refute vBinary.valid "Refute that binary blob with .md extension passes audit") true)

fn runTests -> Bool
  (do (assert (testShebangDocAndConfigWhitelist) "testShebangDocAndConfigWhitelist must pass") (assert (testDualPolarityRefutations) "testDualPolarityRefutations must pass") true)
