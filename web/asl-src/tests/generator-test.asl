(module asl-web/generator-test
  :d "Unit verification test suite for Web API and installer ASL models"
  :x [test-packages-catalog test-plugins-catalog test-skills-catalog test-version-info test-installer-config test-installer-script-generation run-tests]
  :i [(../api/packages :a pkg)
      (../api/plugins :a plg)
      (../api/skills :a skl)
      (../api/version :a ver)
      (../scripts/installer :a inst)])

(df test-packages-catalog [] -> Bool
  :d "Validates packages catalog structure and count"
  (let [(pkgs (pkg/package-catalog))]
    (assert (>= (list-length pkgs) 10) "Packages catalog must have at least 10 entries")
    (assert (not (list-empty? pkgs)) "Packages catalog must not be empty")
    true))

(df test-plugins-catalog [] -> Bool
  :d "Validates plugins catalog structure and count"
  (let [(plugins (plg/plugin-catalog))]
    (assert (>= (list-length plugins) 5) "Plugins catalog must have at least 5 entries")
    (assert (not (list-empty? plugins)) "Plugins catalog must not be empty")
    true))

(df test-skills-catalog [] -> Bool
  :d "Validates skills catalog structure and count"
  (let [(skills (skl/skill-catalog))]
    (assert (>= (list-length skills) 5) "Skills catalog must have at least 5 entries")
    (assert (not (list-empty? skills)) "Skills catalog must not be empty")
    true))

(df test-version-info [] -> Bool
  :d "Validates version information and download endpoints"
  (let [(v (ver/version-info))]
    (assert (not (string-empty? (.-version v))) "Version must not be empty")
    (assert (= (.-channel v) "stable") "Channel must be stable")
    true))

(df test-installer-config [] -> Bool
  :d "Validates installer parameters and target binaries"
  (let [(cfg (inst/installer-config))]
    (assert (= (.-cli_name cfg) "asl") "CLI name must be asl")
    (assert (string-contains? (.-repo_url cfg) "github.com") "Repo url must contain github.com")
    true))

(df test-installer-script-generation [] -> Bool
  :d "Validates pure ASL generation of POSIX Bash installer with automatic PATH setup"
  (let [(script (inst/generate-install-script))]
    (assert (string-contains? script "#!/bin/bash") "Script must contain bash shebang")
    (assert (string-contains? script "export PATH=") "Script must export PATH")
    (assert (string-contains? script ".local/bin/asl") "Script must contain .local/bin/asl")
    (assert (string-contains? script ".zshrc") "Script must configure .zshrc")
    (assert (string-contains? script ".bashrc") "Script must configure .bashrc")
    true))

(df run-tests [] -> Bool
  :d "Runs all generator model unit tests"
  (do
    (assert (test-packages-catalog) "test-packages-catalog must pass")
    (assert (test-plugins-catalog) "test-plugins-catalog must pass")
    (assert (test-skills-catalog) "test-skills-catalog must pass")
    (assert (test-version-info) "test-version-info must pass")
    (assert (test-installer-config) "test-installer-config must pass")
    (assert (test-installer-script-generation) "test-installer-script-generation must pass")
    true))
