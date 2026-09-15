(module aslWeb/generatorTest
  :d "Unit verification test suite for Web API and installer ASL models"
  :x [testPackagesCatalog testPluginsCatalog testSkillsCatalog testVersionInfo testInstallerConfig testInstallerScriptGeneration runTests]
  :i [(aslWeb/apiPackages :a pkg)
      (aslWeb/apiPlugins :a plg)
      (aslWeb/apiSkills :a skl)
      (aslWeb/apiVersion :a ver)
      (aslWeb/installer :a inst)])

(df testPackagesCatalog [] -> Bool
  :d "Validates packages catalog structure and count"
  (let [(pkgs (pkg/packageCatalog))]
    (assert (>= (list-length pkgs) 10) "Packages catalog must have at least 10 entries")
    (assert (not (list-empty? pkgs)) "Packages catalog must not be empty")
    true))

(df testPluginsCatalog [] -> Bool
  :d "Validates plugins catalog structure and count"
  (let [(plugins (plg/pluginCatalog))]
    (assert (>= (list-length plugins) 5) "Plugins catalog must have at least 5 entries")
    (assert (not (list-empty? plugins)) "Plugins catalog must not be empty")
    true))

(df testSkillsCatalog [] -> Bool
  :d "Validates skills catalog structure and count"
  (let [(skills (skl/skillCatalog))]
    (assert (>= (list-length skills) 5) "Skills catalog must have at least 5 entries")
    (assert (not (list-empty? skills)) "Skills catalog must not be empty")
    true))

(df testVersionInfo [] -> Bool
  :d "Validates version information and download endpoints"
  (let [(v (ver/versionInfo))]
    (assert (not (string-empty? (.-version v))) "Version must not be empty")
    (assert (= (.-channel v) "stable") "Channel must be stable")
    true))

(df testInstallerConfig [] -> Bool
  :d "Validates installer parameters and target binaries"
  (let [(cfg (inst/installerConfig))]
    (assert (= (.-cli_name cfg) "asl") "CLI name must be asl")
    (assert (string-contains? (.-repo_url cfg) "github.com") "Repo url must contain github.com")
    true))

(df testInstallerScriptGeneration [] -> Bool
  :d "Validates pure ASL generation of POSIX Bash installer with automatic PATH setup"
  (let [(script (inst/generateInstallScript))]
    (assert (string-contains? script "#!/bin/bash") "Script must contain bash shebang")
    (assert (string-contains? script "export PATH=") "Script must export PATH")
    (assert (string-contains? script ".local/bin/asl") "Script must contain .local/bin/asl")
    (assert (string-contains? script ".zshrc") "Script must configure .zshrc")
    (assert (string-contains? script ".bashrc") "Script must configure .bashrc")
    true))

(df runTests [] -> Bool
  :d "Runs all generator model unit tests"
  (do
    (assert (testPackagesCatalog) "test-packages-catalog must pass")
    (assert (testPluginsCatalog) "test-plugins-catalog must pass")
    (assert (testSkillsCatalog) "test-skills-catalog must pass")
    (assert (testVersionInfo) "test-version-info must pass")
    (assert (testInstallerConfig) "test-installer-config must pass")
    (assert (testInstallerScriptGeneration) "test-installer-script-generation must pass")
    true))
