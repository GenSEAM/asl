(module asl-store-fs/fs
  :x [FsStore fsOpen! fsOpenWith! fsCall! fsFault!]
  :i [(asl-store/types :a ty) (asl-store/kv :a kv) (asl-store-fs/log :a lg) (asl-store-fs/wal :a wal)])

; (:m :ref VS-CORE :do "an open store is only a root and the log settings; every fact lives on disk, so a second process or a reopened store sees the same rows and a crash needs no replay")
(schema FsStore (:f root String) (:f cfg lg/LogCfg))

fn ! fsOpenWith! root: String segmentMax: Int64 recover: (fn [String Int64] -> lg/Recovered) -> (Result FsStore String)
  (if (< segmentMax 1)
    (err "segmentMax must be at least 1")
    (match (lg/ensureTree! (str root "/kv"))
      ((err e) (err e))
      ((ok _) (match (lg/ensureTree! (str root "/log"))
                ((err e) (err e))
                ((ok _) (ok (FsStore :root root :cfg (lg/LogCfg :root root :segmentMax segmentMax :lockWaitMs 10000 :recover recover))))))))

fn ! fsOpen! root: String segmentMax: Int64 -> (Result FsStore String)
  (fsOpenWith! root segmentMax (lg/defaultRecover))

fn rowPath st: FsStore k: ty/Key -> String
  (str st.root "/kv/" k.collection "/" k.id ".row")

fn headerOf e: kv/Entry -> String
  (str "asl-store-row " (stringFromInt64 e.rev) " " (stringFromInt64 e.expiresAt) "\n")

fn parseRow text: String -> (Option kv/Entry)
  (match (stringIndexOf text "\n")
    ((none) (none))
    ((some i)
      (let [(head (stringSplit (optionOr (stringSlice text 0 i) "") " "))
            (value (optionOr (stringSlice text (+ i 1) (stringLength text)) ""))]
        (if (and (= (listLength head) 3) (= (optionOr (listHead head) "") "asl-store-row"))
          (match (stringToInt64 (optionOr (listGet head 1) ""))
            ((some rev) (match (stringToInt64 (optionOr (listGet head 2) ""))
                          ((some exp) (some (kv/Entry :rev rev :value value :expiresAt exp)))
                          ((none) (none))))
            ((none) (none)))
          (none)))))

; (:m :ref VS-CORE :do "ok none is a missing row, err is a row file that exists and does not parse, which no op may paper over")
fn ! loadRow! path: String -> (Result (Option kv/Entry) String)
  (if (not (fileExists? path))
    (ok (none))
    (match (fileReadString path)
      ((err e) (err (str "read " path ": " e)))
      ((ok text) (match (parseRow text) ((some e) (ok (some e))) ((none) (err (str "row " path " is damaged")))))))

fn errOf code: String text: String -> ty/Reply
  (ty/rErr code text)

fn ! writeUnderLock! st: FsStore op: ty/Op -> ty/Reply
  (let [(k (kv/keyOfOp op)) (path (rowPath st k))]
    (match (loadRow! path)
      ((err e) (errOf "rowCorrupt" e))
      ((ok cur)
        (let [(out (kv/decide cur op))]
          (match out.write
            ((some e) (match (lg/replaceFile! path (str (headerOf e) e.value)) ((err m) (errOf "io" m)) ((ok _) out.reply)))
            ((none) (if out.remove
                      (match (pathRemove path) ((err m) (if (fileExists? path) (errOf "io" m) out.reply)) ((ok _) out.reply))
                      out.reply)))))))

; (:m :ref VS-CORE :do "a write holds the flock on root/kv/<collection>/.lock across read, decide and tmp+rename, so two processes racing on one key get one winner; the lock is released by fdClose or by the holder's death")
fn ! kvLocked! st: FsStore op: ty/Op -> ty/Reply
  (let [(k (kv/keyOfOp op)) (path (rowPath st k))]
    (match (lg/ensureTree! (lg/dirName path))
      ((err e) (errOf "io" e))
      ((ok _) (match (lg/lockUntil! (str st.root "/kv/" k.collection "/.lock") (+ (monotonicNs) (* st.cfg.lockWaitMs 1000000)))
                ((err e) (errOf (if (stringEndsWith? e "busy") "busy" "io") e))
                ((ok fd) (let [(r (writeUnderLock! st op)) (_ (fdClose fd))] r))))))

; (:m :ref VS-CORE :do "a get reads without the lock; only when it meets an expired row does it redo the decision under the lock, which reclaims the row lazily")
fn ! kvGet! st: FsStore op: ty/Op -> ty/Reply
  (match (loadRow! (rowPath st (kv/keyOfOp op)))
    ((err e) (errOf "rowCorrupt" e))
    ((ok cur) (let [(out (kv/decide cur op))] (if out.remove (kvLocked! st op) out.reply))))

fn ! walk! dir: String rel: String -> (List String)
  (match (dirList dir)
    ((err _) (list))
    ((ok names)
      (fold (fn [(acc (List String)) (n String)] -> (List String)
              (let [(p (str dir "/" n))]
                (cond
                  ((stringStartsWith? n ".") acc)
                  ((stringEndsWith? n ".row") (listAppend acc (list (str rel (optionOr (stringSlice n 0 (- (stringLength n) 4)) "")))))
                  ((ok? (fileStat p)) (if (match (fileStat p) ((ok s) s.isDir) ((err _) false)) (listAppend acc (walk! p (str rel n "/"))) acc))
                  (else acc))))
            (list) names)))

fn ! loadLive! st: FsStore collection: String ids: (List String) now: Int64 want: Int64 acc: (List ty/ScanRow) -> (Result (List ty/ScanRow) String)
  (if (or (listEmpty? ids) (>= (listLength acc) want))
    (ok acc)
    (let [(id (optionOr (listHead ids) "")) (rest (optionOr (listTail ids) (list)))]
      (match (loadRow! (rowPath st (ty/Key :collection collection :id id)))
        ((err e) (err e))
        ((ok cur) (match cur
                    ((some e) (if (kv/liveAt? e now)
                                (loadLive! st collection rest now want (listAppend acc (list (ty/ScanRow :id id :rev e.rev :value e.value :expiresAt e.expiresAt))))
                                (loadLive! st collection rest now want acc)))
                    ((none) (loadLive! st collection rest now want acc)))))))

; (:m :ref VS-CORE :do "scan lists row names, sorts the ids, drops those outside the prefix and cursor, and loads rows in order only until one more than the page is live, so it never reads the values it will not return")
fn ! kvScan! st: FsStore collection: String prefix: String after: String limit: Int64 now: Int64 -> ty/Reply
  (let [(ids (listSort (walk! (str st.root "/kv/" collection) "")))
        (hits (filter (fn [(id String)] -> Bool (and (stringStartsWith? id prefix) (or (stringEmpty? after) (> id after)))) ids))]
    (match (loadLive! st collection hits now (+ (ty/capLimit limit) 1) (list))
      ((err e) (errOf "rowCorrupt" e))
      ((ok rows) (kv/scanPage rows prefix after limit))))

; (:m :ref VS-CORE :do "the effectful adapter: checkOp first, then the same Op rows the memory adapter answers, with the same Reply rows")
fn ! fsCall! st: FsStore op: ty/Op -> ty/Reply
  (match (ty/checkOp op)
    ((some bad) bad)
    ((none)
      (match op
        ((ty/opGet _ _) (kvGet! st op))
        ((ty/opPut _ _ _ _) (kvLocked! st op))
        ((ty/opCas _ _ _ _ _) (kvLocked! st op))
        ((ty/opDel _ _ _) (kvLocked! st op))
        ((ty/opScan c p a l now) (kvScan! st c p a l now))
        ((ty/opAppend s v now) (lg/logAppend! st.cfg s v now))
        ((ty/opRead s f l) (lg/logRead! st.cfg s f l))
        ((ty/opCommit s c o) (lg/logCommit! st.cfg s c o))
        ((ty/opCursor s c) (lg/logCursor! st.cfg s c)))))

; (:m :ref VS-CORE :do "damage for the conformance harness: tearLogTail appends half a frame without its newline to the last segment of a stream, what a crash in the middle of an append leaves")
fn ! fsFault! st: FsStore name: String arg: String -> Bool
  (if (= name "tearLogTail")
    (match (listLast (lg/segBases! st.cfg arg))
      ((none) false)
      ((some b) (ok? (fileAppend (lg/segPath st.cfg arg b) (stringToBytes "(WalEntry :seq 99 :epo")))))
    false)
