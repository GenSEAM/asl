(module aslAgent/swarmPartition
  :x [PartitionSet ScopeLease LeaseRegistry makePartitionSet emptyLeaseRegistry pathsOverlap? detectCollision? validateScopeOwnership claimScopeLease releaseScopeLease]
  :i [])

(schema PartitionSet
  (:f workerId Str)
  (:f paths (List Str)))

(schema ScopeLease
  (:f workerId Str)
  (:f path Str)
  (:f leaseDurationMs I64))

(schema LeaseRegistry
  (:f leases (List ScopeLease)))

fn makePartitionSet workerId: Str paths: (List Str) -> PartitionSet
  (PartitionSet :workerId workerId :paths paths)

fn emptyLeaseRegistry -> LeaseRegistry
  (LeaseRegistry :leases (list))

fn pathsOverlap? a: Str b: Str -> Bool
  (if (= a b)
    true
    (let [(prefixA (str a "/"))
          (prefixB (str b "/"))]
      (or (stringStartsWith? a prefixB)
          (stringStartsWith? b prefixA))))

fn detectCollision? p1: PartitionSet p2: PartitionSet -> Bool
  (let [(paths1 p1.paths)
        (paths2 p2.paths)]
    (fold (fn [(collisionFound Bool) (pA Str)] -> Bool
            (if collisionFound
              true
              (fold (fn [(innerCollision Bool) (pB Str)] -> Bool
                      (if innerCollision
                        true
                        (pathsOverlap? pA pB)))
                    false paths2)))
          false paths1))

fn pathBelongsToPartition? target: Str partitionPaths: (List Str) -> Bool
  (fold (fn [(matched Bool) (prefix Str)] -> Bool
          (if matched
            true
            (if (= target prefix)
              true
              (stringStartsWith? target (str prefix "/")))))
        false partitionPaths)

fn validateScopeOwnership partition: PartitionSet targets: (List Str) -> Bool
  (if (listEmpty? targets)
    true
    (let [(partitionPaths partition.paths)]
      (fold (fn [(allValid Bool) (target Str)] -> Bool
              (if (not allValid)
                false
                (pathBelongsToPartition? target partitionPaths)))
            true targets)))

fn claimScopeLease registry: LeaseRegistry partition: PartitionSet durationMs: I64 -> (Result LeaseRegistry Str)
  (let [(existing registry.leases)
        (newPaths partition.paths)
        (wid partition.workerId)
        (hasConflict (fold (fn [(conflict Bool) (l ScopeLease)] -> Bool
                             (if conflict
                               true
                               (if (= l.workerId wid)
                                 false
                                 (fold (fn [(innerConf Bool) (pNew Str)] -> Bool
                                         (if innerConf
                                           true
                                           (pathsOverlap? l.path pNew)))
                                       false newPaths))))
                           false existing))]
    (if hasConflict
      (err (str "Collision detected: path lease conflict for worker " wid))
      (let [(newLeases (fold (fn [(acc (List ScopeLease)) (pNew Str)] -> (List ScopeLease)
                               (cons (ScopeLease :workerId wid :path pNew :leaseDurationMs durationMs) acc))
                             existing newPaths))]
        (ok (LeaseRegistry :leases newLeases)))))

fn releaseScopeLease registry: LeaseRegistry workerId: Str paths: (List Str) -> (Result LeaseRegistry Str)
  (let [(existing registry.leases)
        (remaining (filter (fn [(l ScopeLease)] -> Bool
                             (if (!= l.workerId workerId)
                               true
                               (not (listContains? paths l.path))))
                           existing))]
    (ok (LeaseRegistry :leases remaining)))
