(module aslMem/tests/vfsTest :x [runTests testVfsInit testBufferCreationAndRead testCasContentAddressing testInMemoryOverwrites testDirtyBufferDiffing testBaseHeadAdvancesWhenCurrentHeadIsInBase testBrowserVfsStorage testFencedStagedWrite] :i [(vfs :a v)])

fn testVfsInit -> Bool
  (let [(reg (v/vfs-init)) (lookup (v/vfs-read reg "nonexistent.asl"))] (assert (= reg.size 0) "Initial registry size must equal 0") (assert (= (listLength reg.activePaths) 0) "Initial active paths list must be empty") (assert (none? lookup) "Lookup of non-existent buffer must return None") (assert (= (listLength (mapKeys reg.buffers)) 0) "Initial buffer map keys count must be 0") true)

fn testBufferCreationAndRead -> Bool
  (let [(reg0 (v/vfs-init)) (reg1 (v/vfs-write reg0 "./src/core/model.asl" "(module model :x [])")) (lookup (v/vfs-read reg1 "src/core/model.asl"))] (assert (some? lookup) "Newly written buffer must be retrievable by normalized path") (let [(buf (optionOr lookup (v/VFSBuffer :path "" :content "" :baseContent "" :casHash "" :baseHash "" :revision 0 :dirty true :loadedAt 0 :leaseHolder "" :leaseExpiresAt 0 :leaseToken 0)))] (assert (= buf.path "src/core/model.asl") "Path must be normalized by stripping leading dot-slash") (assert (= buf.content "(module model :x [])") "Buffer payload must match written content") (assert (= buf.revision 1) "Initial buffer revision counter must equal 1") (assert (not buf.dirty) "Freshly staged buffer must not be dirty relative to its base") true))

fn testCasContentAddressing -> Bool
  (let [(c1 "alpha payload") (c2 "alpha payload") (c3 "beta payload") (h1 (v/vfs-cas-hash c1)) (h2 (v/vfs-cas-hash c2)) (h3 (v/vfs-cas-hash c3)) (reg (v/vfs-write (v/vfs-init) "pkg/test.asl" c1)) (buf (optionOr (v/vfs-read reg "pkg/test.asl") (v/VFSBuffer :path "" :content "" :baseContent "" :casHash "" :baseHash "" :revision 0 :dirty true :loadedAt 0 :leaseHolder "" :leaseExpiresAt 0 :leaseToken 0)))] (assert (= h1 h2) "Identical content payloads must produce identical CAS hashes") (assert (!= h1 h3) "Different content payloads must produce distinct CAS hashes") (assert (= (stringLength h1) 64) "CAS hash digest must be a 64-character hexadecimal string") (assert (= buf.casHash h1) "Buffer cas-hash field must match hash of current content") (assert (= buf.baseHash h1) "Buffer base-hash field must match hash of pristine base content") true)

fn testInMemoryOverwrites -> Bool
  (let [(reg0 (v/vfs-init)) (baseText "(module state-v1 :x [run])") (editText "(module state-v2 :x [run stop])") (reg1 (v/vfs-write reg0 "app/state.asl" baseText)) (reg2 (v/vfs-write reg1 "app/state.asl" editText)) (buf2 (optionOr (v/vfs-read reg2 "app/state.asl") (v/VFSBuffer :path "" :content "" :baseContent "" :casHash "" :baseHash "" :revision 0 :dirty false :loadedAt 0 :leaseHolder "" :leaseExpiresAt 0 :leaseToken 0))) (reg3 (v/vfs-write reg2 "app/state.asl" baseText)) (buf3 (optionOr (v/vfs-read reg3 "app/state.asl") (v/VFSBuffer :path "" :content "" :baseContent "" :casHash "" :baseHash "" :revision 0 :dirty false :loadedAt 0 :leaseHolder "" :leaseExpiresAt 0 :leaseToken 0)))] (assert (= buf2.revision 2) "Second write to same path must increment revision to 2") (assert buf2.dirty "Mutating content away from base version must set dirty flag to true") (assert (= reg2.size 1) "Overwriting existing buffer must not duplicate registry entries") (assert (= buf3.revision 3) "Third write reverting content must increment revision to 3") (assert (not buf3.dirty) "Reverting content back to base version must clear dirty flag to false") true)

fn testDirtyBufferDiffing -> Bool
  (let [(reg0 (v/vfs-init)) (baseText "line 1: prelude\nline 2: body\nline 3: closing") (modText "line 1: prelude\nline 2: modified body\nline 3: closing\nline 4: footer") (reg1 (v/vfs-write reg0 "doc.txt" baseText)) (cleanBuf (optionOr (v/vfs-read reg1 "doc.txt") (v/VFSBuffer :path "" :content "" :baseContent "" :casHash "" :baseHash "" :revision 0 :dirty true :loadedAt 0 :leaseHolder "" :leaseExpiresAt 0 :leaseToken 0))) (reg2 (v/vfs-write reg1 "doc.txt" modText)) (dirtyBuf (optionOr (v/vfs-read reg2 "doc.txt") (v/VFSBuffer :path "" :content "" :baseContent "" :casHash "" :baseHash "" :revision 0 :dirty false :loadedAt 0 :leaseHolder "" :leaseExpiresAt 0 :leaseToken 0))) (cleanDiff (v/vfs-diff cleanBuf)) (dirtyDiff (v/vfs-diff dirtyBuf))] (assert (= (listLength cleanDiff) 0) "Diff on clean buffer must return empty list of delta lines") (assert (> (listLength dirtyDiff) 0) "Diff on dirty buffer must return non-empty delta lines") (assert (listContains? dirtyDiff " line 1: prelude") "Diff must preserve unchanged line 1 as context") (assert (listContains? dirtyDiff "-line 2: body") "Diff must flag deleted or replaced base line with minus prefix") (assert (listContains? dirtyDiff "+line 2: modified body") "Diff must flag added or modified current line with plus prefix") (assert (listContains? dirtyDiff "+line 4: footer") "Diff must flag newly appended line with plus prefix") true)

fn testBaseHeadAdvancesWhenCurrentHeadIsInBase -> Bool
  (let [(reg1 (v/vfs-write (v/vfs-init) "doc.txt" "a\nb"))
        (reg2 (v/vfs-write reg1 "doc.txt" "b\nc"))
        (buf (optionOr (v/vfs-read reg2 "doc.txt") (v/VFSBuffer :path "" :content "" :baseContent "" :casHash "" :baseHash "" :revision 0 :dirty false :loadedAt 0 :leaseHolder "" :leaseExpiresAt 0 :leaseToken 0)))
        (diff (v/vfs-diff buf))]
    (assert (= diff (list "-a" " b" "+c")) "Diff advances base when current head is a later base line")
    true)

fn testBrowserVfsStorage -> Bool
  (let [(reg (v/vfs-write (v/vfs-init) "src/app.asl" "(module app)")) (storage0 (v/makeBrowserVfsStorage reg)) (opfs storage0.opfs) (idb storage0.idb)] (assert (= opfs.rootDirectory "/asl-vfs") "OPFS root directory must be /asl-vfs") (assert opfs.isAvailable "OPFS storage must be marked available") (assert (= opfs.syncIntervalMs 1000) "OPFS sync interval must be 1000ms") (assert (= idb.databaseName "asl_storage") "IndexedDB database name must match") (assert (= idb.storeName "vfs_buffers") "IndexedDB store name must match") (assert idb.isActive "IndexedDB backup store must be active") (let [(storageDirty (v/BrowserVfsStorage :registry storage0.registry :opfs opfs :idb idb :dirtyCount 2)) (storageSynced (v/syncBrowserVfsStorage storageDirty))] (assert (= storageSynced.dirtyCount 0) "Dirty buffer count must be 0 after sync flush") (assert (> storageSynced.opfs.bytesWritten 0) "OPFS bytes written must increment after sync flush") true))

fn testFencedStagedWrite -> Bool
  (let [(reg0 (v/vfs-init))
        (reg1Res (v/vfs-acquire-lease reg0 "src/test.asl" "agent-1" 1000 5000))
        (reg1 (resultOr reg1Res reg0))
        (buf1 (optionOr (v/vfs-read reg1 "src/test.asl") (v/VFSBuffer :path "" :content "" :baseContent "" :casHash "" :baseHash "" :revision 0 :dirty false :loadedAt 0 :leaseHolder "" :leaseExpiresAt 0 :leaseToken 0)))]
    (assert (= buf1.leaseToken 1) "Acquired lease buffer must initialize leaseToken to 1")
    (let [(staleRes (v/vfs-fenced-staged-write reg1 "src/test.asl" "agent-1" 0 "" "hello" 1500))]
      (assert (err? staleRes) "Stale token 0 write must be rejected")
      (let [(validRes (v/vfs-fenced-staged-write reg1 "src/test.asl" "agent-1" 1 buf1.casHash "hello" 1500))]
        (assert (ok? validRes) "Matching leaseToken 1 write must succeed")
        (let [(reg2 (resultOr validRes reg1))
              (reg3Res (v/vfs-acquire-lease reg2 "src/test.asl" "agent-2" 7000 5000))
              (reg3 (resultOr reg3Res reg2))
              (buf3 (optionOr (v/vfs-read reg3 "src/test.asl") (v/VFSBuffer :path "" :content "" :baseContent "" :casHash "" :baseHash "" :revision 0 :dirty false :loadedAt 0 :leaseHolder "" :leaseExpiresAt 0 :leaseToken 0)))]
          (assert (= buf3.leaseToken 2) "Subsequent lease acquisition must increment leaseToken to 2")
          (let [(staleRes2 (v/vfs-fenced-staged-write reg3 "src/test.asl" "agent-2" 1 buf3.casHash "world" 7500))]
            (assert (err? staleRes2) "Previous token 1 write must be rejected as stale against token 2")
            true)))))

fn testDiffReorderIsMinimal -> Bool
  (let [(reg1 (v/vfs-write (v/vfs-init) "r.txt" "a\nb"))
        (reg2 (v/vfs-write reg1 "r.txt" "b\na"))
        (buf (optionOr (v/vfs-read reg2 "r.txt") (v/VFSBuffer :path "" :content "" :baseContent "" :casHash "" :baseHash "" :revision 0 :dirty false :loadedAt 0 :leaseHolder "" :leaseExpiresAt 0 :leaseToken 0)))
        (d (v/vfs-diff buf))]
    (assert (= (listLength d) 3) "swapping two lines yields a three-line edit script, not four")
    (assert (= (optionOr (listGet d 0) "") "+b") "cur-only head line is added first")
    (assert (= (optionOr (listGet d 1) "") " a") "shared line kept")
    (assert (= (optionOr (listGet d 2) "") "-b") "base-only tail line removed last")
    true)

fn runTests -> Bool
  (and (testVfsInit) (and (testBufferCreationAndRead) (and (testCasContentAddressing) (and (testInMemoryOverwrites) (and (testDirtyBufferDiffing) (and (testBaseHeadAdvancesWhenCurrentHeadIsInBase) (and (testBrowserVfsStorage) (and (testFencedStagedWrite) (testDiffReorderIsMinimal)))))))))
