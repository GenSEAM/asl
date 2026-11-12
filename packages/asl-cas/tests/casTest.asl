(module asl-cas/tests/casTest
  :x [runTests]
  :i [(asl-cas/cas :a cas)])

; (:m :ref DS-BLOBSTORE :do "every store lives in a scratch dir under the worktree's .asl/cache, never in ~/.asl, and is removed by an in-process tree walk")
fn ! scratch name: String -> String
  (str (resultOr (realPath ".") ".") "/.asl/cache/casTest-" (stringFromInt64 (procSelf)) "-" name)

fn ! rmTree! p: String -> Unit
  (match (fileStat p)
    ((err _) ())
    ((ok st) (let [(_ (if st.isDir (map (fn [(n String)] -> Unit (rmTree! (str p "/" n))) (resultOr (dirList p) (list))) (list)))
                   (_ (pathRemove p))]
               ())))

fn ! openOk! dir: String graceMs: Int64 -> cas/Cas
  (match (cas/casOpen! dir graceMs)
    ((ok c) c)
    ((err e) (do (assert false (str "open " dir ": " e)) (cas/Cas :root dir :graceMs graceMs))))

fn ! putOk! c: cas/Cas s: String -> String
  (match (cas/put! c (stringToBytes s))
    ((ok h) h)
    ((err e) (do (assert false (str "put " s ": " e)) "")))

; (:m :ref DS-BLOBSTORE :do "bytes are compared by length and sha256, since the runtime has no bytes-to-string builtin")
fn sig b: Bytes -> String
  (str (stringFromInt64 (bytesLength b)) ":" (bytesSha256 b))

fn want s: String -> String
  (sig (stringToBytes s))

fn ! getText! c: cas/Cas h: String -> String
  (match (cas/get! c h)
    ((ok (some b)) (sig b))
    ((ok (none)) "<none>")
    ((err e) (str "<err " e ">")))

fn ! fileCount! dir: String -> Int64
  (match (fileStat dir)
    ((err _) 0)
    ((ok st) (if st.isDir (fold (fn [(a Int64) (n String)] -> Int64 (+ a (fileCount! (str dir "/" n)))) 0 (resultOr (dirList dir) (list))) 1)))

fn bp c: cas/Cas h: String -> String
  (optionOr (cas/blobPath c h) "")

fn ! age! p: String -> Bool
  (ok? (fileUtime p (- (nowNs) 864000000000000)))

; (:m :ref DS-BLOBSTORE :do "put/get by sha256: the hash is the sha256 of the bytes, get returns them, a second put of the same bytes stores no second file, a missing blob is none and a malformed hash an err")
fn ! testPutGet! -> Bool
  (let [(dir (scratch "putget"))
        (_ (rmTree! dir))
        (c (openOk! dir 60000))
        (h (putOk! c "hello blob"))
        (h2 (putOk! c "hello blob"))
        (other (putOk! c "other blob"))
        (blobs (fileCount! (str dir "/blobs")))
        (tmps (fileCount! (str dir "/tmp")))
        (got (getText! c h))
        (missing (getText! c (bytesSha256 (stringToBytes "never stored"))))
        (bad (match (cas/get! c "../etc") ((err _) true) ((ok _) false)))
        (st (cas/stat! c h))
        (src (str dir "/source.txt"))
        (_ (fileWrite src "hello blob"))
        (fromFile (resultOr (cas/putFile! c src) ""))
        (_ (rmTree! dir))]
    (do (assert (= h (bytesSha256 (stringToBytes "hello blob"))) (str "the hash is the content sha256: " h))
        (assert (= got (want "hello blob")) (str "get returns the stored bytes: " got))
        (assert (= h h2) "a second put returns the same hash")
        (assert (= blobs 2) (str "two distinct contents, three puts: two blob files: " (stringFromInt64 blobs)))
        (assert (= tmps 0) (str "no tmp file is left after a put: " (stringFromInt64 tmps)))
        (assert (!= other h) "different bytes get a different hash")
        (assert (= missing "<none>") (str "a hash never stored is none: " missing))
        (assert bad "a malformed hash is an err, not a path")
        (assert (= fromFile h) "putFile! of the same bytes gives the same hash")
        (assert (and (cas/validHash? h) (not (cas/validHash? (stringUpper h)))) "validHash? takes lowercase hex sha256 only")
        (refute (or (cas/validOwner? "..") (cas/validOwner? "a/b")) "validOwner? refuses dot-dot and a slash")
        (assert (= (optionOr (optionMap (fn [(s cas/BlobStat)] -> Int64 s.size) st) -1) 10) "stat reports the size")
        true))

; (:m :ref DS-BLOBSTORE :do "a blob with one byte changed on disk is rejected on get with a corrupt err, and the next put of the true bytes repairs it")
fn ! testCorrupt! -> Bool
  (let [(dir (scratch "corrupt"))
        (_ (rmTree! dir))
        (c (openOk! dir 60000))
        (h (putOk! c "precious bytes"))
        (_ (fileWrite (bp c h) (stringToBytes "precious bytez")))
        (got (getText! c h))
        (h2 (putOk! c "precious bytes"))
        (again (getText! c h2))
        (_ (rmTree! dir))]
    (do (assert (stringStartsWith? got "<err corrupt blob ") (str "a flipped blob is rejected: " got))
        (assert (= again (want "precious bytes")) (str "a put over a corrupt blob rewrites it: " again))
        true))

; (:m :ref DS-BLOBSTORE :do "writes go through tmp/ and a rename: with tmp/ unusable a put fails and leaves no blob; a leftover tmp file from a crash is invisible to has? and get, the next put of those bytes succeeds, and gc removes the stale tmp file")
fn ! testAtomic! -> Bool
  (let [(dir (scratch "atomic"))
        (_ (rmTree! dir))
        (c (openOk! dir 60000))
        (_ (rmTree! (str dir "/tmp")))
        (_ (fileWrite (str dir "/tmp") "not a directory"))
        (blocked (cas/put! c (stringToBytes "half written")))
        (h (bytesSha256 (stringToBytes "half written")))
        (leftAfterFail (cas/has? c h))
        (_ (pathRemove (str dir "/tmp")))
        (_ (dirCreate (str dir "/tmp")))
        (crash (str dir "/tmp/" h ".1.1"))
        (_ (fileWrite crash "half"))
        (_ (age! crash))
        (seenBefore (cas/has? c h))
        (h2 (putOk! c "half written"))
        (got (getText! c h2))
        (r (cas/gc! c (nowNs)))
        (_ (rmTree! dir))]
    (do (assert (not (ok? blocked)) "a put whose tmp write fails is an err")
        (refute leftAfterFail "a failed put leaves no blob at its hash")
        (refute seenBefore "a crash leftover in tmp/ is not a blob")
        (assert (= got (want "half written")) (str "the next put succeeds and reads back: " got))
        (assert (= r.tmpRemoved 1) (str "gc removes the stale tmp file: " (stringFromInt64 r.tmpRemoved)))
        true))

; (:m :ref DS-BLOBSTORE :do "pins: one marker per owner, refcount after each change, pin of a missing blob and a path-like owner refused; gc removes only unpinned blobs older than the grace period, and a re-put refreshes a blob's age")
fn ! testPinsGc! -> Bool
  (let [(dir (scratch "gc"))
        (_ (rmTree! dir))
        (c (openOk! dir 60000))
        (a (putOk! c "pinned old"))
        (b (putOk! c "unpinned old"))
        (y (putOk! c "unpinned young"))
        (r (putOk! c "re-put old"))
        (p1 (resultOr (cas/pin! c a "manifest") -1))
        (p2 (resultOr (cas/pin! c a "manifest") -1))
        (p3 (resultOr (cas/pin! c a "run.7") -1))
        (u1 (resultOr (cas/unpin! c a "run.7") -1))
        (noBlob (ok? (cas/pin! c (bytesSha256 (stringToBytes "absent")) "manifest")))
        (badOwner (ok? (cas/pin! c a "../x")))
        (_ (age! (bp c a)))
        (_ (age! (bp c b)))
        (_ (age! (bp c r)))
        (r2 (putOk! c "re-put old"))
        (g (cas/gc! c (nowNs)))
        (alive (map (fn [(h String)] -> Bool (cas/has? c h)) (list a b y r)))
        (_ (rmTree! dir))]
    (do (assert (= (list p1 p2 p3 u1) (list 1 1 2 1)) (str "refcounts after pin, same pin, second owner, unpin: " (stringJoin (map stringFromInt64 (list p1 p2 p3 u1)) ",")))
        (refute noBlob "a missing blob cannot be pinned")
        (refute badOwner "an owner id with a path separator is refused")
        (assert (= r r2) "the re-put returns the same hash")
        (assert (= g.removed (list b)) (str "only the unpinned old blob is removed: " (stringJoin g.removed ",")))
        (assert (= alive (list true false true true)) (str "pinned, removed, young, re-put: " (stringJoin (map (fn [(x Bool)] -> String (if x "1" "0")) alive) ",")))
        (assert (= (list g.pinned g.young) (list 1 2)) (str "receipt counts pinned 1, young 2: " (stringFromInt64 g.pinned) "," (stringFromInt64 g.young)))
        true))

; (:m :ref DS-BLOBSTORE :do "property: 200 pin and unpin steps from a fixed LCG over 5 blobs and 3 owners with a gc (grace 0) every 10 steps, a pin of a removed blob putting it again first; a model of pins and presence must match the store after every step, so gc never removes a blob with a live pin")
fn lcg x: Int64 -> Int64
  (mod (+ (* x 1103515245) 12345) 2147483648)

schema Model (:f seed Int64) (:f pins (List String)) (:f present (List String)) (:f bad Int64) (:f removed Int64)

fn key h: String o: String -> String
  (str h "/" o)

fn ! step! c: cas/Cas hs: (List String) os: (List String) m: Model i: Int64 -> Model
  (let [(s1 (lcg m.seed)) (s2 (lcg s1)) (s3 (lcg s2))
        (idx (mod (/ s1 65536) 5))
        (h (optionOr (listGet hs idx) ""))
        (o (optionOr (listGet os (mod (/ s2 65536) 3)) ""))
        (doPin (= (mod (/ s3 65536) 2) 0))
        (k (key h o))
        (wasHere (listContains? m.present h))
        (reput (if (and doPin (not wasHere)) (ok? (cas/put! c (stringToBytes (str "blob " (stringFromInt64 idx))))) false))
        (here (or wasHere reput))
        (res (if doPin (cas/pin! c h o) (cas/unpin! c h o)))
        (pins1 (if doPin (if (and here (not (listContains? m.pins k))) (listAppend m.pins (list k)) m.pins) (filter (fn [(x String)] -> Bool (!= x k)) m.pins)))
        (okExpected (or (not doPin) here))
        (gcNow (= (mod (+ i 1) 10) 0))
        (g (if gcNow (cas/gc! c (+ (nowNs) 1000000000)) (cas/GcReceipt :removed (list) :pinned 0 :young 0 :tmpRemoved 0 :errors (list))))
        (present1 (filter (fn [(x String)] -> Bool (not (listContains? g.removed x))) (if (and reput (not wasHere)) (listAppend m.present (list h)) m.present)))
        (refs (fn [(x String)] -> Int64 (listLength (filter (fn [(p String)] -> Bool (stringStartsWith? p (str x "/"))) pins1))))
        (lostPinned (listAny? (fn [(x String)] -> Bool (and (> (refs x) 0) (not (cas/has? c x)))) hs))
        (countsOff (listAny? (fn [(x String)] -> Bool (and (cas/has? c x) (!= (refs x) (listLength (resultOr (cas/pinsOf! c x) (list "unreadable")))))) hs))
        (presenceOff (listAny? (fn [(x String)] -> Bool (!= (listContains? present1 x) (cas/has? c x))) hs))
        (bad (+ m.bad (if (or (!= (ok? res) okExpected) (or lostPinned (or countsOff presenceOff))) 1 0)))]
    (Model :seed s3 :pins pins1 :present present1 :bad bad :removed (+ m.removed (listLength g.removed))))

fn ! testProperty! -> Bool
  (let [(dir (scratch "prop"))
        (_ (rmTree! dir))
        (c (openOk! dir 0))
        (hs (map (fn [(i Int64)] -> String (putOk! c (str "blob " (stringFromInt64 i)))) (range 0 5)))
        (os (list "manifest" "run.1" "library"))
        (end (fold (fn [(m Model) (i Int64)] -> Model (step! c hs os m i)) (Model :seed 42 :pins (list) :present hs :bad 0 :removed 0) (range 0 200)))
        (_ (rmTree! dir))]
    (do (assert (= end.bad 0) (str "steps where the store and the model disagree: " (stringFromInt64 end.bad)))
        (assert (> end.removed 2) (str "gc removed unpinned blobs over the run: " (stringFromInt64 end.removed)))
        (assert (> (listLength end.pins) 0) (str "pins are live at the end: " (stringFromInt64 (listLength end.pins))))
        true))

; (:m :ref DS-BLOBSTORE :do "layout: a blob lives at blobs/<first two hex>/<sha256> on disk, blobs/ holds only two-character fan-out directories, and blobPath refuses a malformed hash")
fn ! testLayout! -> Bool
  (let [(dir (scratch "layout"))
        (_ (rmTree! dir))
        (c (openOk! dir 60000))
        (h (putOk! c "layout bytes"))
        (fan (optionOr (stringSlice h 0 2) "??"))
        (fans (resultOr (dirList (str dir "/blobs")) (list)))
        (onDisk (ok? (fileStat (str dir "/blobs/" fan "/" h))))
        (_ (rmTree! dir))]
    (do (assert (= fans (list fan)) (str "the only fan-out directory is the two hex digits " fan ": " (stringJoin fans ",")))
        (assert onDisk "the blob file is blobs/<h0h1>/<sha256>")
        (assert (= (bp c h) (str dir "/blobs/" fan "/" h)) (str "blobPath names that file: " (bp c h)))
        (refute (some? (cas/blobPath c "../../etc/passwd")) "blobPath refuses a malformed hash")
        true))

; (:m :ref DS-BLOBSTORE :do "a pinned old blob whose pin directory cannot be listed (mode 000) is kept by gc and reported in :errors; pinsOf! is an err, not an empty list; the mode is restored before cleanup")
fn ! testUnlistablePins! -> Bool
  (let [(dir (scratch "unlistable"))
        (_ (rmTree! dir))
        (c (openOk! dir 60000))
        (a (putOk! c "pinned but unreadable"))
        (_ (cas/pin! c a "manifest"))
        (_ (age! (bp c a)))
        (pd (str dir "/pins/" a))
        (_ (fileChmod pd 0))
        (pins (cas/pinsOf! c a))
        (g (cas/gc! c (nowNs)))
        (kept (cas/has? c a))
        (_ (fileChmod pd 493))
        (_ (rmTree! dir))]
    (do (refute (ok? pins) "an unlistable pin directory is an err from pinsOf!")
        (assert kept "gc keeps a blob whose pins it cannot read")
        (assert (listEmpty? g.removed) (str "nothing removed: " (stringJoin g.removed ",")))
        (assert (listAny? (fn [(e String)] -> Bool (stringContains? e (str "pins of " a))) g.errors) (str "the unreadable pins are reported: " (stringJoin g.errors " | ")))
        true))

; (:m :ref DS-BLOBSTORE :do "gc rechecks before each removal: a pin! and a dedup put! that land after gc planned (through the gcWith! hook) keep their blobs, while an untouched old unpinned blob in the same pass goes")
fn ! testRecheck! -> Bool
  (let [(dir (scratch "recheck"))
        (_ (rmTree! dir))
        (c (openOk! dir 60000))
        (pinned (putOk! c "pinned during gc"))
        (reput (putOk! c "put again during gc"))
        (gone (putOk! c "nobody wants me"))
        (_ (map (fn [(h String)] -> Bool (age! (bp c h))) (list pinned reput gone)))
        (g (cas/gcWith! c (nowNs) (fn [] -> Unit (let [(_ (cas/pin! c pinned "late")) (_ (cas/put! c (stringToBytes "put again during gc")))] ()))))
        (alive (map (fn [(h String)] -> Bool (cas/has? c h)) (list pinned reput gone)))
        (_ (rmTree! dir))]
    (do (assert (= alive (list true true false)) (str "late pin kept, late put kept, untouched removed: " (stringJoin (map (fn [(x Bool)] -> String (if x "1" "0")) alive) ",")))
        (assert (= g.removed (list gone)) (str "the receipt removes only the untouched blob: " (stringJoin g.removed ",")))
        true))

fn ! runTests -> Bool
  (do (assert (testPutGet!) "put and get by sha256")
      (assert (testCorrupt!) "corrupt blob detected on read")
      (assert (testAtomic!) "atomic write through tmp and rename")
      (assert (testPinsGc!) "pins and gc with a grace period")
      (assert (testProperty!) "gc never removes a pinned blob over 200 random steps")
      (assert (testLayout!) "on-disk fan-out layout and blobPath validation")
      (assert (testUnlistablePins!) "gc keeps a blob whose pins cannot be listed")
      (assert (testRecheck!) "gc rechecks pins and age before each removal")
      true)
