(module asl-mesh/coord :x [SwarmClaim WorkerPartition StealResult makeSwarmClaim makeSwarmClaimWithEpoch makeWorkerPartition makeStealResult areClaimsDisjoint areClaimsFullyDisjoint isClaimExpired? isClaimSafeToCommit? scheduleDisjointTasks canStealTask? canStealClaim? stealDisjointTask stealDisjointTaskWithEpoch stealDisjointClaim listsOverlap canFitPartitionWithReadClosure] :i [])

(schema SwarmClaim (:f taskId String) (:f workerId String) (:f leaseTimestamp Int64) (:f leaseDuration Int64) (:f claimEpoch Int64) (:f writeSet (List String)) (:f readClosure (List String)) (:f baseMerkleRoot String))

(schema WorkerPartition (:f workerId String) (:f taskIds (List String)) (:f combinedWriteSet (List String)))

(schema StealResult (:f victim WorkerPartition) (:f thief WorkerPartition) (:f success Bool))

fn makeSwarmClaim taskId: String workerId: String leaseTimestamp: Int64 writeSet: (List String) readClosure: (List String) baseMerkleRoot: String -> SwarmClaim
  (SwarmClaim :taskId taskId :workerId workerId :leaseTimestamp leaseTimestamp :leaseDuration 0 :claimEpoch 1 :writeSet writeSet :readClosure readClosure :baseMerkleRoot baseMerkleRoot)

fn makeSwarmClaimWithEpoch taskId: String workerId: String leaseTimestamp: Int64 leaseDuration: Int64 claimEpoch: Int64 writeSet: (List String) readClosure: (List String) baseMerkleRoot: String -> SwarmClaim
  (SwarmClaim :taskId taskId :workerId workerId :leaseTimestamp leaseTimestamp :leaseDuration leaseDuration :claimEpoch claimEpoch :writeSet writeSet :readClosure readClosure :baseMerkleRoot baseMerkleRoot)

fn makeWorkerPartition workerId: String taskIds: (List String) combinedWriteSet: (List String) -> WorkerPartition
  (WorkerPartition :workerId workerId :taskIds taskIds :combinedWriteSet combinedWriteSet)

fn listsOverlap l1: (List String) l2: (List String) -> Bool
  (if (listEmpty? l1) false (let [(head (optionOr (listHead l1) "")) (tail (optionOr (listTail l1) (list)))] (if (listContains? l2 head) true (listsOverlap tail l2))))

fn areClaimsDisjoint c1: SwarmClaim c2: SwarmClaim -> Bool
  (areClaimsFullyDisjoint c1 c2)

fn areClaimsFullyDisjoint c1: SwarmClaim c2: SwarmClaim -> Bool
  (and (not (listsOverlap c1.writeSet c2.writeSet)) (and (not (listsOverlap c1.writeSet c2.readClosure)) (not (listsOverlap c1.readClosure c2.writeSet))))

fn isClaimExpired? claim: SwarmClaim now: Int64 -> Bool
  (and (> claim.leaseDuration 0) (> now (+ claim.leaseTimestamp claim.leaseDuration)))

fn isClaimSafeToCommit? claim: SwarmClaim currentMerkle: String now: Int64 -> Bool
  (and (not (isClaimExpired? claim now)) (= claim.baseMerkleRoot currentMerkle))

fn canFitPartition claim: SwarmClaim part: WorkerPartition -> Bool
  (not (listsOverlap claim.writeSet part.combinedWriteSet))

fn canFitPartitionWithReadClosure claim: SwarmClaim part: WorkerPartition -> Bool
  (and (not (listsOverlap claim.writeSet part.combinedWriteSet))
       (not (listsOverlap claim.readClosure part.combinedWriteSet)))

fn assignToPartitions claim: SwarmClaim partitions: (List WorkerPartition) visited: (List WorkerPartition) placed: Bool -> (List WorkerPartition)
  (if (listEmpty? partitions)
    (if placed visited (listAppend visited (list (makeWorkerPartition claim.workerId (list claim.taskId) claim.writeSet))))
    (let [(head (optionOr (listHead partitions) (makeWorkerPartition "" (list) (list))))
          (tail (optionOr (listTail partitions) (list)))]
      (if (and (not placed) (canFitPartitionWithReadClosure claim head))
        (let [(updatedPart (makeWorkerPartition head.workerId (listAppend head.taskIds (list claim.taskId)) (listAppend head.combinedWriteSet claim.writeSet)))]
          (assignToPartitions claim tail (listAppend visited (list updatedPart)) true))
        (assignToPartitions claim tail (listAppend visited (list head)) placed))))

fn scheduleLoop claims: (List SwarmClaim) acc: (List WorkerPartition) -> (List WorkerPartition)
  (if (listEmpty? claims) acc (let [(head (optionOr (listHead claims) (makeSwarmClaim "" "" 0 (list) (list) ""))) (tail (optionOr (listTail claims) (list))) (nextAcc (assignToPartitions head acc (list) false))] (scheduleLoop tail nextAcc)))

fn scheduleDisjointTasks tasks: (List SwarmClaim) -> (List WorkerPartition)
  (scheduleLoop tasks (list))

fn makeStealResult victim: WorkerPartition thief: WorkerPartition success: Bool -> StealResult
  (StealResult :victim victim :thief thief :success success)

fn canStealTask? thief: WorkerPartition claim: SwarmClaim -> Bool
  (and (not (listsOverlap claim.writeSet thief.combinedWriteSet))
       (not (listsOverlap claim.readClosure thief.combinedWriteSet)))

fn canStealClaim? thief: WorkerPartition claim: SwarmClaim expectedEpoch: Int64 -> Bool
  (and (= claim.claimEpoch expectedEpoch)
       (canStealTask? thief claim))

fn stealDisjointTaskWithEpoch victim: WorkerPartition thief: WorkerPartition taskId: String taskWriteSet: (List String) currentEpoch: Int64 expectedEpoch: Int64 -> StealResult
  (if (!= currentEpoch expectedEpoch)
    (makeStealResult victim thief false)
    (let [(victimTasks (filter (fn [(t String)] (!= t taskId)) victim.taskIds))
          (victimWrites (filter (fn [(w String)] (not (listContains? taskWriteSet w))) victim.combinedWriteSet))
          (thiefTasks (listAppend thief.taskIds (list taskId)))
          (thiefWrites (listAppend thief.combinedWriteSet taskWriteSet))
          (newVictim (makeWorkerPartition victim.workerId victimTasks victimWrites))
          (newThief (makeWorkerPartition thief.workerId thiefTasks thiefWrites))]
      (makeStealResult newVictim newThief true)))

fn stealDisjointTask victim: WorkerPartition thief: WorkerPartition taskId: String taskWriteSet: (List String) -> StealResult
  (stealDisjointTaskWithEpoch victim thief taskId taskWriteSet 1 1)

fn stealDisjointClaim victim: WorkerPartition thief: WorkerPartition claim: SwarmClaim expectedEpoch: Int64 -> (Option (Pair StealResult SwarmClaim))
  (if (!= claim.claimEpoch expectedEpoch)
    (none)
    (if (not (canStealTask? thief claim))
      (none)
      (let [(res (stealDisjointTaskWithEpoch victim thief claim.taskId claim.writeSet claim.claimEpoch expectedEpoch))
            (updatedClaim (SwarmClaim
                            :taskId claim.taskId
                            :workerId thief.workerId
                            :leaseTimestamp claim.leaseTimestamp
                            :leaseDuration claim.leaseDuration
                            :claimEpoch (+ claim.claimEpoch 1)
                            :writeSet claim.writeSet
                            :readClosure claim.readClosure
                            :baseMerkleRoot claim.baseMerkleRoot))]
        (some (pair res updatedClaim)))))
