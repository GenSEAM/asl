(module aslMem/tasksDag :x [taskOwnsFile? taskOwnsIntersect? taskOverlapFiles taskOverlapBlastRadius? taskDependenciesSatisfied? taskParallelEligible? taskIsReady? taskFindReady] :i [(tasksStore :a ts) (vfs :a v)])

fn taskOwnsFile? task: ts/TaskRecord file: Str -> Bool
  (let [(norm (v/normalizePath file)) (ownsNorm (map (fn [(f Str)] -> Str (v/normalizePath f)) task.owns))] (listContains? ownsNorm norm))

fn taskOwnsIntersect? t1: ts/TaskRecord t2: ts/TaskRecord -> Bool
  (let [(files1 (filter (fn [(f Str)] -> Bool (!= f "-")) (map (fn [(f Str)] -> Str (v/normalizePath f)) t1.owns))) (files2 (filter (fn [(f Str)] -> Bool (!= f "-")) (map (fn [(f Str)] -> Str (v/normalizePath f)) t2.owns)))] (let [(common (filter (fn [(f Str)] -> Bool (listContains? files2 f)) files1))] (> (listLength common) 0)))

fn taskOverlapFiles t1: ts/TaskRecord t2: ts/TaskRecord -> (List Str)
  (let [(files1 (filter (fn [(f Str)] -> Bool (!= f "-")) (map (fn [(f Str)] -> Str (v/normalizePath f)) t1.owns))) (files2 (filter (fn [(f Str)] -> Bool (!= f "-")) (map (fn [(f Str)] -> Str (v/normalizePath f)) t2.owns)))] (filter (fn [(f Str)] -> Bool (listContains? files2 f)) files1))

fn taskOverlapBlastRadius? t1: ts/TaskRecord t2: ts/TaskRecord -> Bool
  (let [(t1Targets (filter (fn [(s Str)] -> Bool (!= s "")) t1.targetSymbols)) (t2Targets (filter (fn [(s Str)] -> Bool (!= s "")) t2.targetSymbols)) (t1Related (filter (fn [(s Str)] -> Bool (!= s "")) t1.relatedSymbols)) (t2Related (filter (fn [(s Str)] -> Bool (!= s "")) t2.relatedSymbols)) (targetCollision (filter (fn [(s Str)] -> Bool (listContains? t2Targets s)) t1Targets)) (blast1 (filter (fn [(s Str)] -> Bool (listContains? t2Related s)) t1Targets)) (blast2 (filter (fn [(s Str)] -> Bool (listContains? t1Related s)) t2Targets))] (or (> (listLength targetCollision) 0) (or (> (listLength blast1) 0) (> (listLength blast2) 0))))

fn taskDependenciesSatisfied? task: ts/TaskRecord completedIds: (List Str) -> Bool
  (let [(missing (filter (fn [(dep Str)] -> Bool (not (listContains? completedIds dep))) task.dependsOn))] (listEmpty? missing))

fn taskParallelEligible? t1: ts/TaskRecord t2: ts/TaskRecord -> Bool
  (and (!= t1.id t2.id) (and (not (listContains? t1.dependsOn t2.id)) (and (not (listContains? t2.dependsOn t1.id)) (and (not (taskOwnsIntersect? t1 t2)) (not (taskOverlapBlastRadius? t1 t2))))))

fn taskIsReady? task: ts/TaskRecord completedIds: (List Str) -> Bool
  (and (or (= task.state "queued") (= task.state "ready")) (taskDependenciesSatisfied? task completedIds))

fn taskFindReady tasks: (List ts/TaskRecord) completedIds: (List Str) -> (List ts/TaskRecord)
  (filter (fn [(t ts/TaskRecord)] -> Bool (taskIsReady? t completedIds)) tasks)
