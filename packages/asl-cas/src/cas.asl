(module asl-cas/cas
  :x [Cas BlobStat GcReceipt casOpen! validHash? validOwner? blobPath put! putFile! get! has? stat! pin! unpin! pinsOf! gc! gcWith!]
  :i [])

; (:m :ref DS-BLOBSTORE :do "a store root holds blobs/<h0h1>/<sha256> (two-hex fan-out), tmp/ for writes in flight and pins/<sha256>/<owner> markers; graceMs is how long an unpinned blob or a leftover tmp file survives gc")
; (:m :ref DSBLOB-LOWS :do "lockWaitMs bounds how long pin!, a dedup put! and gc wait for the store lock root/lock before giving up with a busy err")
(schema Cas (:f root String) (:f graceMs Int64) (:f lockWaitMs Int64))

(schema BlobStat (:f hash String) (:f size Int64) (:f pins Int64))

; (:m :ref DS-BLOBSTORE :do "what one gc did: blobs removed, blobs kept because pinned or younger than the grace period, leftover tmp files removed, and every path that failed")
(schema GcReceipt (:f removed (List String)) (:f pinned Int64) (:f young Int64) (:f tmpRemoved Int64) (:f errors (List String)))

fn hexChar? c: String -> Bool
  (stringContains? "0123456789abcdef" c)

fn validHash? h: String -> Bool
  (and (= (stringLength h) 64) (listAll? hexChar? (stringChars h)))

fn ownerChar? c: String -> Bool
  (stringContains? "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-" c)

; (:m :ref DS-BLOBSTORE :do "an owner id names a marker file, so it is 1..128 characters of letters, digits, dot, underscore and dash and not . or ..")
fn validOwner? o: String -> Bool
  (and (> (stringLength o) 0) (and (<= (stringLength o) 128) (and (not (or (= o ".") (= o ".."))) (listAll? ownerChar? (stringChars o)))))

fn ! ensureDir! p: String -> (Result Unit String)
  (match (fileStat p)
    ((ok st) (if st.isDir (ok ()) (err (str p ": not a directory"))))
    ((err _) (match (dirCreate p) ((ok _) (ok ())) ((err e) (match (fileStat p) ((ok st) (if st.isDir (ok ()) (err e))) ((err _) (err (str p ": " e))))))))

fn ! casOpen! root: String graceMs: Int64 -> (Result Cas String)
  (if (< graceMs 0) (err (str "graceMs " (stringFromInt64 graceMs) " is negative"))
    (match (ensureDir! root)
      ((err e) (err e))
      ((ok _) (match (ensureDir! (str root "/blobs"))
                ((err e) (err e))
                ((ok _) (match (ensureDir! (str root "/tmp"))
                          ((err e) (err e))
                          ((ok _) (match (ensureDir! (str root "/pins"))
                                    ((err e) (err e))
                                    ((ok _) (ok (Cas :root root :graceMs graceMs :lockWaitMs 10000)))))))))))

; (:m :ref DS-BLOBSTORE :do "the fan-out directory is the first two hex digits of the hash")
fn fanOf h: String -> String
  (optionOr (stringSlice h 0 2) "")

fn blobFile cas: Cas h: String -> String
  (str cas.root "/blobs/" (fanOf h) "/" h)

; (:m :ref DS-BLOBSTORE :do "the path of a blob for a well-formed hash only, so a caller never turns a name into a path outside blobs/")
fn blobPath cas: Cas h: String -> (Option String)
  (if (validHash? h) (some (blobFile cas h)) (none))

fn pinDir cas: Cas h: String -> String
  (str cas.root "/pins/" h)

fn ! exists? p: String -> Bool
  (ok? (fileStat p))

; (:m :ref DSBLOB-LOWS :do "the store lock is an flock on root/lock, released by fdClose or by the holder's death, so a crashed holder never wedges the store; it serialises pin!, the dedup touch in put! and gc's recheck-and-remove, which closes the window where a pin landing after gc's recheck lost its blob")
fn ! lockUntil! path: String untilNs: Int64 -> (Result Int64 String)
  (match (fileLock path true)
    ((ok fd) (ok fd))
    ((err e) (cond
               ((!= e "busy") (err (str "store lock " path ": " e)))
               ((< (monotonicNs) untilNs) (do (sleepMs 10) (lockUntil! path untilNs)))
               (else (err (str "store lock " path ": busy"))))))

fn ! lockStore! cas: Cas -> (Result Int64 String)
  (lockUntil! (str cas.root "/lock") (+ (monotonicNs) (* (max 0 cas.lockWaitMs) 1000000)))

fn ! intact? dest: String h: String -> Bool
  (match (fileReadBytes dest) ((ok b) (= (bytesSha256 b) h)) ((err _) false))

; (:m :ref DSBLOB-LOWS :do "the dedup touch takes the store lock and re-reads the blob under it, so gc cannot remove it between the intact check and the touch; ok true is a kept copy, ok false a blob that must be written")
fn ! touchIntact! cas: Cas dest: String h: String -> (Result Bool String)
  (match (lockStore! cas)
    ((err e) (err e))
    ((ok fd) (let [(r (if (intact? dest h)
                        (match (fileUtime dest (nowNs)) ((ok _) (ok true)) ((err e) (err (str "touch " dest ": " e))))
                        (ok false)))
                   (_ (fdClose fd))]
               r)))

; (:m :ref DS-BLOBSTORE :do "a blob already present is kept when it still hashes to its name (dedup, its mtime refreshed so a pending gc sees it young) and replaced when it does not; a new blob is written to tmp/, fsynced, renamed into place and its directory fsynced, so a crash leaves at most a tmp file gc removes and never a partial blob")
fn ! put! cas: Cas data: Bytes -> (Result String String)
  (let [(h (bytesSha256 data))
        (dest (blobFile cas h))
        (fan (str cas.root "/blobs/" (fanOf h)))
        (kept (if (intact? dest h) (touchIntact! cas dest h) (ok false)))]
    (match kept ((err e) (err e)) ((ok k) (if k (ok h)
      (let [(tmp (str cas.root "/tmp/" h "." (stringFromInt64 (procSelf)) "." (stringFromInt64 (nowNs))))]
        (match (ensureDir! fan)
          ((err e) (err e))
          ((ok _)
            (match (fileWrite tmp data)
              ((err e) (do (pathRemove tmp) (err (str "write " tmp ": " e))))
              ((ok _)
                (match (fileFsync tmp)
                  ((err e) (do (pathRemove tmp) (err (str "fsync " tmp ": " e))))
                  ((ok _)
                    (match (pathRename tmp dest)
                      ((err e) (do (pathRemove tmp) (err (str "rename " tmp ": " e))))
                      ((ok _) (match (fileFsync fan)
                                ((err e) (err (str "fsync dir of " h ": " e)))
                                ((ok _) (ok h))))))))))))))))

fn ! putFile! cas: Cas path: String -> (Result String String)
  (match (fileReadBytes path)
    ((err e) (err (str "read " path ": " e)))
    ((ok b) (put! cas b)))

; (:m :ref DS-BLOBSTORE :do "get re-hashes what it read: a missing blob is none, a blob whose bytes no longer hash to its name is a labelled corrupt err, never returned")
fn ! get! cas: Cas h: String -> (Result (Option Bytes) String)
  (if (not (validHash? h)) (err (str "invalid hash " h))
    (if (not (exists? (blobFile cas h))) (ok (none))
      (match (fileReadBytes (blobFile cas h))
        ((err e) (err (str "read " h ": " e)))
        ((ok b) (let [(got (bytesSha256 b))]
                  (if (= got h) (ok (some b)) (err (str "corrupt blob " h ": content hashes to " got))))))))

fn ! has? cas: Cas h: String -> Bool
  (and (validHash? h) (exists? (blobFile cas h)))

; (:m :ref DSBLOB-LOWS :do "the kind comes from the prelude's typed IoError classifier, the runtime's one mapping of error text to kinds, and casTest pins that a missing path still classifies as notFound")
fn notFound? e: String -> Bool
  (= (preludeIoError e) (notFound))

; (:m :ref DS-BLOBSTORE :do "the owners pinning a blob: only a pin directory that is not found is no pins; any other stat error (EACCES or EIO on the pin directory, on pins/ or on an ancestor) and a pin directory that cannot be listed are an err, never an empty list, so gc cannot read them as unpinned")
fn ! pinsOf! cas: Cas h: String -> (Result (List String) String)
  (if (not (validHash? h)) (err (str "invalid hash " h))
    (match (fileStat (pinDir cas h))
      ((err e) (if (notFound? e) (ok (list)) (err (str "pins of " h ": " e))))
      ((ok _) (match (dirList (pinDir cas h))
                ((ok ns) (ok (filter validOwner? ns)))
                ((err e) (err (str "pins of " h ": " e)))))))

fn countOf r: (Result (List String) String) -> (Result Int64 String)
  (match r ((ok ps) (ok (listLength ps))) ((err e) (err e)))

; (:m :ref DS-BLOBSTORE :do "stat reports -1 pins when the pin directory cannot be listed")
fn ! stat! cas: Cas h: String -> (Option BlobStat)
  (if (not (validHash? h)) (none)
    (match (fileStat (blobFile cas h))
      ((err _) (none))
      ((ok st) (some (BlobStat :hash h :size st.size :pins (resultOr (countOf (pinsOf! cas h)) -1))))))

; (:m :ref DS-BLOBSTORE :do "pin records one marker per owner, so pinning twice by the same owner counts once; it returns the reference count after the change and refuses a blob that is not stored; the stored check and the marker write run under the store lock, so a gc never removes a blob a returned pin! holds")
fn ! pin! cas: Cas h: String owner: String -> (Result Int64 String)
  (cond
    ((not (validHash? h)) (err (str "invalid hash " h)))
    ((not (validOwner? owner)) (err (str "invalid owner " owner)))
    (else (match (lockStore! cas)
            ((err e) (err (str "pin " owner ": " e)))
            ((ok fd) (let [(r (pinLocked! cas h owner)) (_ (fdClose fd))] r)))))

fn ! pinLocked! cas: Cas h: String owner: String -> (Result Int64 String)
  (if (not (has? cas h)) (err (str "no blob " h))
    (match (ensureDir! (pinDir cas h))
      ((err e) (err e))
      ((ok _) (match (fileWrite (str (pinDir cas h) "/" owner) "")
                ((err e) (err (str "pin " owner ": " e)))
                ((ok _) (countOf (pinsOf! cas h)))))))

fn ! unpin! cas: Cas h: String owner: String -> (Result Int64 String)
  (cond
    ((not (validHash? h)) (err (str "invalid hash " h)))
    ((not (validOwner? owner)) (err (str "invalid owner " owner)))
    (else (match (lockStore! cas)
            ((err e) (err (str "unpin " owner ": " e)))
            ((ok fd) (let [(r (unpinLocked! cas h owner)) (_ (fdClose fd))] r)))))

; (:m :ref DSBLOB-LOWS :do "unpin runs under the store lock, so a pin! cannot add a marker between the empty pins read and the pin directory remove")
fn ! unpinLocked! cas: Cas h: String owner: String -> (Result Int64 String)
  (let [(p (str (pinDir cas h) "/" owner))
        (_ (if (exists? p) (ok? (pathRemove p)) true))
        (left (pinsOf! cas h))
        (_ (match left ((ok ps) (if (listEmpty? ps) (ok? (pathRemove (pinDir cas h))) true)) ((err _) true)))]
    (if (exists? p) (err (str "unpin " owner ": marker still present")) (countOf left)))

fn ! old? p: String cutNs: Int64 -> Bool
  (match (fileStat p) ((ok st) (< st.mtimeNs cutNs)) ((err _) false))

fn ! listing! dir: String -> (Result (List String) String)
  (match (dirList dir) ((ok ns) (ok ns)) ((err e) (err (str "list " dir ": " e))))

; (:m :ref DS-BLOBSTORE :do "every blob under every fan-out directory, and the listing errors: a directory that cannot be listed is reported, its blobs are neither counted nor removed")
fn ! blobsAll! cas: Cas -> (Pair (List String) (List String))
  (match (listing! (str cas.root "/blobs"))
    ((err e) (pair (list) (list e)))
    ((ok fans) (fold (fn [(acc (Pair (List String) (List String))) (d String)] -> (Pair (List String) (List String))
                       (match (listing! (str cas.root "/blobs/" d))
                         ((ok ns) (pair (listAppend (pairFirst acc) (filter validHash? ns)) (pairSecond acc)))
                         ((err e) (pair (pairFirst acc) (listAppend (pairSecond acc) (list e))))))
                     (pair (list) (list)) fans)))

fn ! unpinned? cas: Cas h: String -> Bool
  (match (pinsOf! cas h) ((ok ps) (listEmpty? ps)) ((err _) false))

; (:m :ref DS-BLOBSTORE :do "gc at nowNs removes a blob only when it has no pin and its mtime is older than graceMs, and tmp files older than graceMs (left by a crash between write and rename); a pinned blob is never removed, a blob whose pins cannot be read is kept and reported in :errors")
fn ! gc! cas: Cas nowNs: Int64 -> GcReceipt
  (gcWith! cas nowNs (fn [] -> Unit ()))

fn freeOf p: (Pair String (Result (List String) String)) -> Bool
  (match (pairSecond p) ((ok ps) (listEmpty? ps)) ((err _) false))

fn pinnedOf p: (Pair String (Result (List String) String)) -> Bool
  (match (pairSecond p) ((ok ps) (not (listEmpty? ps))) ((err _) false))

fn pinErrOf p: (Pair String (Result (List String) String)) -> (List String)
  (match (pairSecond p) ((ok _) (list)) ((err e) (list e)))

fn failedOf rs: (List (Pair String Bool)) -> (List String)
  (map pairFirst (filter (fn [(p (Pair String Bool))] -> Bool (not (pairSecond p))) rs))

; (:m :ref DS-BLOBSTORE :do "gc! with a hook run after the plan and before any removal, where a concurrent pin! or dedup put! can land: pins and age are read again right before each removal, so such a blob is kept; the recheck and the removals run under the store lock that pin! and a dedup put! also take, so neither can land between a recheck and its pathRemove; a lock still busy after lockWaitMs removes no blob and is reported in :errors. gc starts only when pins/ itself lists: an unreadable pins/ removes nothing and is reported. :young counts the unpinned blobs kept for age at plan time")
fn ! gcWith! cas: Cas nowNs: Int64 between: (fn ! [] -> Unit) -> GcReceipt
  (match (listing! (str cas.root "/pins"))
    ((err e) (GcReceipt :removed (list) :pinned 0 :young 0 :tmpRemoved 0 :errors (list e)))
    ((ok _) (gcPlanned! cas nowNs between)))

fn ! gcPlanned! cas: Cas nowNs: Int64 between: (fn ! [] -> Unit) -> GcReceipt
  (let [(cut (- nowNs (* cas.graceMs 1000000)))
        (all (blobsAll! cas))
        (pinRead (map (fn [(h String)] -> (Pair String (Result (List String) String)) (pair h (pinsOf! cas h))) (pairFirst all)))
        (free (map pairFirst (filter freeOf pinRead)))
        (due (filter (fn [(h String)] -> Bool (old? (blobFile cas h) cut)) free))
        (_ (between))
        (lock (if (listEmpty? due) (ok -1) (lockStore! cas)))
        (still (match lock ((ok _) (filter (fn [(h String)] -> Bool (and (unpinned? cas h) (old? (blobFile cas h) cut))) due)) ((err _) (list))))
        (results (map (fn [(h String)] -> (Pair String Bool) (pair h (ok? (pathRemove (blobFile cas h))))) still))
        (_ (match lock ((ok fd) (if (>= fd 0) (ok? (fdClose fd)) true)) ((err _) true)))
        (tmpList (listing! (str cas.root "/tmp")))
        (tmps (filter (fn [(t String)] -> Bool (old? (str cas.root "/tmp/" t) cut)) (resultOr tmpList (list))))
        (tmpResults (map (fn [(t String)] -> (Pair String Bool) (pair t (ok? (pathRemove (str cas.root "/tmp/" t))))) tmps))]
    (GcReceipt :removed (map pairFirst (filter pairSecond results))
               :pinned (listLength (filter pinnedOf pinRead))
               :young (- (listLength free) (listLength due))
               :tmpRemoved (listLength (filter pairSecond tmpResults))
               :errors (listAppend (listAppend (listAppend (pairSecond all) (listFlatMap pinErrOf pinRead)) (match lock ((err e) (list e)) ((ok _) (list))))
                                   (listAppend (match tmpList ((err e) (list e)) ((ok _) (list)))
                                               (listAppend (map (fn [(h String)] -> String (blobFile cas h)) (failedOf results))
                                                           (map (fn [(t String)] -> String (str cas.root "/tmp/" t)) (failedOf tmpResults)))))))
