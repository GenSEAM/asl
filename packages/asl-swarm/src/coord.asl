(module asl-swarm/coord
  :d "Autonomous Agent Swarm Coordinator, Task Claim Management, and Disjoint Blast Scheduling under ADR D97"
  :x [SwarmClaim
      WorkerPartition
      makeSwarmClaim
      makeWorkerPartition
      areClaimsDisjoint
      scheduleDisjointTasks
      listsOverlap]
  :i [])

(dfs SwarmClaim
  (:f taskId String)
  (:f workerId String)
  (:f leaseTimestamp Int64)
  (:f writeSet (List String))
  (:f readClosure (List String))
  (:f baseMerkleRoot String))

(dfs WorkerPartition
  (:f workerId String)
  (:f taskIds (List String))
  (:f combinedWriteSet (List String)))

(df makeSwarmClaim [(taskId String)
                    (workerId String)
                    (leaseTimestamp Int64)
                    (writeSet (List String))
                    (readClosure (List String))
                    (baseMerkleRoot String)] -> SwarmClaim
  :d "Constructs a swarm task claim descriptor"
  (SwarmClaim :taskId taskId
              :workerId workerId
              :leaseTimestamp leaseTimestamp
              :writeSet writeSet
              :readClosure readClosure
              :baseMerkleRoot baseMerkleRoot))

(df makeWorkerPartition [(workerId String)
                         (taskIds (List String))
                         (combinedWriteSet (List String))] -> WorkerPartition
  :d "Constructs a disjoint worker partition descriptor"
  (WorkerPartition :workerId workerId
                   :taskIds taskIds
                   :combinedWriteSet combinedWriteSet))

(df listsOverlap [(l1 (List String)) (l2 (List String))] -> Bool
  :d "Checks whether two string lists share at least one common element"
  (if (list-empty? l1)
    false
    (let [(head (option-or (list-head l1) ""))
          (tail (option-or (list-tail l1) (list)))]
      (if (list-contains? l2 head)
        true
        (listsOverlap tail l2)))))

(df areClaimsDisjoint [(c1 SwarmClaim) (c2 SwarmClaim)] -> Bool
  :d "Determines whether two swarm claims have mutually disjoint write sets"
  (not (listsOverlap (.-writeSet c1) (.-writeSet c2))))

(df canFitPartition [(claim SwarmClaim) (part WorkerPartition)] -> Bool
  :d "Checks if a claim has no write set collision with an existing worker partition"
  (not (listsOverlap (.-writeSet claim) (.-combinedWriteSet part))))

(df assignToPartitions [(claim SwarmClaim)
                        (partitions (List WorkerPartition))
                        (visited (List WorkerPartition))
                        (placed Bool)] -> (List WorkerPartition)
  :d "Greedily bins a claim into the first compatible non-conflicting partition or appends new partition"
  (if (list-empty? partitions)
    (if placed
      visited
      (list-append visited (list (makeWorkerPartition (.-workerId claim)
                                                      (list (.-taskId claim))
                                                      (.-writeSet claim)))))
    (let [(head (option-or (list-head partitions) (makeWorkerPartition "" (list) (list))))
          (tail (option-or (list-tail partitions) (list)))]
      (if (and (not placed) (canFitPartition claim head))
        (let [(updatedPart (makeWorkerPartition (.-workerId head)
                                                (list-append (.-taskIds head) (list (.-taskId claim)))
                                                (list-concat (.-combinedWriteSet head) (.-writeSet claim))))]
          (assignToPartitions claim tail (list-append visited (list updatedPart)) true))
        (assignToPartitions claim tail (list-append visited (list head)) placed)))))

(df scheduleLoop [(claims (List SwarmClaim)) (acc (List WorkerPartition))] -> (List WorkerPartition)
  :d "Recursively schedules a list of claims into disjoint worker partitions"
  (if (list-empty? claims)
    acc
    (let [(head (option-or (list-head claims) (makeSwarmClaim "" "" 0 (list) (list) "")))
          (tail (option-or (list-tail claims) (list)))
          (nextAcc (assignToPartitions head acc (list) false))]
      (scheduleLoop tail nextAcc))))

(df scheduleDisjointTasks [(tasks (List SwarmClaim))] -> (List WorkerPartition)
  :d "Schedules a batch of task claims into disjoint non-interfering worker partitions"
  (scheduleLoop tasks (list)))
