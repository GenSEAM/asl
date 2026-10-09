(module asl-mesh/occ :x [OccState ConflictReport makeOccState makeConflictReport validateMerkleCommit getCommitConflictReport resolveLeaseConflict canRetryOccCommit discardStagingBuffer] :i [(asl-mesh/coord :a coord)])

(schema OccState (:f currentRoot String) (:f activeLeases (Map String Int64)))

(schema ConflictReport (:f status String) (:f reason String) (:f baseRoot String) (:f currentRoot String) (:f conflictingWorker String) (:f retryCount Int64))

fn makeOccState currentRoot: String activeLeases: (Map String Int64) -> OccState
  (OccState :currentRoot currentRoot :activeLeases activeLeases)

fn makeConflictReport status: String reason: String baseRoot: String currentRoot: String conflictingWorker: String retryCount: Int64 -> ConflictReport
  (ConflictReport :status status :reason reason :baseRoot baseRoot :currentRoot currentRoot :conflictingWorker conflictingWorker :retryCount retryCount)

fn validateMerkleCommit claim: coord/SwarmClaim state: OccState candidateRoot: String -> (Result OccState ConflictReport)
  (if (not (= claim.baseMerkleRoot state.currentRoot)) (err (makeConflictReport "conflict" "ERR_OCC_MERKLE_ROOT_DIVERGED" claim.baseMerkleRoot state.currentRoot claim.workerId 0)) (ok (makeOccState candidateRoot state.activeLeases)))

fn getCommitConflictReport res: (Result OccState ConflictReport) -> ConflictReport
  (mt res ((ok _val) (makeConflictReport "ok" "SUCCESS" "" "" "" 0)) ((err report) report))

fn resolveLeaseConflict c1: coord/SwarmClaim c2: coord/SwarmClaim -> coord/SwarmClaim
  (if (< c1.leaseTimestamp c2.leaseTimestamp)
    c1
    (if (> c1.leaseTimestamp c2.leaseTimestamp)
      c2
      (if (<= c1.workerId c2.workerId)
        c1
        c2)))

fn canRetryOccCommit retryCount: Int64 -> Bool
  (if (< retryCount 3) (if (>= retryCount 0) true false) false)

fn discardStagingBuffer workerId: String -> Bool
  (if (stringEmpty? workerId) false true)
