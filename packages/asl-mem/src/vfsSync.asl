(module aslMem/vfsSync :x [VFSSyncState makeSyncState detectDiskDrift validateFlushSafety updateStagedHash recordFlushSuccess resolveSyncAction] :i [(vfs :a v)])

(schema VFSSyncState (:f path Str) (:f diskBaseHash Str) (:f diskMtime I64) (:f stagedHash Str) (:f stagedRevision I64) (:f status Str))

fn makeSyncState path: Str diskBaseHash: Str diskMtime: I64 -> VFSSyncState
  (let [(norm (v/normalizePath path))] (VFSSyncState :path norm :diskBaseHash diskBaseHash :diskMtime diskMtime :stagedHash diskBaseHash :stagedRevision 1 :status "clean"))

fn detectDiskDrift state: VFSSyncState currentDiskHash: Str currentDiskMtime: I64 -> Bool
  (or (!= state.diskBaseHash currentDiskHash) (!= state.diskMtime currentDiskMtime))

fn validateFlushSafety state: VFSSyncState currentDiskHash: Str -> Bool
  (= state.diskBaseHash currentDiskHash)

fn updateStagedHash state: VFSSyncState newStagedHash: Str -> VFSSyncState
  (let [(isDirty (!= newStagedHash state.diskBaseHash)) (newStatus (if isDirty "staged" "clean"))] (with state :stagedHash newStagedHash :stagedRevision (+ state.stagedRevision 1) :status newStatus))

fn recordFlushSuccess state: VFSSyncState newDiskHash: Str newMtime: I64 -> VFSSyncState
  (with state :diskBaseHash newDiskHash :diskMtime newMtime :stagedHash newDiskHash :status "synced")

fn resolveSyncAction state: VFSSyncState currentDiskHash: Str currentDiskMtime: I64 -> Str
  (if (and (= state.diskBaseHash currentDiskHash) (= state.stagedHash currentDiskHash)) "clean" (if (validateFlushSafety state currentDiskHash) "safe" ":conflict"))
