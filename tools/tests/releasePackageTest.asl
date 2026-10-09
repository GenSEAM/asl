(module asl/tools/tests/releasePackageTest
  :x [runTests RunTests! testBuildReleasePackageSuccess testBuildReleasePackageFailure testSuperviseClosureGateSuccess testSuperviseClosureGateFailure testReleaseBundleStructure testMilestoneReceiptStructure testDualPolarityAliases]
  :i [(asl-tools/release :a rel)])

fn testBuildReleasePackageSuccess -> Bool
  (let [(rootHash "2aa30a62efbc5a427d876cbaf97d133d786ceb51a69353a31bd0f7ec88a3a0cd")
        (res (rel/buildReleasePackage "0.1.0" "M09" rootHash 38 true))]
    (do
      (assert (ok? res) "buildReleasePackage must succeed when certified and root hash provided")
      (refute (err? res) "Must not fail on valid release parameters")
      (mt res
        ((ok bundle)
         (do
           (assert (= bundle.version "0.1.0") "Version must match")
           (assert (= bundle.milestone "M09") "Milestone must match")
           (assert (= bundle.merkleRoot rootHash) "Merkle root must match")
           (assert (= bundle.totalPackages 38) "Total packages must match")
           (assert bundle.isCertified "isCertified must be true")
           (refute (not bundle.isCertified) "isCertified must refute false")
           true))
        ((err _) (assert false "Unexpected err in buildReleasePackageSuccess")))
      true))

fn testBuildReleasePackageFailure -> Bool
  (let [(rootHash "2aa30a62efbc5a427d876cbaf97d133d786ceb51a69353a31bd0f7ec88a3a0cd")
        (resUncert (rel/buildReleasePackage "0.1.0" "M09" rootHash 38 false))
        (resNoHash (rel/buildReleasePackage "0.1.0" "M09" "" 38 true))]
    (do
      (assert (err? resUncert) "Must fail when certified is false")
      (assert (err? resNoHash) "Must fail when rootHash is empty")
      (refute (ok? resUncert) "Must refute ok on uncertified")
      (refute (ok? resNoHash) "Must refute ok on empty hash")
      true))

fn testSuperviseClosureGateSuccess -> Bool
  (let [(rootHash "2aa30a62efbc5a427d876cbaf97d133d786ceb51a69353a31bd0f7ec88a3a0cd")
        (res (rel/superviseClosureGate 10 10 rootHash))]
    (do
      (assert (ok? res) "superviseClosureGate must succeed with 10/10 tiers and valid root hash")
      (refute (err? res) "Must not return error on certified closure")
      (mt res
        ((ok receipt)
         (do
           (assert (= receipt.milestone "M09") "Milestone must be M09")
           (assert (= receipt.status "CERTIFIED") "Status must be CERTIFIED")
           (assert (= receipt.passedTiers 10) "Passed tiers must be 10")
           (assert (= receipt.totalTiers 10) "Total tiers must be 10")
           (assert (= receipt.merkleRoot rootHash) "Merkle root must match")
           (assert (= receipt.sealedBy "agent:antigravity:sovereign") "SealedBy must match sovereign role")
           (refute (!= receipt.passedTiers 10) "Passed tiers must not diverge")
           true))
        ((err _) (assert false "Unexpected err in superviseClosureGateSuccess")))
      true))

fn testSuperviseClosureGateFailure -> Bool
  (let [(rootHash "2aa30a62efbc5a427d876cbaf97d133d786ceb51a69353a31bd0f7ec88a3a0cd")
        (resIncomplete (rel/superviseClosureGate 9 10 rootHash))
        (resNoHash (rel/superviseClosureGate 10 10 ""))]
    (do
      (assert (err? resIncomplete) "Must fail when passedTiers < totalTiers")
      (assert (err? resNoHash) "Must fail when rootHash is empty")
      (refute (ok? resIncomplete) "Must refute ok on incomplete tiers")
      (refute (ok? resNoHash) "Must refute ok on empty hash")
      true))

fn testReleaseBundleStructure -> Bool
  (let [(bundle (rel/makeReleaseBundle "0.1.0" "M09" "hash1234" 38 true 1789459200000))]
    (do
      (assert (= bundle.version "0.1.0") "Version must be 0.1.0")
      (assert (= bundle.milestone "M09") "Milestone must be M09")
      (assert (= bundle.totalPackages 38) "Packages must be 38")
      (assert bundle.isCertified "isCertified must be true")
      (refute (< bundle.totalPackages 1) "Total packages must refute < 1")
      true))

fn testMilestoneReceiptStructure -> Bool
  (let [(rcpt (rel/makeMilestoneReceipt "M09" "CERTIFIED" 10 10 "hash1234" "sovereign" 1789459200000))]
    (do
      (assert (= rcpt.milestone "M09") "Milestone must match")
      (assert (= rcpt.status "CERTIFIED") "Status must be CERTIFIED")
      (assert (= rcpt.passedTiers 10) "Passed tiers must match")
      (refute (!= rcpt.totalTiers 10) "Total tiers must refute != 10")
      true))

fn testDualPolarityAliases -> Bool
  (let [(rootHash "2aa30a62efbc5a427d876cbaf97d133d786ceb51a69353a31bd0f7ec88a3a0cd")
        (pkgRes (rel/build_release_package "0.1.0" "M09" rootHash 38 true))
        (gateRes (rel/supervise_closure_gate 10 10 rootHash))
        (bundle (rel/release_bundle "0.1.0" "M09" rootHash 38 true 1789459200000))
        (rcpt (rel/milestone_receipt "M09" "CERTIFIED" 10 10 rootHash "authority" 1789459200000))]
    (do
      (assert (ok? pkgRes) "build_release_package alias must succeed")
      (assert (ok? gateRes) "supervise_closure_gate alias must succeed")
      (assert bundle.isCertified "release_bundle alias must yield certified bundle")
      (assert (= rcpt.status "CERTIFIED") "milestone_receipt alias must yield certified receipt")
      (refute (err? pkgRes) "Must refute err on build_release_package")
      (refute (err? gateRes) "Must refute err on supervise_closure_gate")
      true))


fn ! runTests -> Bool
  (do
    (assert (testBuildReleasePackageSuccess) "testBuildReleasePackageSuccess passed")
    (assert (testBuildReleasePackageFailure) "testBuildReleasePackageFailure passed")
    (assert (testSuperviseClosureGateSuccess) "testSuperviseClosureGateSuccess passed")
    (assert (testSuperviseClosureGateFailure) "testSuperviseClosureGateFailure passed")
    (assert (testReleaseBundleStructure) "testReleaseBundleStructure passed")
    (assert (testMilestoneReceiptStructure) "testMilestoneReceiptStructure passed")
    (assert (testDualPolarityAliases) "testDualPolarityAliases passed")
    true)

fn RunTests! -> Bool
  (runTests)
