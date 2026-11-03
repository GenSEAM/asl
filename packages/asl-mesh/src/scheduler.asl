(module asl-mesh/scheduler :x [schedulePartitions allocateWorkerWorktree partitionMap worktreePool] :i [])

; (:m :ref BASE-CHECK-DRIFT :do "field access needs a record type the checker can see: a worker spec is a WorkerSpec, and the literal {:workerId .. :tier ..} callers pass is one")
(schema WorkerSpec
  (:f workerId String)
  (:f tier String))

fn partitionMap packages: Any workers: Any -> Map
  (do {:packages packages :workers workers :count (listLength packages)})

fn workerPaths baseDir: String index: Int64 count: Int64 -> (List String)
  (if (>= index count) (list)
    (listAppend (list (str baseDir "/worker-" (stringFromInt64 index)))
      (workerPaths baseDir (+ index 1) count)))

fn worktreePool baseDir: String count: Int64 -> (List String)
  (workerPaths baseDir 0 count)

fn schedulePartitions packages: Any workerSpecs: (List WorkerSpec) -> List
  (match (listHead workerSpecs)
    ((none) (list))
    ((some worker) (list {:worker worker.workerId :partition packages :tier worker.tier})))

fn allocateWorkerWorktree workerId: Any baseRoot: Any -> Str
  (str baseRoot "/.asl/worktrees/" workerId)
