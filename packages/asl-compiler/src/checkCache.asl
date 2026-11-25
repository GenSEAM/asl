(module asl-compiler/checkCache :x [Verdict cacheDir! verdictKey! verdictKeyWith! keyText rootPairs! portable localize encodeVerdict decodeVerdict lookup! store! replay! capOf defaultCap sweepWith!] :i [(asl-checker/resolve :a r)])

(schema Verdict (:f exitCode Int64) (:f body String))

fn magic -> String
  "aslCheckVerdict 1"

fn ! cacheDir! -> String
  (let [(configured (optionOr (envGet "ASL_CHECK_CACHE") ""))]
    (if (stringEmpty? configured) (str (optionOr (envGet "HOME") ".") "/.asl/cache/check") configured))

fn ! shaOf! memo: (Map String String) path: String -> (Option (Pair String (Map String String)))
  (match (mapGet memo path)
    ((some d) (some (pair d memo)))
    ((none) (match (fileReadBytes path)
      ((err _) (none))
      ((ok bytes) (let [(d (bytesSha256 bytes))] (some (pair d (mapSet memo path d))))))))

fn dirParts path: String -> (List String)
  (let [(parts (stringSplit path "/"))]
    (listTake parts (- (listLength parts) 1)))

fn commonLen a: (List String) b: (List String) -> Int64
  (match (listHead a)
    ((none) 0)
    ((some x) (match (listHead b)
      ((none) 0)
      ((some y) (if (= x y) (+ 1 (commonLen (optionOr (listTail a) (list)) (optionOr (listTail b) (list)))) 0)))))

; (:m :ref CHECK-VERDICT-RELPATH :do "a closure path is keyed relative to the directory of the file that roots the closure, so the same content in another tree root keys the same; the entry itself is the token <entry>")
fn relTo baseParts: (List String) entryReal: String path: String -> String
  (if (= path entryReal)
    "<entry>"
    (let [(parts (stringSplit path "/"))
          (n (commonLen baseParts parts))
          (ups (- (listLength baseParts) n))]
      (stringJoin (listAppend (map (fn [(i Int64)] -> String "..") (range 0 ups)) (listDrop parts n)) "/")))

fn ! hashLines! base: String entryReal: String paths: (List String) memo: (Map String String) acc: (List String) -> (Option (Pair String (Map String String)))
  (match (listHead paths)
    ((none) (some (pair (stringJoin (listSort acc) "") memo)))
    ((some p) (match (shaOf! memo p)
      ((none) (none))
      ((some got) (hashLines! base entryReal (optionOr (listTail paths) (list)) (pairSecond got) (cons (str (relTo (dirParts base) entryReal p) "=" (pairFirst got) "\n") acc))))))

fn ! closureOf! real: String -> (Option (List String))
  (let [(cl (r/loadModuleClosure! real false))]
    (if (and (listEmpty? cl.unresolved) (listEmpty? cl.errors)) (some (listSort (cons real cl.paths))) (none)))

fn ! checkerSource! -> (Option String)
  (let [(p "./asl/packages/asl-compiler/src/asl1.asl")]
    (if (fileExists? p) (resultToOption (realPath p)) (none)))

fn keyText entryLabel: String deps: String checker: String -> String
  (str (magic) "\nentry " entryLabel "\ndeps\n" deps "checker\n" checker)

; (:m :ref CHECK-VERDICT-RELPATH :do "the key names the entry by its path under the nearest workspace config (basename when none), so two identical files at different paths in one tree get two verdicts and the same path in two trees shares one")
fn ! wsRootOf! parts: (List String) -> String
  (let [(dir (stringJoin parts "/"))]
    (if (listEmpty? parts) ""
      (if (fileExists? (str dir "/.asl.config.asn")) dir (wsRootOf! (listTake parts (- (listLength parts) 1))))))

fn ! entryLabel! entryReal: String -> String
  (let [(root (wsRootOf! (dirParts entryReal)))
        (prefix (str root "/"))]
    (if (and (not (stringEmpty? root)) (stringStartsWith? entryReal prefix))
      (optionOr (stringSlice entryReal (stringLength prefix) (stringLength entryReal)) entryReal)
      (optionOr (listLast (stringSplit entryReal "/")) entryReal)))

fn ! verdictKey! entry: String -> (Option String)
  (match (resultToOption (realPath entry))
    ((none) (none))
    ((some entryReal) (match (closureOf! entryReal)
      ((none) (none))
      ((some deps) (match (checkerSource!)
        ((none) (none))
        ((some checkerReal) (match (if (= checkerReal entryReal) (some deps) (closureOf! checkerReal))
          ((none) (none))
          ((some checkerDeps) (match (hashLines! entryReal entryReal deps (mapEmpty) (list))
            ((none) (none))
            ((some d) (match (hashLines! checkerReal entryReal checkerDeps (pairSecond d) (list))
              ((none) (none))
              ((some c) (some (bytesSha256 (stringToBytes (keyText (entryLabel! entryReal) (pairFirst d) (pairFirst c)))))))))))))))))

; (:m :ref SCRIPT-RUN-UNCHECKED :do "a caller whose checker is compiled into it keys by its own build id instead of rehashing the checker source closure, and an entry staged under a per-run name (asl -e, asl -) is keyed under a stable alias in place of its path; the deps lines still carry its content digest")
fn ! verdictKeyWith! entry: String alias: String checkerId: String -> (Option String)
  (match (resultToOption (realPath entry))
    ((none) (none))
    ((some entryReal) (match (closureOf! entryReal)
      ((none) (none))
      ((some deps) (match (hashLines! entryReal entryReal deps (mapEmpty) (list))
        ((none) (none))
        ((some d) (let [(text (keyText (if (stringEmpty? alias) "<entry>" alias) (pairFirst d) checkerId))]
                    (some (bytesSha256 (stringToBytes text))))))))))

; (:m :ref CHECK-VERDICT-RELPATH :do "a stored body names the writing tree by placeholder tokens for the entry directory and the working root, and a replay substitutes the asking tree, so a shared verdict never sends the reader to another tree; a path outside both roots stays absolute")
fn ! rootPairs! entry: String -> (List (Pair String String))
  (let [(entryDir (match (resultToOption (realPath entry)) ((some r) (stringJoin (dirParts r) "/")) ((none) "")))
        (cwd (optionOr (resultToOption (realPath ".")) ""))
        (all (filter (fn [(q (Pair String String))] -> Bool (not (stringEmpty? (pairFirst q)))) (list (pair entryDir "<root:entry>/") (pair cwd "<root:cwd>/"))))]
    (listSortBy (fn [(q (Pair String String))] -> Int64 (- 0 (stringLength (pairFirst q)))) all))

fn portable v: Verdict roots: (List (Pair String String)) -> Verdict
  (Verdict :exitCode v.exitCode :body (fold (fn [(b String) (q (Pair String String))] -> String (stringReplace b (str (pairFirst q) "/") (pairSecond q))) v.body roots))

fn localize v: Verdict roots: (List (Pair String String)) -> Verdict
  (Verdict :exitCode v.exitCode :body (fold (fn [(b String) (q (Pair String String))] -> String (stringReplace b (pairSecond q) (str (pairFirst q) "/"))) v.body roots))

fn entryPath dir: String key: String -> String
  (str dir "/" key ".verdict")

fn encodeVerdict key: String v: Verdict -> String
  (str (magic) "\n" key "\n" (stringFromInt64 v.exitCode) "\n" (bytesSha256 (stringToBytes v.body)) "\n" v.body)

fn lineAt s: String from: Int64 -> (Option (Pair String Int64))
  (match (stringSlice s from (stringLength s))
    ((none) (none))
    ((some rest) (match (stringIndexOf rest "\n")
      ((none) (none))
      ((some i) (optionMap (fn [(l String)] -> (Pair String Int64) (pair l (+ from (+ i 1)))) (stringSlice s from (+ from i)))))))

fn decodeVerdict key: String text: String -> (Option Verdict)
  (match (lineAt text 0)
    ((none) (none))
    ((some l1) (match (lineAt text (pairSecond l1))
      ((none) (none))
      ((some l2) (match (lineAt text (pairSecond l2))
        ((none) (none))
        ((some l3) (match (lineAt text (pairSecond l3))
          ((none) (none))
          ((some l4) (match (stringSlice text (pairSecond l4) (stringLength text))
            ((none) (none))
            ((some body) (match (stringToInt64 (pairFirst l3))
              ((none) (none))
              ((some code) (if (and (= (pairFirst l1) (magic)) (and (= (pairFirst l2) key) (= (pairFirst l4) (bytesSha256 (stringToBytes body)))))
                             (some (Verdict :exitCode code :body body))
                             (none))))))))))))))

; (:m :ref CHECK-VERDICT-CAP :do "a hit stamps its entry, so the sweep drops the least recently used verdicts")
fn ! lookup! key: String -> (Option Verdict)
  (match (fileReadString (entryPath (cacheDir!) key))
    ((err _) (none))
    ((ok text) (match (decodeVerdict key text)
                 ((none) (none))
                 ((some v) (do (fileUtime (entryPath (cacheDir!) key) (nowNs)) (some v))))))

; (:m :ref CHECK-VERDICT-CAP :do "the verdict cache held 59090 files (2026-10-27); it is capped at the (:check :cacheCap N) row of ~/.asl/config.asn, 20000 entries when absent")
fn defaultCap -> Int64
  20000

fn capOf configText: String -> Int64
  (match (stringIndexOf configText "(:check :cacheCap ")
    ((none) (defaultCap))
    ((some i) (let [(rest (optionOr (stringSlice configText (+ i 18) (stringLength configText)) ""))
                    (digits (stringTrim (optionOr (listHead (stringSplit (stringReplace rest ")" " ") " ")) "")))]
                (match (stringToInt64 digits)
                  ((some n) (if (> n 0) n (defaultCap)))
                  ((none) (defaultCap))))))

fn ! capFor! -> Int64
  (capOf (resultOr (fileReadString (str (optionOr (envGet "HOME") ".") "/.asl/config.asn")) ""))

; (:m :ref CHECK-VERDICT-CAP :do "one sweep at a time under sweep.lock: when more than cap verdicts are stored the oldest by mtime go until cap remain; returns the count removed, 0 when the lock is held")
fn ! sweepOne! dir: String cap: Int64 -> Int64
  (let [(lock (str dir "/sweep.lock"))]
    (match (fileCreateExclusive lock (stringFromInt64 (procSelf)))
      ((err _) 0)
      ((ok _)
       (let [(names (filter (fn [(n String)] -> Bool (stringEndsWith? n ".verdict")) (resultOr (dirList dir) (list))))
             (excess (- (listLength names) cap))
             (removed (if (<= excess 0)
                        0
                        (let [(stamped (map (fn [(n String)] -> (Pair String Int64) (pair n (match (fileStat (str dir "/" n)) ((ok st) st.mtimeNs) ((err _) 0)))) names))
                              (oldest (listTake (listSortBy (fn [(p (Pair String Int64))] -> Int64 (pairSecond p)) stamped) excess))]
                          (listLength (filter (fn [(p (Pair String Int64))] -> Bool (ok? (pathRemove (str dir "/" (pairFirst p))))) oldest)))))
             (_ (pathRemove lock))]
         removed))))

; (:m :ref TRAIN-SUITE-FRONTEND-SHARE :do "the per-module body stamps of asl-checker/checkCached live in DIR/modules and are swept under the same cap and oldest-first policy as the top level")
fn ! sweepWith! dir: String cap: Int64 -> Int64
  (+ (sweepOne! dir cap) (sweepOne! (str dir "/modules") cap))

; (:m :ref CHECK-VERDICT-CAP :do "a sweep lists every entry, so a store sweeps at most once a minute per cache, marked by the swept file")
fn ! sweepSoon! dir: String -> Int64
  (let [(mark (str dir "/swept"))
        (last (match (fileStat mark) ((ok st) st.mtimeNs) ((err _) 0)))]
    (if (< (- (nowNs) last) 60000000000)
      0
      (do (fileWrite mark "") (sweepWith! dir (capFor!)))))

fn ! dropTmp! tmp: String -> Unit
  (if (fileExists? tmp) (match (pathRemove tmp) ((ok _) ()) ((err _) ())) ())

fn ! store! key: String v: Verdict -> (Result Unit String)
  (let [(dir (cacheDir!))
        (tmp (str (entryPath dir key) ".tmp." (stringFromInt64 (procSelf)) "x" (stringFromInt64 (nowNs))))]
    (match (dirCreate dir)
      ((err e) (err (str "cannot create " dir ": " e)))
      ((ok _) (match (fileWrite tmp (encodeVerdict key v))
        ((err _) (do (dropTmp! tmp) (err (str "cannot write " tmp))))
        ((ok _) (match (pathRename tmp (entryPath dir key))
          ((err e) (do (dropTmp! tmp) (err (str "cannot rename " tmp ": " e))))
          ((ok _) (do (sweepSoon! dir) (ok ())))))))))

fn ! replay! v: Verdict -> (Result Int64 String)
  (do (if (stringEmpty? v.body) ()
        (do (eprintln (optionOr (stringSlice v.body 0 (- (stringLength v.body) (if (stringEndsWith? v.body "\n") 1 0))) v.body)) ()))
      (ok v.exitCode))
