(module aslPack/distTest
  :d "Unit tests for distribution generator: installer scripts, package manifests, and bin launcher."
  :x [runTests]
  :i [(dist :a d)])

(df testDistConfig [] -> Bool
  :d "Verifies distribution configuration setup."
  (let [(cfg (d/makeDistConfig "0.1.0"))]
    (assert (= (.-version cfg) "0.1.0") "Version must be 0.1.0")
    (assert (= (.-npmPackageName cfg) "asl") "Package name must match")
    (assert (string-contains? (.-binaryBaseUrl cfg) "v0.1.0") "Binary URL must contain version")
    true))

(df testEmitInstallSh [] -> Bool
  :d "Verifies generated install.sh contains binary download and source fallback."
  (let [(cfg (d/makeDistConfig "0.1.0"))
        (script (d/emitInstallSh cfg))]
    (assert (string-contains? script "asl-${VERSION}-${OS}-${ARCH_TAG}.tar.gz") "Script must have tarball name")
    (assert (string-contains? script "REPO_URL") "Script must have REPO_URL")
    (assert (string-contains? script "chmod +x") "Script must have chmod +x")
    (assert (string-contains? script "sha256sum") "Script must have sha256sum verification")
    (assert (string-contains? script "shasum -a 256") "Script must have shasum fallback")
    (assert (string-contains? script "VERIFIED") "Script must track verification state")
    true))

(df testEmitBuildFromSource [] -> Bool
  :d "Verifies build-from-source script executes gate and symlinks binary."
  (let [(cfg (d/makeDistConfig "0.1.0"))
        (script (d/emitBuildFromSourceSh cfg))]
    (assert (string-contains? script "Building AgentScript from source") "Script must announce build")
    (assert (string-contains? script "gate") "Script must invoke gate")
    (assert (string-contains? script "ln -sf") "Script must create symlink")
    true))

(df testEmitNpmFiles [] -> Bool
  :d "Verifies package.json and bin launcher generation."
  (let [(cfg (d/makeDistConfig "0.1.0"))
        (pkg (d/emitNpmPackageJson cfg))
        (launcher (d/emitNpmBin cfg))]
    (assert (string-contains? pkg "\"name\": \"asl\"") "Package name must be serialized")
    (assert (string-contains? pkg "\"bin\":") "Package bin field must exist")
    (assert (string-contains? launcher "spawn") "Launcher must invoke spawn")
    true))

(df testEmitInstallPs1 [] -> Bool
  :d "Verifies generated ps1 installer."
  (let [(cfg (d/makeDistConfig "0.1.0"))
        (script (d/emitInstallPs1 cfg))]
    (assert (string-contains? script "Windows PowerShell Installer") "Script must announce build")
    (assert (string-contains? script "Invoke-WebRequest") "Script must use Invoke-WebRequest")
    (assert (string-contains? script "Expand-Archive") "Script must extract")
    true))

(df runTests [] -> Bool
  :d "Executes dist test suite."
  (do
    (assert (testDistConfig) "test-dist-config must pass")
    (assert (testEmitInstallSh) "test-emit-install-sh must pass")
    (assert (testEmitBuildFromSource) "test-emit-build-from-source must pass")
    (assert (testEmitNpmFiles) "test-emit-npm-files must pass")
    (assert (testEmitInstallPs1) "test-emit-install-ps1 must pass")
    true))
