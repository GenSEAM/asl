(module asl-mesh/scheduler :x [schedulePartitions allocateWorkerWorktree partitionMap worktreePool] :i [])

fn partitionMap packages: Any workers: Any -> Map
  (do {:packages packages :workers workers :count (listLength packages)})

fn workerPaths baseDir: String index: Int64 count: Int64 -> (List String)
  (if (>= index count) (list)
    (listAppend (list (str baseDir "/worker-" (stringFromInt64 index)))
      (workerPaths baseDir (+ index 1) count)))

fn worktreePool baseDir: String count: Int64 -> (List String)
  (workerPaths baseDir 0 count)

fn schedulePartitions packages: Any workerSpecs: Any -> List
  (let [(totalPkgs (listLength packages)) (workerCount (listLength workerSpecs))
        (worker (optionOr (listHead workerSpecs) mapEmpty))]
    (if (= workerCount 0) (list)
      (list {:worker worker.workerId :partition packages :tier worker.tier})))

fn allocateWorkerWorktree workerId: Any baseRoot: Any -> Str
  (str baseRoot "/.asl/worktrees/" workerId)
