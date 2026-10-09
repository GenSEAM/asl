(module aslMem/taskLease :x [SessionLease makeSessionLease renewSessionLease isLeaseExpired? stealExpiredLease formatLeaseAsn make renew expired? steal formatLease] :i [(asl-text/escape :a esc)])

(schema SessionLease (:f taskId Str) (:f sessionId Str) (:f holderRole Str) (:f acquiredAt I64) (:f renewedAt I64) (:f expiresAt I64) (:f ttlMs I64) (:f heartbeatCount I64))

fn makeSessionLease taskId: Str sessionId: Str holderRole: Str ttlMs: I64 nowEpoch: I64 -> SessionLease
  (SessionLease :taskId taskId :sessionId sessionId :holderRole holderRole :acquiredAt nowEpoch :renewedAt nowEpoch :expiresAt (+ nowEpoch ttlMs) :ttlMs ttlMs :heartbeatCount 0)

fn renewSessionLease lease: SessionLease nowEpoch: I64 -> SessionLease
  (with lease :renewedAt nowEpoch :expiresAt (+ nowEpoch lease.ttlMs) :heartbeatCount (+ lease.heartbeatCount 1))

fn isLeaseExpired? lease: SessionLease nowEpoch: I64 -> Bool
  (and (> lease.expiresAt 0) (>= nowEpoch lease.expiresAt))

fn stealExpiredLease lease: SessionLease newSessionId: Str newHolderRole: Str newTtlMs: I64 nowEpoch: I64 -> SessionLease
  (if (isLeaseExpired? lease nowEpoch) (with lease :sessionId newSessionId :holderRole newHolderRole :acquiredAt nowEpoch :renewedAt nowEpoch :expiresAt (+ nowEpoch newTtlMs) :ttlMs newTtlMs :heartbeatCount 0) lease)

fn formatLeaseAsn lease: SessionLease -> Str
  (str "(:lease\n" "  :task-id \"" (esc/escapeAsnStr lease.taskId) "\"\n" "  :session-id \"" (esc/escapeAsnStr lease.sessionId) "\"\n" "  :holder-role \"" (esc/escapeAsnStr lease.holderRole) "\"\n" "  :acquired-at " (stringFromInt64 lease.acquiredAt) "\n" "  :renewed-at " (stringFromInt64 lease.renewedAt) "\n" "  :expires-at " (stringFromInt64 lease.expiresAt) "\n" "  :ttl-ms " (stringFromInt64 lease.ttlMs) "\n" "  :heartbeat-count " (stringFromInt64 lease.heartbeatCount) ")\n")

fn make taskId: Str sessionId: Str holderRole: Str ttlMs: I64 nowEpoch: I64 -> SessionLease
  (makeSessionLease taskId sessionId holderRole ttlMs nowEpoch)

fn renew lease: SessionLease nowEpoch: I64 -> SessionLease
  (renewSessionLease lease nowEpoch)

fn expired? lease: SessionLease nowEpoch: I64 -> Bool
  (isLeaseExpired? lease nowEpoch)

fn steal lease: SessionLease newSessionId: Str newHolderRole: Str newTtlMs: I64 nowEpoch: I64 -> SessionLease
  (stealExpiredLease lease newSessionId newHolderRole newTtlMs nowEpoch)

fn formatLease lease: SessionLease -> Str
  (formatLeaseAsn lease)
