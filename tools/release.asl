(module asl-tools/release
  :x [ReleaseBundle MilestoneReceipt makeReleaseBundle makeMilestoneReceipt buildReleasePackage superviseClosureGate build_release_package supervise_closure_gate release_bundle milestone_receipt]
  :i [(reader :a rd)])

(schema ReleaseBundle
  (:f version Str)
  (:f milestone Str)
  (:f merkleRoot Str)
  (:f totalPackages Int64)
  (:f isCertified Bool)
  (:f timestamp Int64))

(schema MilestoneReceipt
  (:f milestone Str)
  (:f status Str)
  (:f passedTiers Int64)
  (:f totalTiers Int64)
  (:f merkleRoot Str)
  (:f sealedBy Str)
  (:f sealedAt Int64))

fn makeReleaseBundle version: Str milestone: Str merkleRoot: Str totalPackages: Int64 isCertified: Bool timestamp: Int64 -> ReleaseBundle
  (ReleaseBundle :version version :milestone milestone :merkleRoot merkleRoot :totalPackages totalPackages :isCertified isCertified :timestamp timestamp)

fn makeMilestoneReceipt milestone: Str status: Str passedTiers: Int64 totalTiers: Int64 merkleRoot: Str sealedBy: Str sealedAt: Int64 -> MilestoneReceipt
  (MilestoneReceipt :milestone milestone :status status :passedTiers passedTiers :totalTiers totalTiers :merkleRoot merkleRoot :sealedBy sealedBy :sealedAt sealedAt)

fn buildReleasePackage version: Str milestone: Str rootHash: Str packageCount: Int64 certified: Bool -> (Result ReleaseBundle Str)
  (if (and certified (> (stringLength rootHash) 0))
      (ok (makeReleaseBundle version milestone rootHash packageCount true 1789459200000))
      (err "Release package creation failed: uncertified state or missing root hash"))

fn superviseClosureGate passedTiers: Int64 totalTiers: Int64 rootHash: Str -> (Result MilestoneReceipt Str)
  (if (and (= passedTiers totalTiers) (> (stringLength rootHash) 0))
      (ok (makeMilestoneReceipt "M09" "CERTIFIED" passedTiers totalTiers rootHash "agent:antigravity:sovereign" 1789459200000))
      (err "Supervise closure gate failed: incomplete tiers or unsealed root hash"))

fn build_release_package version: Str milestone: Str rootHash: Str packageCount: Int64 certified: Bool -> (Result ReleaseBundle Str)
  (buildReleasePackage version milestone rootHash packageCount certified)

fn supervise_closure_gate passedTiers: Int64 totalTiers: Int64 rootHash: Str -> (Result MilestoneReceipt Str)
  (superviseClosureGate passedTiers totalTiers rootHash)

fn release_bundle version: Str milestone: Str merkleRoot: Str totalPackages: Int64 isCertified: Bool timestamp: Int64 -> ReleaseBundle
  (makeReleaseBundle version milestone merkleRoot totalPackages isCertified timestamp)

fn milestone_receipt milestone: Str status: Str passedTiers: Int64 totalTiers: Int64 merkleRoot: Str sealedBy: Str sealedAt: Int64 -> MilestoneReceipt
  (makeMilestoneReceipt milestone status passedTiers totalTiers merkleRoot sealedBy sealedAt)
