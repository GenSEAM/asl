(module aslPack/distTest :x [runTests] :i [(dist :a d)])

fn testDistConfig -> Bool
  (let [(cfg (d/makeDistConfig "0.1.0"))] (assert (= cfg.version "0.1.0") "Version must be 0.1.0") (assert (= cfg.npmPackageName "asl") "Package name must match") (assert (stringContains? cfg.binaryBaseUrl "v0.1.0") "Binary URL must contain version") true)

fn testEmitInstallSh -> Bool
  (let [(cfg (d/makeDistConfig "0.1.0")) (script (d/emitInstallSh cfg))] (assert (stringContains? script "asl-${VERSION}-${OS}-${ARCH_TAG}.tar.gz") "Script must have tarball name") (assert (stringContains? script "REPO_URL") "Script must have REPO_URL") (assert (stringContains? script "chmod +x") "Script must have chmod +x") (assert (stringContains? script "sha256sum") "Script must have sha256sum verification") (assert (stringContains? script "shasum -a 256") "Script must have shasum fallback") (assert (stringContains? script "VERIFIED") "Script must track verification state") true)

fn testEmitBuildFromSource -> Bool
  (let [(cfg (d/makeDistConfig "0.1.0")) (script (d/emitBuildFromSourceSh cfg))] (assert (stringContains? script "Building AgentSlang from source") "Script must announce build") (assert (stringContains? script "gate") "Script must invoke gate") (assert (stringContains? script "ln -sf") "Script must create symlink") true)

fn testEmitNpmFiles -> Bool
  (let [(cfg (d/makeDistConfig "0.1.0")) (pkg (d/emitNpmPackageJson cfg)) (launcher (d/emitNpmBin cfg))] (assert (stringContains? pkg "\"name\": \"asl\"") "Package name must be serialized") (assert (stringContains? pkg "\"bin\":") "Package bin field must exist") (assert (stringContains? launcher "spawn") "Launcher must invoke spawn") true)

fn testEmitInstallPs1 -> Bool
  (let [(cfg (d/makeDistConfig "0.1.0")) (script (d/emitInstallPs1 cfg))] (assert (stringContains? script "Windows PowerShell Installer") "Script must announce build") (assert (stringContains? script "Invoke-WebRequest") "Script must use Invoke-WebRequest") (assert (stringContains? script "Expand-Archive") "Script must extract") true)

fn runTests -> Bool
  (do (assert (testDistConfig) "test-dist-config must pass") (assert (testEmitInstallSh) "test-emit-install-sh must pass") (assert (testEmitBuildFromSource) "test-emit-build-from-source must pass") (assert (testEmitNpmFiles) "test-emit-npm-files must pass") (assert (testEmitInstallPs1) "test-emit-install-ps1 must pass") true)
