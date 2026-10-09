(module asl-mesh
  :x [SwarmClaim
      WorkerPartition
      makeSwarmClaim
      makeWorkerPartition
      areClaimsDisjoint
      scheduleDisjointTasks
      listsOverlap
      OccState
      ConflictReport
      makeOccState
      makeConflictReport
      validateMerkleCommit
      getCommitConflictReport
      resolveLeaseConflict
      canRetryOccCommit
      discardStagingBuffer]
  :i [(asl-mesh/coord :a coord)
      (asl-mesh/occ :a occ)])
