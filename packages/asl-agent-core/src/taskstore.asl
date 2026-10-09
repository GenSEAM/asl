(module aslAgentCore/taskstore :x [TaskStore taskstoreCreate taskstorePut! taskstoreGet isTaskQueued? filterQueued insertTask sortTasks taskstoreListQueued taskstoreClaim! taskstoreTransition! taskstoreListInFlight taskstoreCountByState taskstoreSpawnChildren!] :i [(tasktypes :a tt) (statemachine :a sm)])

(schema TaskStore (:f basePath Str) (:f tasks (Map Str tt/TaskRecord)))

fn taskstoreCreate basePath: Str -> TaskStore
  (TaskStore :basePath basePath :tasks (mapEmpty))

fn taskstorePut! store: TaskStore task: tt/TaskRecord -> (Result TaskStore Str)
  (let [(fpath (str store.basePath "/" task.id ".task")) (dummy (fileWrite fpath task.payload))] (ok (with store :tasks (mapSet store.tasks task.id task))))

fn taskstoreGet store: TaskStore id: Str -> (Option tt/TaskRecord)
  (mapGet store.tasks id)

fn isTaskQueued? task: tt/TaskRecord -> Bool
  (mt task.state ((stateQueued) true) (_ false))

fn filterQueued tasks: (List tt/TaskRecord) -> (List tt/TaskRecord)
  (if (listEmpty? tasks) (list) (let [(h (optionOr (listHead tasks) (tt/taskRecordCreate "" "" "" (tt/priorityNormal) 0 ""))) (tailList (optionOr (listTail tasks) (list)))] (if (isTaskQueued? h) (cons h (filterQueued tailList)) (filterQueued tailList))))

fn filterInFlight tasks: (List tt/TaskRecord) -> (List tt/TaskRecord)
  (if (listEmpty? tasks) (list) (let [(h (optionOr (listHead tasks) (tt/taskRecordCreate "" "" "" (tt/priorityNormal) 0 ""))) (tailList (optionOr (listTail tasks) (list)))] (if (tt/taskStateInFlight? h.state) (cons h (filterInFlight tailList)) (filterInFlight tailList))))

fn insertTask t: tt/TaskRecord sorted: (List tt/TaskRecord) -> (List tt/TaskRecord)
  (if (listEmpty? sorted) (list t) (let [(h (optionOr (listHead sorted) t)) (tailList (optionOr (listTail sorted) (list)))] (if (<= t.createdAt h.createdAt) (cons t sorted) (cons h (insertTask t tailList)))))

fn sortTasks tasks: (List tt/TaskRecord) -> (List tt/TaskRecord)
  (if (listEmpty? tasks) (list) (let [(h (optionOr (listHead tasks) (tt/taskRecordCreate "" "" "" (tt/priorityNormal) 0 ""))) (tailList (optionOr (listTail tasks) (list)))] (insertTask h (sortTasks tailList))))

fn taskstoreListQueued store: TaskStore -> (List tt/TaskRecord)
  (sortTasks (filterQueued (mapValues store.tasks)))

fn taskstoreListInFlight store: TaskStore -> (List tt/TaskRecord)
  (sortTasks (filterInFlight (mapValues store.tasks)))

fn taskstoreCountByState store: TaskStore state: tt/TaskState -> I64
  (let [(allTasks (mapValues store.tasks)) (matching (filter (fn [(t tt/TaskRecord)] -> Bool (= t.state state)) allTasks))] (listLength matching))

fn taskstoreClaim! store: TaskStore id: Str -> (Result TaskStore Str)
  (mt (taskstoreGet store id) ((none) (err "Task not found")) ((some t) (mt t.state ((stateQueued) (let [(claimed (tt/TaskRecord :id t.id :lane t.lane :projectPath t.projectPath :state (tt/stateRouting) :priority t.priority :createdAt t.createdAt :updatedAt t.updatedAt :payload t.payload))] (taskstorePut! store claimed))) (_ (err "Task is not in state-queued")))))

fn taskstoreTransition! store: TaskStore id: Str newState: tt/TaskState nowTs: I64 -> (Result TaskStore Str)
  (mt (taskstoreGet store id) ((none) (err "Task not found")) ((some t) (if (sm/validTransition? t.state newState) (let [(updated (tt/TaskRecord :id t.id :lane t.lane :projectPath t.projectPath :state newState :priority t.priority :createdAt t.createdAt :updatedAt nowTs :payload t.payload))] (taskstorePut! store updated)) (err "Illegal state transition"))))

fn spawnRecursive! store: TaskStore parent: tt/TaskRecord payloads: (List Str) idx: I64 nowTs: I64 -> TaskStore
  (if (listEmpty? payloads) store (let [(payload (optionOr (listHead payloads) "")) (restPayloads (optionOr (listTail payloads) (list))) (childId (str parent.id "-child-" (stringFromInt64 idx))) (childTask (tt/taskRecordCreate childId parent.lane parent.projectPath parent.priority nowTs payload)) (putRes (taskstorePut! store childTask)) (nextStore (resultOr putRes store))] (spawnRecursive! nextStore parent restPayloads (+ idx 1) nowTs)))

fn taskstoreSpawnChildren! store: TaskStore parent: tt/TaskRecord childrenPayloads: (List Str) nowTs: I64 -> TaskStore
  (spawnRecursive! store parent childrenPayloads 1 nowTs)
