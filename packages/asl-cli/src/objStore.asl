(module asl-cli/objStore
  :x [objPath metaPath objTmpPath statOf fileSha objVerified! writeMeta! installObj! dropObj! partState! inFlightNs]
  :i [(asl/prelude/native/sha256 :a sh)])

; (:m :ref BUILD-CACHE :do "the store protocol of content-addressed objects, shared by every build that links from KEY.o + KEY.meta; it imports only sha256 so a multi-process fixture can drive it from a small program")
fn objPath objs: String key: String -> String
  (str objs "/" key ".o")

fn metaPath objs: String key: String -> String
  (str objs "/" key ".meta")

; (:m :ref BUILD-CACHE :do "clang writes an object beside its final name under a name of its own pid, and installObj! renames it into place: a reader sees no object or a whole one, never a half-written file")
fn objTmpPath objs: String key: String pid: Int64 -> String
  (str objs "/" key ".o.tmp." (stringFromInt64 pid))

fn ! statOf path: String -> (Pair Int64 Int64)
  (match (fileStat path) ((ok st) (pair st.size st.mtimeNs)) ((err _) (pair -1 -1)))

fn ! fileSha path: String -> (Result String String)
  (match (fileReadBytes path)
    ((err e) (err (str "cannot read " path ": " e)))
    ((ok bytes) (ok (sh/bytesSha256 bytes))))

; (:m :ref BUILD-CACHE :do "a hit is an object whose size matches its meta row and whose mtime matches too, or else whose sha256 does; the meta file's mtime is the entry's last use for the sweep")
fn ! objVerified! objs: String key: String -> Bool
  (let [(obj (objPath objs key))
        (meta (metaPath objs key))
        (words (stringSplit (stringTrim (resultOr (fileReadString meta) "")) " "))
        (st (statOf obj))]
    (cond
      ((< (listLength words) 3) false)
      ((!= (stringFromInt64 (pairFirst st)) (optionOr (listGet words 1) "")) false)
      ((or (= (stringFromInt64 (pairSecond st)) (optionOr (listGet words 2) ""))
           (= (resultOr (fileSha obj) "") (optionOr (listGet words 0) "")))
       (do (fileUtime meta (nowNs)) true))
      (else false)))

fn ! writeMeta! objs: String key: String text: String -> (Result Unit String)
  (let [(part (str (metaPath objs key) ".tmp." (stringFromInt64 (procSelf))))]
    (match (fileWrite part text)
      ((err e) (err (str "cannot write " part ": " e)))
      ((ok _) (match (pathRename part (metaPath objs key)) ((err e) (err (str "cannot install " (metaPath objs key) ": " e))) ((ok _) (ok ()))))))

; (:m :ref BUILD-CACHE :do "the meta row lands before the object: rename keeps the tmp file's size and mtime, so the row written from the tmp describes the installed object, and a reader never sees an object without its row; the window it can see is a row without an object, which partState! reads as in flight")
fn ! installObj! objs: String key: String tmp: String -> (Result String String)
  (match (fileSha tmp)
    ((err e) (err e))
    ((ok sha) (let [(st (statOf tmp))
                    (obj (objPath objs key))]
                (match (writeMeta! objs key (str sha " " (stringFromInt64 (pairFirst st)) " " (stringFromInt64 (pairSecond st)) "\n"))
                  ((err e) (err e))
                  ((ok _) (match (pathRename tmp obj)
                    ((err e) (err (str "cannot install " obj ": " e)))
                    ((ok _) (ok obj))))))))

fn ! dropObj! objs: String key: String -> Bool
  (let [(_ (pathRemove (objPath objs key))) (_ (pathRemove (metaPath objs key)))] true)

fn inFlightNs -> Int64
  60000000000

fn ! young? path: String now: Int64 -> Bool
  (let [(st (statOf path))] (and (>= (pairSecond st) 0) (< (- now (pairSecond st)) (inFlightNs))))

; (:m :ref BUILD-CACHE :do "the state of one part in the store: 0 a verified hit, 1 absent, 3 in flight (only one of KEY.o and KEY.meta exists and it is younger than 60 s: another build is installing it, so it is a miss that removes nothing), 2 corrupt (anything else present under the key: removed, compiled again, never linked)")
fn ! partState! objs: String key: String -> Int64
  (let [(o (fileExists? (objPath objs key)))
        (m (fileExists? (metaPath objs key)))
        (now (nowNs))]
    (cond
      ((and o m) (if (objVerified! objs key) 0 (do (dropObj! objs key) 2)))
      ((and o (young? (objPath objs key) now)) 3)
      ((and m (young? (metaPath objs key) now)) 3)
      ((or o m) (do (dropObj! objs key) 2))
      (else 1)))
