(module aslMem/storageFile :x [OpfsStorage makeOpfsStorage getRootPrefix isLockedBy? isLocked? acquireWebLock releaseWebLock opfsWrite opfsRead])

(schema OpfsStorage (:f rootPrefix Str) (:f lockHolder Str) (:f lockTimestamp I64) (:f files (Map Str Str)))

fn makeOpfsStorage rootPrefix: Str -> OpfsStorage
  (OpfsStorage :rootPrefix rootPrefix :lockHolder "" :lockTimestamp 0 :files (mapEmpty))

fn getRootPrefix s: OpfsStorage -> Str
  s.rootPrefix

fn isLockedBy? s: OpfsStorage tabId: Str -> Bool
  (and (!= s.lockHolder "") (= s.lockHolder tabId))

fn isLocked? s: OpfsStorage -> Bool
  (!= s.lockHolder "")

fn acquireWebLock s: OpfsStorage tabId: Str nowTs: I64 -> (Option OpfsStorage)
  (if (isLocked? s) (if (= s.lockHolder tabId) (some (with s :lockHolder tabId :lockTimestamp nowTs)) (none)) (some (with s :lockHolder tabId :lockTimestamp nowTs)))

fn releaseWebLock s: OpfsStorage tabId: Str -> (Option OpfsStorage)
  (if (= s.lockHolder tabId) (some (with s :lockHolder "" :lockTimestamp 0)) (none))

fn opfsWrite s: OpfsStorage tabId: Str path: Str data: Str -> (Option OpfsStorage)
  (if (= s.lockHolder tabId) (some (with s :files (mapSet s.files path data))) (none))

fn opfsRead s: OpfsStorage path: Str -> (Option Str)
  (mapGet s.files path)
