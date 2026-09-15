(module aslPack/tests/releaseTest
  :d "Unit test suite for AgentScript production release and self-update pipeline."
  :x [testReleasePlan
      testReleaseScriptGeneration
      testUpgradeScriptGeneration
      testVersionAsnGeneration
      testNativeReleaseOrchestration
      runTests]
  :i [(release :a rel)])

(df testReleasePlan [] -> Bool
  :d "Verifies release plan parameters."
  (let [(plan (rel/makeReleasePlan "0.1.0"))]
    (assert (= (.-version plan) "0.1.0") "Release version must be 0.1.0")
    (assert (= (.-tag plan) "v0.1.0") "Release tag must be v0.1.0")
    (assert (= (list-length (.-targetPlatforms plan)) 5) "Must have 5 target platforms")
    true))

(df testReleaseScriptGeneration [] -> Bool
  :d "Verifies POSIX release script emission contains verification gates and archive building."
  (let [(plan (rel/makeReleasePlan "0.1.0"))
        (sh (rel/emitReleaseScriptSh plan))]
    (assert (string-contains? sh "asl gate") "Release script must run asl gate")
    (assert (string-contains? sh "darwin-arm64") "Release script must contain darwin-arm64")
    (assert (string-contains? sh "SHA256SUMS") "Release script must contain SHA256SUMS")
    true))

(df testUpgradeScriptGeneration [] -> Bool
  :d "Verifies self-update script contains remote version discovery."
  (let [(sh (rel/emitUpgradeScriptSh))]
    (assert (string-contains? sh "version.asn") "Upgrade script must check version.asn")
    (assert (string-contains? sh "install.sh") "Upgrade script must check install.sh")
    true))

(df testVersionAsnGeneration [] -> Bool
  :d "Verifies version.asn manifest generation."
  (let [(plan (rel/makeReleasePlan "0.1.0"))
        (asn (rel/emitVersionAsn plan))]
    (assert (string-contains? asn ":version \"0.1.0\"") "Version manifest must specify version")
    (assert (string-contains? asn ":channel :stable") "Version manifest must specify stable channel")
    true))

(df testNativeReleaseOrchestration [] -> Bool
  :d "Verifies native release step execution and semantic receipts."
  (let [(plan (rel/makeReleasePlan "0.1.0"))
        (step (rel/executeReleaseStep "echoTest" "echo" (list "release-pipeline-ok")))
        (receipt (rel/ReleaseReceipt
                   :plan plan
                   :ok true
                   :steps (list step)
                   :publishedArtifacts (list "dist/v0.1.0/asl.tar.gz")))]
    (assert (.-ok step) "echo test step must succeed")
    (assert (= (.-name step) "echoTest") "step name must match")
    (assert (= (.-message step) "Command succeeded") "step message must match command receipt summary")
    (assert (.-ok receipt) "receipt ok must be true")
    (assert (= (list-length (.-steps receipt)) 1) "receipt steps must contain 1 step")
    true))

(df runTests [] -> Bool
  :d "Executes release test suite."
  (do
    (assert (testReleasePlan) "test-release-plan must pass")
    (assert (testReleaseScriptGeneration) "test-release-script-generation must pass")
    (assert (testUpgradeScriptGeneration) "test-upgrade-script-generation must pass")
    (assert (testVersionAsnGeneration) "test-version-asn-generation must pass")
    (assert (testNativeReleaseOrchestration) "testNativeReleaseOrchestration must pass")
    true))
