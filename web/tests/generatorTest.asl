(module aslWeb/generatorTest :x [testPackagesCatalog testPluginsCatalog testSkillsCatalog testVersionInfo testInstallerConfig testInstallerScriptGeneration runTests] :i [(aslWeb/apiPackages :a pkg) (aslWeb/apiPlugins :a plg) (aslWeb/apiSkills :a skl) (aslWeb/apiVersion :a ver) (aslWeb/installer :a inst)])

fn testPackagesCatalog -> Bool
  (let [(pkgs (pkg/packageCatalog))] (assert (>= (listLength pkgs) 10) "Packages catalog must have at least 10 entries") (assert (not (listEmpty? pkgs)) "Packages catalog must not be empty") true)

fn testPluginsCatalog -> Bool
  (let [(plugins (plg/pluginCatalog))] (assert (>= (listLength plugins) 5) "Plugins catalog must have at least 5 entries") (assert (not (listEmpty? plugins)) "Plugins catalog must not be empty") true)

fn testSkillsCatalog -> Bool
  (let [(skills (skl/skillCatalog))] (assert (>= (listLength skills) 5) "Skills catalog must have at least 5 entries") (assert (not (listEmpty? skills)) "Skills catalog must not be empty") true)

fn testVersionInfo -> Bool
  (let [(v (ver/versionInfo))] (assert (not (stringEmpty? v.version)) "Version must not be empty") (assert (= v.channel "stable") "Channel must be stable") true)

fn testInstallerConfig -> Bool
  (let [(cfg (inst/installerConfig))] (assert (= cfg.cli_name "asl") "CLI name must be asl") (assert (stringContains? cfg.repo_url "github.com") "Repo url must contain github.com") true)

fn testInstallerScriptGeneration -> Bool
  (let [(script (inst/generateInstallScript))] (assert (stringContains? script "#!/bin/bash") "Script must contain bash shebang") (assert (stringContains? script "export PATH=") "Script must export PATH") (assert (stringContains? script ".local/bin/asl") "Script must contain .local/bin/asl") (assert (stringContains? script ".zshrc") "Script must configure .zshrc") (assert (stringContains? script ".bashrc") "Script must configure .bashrc") true)

fn runTests -> Bool
  (do (assert (testPackagesCatalog) "test-packages-catalog must pass") (assert (testPluginsCatalog) "test-plugins-catalog must pass") (assert (testSkillsCatalog) "test-skills-catalog must pass") (assert (testVersionInfo) "test-version-info must pass") (assert (testInstallerConfig) "test-installer-config must pass") (assert (testInstallerScriptGeneration) "test-installer-script-generation must pass") true)
