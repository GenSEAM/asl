(module aslAgent/pathResolve
  :x [resolvedOps resolveIn dirsOf resolveOp!]
  :i [(aslAgent/core :a c) (asl-proc/coreProcess :a cp) (asl-checker/resolve :a rs)])

; (:m :ref LEON-PATH-RESOLVE :do "node2 2026-11-02: the top repeatFailure op was tree (15 of 37), then write (14) and read (6); the runs named files by module name (asl-gates/metaAudit.asl, asl-tools/coord/gateWiden.asl, asl-cli/cacheGc.asl) and repeated the same not-found step until the stop, since the :nearest siblings of a missing first segment point nowhere; a step path that does not exist is resolved against the workspace's own file list, and the receipt says so")
fn resolvedOps -> (List String)
  (list "read" "tree" "outline" "write" "edit" "query" "observe")

fn segmentsOf p: String -> (List String)
  (filter (fn [s] (and (not (stringEmpty? s)) (!= s "."))) (stringSplit p "/"))

fn joinSegs segs: (List String) -> String
  (c/joinSep segs "/")

fn dropSegs segs: (List String) k: Int64 -> (List String)
  (optionOr (listSlice segs k (listLength segs)) (list))

fn endsAt path: String rest: String -> Bool
  (or (= path rest) (stringEndsWith? path (str "/" rest)))

fn uniq xs: (List String) -> (List String)
  (fold (fn [acc x] (if (listContains? acc x) acc (listAppend acc (list x)))) (list) xs)

fn ancestors path: String -> (List String)
  (let [segs (segmentsOf path)
        n (listLength segs)]
    (map (fn [k] (joinSegs (optionOr (listSlice segs 0 k) (list)))) (range 1 n)))

; (:m :do "every directory that holds a listed file, each once, in first-seen order")
fn dirsOf files: (List String) -> (List String)
  (uniq (fold (fn [acc f] (listAppend acc (ancestors f))) (list) files))

fn hasSegment path: String seg: String -> Bool
  (listContains? (segmentsOf path) seg)

; (:m :ref LEON-W2-FIX :do "a path whose first segment is itself a listed top-level directory is never resolved by dropping segments: a new nested dir under a real prefix stays where it was named")
; (:m :do "the one candidate path that a missing path names: drop leading segments one at a time and keep the candidates ending in the rest; several candidates narrow to those that also carry a dropped segment; a single-segment path matches by its last segment; none when nothing or more than one candidate is left")
fn resolveIn candidates: (List String) want: String -> (Option String)
  (let [segs (segmentsOf want)
        n (listLength segs)]
    (if (= n 0)
      (none)
      (if (= n 1)
        (pickOne (filter (fn [p] (endsAt p want)) candidates) segs)
        (if (listContains? candidates (optionOr (listHead segs) ""))
          (none)
          (dropTry candidates segs 1)))))

fn pickOne hits: (List String) dropped: (List String) -> (Option String)
  (cond
    ((= (listLength hits) 1) (listHead hits))
    ((listEmpty? hits) (none))
    (else
      (let [narrow (filter (fn [p] (listAny? (fn [s] (hasSegment p s)) dropped)) hits)]
        (if (= (listLength narrow) 1) (listHead narrow) (none)))))

fn dropTry candidates: (List String) segs: (List String) k: Int64 -> (Option String)
  (if (>= k (listLength segs))
    (none)
    (let [rest (joinSegs (dropSegs segs k))
          hits (filter (fn [p] (endsAt p rest)) candidates)]
      (if (listEmpty? hits)
        (dropTry candidates segs (+ k 1))
        (pickOne hits (optionOr (listSlice segs 0 k) (list))))))

fn ! exists! root: String rel: String -> Bool
  (match (fileStat (str root "/" rel)) ((ok _) true) ((err _) false))

fn ! listed! root: String -> (List String)
  (match (cp/exec! (cp/withTimeout (cp/withCwd (cp/cmd "git" (list "ls-files" "-c" "-o" "--exclude-standard")) root) 60000))
    ((ok out) (if (= out.exitCode 0) (filter (fn [l] (not (stringEmpty? l))) (stringSplit out.stdout "\n")) (list)))
    ((err _) (list)))

fn keyOf op: (List (Pair String c/KvVal)) -> String
  (if (some? (c/dictGet op "file")) "file" "path")

fn textOf v: (Option c/KvVal) -> String
  (match v ((some (c/kvStr t)) t) ((some (c/kvInt t)) t) ((none) ""))

fn withKey op: (List (Pair String c/KvVal)) k: String v: String -> (List (Pair String c/KvVal))
  (map (fn [p] (if (= (pairFirst p) k) (pair k (c/kvStr v)) p)) op)

; (:m :ref LEON-MODULE-PATH-ASLTOOLS :do "a missing path that is a module name, with or without .asl, resolves the way the checker resolves that import from the workspace root (package index and declared module headers), so asl-tools/fleet/run reaches asl/tools/fleet/run.asl, where suffix matching found no file or several")
fn moduleName want: String -> (Option String)
  (let [name (if (stringEndsWith? want ".asl") (optionOr (stringSlice want 0 (- (stringLength want) 4)) want) want)]
    (if (and (stringContains? name "/") (not (stringContains? name "."))) (some name) (none)))

fn ! buildTarget! root: String name: String -> (Option String)
  (let [r (rs/resolveImport! (str root "/.asl.config.asn") name (rs/emptyModIndex))
        base (str (resultOr (realPath root) root) "/")]
    (if (and (stringStartsWith? r.path base) (exists! root (optionOr (stringSlice r.path (stringLength base) (stringLength r.path)) "")))
      (some (optionOr (stringSlice r.path (stringLength base) (stringLength r.path)) ""))
      (none)))

; (:m :ref MODPATH-LOWS :do "a module lookup walks the whole root to build the checker's index (about 0.5 s) and resolveOp! has no state to keep it in, so each build appends one (:mod NAME :path P :at MS) row to .asl/run/pathResolve/modules.asn under the root and a later lookup of NAME takes the newest row: a found path counts while the file still declares NAME in its module header, a miss counts for 10 minutes, about one run")
fn memoPath root: String -> String
  (str root "/.asl/run/pathResolve/modules.asn")

fn memoMissMs -> Int64
  600000

fn rowName row: String -> String
  (optionOr (listGet (stringSplit row "\"") 1) "")

fn rowTarget row: String -> String
  (optionOr (listGet (stringSplit row "\"") 3) "")

fn rowAt row: String -> Int64
  (optionOr (stringToInt64 (stringTrim (stringReplace (optionOr (listLast (stringSplit row ":at ")) "") ")" ""))) 0)

fn ! declares! root: String path: String name: String -> Bool
  (let [text (resultOr (fileReadString (str root "/" path)) "")]
    (or (stringContains? text (str "(module " name "\n")) (stringContains? text (str "(module " name " "))))

fn ! memoHit! root: String name: String -> (Option (Option String))
  (match (listLast (filter (fn [l] (and (stringStartsWith? l "(:mod ") (= (rowName l) name))) (stringLines (resultOr (fileReadString (memoPath root)) ""))))
    ((none) (none))
    ((some row)
      (let [p (rowTarget row)]
        (if (stringEmpty? p)
          (if (< (- (/ (nowNs) 1000000) (rowAt row)) (memoMissMs)) (some (none)) (none))
          (if (and (exists! root p) (declares! root p name)) (some (some p)) (none))))))

fn ! memoWrite! root: String name: String got: (Option String) -> Bool
  (and (ok? (dirCreate (str root "/.asl/run/pathResolve")))
       (ok? (fileAppend (memoPath root) (str "(:mod \"" name "\" :path \"" (optionOr got "") "\" :at " (stringFromInt64 (/ (nowNs) 1000000)) ")\n"))))

fn ! moduleTarget! root: String want: String -> (Option String)
  (match (moduleName want)
    ((none) (none))
    ((some name)
      (match (memoHit! root name)
        ((some got) got)
        ((none) (let [got (buildTarget! root name)
                      _ (memoWrite! root name got)]
                  got)))))

; (:m :ref MODPATH-LOWS :do "outline, query and observe of a missing x/y run on x/y.asl when that file exists, before any module lookup")
fn ! withAsl! root: String opName: String want: String -> (Option String)
  (if (and (listContains? (list "outline" "query" "observe") opName)
           (and (not (stringContains? (optionOr (listLast (segmentsOf want)) "") ".")) (exists! root (str want ".asl"))))
    (some (str want ".asl"))
    (none))

; (:m :do "a write names a file that may not exist yet: only a missing parent directory is resolved, then the file name is kept")
fn ! targetFor! root: String opName: String want: String -> (Option String)
  (let [files (listed! root)]
    (cond
      ((or (= opName "write") (= opName "edit"))
        (let [segs (segmentsOf want)
              n (listLength segs)
              parent (joinSegs (optionOr (listSlice segs 0 (- n 1)) (list)))
              base (optionOr (listLast segs) "")]
          (if (or (< n 2) (exists! root parent))
            (if (= opName "edit") (resolveIn files want) (none))
            (match (resolveIn (dirsOf files) parent)
              ((some d) (some (str d "/" base)))
              ((none) (none))))))
      ((= opName "tree") (resolveIn (dirsOf files) want))
      (else (match (withAsl! root opName want)
        ((some p) (some p))
        ((none) (match (moduleTarget! root want)
          ((some p) (some p))
          ((none) (resolveIn (listAppend files (dirsOf files)) want))))))))

; (:m :do "the op with its path replaced by the resolved one and the path it was sent with, or the op unchanged and none when the path exists, is absolute, carries a #symbol, or names no single candidate")
fn ! resolveOp! op: (List (Pair String c/KvVal)) opName: String root: String -> (Pair (List (Pair String c/KvVal)) (Option String))
  (let [k (keyOf op)
        want (textOf (c/dictGet op k))]
    (if (or (not (listContains? (resolvedOps) opName))
            (or (stringEmpty? want) (or (stringStartsWith? want "/") (or (stringContains? want "#") (or (stringContains? want "..") (exists! root want))))))
      (pair op (none))
      (match (targetFor! root opName want)
        ((some got) (if (= got want) (pair op (none)) (pair (withKey op k got) (some want))))
        ((none) (pair op (none))))))
