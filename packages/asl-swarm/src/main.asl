(module asl-swarm
  :d "Autonomous Agent Swarm Coordination and Merkle Optimistic Concurrency Control Substrate"
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
  :i [(asl-swarm/coord :a coord)
      (asl-swarm/occ :a occ)])
