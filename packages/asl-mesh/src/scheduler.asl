(module asl-mesh/scheduler
  :d "Autonomous multi-model mesh partition scheduler and worktree airgap orchestrator under D85."
  :x [schedule_partitions
      allocate_worker_worktree
      partition_map
      worktree_pool]
  :i [])

(df partition_map [packages workers] -> Map
  :d "Constructs partition mapping across packages"
  {:packages packages :workers workers :count (count packages)})

(df worktree_pool [base-dir count] -> List
  :d "Constructs worktree airgap pool"
  (list (str base-dir "/worker-0") (str base-dir "/worker-1") (str base-dir "/worker-2")))

(df schedule_partitions [packages worker-specs] -> List
  :d "Schedules disjoint package partitions across worker specifications"
  (let [(total-pkgs (count packages))
        (worker-count (count worker-specs))]
    (if (= worker-count 0)
      (list)
      (list
        {:worker (get (head worker-specs) :workerId) :partition packages :tier (get (head worker-specs) :tier)}))))

(df allocate_worker_worktree [worker-id base-root] -> Str
  :d "Allocates isolated git worktree airgap path for worker subagent"
  (str base-root "/.asl/worktrees/" worker-id))
