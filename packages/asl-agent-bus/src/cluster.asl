(module aslAgentBus/cluster :x [NodeState WorkerNode ClusterPool OpKind ClusterFrame packKeys unpackKeys packDag poolCreate poolAdd poolSelect dispatchTask makeReceipt workerIdle? RelayLease RelayLeaseRegistry TaskPartition createRelayLeaseRegistry isRelayLeaseExpired? relayClaimLease relayRegistryWithLease relayReleaseLease relayVerifyWrite derivePartitionFromTask isPathInPartition? pathInList? checkPartitionConflicts partitionsDisjoint?] :i [])

(enum NodeState (:c stateIdle [] "Worker is idle and ready for tasks") (:c stateBusy [] "Worker is executing assigned task") (:c stateDown [] "Worker node offline or unreachable"))

(schema WorkerNode (:f id Str) (:f host Str) (:f port I64) (:f role Str) (:f arm Str) (:f state NodeState) (:f caps (List Str)) (:f ping I64))

(schema ClusterPool (:f workers (List WorkerNode)))

(enum OpKind (:c opProp [] "Task proposal to remote node") (:c opAcc [] "Task acceptance confirmation") (:c opExec [] "Task execution directive") (:c opRc [] "Completion receipt") (:c opFail [] "Task execution failure"))

(schema ClusterFrame (:f id Str) (:f from Str) (:f to Str) (:f op OpKind) (:f taskId Str) (:f payload Str) (:f wirePayload Str))

fn workerIdle? w: WorkerNode -> Bool
  (mt w.state ((stateIdle) true) (_ false))

fn packKeys raw: Str -> Str
  (let [(s1 (stringReplace raw ":dependencies" ":deps")) (s2 (stringReplace s1 ":sender" ":from")) (s3 (stringReplace s2 ":target" ":to"))] s3)

fn unpackKeys normalized: Str -> Str
  (let [(s1 (stringReplace normalized ":deps" ":dependencies")) (s2 (stringReplace s1 ":from" ":sender")) (s3 (stringReplace s2 ":to" ":target"))] s3)

fn packDag taskId: Str title: Str deps: (List Str) premises: (List Str) -> Str
  (let [(dCount (listLength deps)) (pCount (listLength premises))] (packKeys (str "(:node :id \"" taskId "\" :title \"" title "\" :deps " (stringFromInt64 dCount) " :premises " (stringFromInt64 pCount) " :state :pending)")))

fn poolCreate -> ClusterPool
  (ClusterPool :workers (list))

fn poolAdd pool: ClusterPool w: WorkerNode -> ClusterPool
  (ClusterPool :workers (listAppend pool.workers (list w)))

fn poolSelect pool: ClusterPool role: Str requiredCap: Str -> (Option WorkerNode)
  (let [(matches (filter (fn [(w WorkerNode)] -> Bool (and (workerIdle? w) (= w.role role) (listContains? w.caps requiredCap))) pool.workers))] (listHead matches))

fn dispatchTask frameId: Str fromNode: Str worker: WorkerNode taskId: Str dagPayload: Str -> ClusterFrame
  (ClusterFrame :id frameId :from fromNode :to worker.id :op (opExec) :taskId taskId :payload dagPayload :wirePayload (packKeys dagPayload))

fn makeReceipt frameId: Str workerId: Str targetNode: Str taskId: Str diffLines: I64 gateMs: I64 -> ClusterFrame
  (let [(rawReceipt (str "(:receipt :node \"" workerId "\" :task \"" taskId "\" :status :pass :action \"ast-patch\" :diff " (stringFromInt64 diffLines) " :gate-ms " (stringFromInt64 gateMs) ")"))] (ClusterFrame :id frameId :from workerId :to targetNode :op (opRc) :taskId taskId :payload rawReceipt :wirePayload rawReceipt))

(schema RelayLease (:f logicalPath Str) (:f sessionId Str) (:f taskId Str) (:f grantedAt I64) (:f ttlMs I64) (:f digest Str))

(schema RelayLeaseRegistry (:f leases (Map Str RelayLease)))

(schema TaskPartition (:f taskId Str) (:f sessionId Str) (:f owns (List Str)))

fn createRelayLeaseRegistry -> RelayLeaseRegistry
  (RelayLeaseRegistry :leases (mapEmpty))

fn derivePartitionFromTask taskId: Str sessionId: Str owns: (List Str) -> TaskPartition
  (TaskPartition :taskId taskId :sessionId sessionId :owns owns)

fn pathInList? path: Str paths: (List Str) -> Bool
  (if (listEmpty? paths) false (let [(h (optionOr (listHead paths) "")) (t (optionOr (listTail paths) (list)))] (if (= h path) true (pathInList? path t))))

fn isPathInPartition? partition: TaskPartition path: Str -> Bool
  (pathOverlapsList? path partition.owns)

fn pathOverlapsList? path: Str paths: (List Str) -> Bool
  (if (listEmpty? paths) false (let [(h (optionOr (listHead paths) "")) (t (optionOr (listTail paths) (list)))] (if (or (= h path) (stringStartsWith? path (str h "/")) (stringStartsWith? h (str path "/"))) true (pathOverlapsList? path t))))

fn checkPartitionConflicts ownedA: (List Str) ownedB: (List Str) -> Bool
  (if (listEmpty? ownedA) false (let [(h (optionOr (listHead ownedA) "")) (t (optionOr (listTail ownedA) (list)))] (if (pathOverlapsList? h ownedB) true (checkPartitionConflicts t ownedB))))

fn partitionsDisjoint? p1: TaskPartition p2: TaskPartition -> Bool
  (not (checkPartitionConflicts p1.owns p2.owns))

fn isRelayLeaseExpired? lease: RelayLease now: I64 -> Bool
  (>= now (+ lease.grantedAt lease.ttlMs))

fn relayClaimLease reg: RelayLeaseRegistry logicalPath: Str sessionId: Str taskId: Str ttlMs: I64 now: I64 digest: Str -> (Result RelayLease Str)
  (let [(existingOpt (mapGet reg.leases logicalPath))] (mt existingOpt ((none) (let [(newLease (RelayLease :logicalPath logicalPath :sessionId sessionId :taskId taskId :grantedAt now :ttlMs ttlMs :digest digest))] (ok newLease))) ((some cur) (if (isRelayLeaseExpired? cur now) (let [(renewed (RelayLease :logicalPath logicalPath :sessionId sessionId :taskId taskId :grantedAt now :ttlMs ttlMs :digest digest))] (ok renewed)) (if (= cur.sessionId sessionId) (let [(extended (RelayLease :logicalPath logicalPath :sessionId sessionId :taskId taskId :grantedAt now :ttlMs ttlMs :digest digest))] (ok extended)) (err "ERR_LEASE_CONFLICT"))))))

fn relayRegistryWithLease reg: RelayLeaseRegistry lease: RelayLease -> RelayLeaseRegistry
  (RelayLeaseRegistry :leases (mapSet reg.leases lease.logicalPath lease))

fn relayReleaseLease reg: RelayLeaseRegistry logicalPath: Str sessionId: Str -> (Result RelayLeaseRegistry Str)
  (let [(existingOpt (mapGet reg.leases logicalPath))] (mt existingOpt ((none) (err "ERR_LEASE_NOT_FOUND")) ((some cur) (if (= cur.sessionId sessionId) (ok (RelayLeaseRegistry :leases (mapRemove reg.leases logicalPath))) (err "ERR_NOT_LEASE_HOLDER")))))

fn relayVerifyWrite reg: RelayLeaseRegistry logicalPath: Str sessionId: Str digest: Str now: I64 -> (Result Bool Str)
  (let [(existingOpt (mapGet reg.leases logicalPath))] (mt existingOpt ((none) (err "ERR_STALE_LEASE")) ((some cur) (if (isRelayLeaseExpired? cur now) (err "ERR_STALE_LEASE") (if (!= cur.sessionId sessionId) (err "ERR_STALE_LEASE") (if (!= cur.digest digest) (err "ERR_CAS_MISMATCH") (ok true)))))))
