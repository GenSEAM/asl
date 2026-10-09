(module aslMem/vfs :x [VFSBuffer VFSRegistry makeVFSRegistry vfsInit vfs-init vfs-read vfs-write vfsCasHash vfs-cas-hash vfs-cas-update vfs-discard vfs-flush vfs-acquire-lease vfs-release-lease vfs-staged-write vfs-fenced-staged-write normalizePath norm resolve read write vNorm vResolve vRead vWrite vfsRead vfsWrite vfs-diff vfsDiff BrowserVfsStorage OpfsPersistence IndexedDbBackup makeOpfsPersistence makeIndexedDbBackup makeBrowserVfsStorage syncBrowserVfsStorage charToCode] :i [])

(schema VFSBuffer (:f path Str) (:f content Str) (:f baseContent Str) (:f casHash Str) (:f baseHash Str) (:f revision I64) (:f dirty Bool) (:f loadedAt I64) (:f leaseHolder Str) (:f leaseExpiresAt I64) (:f leaseToken I64))

(schema VFSRegistry (:f buffers (Map Str VFSBuffer)) (:f activePaths (List Str)) (:f size I64))

fn hexNibble n: I64 -> Str
  (let [(chars "0123456789abcdef")] (optionOr (stringSlice chars n (+ n 1)) "0"))

fn hexU32 val: I64 -> Str
  (let [(d7 (hexNibble (mod val 16))) (v6 (/ val 16)) (d6 (hexNibble (mod v6 16))) (v5 (/ v6 16)) (d5 (hexNibble (mod v5 16))) (v4 (/ v5 16)) (d4 (hexNibble (mod v4 16))) (v3 (/ v4 16)) (d3 (hexNibble (mod v3 16))) (v2 (/ v3 16)) (d2 (hexNibble (mod v2 16))) (v1 (/ v2 16)) (d1 (hexNibble (mod v1 16))) (v0 (/ v1 16)) (d0 (hexNibble (mod v0 16)))] (str d0 d1 d2 d3 d4 d5 d6 d7))

fn charToCode ch: Str -> I64
  (let [(charset "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ !\"#$%&'()*+,-./:<=>?@[\\]^_`{|}~\t\n\r")] (mt (stringIndexOf charset ch) ((none) 127) ((some idx) (+ idx 32))))

fn vfs-cas-hash content: Str -> Str
  (let [(initState (list 1779033703 996650630 1013904242 625997115 1359893119 453339277 528734635 1541459225)) (chars (stringChars content)) (finalState (fold (fn [(acc (List I64)) (ch Str)] -> (List I64) (let [(code (charToCode ch)) (h0 (optionOr (listGet acc 0) 0)) (h1 (optionOr (listGet acc 1) 0)) (h2 (optionOr (listGet acc 2) 0)) (h3 (optionOr (listGet acc 3) 0)) (h4 (optionOr (listGet acc 4) 0)) (h5 (optionOr (listGet acc 5) 0)) (h6 (optionOr (listGet acc 6) 0)) (h7 (optionOr (listGet acc 7) 0)) (n0 (mod (+ (* h0 31) code) 2147483647)) (n1 (mod (+ (* h1 37) code) 2147483629)) (n2 (mod (+ (* h2 41) code) 2147483587)) (n3 (mod (+ (* h3 43) code) 2147483579)) (n4 (mod (+ (* h4 47) code) 2147483563)) (n5 (mod (+ (* h5 53) code) 2147483543)) (n6 (mod (+ (* h6 59) code) 2147483497)) (n7 (mod (+ (* h7 61) code) 2147483489))] (list n0 n1 n2 n3 n4 n5 n6 n7))) initState chars)) (len (stringLength content)) (f0 (mod (+ (* (optionOr (listGet finalState 0) 0) 67) len) 2147483647)) (f1 (mod (+ (* (optionOr (listGet finalState 1) 0) 71) len) 2147483629)) (f2 (mod (+ (* (optionOr (listGet finalState 2) 0) 73) len) 2147483587)) (f3 (mod (+ (* (optionOr (listGet finalState 3) 0) 79) len) 2147483579)) (f4 (mod (+ (* (optionOr (listGet finalState 4) 0) 83) len) 2147483563)) (f5 (mod (+ (* (optionOr (listGet finalState 5) 0) 89) len) 2147483543)) (f6 (mod (+ (* (optionOr (listGet finalState 6) 0) 97) len) 2147483497)) (f7 (mod (+ (* (optionOr (listGet finalState 7) 0) 101) len) 2147483489))] (str (hexU32 f0) (hexU32 f1) (hexU32 f2) (hexU32 f3) (hexU32 f4) (hexU32 f5) (hexU32 f6) (hexU32 f7)))

fn vfsCasHash content: Str -> Str
  (vfs-cas-hash content)

fn normalizePath path: Str -> Str
  (let [(trimmed (stringTrim path))] (if (stringStartsWith? trimmed "./") (optionOr (stringSlice trimmed 2 (stringLength trimmed)) "") (if (stringStartsWith? trimmed "/") (optionOr (stringSlice trimmed 1 (stringLength trimmed)) "") trimmed)))

fn vfs-init -> VFSRegistry
  (VFSRegistry :buffers (mapEmpty) :activePaths (list) :size 0)

fn vfs-read registry: VFSRegistry path: Str -> (Option VFSBuffer)
  (let [(norm (normalizePath path))] (mapGet registry.buffers norm))

fn vfs-write registry: VFSRegistry path: Str newContent: Str -> VFSRegistry
  (let [(norm (normalizePath path)) (newHash (vfs-cas-hash newContent))] (mt (mapGet registry.buffers norm) ((none) (let [(newBuf (VFSBuffer :path norm :content newContent :baseContent newContent :casHash newHash :baseHash newHash :revision 1 :dirty false :loadedAt 0 :leaseHolder "" :leaseExpiresAt 0 :leaseToken 0))] (VFSRegistry :buffers (mapSet registry.buffers norm newBuf) :activePaths (listAppend registry.activePaths (list norm)) :size (+ registry.size 1)))) ((some prev) (let [(baseH prev.baseHash) (baseC prev.baseContent) (isDirty (!= newHash baseH)) (updatedBuf (VFSBuffer :path norm :content newContent :baseContent baseC :casHash newHash :baseHash baseH :revision (+ prev.revision 1) :dirty isDirty :loadedAt prev.loadedAt :leaseHolder prev.leaseHolder :leaseExpiresAt prev.leaseExpiresAt :leaseToken prev.leaseToken))] (with registry :buffers (mapSet registry.buffers norm updatedBuf))))))

fn vfs-cas-update registry: VFSRegistry path: Str expectedHash: Str newContent: Str -> (Result VFSRegistry Str)
  (let [(norm (normalizePath path))] (mt (mapGet registry.buffers norm) ((none) (if (and (!= expectedHash "") (!= expectedHash "0")) (err "ERR_CAS_VERSION_CONFLICT") (let [(newHash (vfs-cas-hash newContent)) (newBuf (VFSBuffer :path norm :content newContent :baseContent newContent :casHash newHash :baseHash newHash :revision 1 :dirty false :loadedAt 0 :leaseHolder "" :leaseExpiresAt 0 :leaseToken 0))] (ok (VFSRegistry :buffers (mapSet registry.buffers norm newBuf) :activePaths (listAppend registry.activePaths (list norm)) :size (+ registry.size 1)))))) ((some prev) (if (!= prev.casHash expectedHash) (err "ERR_CAS_VERSION_CONFLICT") (let [(newHash (vfs-cas-hash newContent)) (baseH prev.baseHash) (baseC prev.baseContent) (isDirty (!= newHash baseH)) (updatedBuf (VFSBuffer :path norm :content newContent :baseContent baseC :casHash newHash :baseHash baseH :revision (+ prev.revision 1) :dirty isDirty :loadedAt prev.loadedAt :leaseHolder prev.leaseHolder :leaseExpiresAt prev.leaseExpiresAt :leaseToken prev.leaseToken))] (ok (with registry :buffers (mapSet registry.buffers norm updatedBuf))))))))

fn vfs-discard registry: VFSRegistry path: Str -> (Result VFSRegistry Str)
  (let [(norm (normalizePath path))] (mt (mapGet registry.buffers norm) ((none) (err "ERR_BUFFER_NOT_FOUND")) ((some buf) (if (not buf.dirty) (ok registry) (let [(restoredBuf (VFSBuffer :path norm :content buf.baseContent :baseContent buf.baseContent :casHash buf.baseHash :baseHash buf.baseHash :revision (+ buf.revision 1) :dirty false :loadedAt buf.loadedAt :leaseHolder buf.leaseHolder :leaseExpiresAt buf.leaseExpiresAt :leaseToken buf.leaseToken))] (ok (with registry :buffers (mapSet registry.buffers norm restoredBuf))))))))

fn vfs-flush registry: VFSRegistry path: Str expectedBaseHash: Str -> (Result VFSRegistry Str)
  (let [(norm (normalizePath path))] (mt (mapGet registry.buffers norm) ((none) (err "ERR_BUFFER_NOT_FOUND")) ((some buf) (if (and (!= expectedBaseHash "") (!= buf.baseHash expectedBaseHash)) (err "ERR_EXTERNAL_CHANGE_CONFLICT") (let [(flushedBuf (VFSBuffer :path norm :content buf.content :baseContent buf.content :casHash buf.casHash :baseHash buf.casHash :revision (+ buf.revision 1) :dirty false :loadedAt buf.loadedAt :leaseHolder buf.leaseHolder :leaseExpiresAt buf.leaseExpiresAt :leaseToken buf.leaseToken))] (ok (with registry :buffers (mapSet registry.buffers norm flushedBuf))))))))

fn vfs-acquire-lease registry: VFSRegistry path: Str writerId: Str nowTs: I64 ttlMs: I64 -> (Result VFSRegistry Str)
  (let [(norm (normalizePath path))] (mt (mapGet registry.buffers norm) ((none) (let [(emptyHash (vfs-cas-hash "")) (newBuf (VFSBuffer :path norm :content "" :baseContent "" :casHash emptyHash :baseHash emptyHash :revision 1 :dirty false :loadedAt nowTs :leaseHolder writerId :leaseExpiresAt (+ nowTs ttlMs) :leaseToken 1))] (ok (VFSRegistry :buffers (mapSet registry.buffers norm newBuf) :activePaths (listAppend registry.activePaths (list norm)) :size (+ registry.size 1))))) ((some buf) (if (and (!= buf.leaseHolder "") (!= buf.leaseHolder writerId) (> buf.leaseExpiresAt nowTs)) (err "ERR_LEASE_ACTIVE_CONFLICT") (let [(nextToken (+ buf.leaseToken 1)) (updatedBuf (VFSBuffer :path norm :content buf.content :baseContent buf.baseContent :casHash buf.casHash :baseHash buf.baseHash :revision buf.revision :dirty buf.dirty :loadedAt buf.loadedAt :leaseHolder writerId :leaseExpiresAt (+ nowTs ttlMs) :leaseToken nextToken))] (ok (with registry :buffers (mapSet registry.buffers norm updatedBuf))))))))

fn vfs-release-lease registry: VFSRegistry path: Str writerId: Str -> (Result VFSRegistry Str)
  (let [(norm (normalizePath path))] (mt (mapGet registry.buffers norm) ((none) (err "ERR_BUFFER_NOT_FOUND")) ((some buf) (if (and (!= buf.leaseHolder "") (!= buf.leaseHolder writerId)) (err "ERR_LEASE_NOT_OWNED") (let [(updatedBuf (VFSBuffer :path norm :content buf.content :baseContent buf.baseContent :casHash buf.casHash :baseHash buf.baseHash :revision buf.revision :dirty buf.dirty :loadedAt buf.loadedAt :leaseHolder "" :leaseExpiresAt 0 :leaseToken buf.leaseToken))] (ok (with registry :buffers (mapSet registry.buffers norm updatedBuf))))))))

fn vfs-staged-write registry: VFSRegistry path: Str writerId: Str expectedHash: Str newContent: Str nowTs: I64 -> (Result VFSRegistry Str)
  (let [(norm (normalizePath path))] (mt (mapGet registry.buffers norm) ((none) (vfs-cas-update registry norm expectedHash newContent)) ((some buf) (if (and (!= buf.leaseHolder "") (!= buf.leaseHolder writerId) (> buf.leaseExpiresAt nowTs)) (err "ERR_LEASE_ACTIVE_CONFLICT") (vfs-cas-update registry norm expectedHash newContent)))))

fn vfs-fenced-staged-write registry: VFSRegistry path: Str writerId: Str token: I64 expectedHash: Str newContent: Str nowTs: I64 -> (Result VFSRegistry Str)
  (let [(norm (normalizePath path))] (mt (mapGet registry.buffers norm) ((none) (err "ERR_BUFFER_NOT_FOUND")) ((some buf) (if (< token buf.leaseToken) (err "ERR_STALE_FENCING_TOKEN") (if (and (!= buf.leaseHolder "") (!= buf.leaseHolder writerId) (> buf.leaseExpiresAt nowTs)) (err "ERR_LEASE_ACTIVE_CONFLICT") (vfs-cas-update registry norm expectedHash newContent))))))

fn splitLines text: Str -> (List Str)
  (if (stringEmpty? text) (list) (stringSplit text "\n"))

fn norm path: Str -> Str
  (normalizePath path)

fn resolve base: Str relPath: Str -> Str
  (let [(normRel (normalizePath relPath)) (normBase (normalizePath base))] (if (stringEmpty? normBase) normRel (if (stringEmpty? normRel) normBase (str normBase "/" normRel))))

fn makeVFSRegistry -> VFSRegistry
  (vfs-init)

fn vfsInit -> VFSRegistry
  (vfs-init)

fn read registry: VFSRegistry path: Str -> (Option VFSBuffer)
  (vfs-read registry path)

fn write registry: VFSRegistry path: Str newContent: Str -> VFSRegistry
  (vfs-write registry path newContent)

fn vNorm path: Str -> Str
  (norm path)

fn vResolve base: Str relPath: Str -> Str
  (resolve base relPath)

fn vRead registry: VFSRegistry path: Str -> (Option VFSBuffer)
  (read registry path)

fn vWrite registry: VFSRegistry path: Str newContent: Str -> VFSRegistry
  (write registry path newContent)

fn vfsWrite registry: VFSRegistry path: Str newContent: Str -> VFSRegistry
  (vfs-write registry path newContent)

fn vfsRead registry: VFSRegistry path: Str -> (Option VFSBuffer)
  (vfs-read registry path)

fn computeDiffLines baseLines: (List Str) currLines: (List Str) -> (List Str)
  (if (and (listEmpty? baseLines) (listEmpty? currLines)) (list) (if (listEmpty? baseLines) (map (fn [(l Str)] -> Str (str "+" l)) currLines) (if (listEmpty? currLines) (map (fn [(l Str)] -> Str (str "-" l)) baseLines) (let [(bHead (optionOr (listHead baseLines) "")) (bTail (optionOr (listTail baseLines) (list))) (cHead (optionOr (listHead currLines) "")) (cTail (optionOr (listTail currLines) (list)))] (if (= bHead cHead) (cons (str " " bHead) (computeDiffLines bTail cTail)) (if (listContains? currLines bHead) (cons (str "+" cHead) (computeDiffLines baseLines cTail)) (if (listContains? baseLines cHead) (cons (str "-" bHead) (computeDiffLines bTail currLines)) (cons (str "-" bHead) (cons (str "+" cHead) (computeDiffLines bTail cTail))))))))))

fn vfs-diff buf: VFSBuffer -> (List Str)
  (if (not buf.dirty) (list) (computeDiffLines (splitLines buf.baseContent) (splitLines buf.content)))

fn vfsDiff buf: VFSBuffer -> (List Str)
  (vfs-diff buf)

(schema OpfsPersistence (:f rootDirectory Str) (:f isAvailable Bool) (:f syncIntervalMs I64) (:f bytesWritten I64))

(schema IndexedDbBackup (:f databaseName Str) (:f storeName Str) (:f isActive Bool))

(schema BrowserVfsStorage (:f registry VFSRegistry) (:f opfs OpfsPersistence) (:f idb IndexedDbBackup) (:f dirtyCount I64))

fn makeOpfsPersistence rootDir: Str available: Bool -> OpfsPersistence
  (OpfsPersistence :rootDirectory rootDir :isAvailable available :syncIntervalMs 1000 :bytesWritten 0)

fn makeIndexedDbBackup dbName: Str storeName: Str -> IndexedDbBackup
  (IndexedDbBackup :databaseName dbName :storeName storeName :isActive true)

fn makeBrowserVfsStorage reg: VFSRegistry -> BrowserVfsStorage
  (BrowserVfsStorage :registry reg :opfs (makeOpfsPersistence "/asl-vfs" true) :idb (makeIndexedDbBackup "asl_storage" "vfs_buffers") :dirtyCount 0)

fn syncBrowserVfsStorage storage: BrowserVfsStorage -> BrowserVfsStorage
  (with storage :opfs (OpfsPersistence :rootDirectory storage.opfs.rootDirectory :isAvailable storage.opfs.isAvailable :syncIntervalMs storage.opfs.syncIntervalMs :bytesWritten (+ storage.opfs.bytesWritten (* storage.dirtyCount 128))) :dirtyCount 0)
