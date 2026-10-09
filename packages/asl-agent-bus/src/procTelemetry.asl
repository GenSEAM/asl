(module aslAgentBus/procTelemetry :x [ProcDescriptor ProcRegistry ProcTelemetryEvent makeProcLocus makeProcDescriptor emptyProcRegistry recordProcTelemetry removeProcTelemetry updateProcLocus calculateProcElapsed serializeProcPsEntry serializeProcRegistryPs serializeProcTop auditProcHealth filterProcsByLane findProcById] :i [(bus :a b) (ndAsn :a nd)])

(schema ProcDescriptor (:f pid I64) (:f taskId Str) (:f lane Str) (:f startedMs I64) (:f elapsedMs I64) (:f rssBytes I64) (:f locus Str) (:f status Str) (:f value Any))

(schema ProcRegistry (:f procs (List ProcDescriptor)) (:f updatedMs I64))

(schema ProcTelemetryEvent (:f eventId Str) (:f pid I64) (:f taskId Str) (:f tickMs I64) (:f locus Str) (:f memBytes I64) (:f tag Str))

fn makeProcLocus file: Str line: I64 fnName: Str -> Str
  (str file ":" (stringFromInt64 line) ":" fnName)

fn calculateProcElapsed startedMs: I64 nowMs: I64 -> I64
  (if (>= nowMs startedMs) (- nowMs startedMs) 0)

fn makeProcDescriptor pid: I64 taskId: Str lane: Str startedMs: I64 nowMs: I64 rssBytes: I64 locus: Str status: Str -> ProcDescriptor
  (let [(elapsed (calculateProcElapsed startedMs nowMs))] (let [(p (ProcDescriptor :pid pid :taskId taskId :lane lane :startedMs startedMs :elapsedMs elapsed :rssBytes rssBytes :locus locus :status status :value 0))] (ProcDescriptor :pid pid :taskId taskId :lane lane :startedMs startedMs :elapsedMs elapsed :rssBytes rssBytes :locus locus :status status :value p)))

fn emptyProcRegistry -> ProcRegistry
  (ProcRegistry :procs (list) :updatedMs 0)

fn recordProcTelemetry reg: ProcRegistry proc: ProcDescriptor -> ProcRegistry
  (let [(filtered (filter (fn [(p ProcDescriptor)] -> Bool (!= p.pid proc.pid)) reg.procs)) (nextProcs (listAppend filtered (list proc)))] (ProcRegistry :procs nextProcs :updatedMs (+ proc.startedMs proc.elapsedMs)))

fn removeProcTelemetry reg: ProcRegistry pid: I64 -> ProcRegistry
  (let [(filtered (filter (fn [(p ProcDescriptor)] -> Bool (!= p.pid pid)) reg.procs))] (with reg :procs filtered))

fn updateProcLocus proc: ProcDescriptor newLocus: Str nowMs: I64 -> ProcDescriptor
  (let [(elapsed (calculateProcElapsed proc.startedMs nowMs))] (let [(p (with proc :elapsedMs elapsed :locus newLocus :value 0))] (with proc :elapsedMs elapsed :locus newLocus :value p)))

fn serializeProcPsEntry proc: ProcDescriptor -> Str
  (str "(:proc :pid " (stringFromInt64 proc.pid) " :task-id \"" proc.taskId "\"" " :lane \"" proc.lane "\"" " :elapsed-ms " (stringFromInt64 proc.elapsedMs) " :rss-bytes " (stringFromInt64 proc.rssBytes) " :locus \"" proc.locus "\"" " :status \"" proc.status "\")")

fn serializeProcRegistryPs reg: ProcRegistry -> Str
  (fold (fn [(acc Str) (proc ProcDescriptor)] -> Str (let [(entry (serializeProcPsEntry proc))] (if (= (stringLength acc) 0) entry (str acc "\n" entry)))) "" reg.procs)

fn serializeProcTop reg: ProcRegistry -> Str
  (let [(count (listLength reg.procs)) (header (str "=== Process Plane Top: " (stringFromInt64 count) " active task(s) ===\n")) (rows (serializeProcRegistryPs reg))] (str header rows))

fn auditProcHealth proc: ProcDescriptor timeoutLimitMs: I64 -> Bool
  (and (<= proc.elapsedMs timeoutLimitMs) (!= proc.status "failed"))

fn filterProcsByLane reg: ProcRegistry lane: Str -> (List ProcDescriptor)
  (filter (fn [(p ProcDescriptor)] -> Bool (= p.lane lane)) reg.procs)

fn findProcById reg: ProcRegistry pid: I64 -> (List ProcDescriptor)
  (filter (fn [(p ProcDescriptor)] -> Bool (= p.pid pid)) reg.procs)
