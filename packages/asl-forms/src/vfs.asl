(module asl-forms/vfs :x [Vfs VfsMeta vfsAt vfsRoot! vfsContext! vfsContextFrom! storeDir readText! charLength shaText atomicWrite! writeGuard! isLink? vfsKey lockPath stagedContent! stagedMeta! stage! unstage! stagedPaths! stagedByOther! withLock! lockAcquire! lockRelease! discardAll! jsonQuote] :i [(asl-forms/kernel :a k) (asl-json/json :a j)])


(schema Vfs (:f root String) (:f dir String) (:f session String))

(schema VfsMeta (:f present Bool) (:f path String) (:f baseSha String) (:f baseExists Bool))


fn vfsAt root: String dir: String session: String -> Vfs
  (Vfs :root root :dir dir :session session)

fn vfsRoot! root: String given: String home: String -> String
  (let [(wsAsl (k/joinPath root ".asl"))]
    (cond
      ((not (stringEmpty? given)) given)
      ((and (k/isDir! wsAsl) (not (isLink? wsAsl))) (k/joinPath wsAsl "vfs"))
      (else (k/joinPath (k/joinPath (k/joinPath (k/joinPath home ".cache") "asl") "vfs") (optionOr (stringSlice (shaText root) 0 16) "")))))

fn sessionChar? c: String -> Bool
  (let [(n (charCode c))]
    (or (and (>= n 48) (<= n 57)) (and (>= n 65) (<= n 90)) (and (>= n 97) (<= n 122)) (= c ".") (= c "_") (= c "-")))

fn vfsContextFrom! root: String given: String session: String home: String -> (Result Vfs String)
  (let [(wsAsl (k/joinPath root ".asl"))
        (dir (cond
               ((not (stringEmpty? given)) given)
               ((and (k/isDir! wsAsl) (not (isLink? wsAsl))) (k/joinPath wsAsl "vfs"))
               (else (str home "/.cache/asl/vfs/" (optionOr (stringSlice (shaText root) 0 16) "")))))]
    (cond
      ((and (not (stringEmpty? session)) (or (stringContains? session "..") (= session ".") (not (listAll? sessionChar? (stringChars session)))))
        (err (str "ASL_SESSION must match [A-Za-z0-9._-]+ without ..: " session)))
      (else (mt (dirCreate dir) ((err e) (err e)) ((ok _) (ok (vfsAt root dir session)))))))

fn vfsContext! root: String -> (Result Vfs String)
  (vfsContextFrom! root (optionOr (envGet "ASL_VFS_DIR") "") (optionOr (envGet "ASL_SESSION") "") (optionOr (envGet "HOME") ""))

fn storeDir! v: Vfs -> String
  (if (stringEmpty? v.session)
    v.dir
    (let [(d (k/joinPath v.dir v.session))]
      (do (resultOr (dirCreate d) ()) d)))

fn readText! p: String -> (Result String String)
  (mt (fileReadString p) ((err e) (err e)) ((ok s) (ok (k/universalNewlines s))))

fn countChars b: Bytes i: Int64 n: Int64 acc: Int64 -> Int64
  (if (>= i n) acc (countChars b (+ i 1) n (if (= (& (bytesGet b i) 192) 128) acc (+ acc 1))))

fn charLength s: String -> Int64
  (countChars (stringToBytes s) 0 (stringLength s) 0)

fn shaText s: String -> String
  (bytesSha256 (stringToBytes s))

fn vfsKey path: String -> String
  (optionOr (stringSlice (shaText path) 0 32) "")

fn blobPath! v: Vfs path: String -> String
  (k/joinPath (storeDir! v) (str (vfsKey path) ".blob"))

fn metaPath! v: Vfs path: String -> String
  (k/joinPath (storeDir! v) (str (vfsKey path) ".meta"))

fn lockPath v: Vfs path: String -> String
  (k/joinPath v.dir (str (vfsKey path) ".lock"))

fn fileMode! p: String -> (Option Int64)
  (mt (fileStat p) ((ok st) (some (& st.mode 4095))) ((err _) (none)))

fn tempFor! d: String n: Int64 content: String -> (Result String String)
  (let [(tmp (k/joinPath d (str ".aslTmp" (stringFromInt64 (procSelf)) "_" (stringFromInt64 (nowNs)) "_" (stringFromInt64 n))))]
    (mt (fileCreateExclusive tmp content)
      ((ok _) (ok tmp))
      ((err e) (if (and (stringContains? e "exists") (< n 100)) (tempFor! d (+ n 1) content) (err e)))))

fn atomicWrite! path: String content: String -> (Result Bool String)
  (let [(d0 (k/dirName path))
        (d (if (stringEmpty? d0) "." d0))]
    (mt (dirCreate d)
      ((err e) (err e))
      ((ok _)
        (mt (tempFor! d 0 content)
          ((err e) (err e))
          ((ok tmp)
            (let [(old (fileMode! path))]
              (if (and (some? old) (!= old (fileMode! tmp)))
                (do (resultOr (pathRemove tmp) ()) (mt (fileWrite path content) ((ok _) (ok false)) ((err e) (err e))))
                (mt (pathRename tmp path)
                  ((ok _) (ok true))
                  ((err e) (do (resultOr (pathRemove tmp) ()) (err e)))))))))))

fn ! isLink? p: String -> Bool
  (mt (realPath p)
    ((ok real) (!= real (k/normalizePath p)))
    ((err _) (mt (dirList (k/dirName p)) ((ok names) (listContains? names (k/baseName p))) ((err _) false))))

fn under? root: String p: String -> Bool
  (or (= p root) (stringStartsWith? p (str root "/")))

fn linkedPart! root: String cur: String parts: (List String) -> String
  (mt (listHead parts)
    ((none) "")
    ((some part)
      (let [(rest (optionOr (listTail parts) (list)))]
        (if (or (stringEmpty? part) (= part "."))
          (linkedPart! root cur rest)
          (let [(next (k/joinPath cur part))]
            (if (isLink? next)
              (str "Refusing to write through symlinked path component: " (k/relPath next root))
              (linkedPart! root next rest)))))))

fn writeGuard! root: String path: String -> String
  (let [(norm (k/normalizePath path))]
    (if (not (under? root norm))
      (str "Path escapes workspace boundary: " path)
      (let [(linked (linkedPart! root root (stringSplit (k/relPath norm root) "/")))]
        (cond
          ((not (stringEmpty? linked)) linked)
          ((not (stringEmpty? (pairSecond (k/resolveInRoot! root norm)))) (str "Path escapes workspace boundary: " path))
          (else "")))))

fn stagedContent! v: Vfs path: String -> (Option String)
  (let [(bp (blobPath! v path))]
    (if (k/isFile! bp) (mt (readText! bp) ((ok s) (some s)) ((err _) (none))) (none)))

fn jsonText obj: j/Json key: String -> String
  (mt (jsonGetOpt obj key)
    ((none) "")
    ((some v) (mt v ((j/jstr s) s) (_ ""))))

fn jsonGetOpt obj: j/Json key: String -> (Option j/Json)
  (j/jsonGet obj key)

fn noMeta -> VfsMeta
  (VfsMeta :present false :path "" :baseSha "" :baseExists false)

fn parseMeta text: String -> VfsMeta
  (mt (j/jsonParse text)
    ((err _) (noMeta))
    ((ok obj)
      (let [(sha (jsonText obj "baseSha"))]
        (VfsMeta :present true :path (jsonText obj "path") :baseSha sha
                 :baseExists (mt (jsonGetOpt obj "baseExists") ((some v) (mt v ((j/jbool b) b) (_ true))) ((none) (not (stringEmpty? sha))))))))

fn stagedMeta! v: Vfs path: String -> VfsMeta
  (let [(mp (metaPath! v path))]
    (if (k/isFile! mp) (mt (fileReadString mp) ((ok t) (parseMeta t)) ((err _) (noMeta))) (noMeta)))

fn hex4 n: Int64 -> String
  (let [(digits "0123456789abcdef")]
    (str (k/charAt digits (& (/ n 4096) 15)) (k/charAt digits (& (/ n 256) 15)) (k/charAt digits (& (/ n 16) 15)) (k/charAt digits (& n 15))))

fn escapeCodePoint cp: Int64 -> String
  (if (< cp 65536)
    (str "\\u" (hex4 cp))
    (let [(c (- cp 65536))]
      (str "\\u" (hex4 (+ 55296 (/ c 1024))) "\\u" (hex4 (+ 56320 (& c 1023))))))

fn contByte b: Bytes i: Int64 n: Int64 -> Int64
  (if (< i n) (& (bytesGet b i) 63) 0)

fn quoteScan s: String b: Bytes n: Int64 i: Int64 acc: (List String) -> (List String)
  (if (>= i n)
    acc
    (let [(c (bytesGet b i))]
      (cond
        ((= c 34) (quoteScan s b n (+ i 1) (cons "\\\"" acc)))
        ((= c 92) (quoteScan s b n (+ i 1) (cons "\\\\" acc)))
        ((= c 10) (quoteScan s b n (+ i 1) (cons "\\n" acc)))
        ((= c 13) (quoteScan s b n (+ i 1) (cons "\\r" acc)))
        ((= c 9) (quoteScan s b n (+ i 1) (cons "\\t" acc)))
        ((= c 8) (quoteScan s b n (+ i 1) (cons "\\b" acc)))
        ((= c 12) (quoteScan s b n (+ i 1) (cons "\\f" acc)))
        ((< c 32) (quoteScan s b n (+ i 1) (cons (escapeCodePoint c) acc)))
        ((< c 128) (quoteScan s b n (+ i 1) (cons (k/charAt s i) acc)))
        ((< c 224) (quoteScan s b n (+ i 2) (cons (escapeCodePoint (+ (* (& c 31) 64) (contByte b (+ i 1) n))) acc)))
        ((< c 240) (quoteScan s b n (+ i 3) (cons (escapeCodePoint (+ (* (& c 15) 4096) (* (contByte b (+ i 1) n) 64) (contByte b (+ i 2) n))) acc)))
        (else (quoteScan s b n (+ i 4) (cons (escapeCodePoint (+ (* (& c 7) 262144) (* (contByte b (+ i 1) n) 4096) (* (contByte b (+ i 2) n) 64) (contByte b (+ i 3) n))) acc))))))

fn jsonQuote s: String -> String
  (str "\"" (k/concatAll (listReverse (quoteScan s (stringToBytes s) (stringLength s) 0 (list)))) "\"")

fn metaJson v: Vfs path: String baseSha: String baseExists: Bool -> String
  (str "{\"path\": " (jsonQuote path) ", \"rel\": " (jsonQuote (k/relToRoot v.root path)) ", \"baseSha\": " (jsonQuote baseSha)
       ", \"baseExists\": " (if baseExists "true" "false")
       (if (stringEmpty? v.session) "" (str ", \"session\": " (jsonQuote v.session)))
       "}")

fn stage! v: Vfs path: String content: String -> (Result Unit String)
  (let [(mp (metaPath! v path))
        (kept (k/isFile! mp))
        (meta (stagedMeta! v path))
        (onDisk (k/isFile! path))
        (base (cond
                (kept (ok (pair meta.baseSha meta.baseExists)))
                (onDisk (mt (readText! path) ((ok t) (ok (pair (shaText t) true))) ((err e) (err e))))
                (else (ok (pair "" false)))))]
    (mt base
      ((err e) (err e))
      ((ok b)
        (mt (atomicWrite! (blobPath! v path) content)
          ((err e) (err e))
          ((ok _) (mt (atomicWrite! mp (metaJson v path (pairFirst b) (pairSecond b))) ((ok _) (ok ())) ((err e) (err e))))))))

fn removeIfFile! p: String -> (Result Unit String)
  (if (k/isFile! p) (pathRemove p) (ok ()))

fn unstage! v: Vfs path: String -> (Result Unit String)
  (let [(b (removeIfFile! (blobPath! v path)))
        (m (removeIfFile! (metaPath! v path)))]
    (mt b ((err e) (err e)) ((ok _) m)))

fn metaNamed! d: String names: (List String) acc: (List String) -> (List String)
  (mt (listHead names)
    ((none) (listReverse acc))
    ((some n)
      (let [(rest (optionOr (listTail names) (list)))
            (p (if (stringEndsWith? n ".meta") (mt (fileReadString (k/joinPath d n)) ((ok t) (parseMeta t).path) ((err _) "")) ""))]
        (metaNamed! d rest (if (stringEmpty? p) acc (cons p acc))))))

fn stagedPaths! v: Vfs -> (List String)
  (let [(d (storeDir! v))]
    (mt (dirList d) ((err _) (list)) ((ok names) (metaNamed! d names (list)))))

fn stagedByOther! v: Vfs path: String -> String
  (let [(key (str (vfsKey path) ".meta"))]
    (mt (dirList v.dir)
      ((err _) "")
      ((ok subs)
        (optionOr (listHead (filter (fn [(sub String)] -> Bool
                                      (and (!= sub v.session)
                                           (k/isDir! (k/joinPath v.dir sub))
                                           (k/isFile! (k/joinPath (k/joinPath v.dir sub) key))))
                                    subs))
                  ""))))

fn tokenFor! -> String
  (let [(t (str (stringFromInt64 (procSelf)) ":" (stringFromInt64 (nowNs))))]
    (str t (stringRepeat " " (- 48 (stringLength t)))))

fn acquire! lp: String tries: Int64 -> (Result Int64 String)
  (mt (fileLock lp true)
    ((err e)
      (if (= e "busy")
        (do (sleepMs (if (< tries 50) 1 10)) (acquire! lp (+ tries 1)))
        (err (str "lock " lp ": " e))))
    ((ok fd)
      (let [(tok (tokenFor!))]
        (mt (fdWrite fd tok)
          ((err e) (do (resultOr (fdClose fd) ()) (err (str "lock " lp ": " e))))
          ((ok _)
            (if (stringStartsWith? (resultOr (fileReadString lp) "") tok)
              (ok fd)
              (do (resultOr (fdClose fd) ()) (acquire! lp tries))))))))

fn release! v: Vfs path: String lp: String fd: Int64 -> (Result Unit String)
  (let [(gone (if (k/isFile! (metaPath! v path)) (ok ()) (removeIfFile! lp)))
        (closed (fdClose fd))]
    (mt gone ((err e) (err e)) ((ok _) closed)))

fn withLock! v: Vfs held: (List String) path: String body: (fn [] -> T) -> (Result T String)
  (let [(lp (lockPath v path))]
    (if (listContains? held lp)
      (ok (body))
      (mt (acquire! lp 0)
        ((err e) (err e))
        ((ok fd)
          (let [(r (body))]
            (mt (release! v path lp fd) ((err e) (err e)) ((ok _) (ok r))))))))

fn resultFlat r: (Result (Result T String) String) -> (Result T String)
  (mt r ((err e) (err e)) ((ok inner) inner))

fn discardLoop! v: Vfs held: (List String) paths: (List String) n: Int64 -> (Result Int64 String)
  (mt (listHead paths)
    ((none) (ok n))
    ((some p)
      (mt (resultFlat (withLock! v held p (fn [] -> (Result Unit String) (unstage! v p))))
        ((err e) (err e))
        ((ok _) (discardLoop! v held (optionOr (listTail paths) (list)) (+ n 1))))))

fn discardAll! v: Vfs held: (List String) -> (Result Int64 String)
  (discardLoop! v held (stagedPaths! v) 0)

fn lockAcquire! v: Vfs path: String -> (Result Int64 String)
  (acquire! (lockPath v path) 0)

fn lockRelease! v: Vfs path: String fd: Int64 -> (Result Unit String)
  (release! v path (lockPath v path) fd)
