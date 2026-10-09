(module aslPack/tests/releaseTest :x [testReleasePlan testReleaseScriptGeneration testUpgradeScriptGeneration testVersionAsnGeneration testNativeReleaseOrchestration! runTests] :i [(release :a rel)])

fn testReleasePlan -> Bool
  (let [(plan (rel/makeReleasePlan "0.1.0"))] (assert (= plan.version "0.1.0") "Release version must be 0.1.0") (assert (= plan.tag "v0.1.0") "Release tag must be v0.1.0") (assert (= (listLength plan.targetPlatforms) 5) "Must have 5 target platforms") true)

fn testReleaseScriptGeneration -> Bool
  (let [(plan (rel/makeReleasePlan "0.1.0")) (sh (rel/emitReleaseScriptSh plan))] (assert (stringContains? sh "asl gate") "Release script must run asl gate") (assert (stringContains? sh "darwin-arm64") "Release script must contain darwin-arm64") (assert (stringContains? sh "SHA256SUMS") "Release script must contain SHA256SUMS") true)

fn testUpgradeScriptGeneration -> Bool
  (let [(sh (rel/emitUpgradeScriptSh))] (assert (stringContains? sh "version.asn") "Upgrade script must check version.asn") (assert (stringContains? sh "install.sh") "Upgrade script must check install.sh") true)

fn testVersionAsnGeneration -> Bool
  (let [(plan (rel/makeReleasePlan "0.1.0")) (asn (rel/emitVersionAsn plan))] (assert (stringContains? asn ":version \"0.1.0\"") "Version manifest must specify version") (assert (stringContains? asn ":channel :stable") "Version manifest must specify stable channel") true)

fn testNativeReleaseOrchestration! -> Bool
  (let [(plan (rel/makeReleasePlan "0.1.0")) (step (rel/executeReleaseStep! "echoTest" "echo" (list "release-pipeline-ok"))) (receipt (rel/ReleaseReceipt :plan plan :ok true :steps (list step) :publishedArtifacts (list "dist/v0.1.0/asl.tar.gz")))] (assert step.ok "echo test step must succeed") (assert (= step.name "echoTest") "step name must match") (assert (= step.message "Command succeeded") "step message must match command receipt summary") (assert receipt.ok "receipt ok must be true") (assert (= (listLength receipt.steps) 1) "receipt steps must contain 1 step") true)

fn ! runTests -> Bool
  (do (assert (testReleasePlan) "test-release-plan must pass") (assert (testReleaseScriptGeneration) "test-release-script-generation must pass") (assert (testUpgradeScriptGeneration) "test-upgrade-script-generation must pass") (assert (testVersionAsnGeneration) "test-version-asn-generation must pass") (assert (testNativeReleaseOrchestration!) "testNativeReleaseOrchestration must pass") true)
