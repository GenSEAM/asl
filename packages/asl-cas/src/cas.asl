(module asl-cas/cas
  :x [Cas BlobStat GcReceipt casOpen! validHash? validOwner? blobPath put! putFile! get! has? stat! pin! unpin! pinsOf! gc!]
  :i [])

; (:m :ref DS-BLOBSTORE :do "a store root holds blobs/<h0h1>/<sha256> (two-hex fan-out), tmp/ for writes in flight and pins/<sha256>/<owner> markers; graceMs is how long an unpinned blob or a leftover tmp file survives gc")
(schema Cas (:f root String) (:f graceMs Int64))

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
                                    ((ok _) (ok (Cas :root root :graceMs graceMs)))))))))))

fn blobPath cas: Cas h: String -> String
  (str cas.root "/blobs/" (stringSlice h 0 2) "/" h)

fn pinDir cas: Cas h: String -> String
  (str cas.root "/pins/" h)

fn ! exists? p: String -> Bool
  (ok? (fileStat p))

; (:m :ref DS-BLOBSTORE :do "a blob already present is kept when it still hashes to its name (dedup, its mtime refreshed so a pending gc sees it young) and replaced when it does not; a new blob is written to tmp/, fsynced, renamed into place and its directory fsynced, so a crash leaves at most a tmp file gc removes and never a partial blob")
fn ! put! cas: Cas data: Bytes -> (Result String String)
  (let [(h (bytesSha256 data))
        (dest (blobPath cas h))
        (intact (match (fileReadBytes dest) ((ok b) (= (bytesSha256 b) h)) ((err _) false)))]
    (if intact
      (match (fileUtime dest (nowNs)) ((ok _) (ok h)) ((err e) (err (str "touch " dest ": " e))))
      (let [(tmp (str cas.root "/tmp/" h "." (stringFromInt64 (procSelf)) "." (stringFromInt64 (nowNs))))]
        (match (ensureDir! (str cas.root "/blobs/" (stringSlice h 0 2)))
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
                      ((ok _) (match (fileFsync (str cas.root "/blobs/" (stringSlice h 0 2)))
                                ((err e) (err (str "fsync dir of " h ": " e)))
                                ((ok _) (ok h))))))))))))))

fn ! putFile! cas: Cas path: String -> (Result String String)
  (match (fileReadBytes path)
    ((err e) (err (str "read " path ": " e)))
    ((ok b) (put! cas b)))

; (:m :ref DS-BLOBSTORE :do "get re-hashes what it read: a missing blob is none, a blob whose bytes no longer hash to its name is a labelled corrupt err, never returned")
fn ! get! cas: Cas h: String -> (Result (Option Bytes) String)
  (if (not (validHash? h)) (err (str "invalid hash " h))
    (if (not (exists? (blobPath cas h))) (ok (none))
      (match (fileReadBytes (blobPath cas h))
        ((err e) (err (str "read " h ": " e)))
        ((ok b) (let [(got (bytesSha256 b))]
                  (if (= got h) (ok (some b)) (err (str "corrupt blob " h ": content hashes to " got))))))))

fn ! has? cas: Cas h: String -> Bool
  (and (validHash? h) (exists? (blobPath cas h)))

fn ! pinsOf! cas: Cas h: String -> (List String)
  (if (not (validHash? h)) (list) (filter validOwner? (resultOr (dirList (pinDir cas h)) (list))))

fn ! stat! cas: Cas h: String -> (Option BlobStat)
  (if (not (validHash? h)) (none)
    (match (fileStat (blobPath cas h))
      ((err _) (none))
      ((ok st) (some (BlobStat :hash h :size st.size :pins (listLength (pinsOf! cas h)))))))

; (:m :ref DS-BLOBSTORE :do "pin records one marker per owner, so pinning twice by the same owner counts once; it returns the reference count after the change and refuses a blob that is not stored")
fn ! pin! cas: Cas h: String owner: String -> (Result Int64 String)
  (cond
    ((not (validHash? h)) (err (str "invalid hash " h)))
    ((not (validOwner? owner)) (err (str "invalid owner " owner)))
    ((not (has? cas h)) (err (str "no blob " h)))
    (else (match (ensureDir! (pinDir cas h))
            ((err e) (err e))
            ((ok _) (match (fileWrite (str (pinDir cas h) "/" owner) "")
                      ((err e) (err (str "pin " owner ": " e)))
                      ((ok _) (ok (listLength (pinsOf! cas h)))))))))

fn ! unpin! cas: Cas h: String owner: String -> (Result Int64 String)
  (cond
    ((not (validHash? h)) (err (str "invalid hash " h)))
    ((not (validOwner? owner)) (err (str "invalid owner " owner)))
    (else (let [(p (str (pinDir cas h) "/" owner))
                (_ (if (exists? p) (ok? (pathRemove p)) true))
                (left (pinsOf! cas h))
                (_ (if (listEmpty? left) (ok? (pathRemove (pinDir cas h))) true))]
            (if (exists? p) (err (str "unpin " owner ": marker still present")) (ok (listLength left))))))

fn ! old? p: String cutNs: Int64 -> Bool
  (match (fileStat p) ((ok st) (< st.mtimeNs cutNs)) ((err _) false))

fn ! blobsAll! cas: Cas -> (List String)
  (listFlatMap (fn [(d String)] -> (List String)
                 (filter validHash? (resultOr (dirList (str cas.root "/blobs/" d)) (list))))
               (resultOr (dirList (str cas.root "/blobs")) (list)))

; (:m :ref DS-BLOBSTORE :do "gc at nowNs removes a blob only when it has no pin and its mtime is older than graceMs, and tmp files older than graceMs (left by a crash between write and rename); a pinned blob is never removed")
fn ! gc! cas: Cas nowNs: Int64 -> GcReceipt
  (let [(cut (- nowNs (* cas.graceMs 1000000)))
        (blobs (blobsAll! cas))
        (pinned (filter (fn [(h String)] -> Bool (not (listEmpty? (pinsOf! cas h)))) blobs))
        (free (filter (fn [(h String)] -> Bool (listEmpty? (pinsOf! cas h))) blobs))
        (due (filter (fn [(h String)] -> Bool (old? (blobPath cas h) cut)) free))
        (results (map (fn [(h String)] -> (Pair String Bool) (pair h (ok? (pathRemove (blobPath cas h))))) due))
        (tmps (filter (fn [(t String)] -> Bool (old? (str cas.root "/tmp/" t) cut)) (resultOr (dirList (str cas.root "/tmp")) (list))))
        (tmpResults (map (fn [(t String)] -> (Pair String Bool) (pair t (ok? (pathRemove (str cas.root "/tmp/" t))))) tmps))]
    (GcReceipt :removed (map pairFirst (filter pairSecond results))
               :pinned (listLength pinned)
               :young (- (listLength free) (listLength due))
               :tmpRemoved (listLength (filter pairSecond tmpResults))
               :errors (listAppend (map (fn [(p (Pair String Bool))] -> String (blobPath cas (pairFirst p))) (filter (fn [(p (Pair String Bool))] -> Bool (not (pairSecond p))) results))
                                   (map (fn [(p (Pair String Bool))] -> String (str cas.root "/tmp/" (pairFirst p))) (filter (fn [(p (Pair String Bool))] -> Bool (not (pairSecond p))) tmpResults)))))
