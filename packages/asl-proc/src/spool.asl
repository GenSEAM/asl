(module asl-proc/spool :x [RingBuffer DiskSpool TwoTierSpool makeRingBuffer ringPush ringTail ringSize ringToString makeDiskSpool spoolWrite spoolSync! spoolWriteSync! spoolTruncate spoolUnlink! spoolPathRelease! spoolIsUnlinked? makeTwoTierSpool twoTierPush twoTierClose spoolDirname twoTierCloseSync! spoolBaseDir! reserveSpoolPath!] :i [(reducer :a red)])

(schema RingBuffer (:f capacity Int64) (:f lines (List String)) (:f count Int64))

fn makeRingBuffer capacity: Int64 -> RingBuffer
  (RingBuffer :capacity (if (<= capacity 0) 200 capacity) :lines (list) :count 0)

fn ringPush rb: RingBuffer line: String -> RingBuffer
  (let [(cap rb.capacity) (cur rb.lines) (cnt rb.count)] (if (< cnt cap) (RingBuffer :capacity cap :lines (listAppend cur (list line)) :count (+ cnt 1)) (let [(evictedTail (optionOr (listSlice cur 1 cnt) (list)))] (RingBuffer :capacity cap :lines (listAppend evictedTail (list line)) :count cap))))

fn ringTail rb: RingBuffer n: Int64 -> (List String)
  (let [(cur rb.lines) (cnt rb.count)] (cond ((<= n 0) (list)) ((>= n cnt) cur) (else (optionOr (listSlice cur (- cnt n) cnt) (list)))))

fn ringSize rb: RingBuffer -> Int64
  rb.count

fn ringToString rb: RingBuffer -> String
  (stringJoin rb.lines "\n")

(schema DiskSpool (:f path String) (:f maxBytes Int64) (:f currentBytes Int64) (:f content String) (:f isUnlinked Bool) (:f truncated Bool))

fn makeDiskSpool path: String maxBytes: Int64 -> DiskSpool
  (DiskSpool :path path :maxBytes (if (<= maxBytes 0) 10485760 maxBytes) :currentBytes 0 :content "" :isUnlinked false :truncated false)

fn spoolWrite spool: DiskSpool chunk: String -> DiskSpool
  (let [(chunkLen (int32ToInt64 (stringLength chunk)))] (if (<= chunkLen 0) spool (let [(cap spool.maxBytes) (curLen spool.currentBytes)] (if (>= chunkLen cap) (let [(truncatedContent (optionOr (stringSlice chunk (- chunkLen cap) chunkLen) ""))] (with spool :maxBytes cap :currentBytes cap :content truncatedContent :isUnlinked false :truncated (or (> chunkLen cap) (> curLen 0)))) (let [(combLen (+ curLen chunkLen))] (if (<= combLen cap) (with spool :maxBytes cap :currentBytes combLen :content (str spool.content chunk) :isUnlinked false) (let [(keepLen (- cap chunkLen)) (headRetained (optionOr (stringSlice spool.content (- curLen keepLen) curLen) "")) (truncatedContent (str headRetained chunk))] (with spool :maxBytes cap :currentBytes cap :content truncatedContent :isUnlinked false :truncated true))))))))

fn ! spoolSync! spool: DiskSpool -> (Result DiskSpool String)
  (mt (fileWrite spool.path spool.content) ((ok _) (ok spool)) ((err e) (err (str "Failed to sync disk spool to " spool.path ": " e))))

fn ! spoolWriteSync! spool: DiskSpool chunk: String -> (Result DiskSpool String)
  (let [(w (spoolWrite spool chunk))] (spoolSync! w))

fn spoolTruncate spool: DiskSpool -> DiskSpool
  (let [(len spool.currentBytes) (cap spool.maxBytes)] (if (<= len cap) spool (let [(txt spool.content) (start (- len cap)) (truncatedContent (optionOr (stringSlice txt start len) ""))] (with spool :maxBytes cap :currentBytes cap :content truncatedContent :truncated true))))

fn ! spoolUnlink! spool: DiskSpool -> (Result DiskSpool String)
  (mt (pathRemove spool.path)
    ((ok _) (ok (with spool :currentBytes 0 :content "" :isUnlinked true)))
    ((err e) (if (stringStartsWith? e "notFound") (ok (with spool :currentBytes 0 :content "" :isUnlinked true)) (err (str "Failed to unlink disk spool at " spool.path ": " e)))))

fn ! spoolPathRelease! path: String -> (Result Unit String)
  (mt (pathRemove path)
    ((ok _) (ok ()))
    ((err e) (if (stringStartsWith? e "notFound") (ok ()) (err (str "Failed to release spool path " path ": " e)))))

fn spoolIsUnlinked? spool: DiskSpool -> Bool
  spool.isUnlinked

(schema TwoTierSpool (:f ring RingBuffer) (:f disk DiskSpool))

fn makeTwoTierSpool path: String ringCap: Int64 diskCap: Int64 -> TwoTierSpool
  (TwoTierSpool :ring (makeRingBuffer ringCap) :disk (makeDiskSpool path diskCap))

fn twoTierPush s: TwoTierSpool line: String -> TwoTierSpool
  (let [(newRing (ringPush s.ring line)) (newDisk (spoolWrite s.disk line))] (TwoTierSpool :ring newRing :disk newDisk))

fn twoTierClose s: TwoTierSpool -> TwoTierSpool
  (with s :disk (DiskSpool :path s.disk.path :maxBytes s.disk.maxBytes :currentBytes s.disk.currentBytes :content s.disk.content :isUnlinked true :truncated s.disk.truncated))

fn spoolDirname path: String -> String
  (let [(parts (stringSplit path "/"))] (if (<= (listLength parts) 1) "" (stringJoin (listTake parts (- (listLength parts) 1)) "/")))

fn ! twoTierCloseSync! s: TwoTierSpool -> (Result TwoTierSpool String)
  (let [(disk s.disk) (dir (spoolDirname disk.path)) (dirRes (if (stringEmpty? dir) (ok ()) (dirCreate dir)))]
    (mt dirRes
      ((err e) (err (str "Failed to create spool directory " dir ": " e)))
      ((ok _) (mt (spoolSync! disk)
                ((ok syncedDisk) (ok (with s :disk (DiskSpool :path syncedDisk.path :maxBytes syncedDisk.maxBytes :currentBytes syncedDisk.currentBytes :content syncedDisk.content :isUnlinked false :truncated syncedDisk.truncated))))
                ((err e) (let [(_ (pathRemove disk.path))] (err e)))))))

fn ! spoolBaseDir! -> (Result String String)
  (let [(dir (str (optionOr (envGet "TMPDIR") "/tmp") "/asl-proc"))] (mt (dirCreate dir) ((ok _) (ok dir)) ((err e) (err (str "Failed to create spool base directory " dir ": " e)))))

fn ! reserveSpoolPath! bin: String attempt: Int64 -> (Result String String)
  (if (> attempt 500)
    (err (str "could not reserve a unique spool path for " bin " after 500 attempts"))
    (mt (spoolBaseDir!)
      ((err e) (err e))
      ((ok baseDir) (let [(candidate (red/generateSpoolPath bin (+ (monotonicNs) attempt) baseDir))]
        (mt (fileCreateExclusive candidate "")
          ((ok _) (ok candidate))
          ((err _) (reserveSpoolPath! bin (+ attempt 1))))))))
