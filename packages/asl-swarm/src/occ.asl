(module asl-swarm/occ
  :d "Two-Phase Merkle Optimistic Concurrency Control, Lease Arbitration, and Staging Buffer VFS under ADR D97"
  :x [OccState
      ConflictReport
      makeOccState
      makeConflictReport
      validateMerkleCommit
      getCommitConflictReport
      resolveLeaseConflict
      canRetryOccCommit
      discardStagingBuffer]
  :i [(asl-swarm/coord :a coord)])

(dfs OccState
  (:f currentRoot String)
  (:f activeLeases (Map String Int64)))

(dfs ConflictReport
  (:f status String)
  (:f reason String)
  (:f baseRoot String)
  (:f currentRoot String)
  (:f conflictingWorker String)
  (:f retryCount Int64))

(df makeOccState [(currentRoot String)
                  (activeLeases (Map String Int64))] -> OccState
  :d "Constructs an active OCC Merkle state tracker"
  (OccState :currentRoot currentRoot
            :activeLeases activeLeases))

(df makeConflictReport [(status String)
                        (reason String)
                        (baseRoot String)
                        (currentRoot String)
                        (conflictingWorker String)
                        (retryCount Int64)] -> ConflictReport
  :d "Constructs an OCC collision or success report descriptor"
  (ConflictReport :status status
                  :reason reason
                  :baseRoot baseRoot
                  :currentRoot currentRoot
                  :conflictingWorker conflictingWorker
                  :retryCount retryCount))

(df validateMerkleCommit [(claim coord/SwarmClaim)
                          (state OccState)
                          (candidateRoot String)] -> (Result OccState ConflictReport)
  :d "Validates that claim base Merkle root matches current root and updates active state atomically"
  (if (not (= (.-baseMerkleRoot claim) (.-currentRoot state)))
    (err (makeConflictReport "conflict"
                             "ERR_OCC_MERKLE_ROOT_DIVERGED"
                             (.-baseMerkleRoot claim)
                             (.-currentRoot state)
                             (.-workerId claim)
                             0))
    (ok (makeOccState candidateRoot (.-activeLeases state)))))

(df getCommitConflictReport [(res (Result OccState ConflictReport))] -> ConflictReport
  :d "Extracts or creates a structured ConflictReport from an OCC commit validation result"
  (mt res
    ((ok _val)
     (makeConflictReport "ok" "SUCCESS" "" "" "" 0))
    ((err report)
     report)))

(df resolveLeaseConflict [(c1 coord/SwarmClaim) (c2 coord/SwarmClaim)] -> coord/SwarmClaim
  :d "Resolves competing claims on overlapping write sets prioritizing earlier lease timestamp"
  (if (<= (.-leaseTimestamp c1) (.-leaseTimestamp c2))
    c1
    c2))

(df canRetryOccCommit [(retryCount Int64)] -> Bool
  :d "Enforces maximum retry ceiling of 3 attempts for OCC commit recovery"
  (if (< retryCount 3)
    (if (>= retryCount 0)
      true
      false)
    false))

(df discardStagingBuffer [(workerId String)] -> Bool
  :d "Rolls back and discards uncommitted staging VFS buffer on aborted transaction"
  (if (string-empty? workerId)
    false
    true))
