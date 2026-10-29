(module ws/asl/tools/obs/corpus
  :x [main mkdirs! readText listDir mtimeMs sizeOf isDir? baseName hk collect! collectArchive! writeDay! dayKey reportText! loadTable! discoverRoots Found]
  :i [(ws/asl/tools/obs/sx :a sx)
      (ws/asl/tools/obs/obs :a ob)
      (ws/asl/tools/obs/classify :a cl)
      (ws/asl/tools/obs/sources :a src)
      (ws/asl/tools/obs/report :a rp)
      (ws/asl/tools/obs/archive :a ar)])

; (:m :ref OBSCORPUS :do "collect walks the known run-log locations, normalises every row into the one observation type and appends day files under the out dir; a state file keeps the byte offset per append-only source and the size per whole-file source, and rows carry a digest id, so a second run adds nothing")
(schema Found
  (:f name String)
  (:f files Int64)
  (:f obs (List ob/Obs))
  (:f marks (List (Pair String Int64))))

fn flagValue args: (List String) name: String -> (Option String)
  (match (listIndexOf args name)
    ((some i) (listGet args (+ i 1)))
    ((none) none))

fn readText path: String -> String
  (resultOr (fileReadString path) "")

fn listDir path: String -> (List String)
  (resultOr (dirList path) (list))

fn mtimeMs path: String -> Int64
  (match (fileStat path)
    ((ok st) (* st.mtime 1000))
    ((err _) 0))

fn sizeOf path: String -> Int64
  (match (fileStat path)
    ((ok st) st.size)
    ((err _) 0))

fn isDir? path: String -> Bool
  (match (fileStat path)
    ((ok st) st.isDir)
    ((err _) false))

fn baseName p: String -> String
  (optionOr (listLast (stringSplit p "/")) p)

fn loadTable! root: String -> (List cl/FailClass)
  (cl/parseTable (readText (str root "/asl/tools/obs/failClasses.asn")))

fn uniq xs: (List String) -> (List String)
  (listReverse (fold (fn [(acc (List String)) (x String)] -> (List String) (if (listContains? acc x) acc (cons x acc))) (list) xs))

; (:m :ref OBSCORPUS :do "run-log roots: the workspace, the main checkout, every worktree under ~/projects/worktrees on the Mac and ~/wt on the VPS, and ~/asex; a root without a .asl dir contributes nothing")
fn discoverRoots root: String home: String -> (List String)
  (uniq (listFlatMap (fn [(r String)] -> (List String) (if (isDir? (str r "/.asl")) (list r) (list)))
          (listAppend (list root (str home "/projects/asex") (str home "/asex"))
                      (listAppend (map (fn [(d String)] -> String (str home "/projects/worktrees/" d)) (listDir (str home "/projects/worktrees")))
                                  (map (fn [(d String)] -> String (str home "/wt/" d)) (listDir (str home "/wt")))))))

; (:m :do "append-only source: the new complete lines past the stored offset, and the new offset")
fn hk p: String -> String
  (optionOr (stringSlice (bytesSha256 (stringToBytes p)) 0 16) "")

fn newLines path: String marks: (Map String Int64) -> (Pair (List String) Int64)
  (let [(size (sizeOf path))
        (off0 (mapGetOr marks (hk path) 0))
        (off (if (< size off0) 0 off0))]
    (if (and (= size off) (> off 0))
      (pair (list) off)
      (let [(text (readText path))
            (tail (optionOr (stringSlice text off (stringLength text)) ""))
            (cut (match (listLast (stringSplit tail "\n")) ((some l) (- (stringLength tail) (stringLength l))) ((none) 0)))
            (whole (optionOr (stringSlice tail 0 cut) ""))]
        (pair (stringLines whole) (+ off cut)))))

fn foldLines! name: String paths: (List String) marks: (Map String Int64) ctxFor: (fn [String] -> src/Ctx) rowFn: (fn [src/Ctx String] -> (Option ob/Obs)) -> Found
  (let [(parts (map (fn [(p String)] -> (Pair (List ob/Obs) (Pair String Int64))
                      (let [(nl (newLines p marks))
                            (ctx (ctxFor p))]
                        (pair (listFlatMap (fn [(l String)] -> (List ob/Obs) (match (rowFn ctx l) ((some o) (list o)) ((none) (list)))) (pairFirst nl))
                              (pair (hk p) (pairSecond nl)))))
                    paths))]
    (Found :name name :files (listLength paths) :obs (listFlatMap (fn [(x (Pair (List ob/Obs) (Pair String Int64)))] -> (List ob/Obs) (pairFirst x)) parts)
           :marks (map (fn [(x (Pair (List ob/Obs) (Pair String Int64)))] -> (Pair String Int64) (pairSecond x)) parts)))

; (:m :do "whole-file source: skipped when the size equals the stored mark")
fn foldFiles! name: String paths: (List String) marks: (Map String Int64) obsFor: (fn [String String] -> (List ob/Obs)) -> Found
  (let [(parts (map (fn [(p String)] -> (Pair (List ob/Obs) (Pair String Int64))
                      (let [(size (sizeOf p))]
                        (if (and (> size 0) (= size (mapGetOr marks (hk p) -1)))
                          (pair (list) (pair (hk p) size))
                          (pair (obsFor p (readText p)) (pair (hk p) size)))))
                    paths))]
    (Found :name name :files (listLength paths) :obs (listFlatMap (fn [(x (Pair (List ob/Obs) (Pair String Int64)))] -> (List ob/Obs) (pairFirst x)) parts)
           :marks (map (fn [(x (Pair (List ob/Obs) (Pair String Int64)))] -> (Pair String Int64) (pairSecond x)) parts)))

fn ctxOf table: (List cl/FailClass) host: String run: String path: String -> src/Ctx
  (src/Ctx :table table :host host :mtime (mtimeMs path) :run run)

fn filesIn dir: String suffix: String -> (List String)
  (map (fn [(f String)] -> String (str dir "/" f)) (filter (fn [(f String)] -> Bool (stringEndsWith? f suffix)) (listDir dir)))

fn one o: (Option ob/Obs) -> (List ob/Obs)
  (match o ((some v) (list v)) ((none) (list)))

fn parentName p: String -> String
  (let [(parts (stringSplit p "/"))]
    (optionOr (listGet parts (- (listLength parts) 2)) ""))

fn existing paths: (List String) -> (List String)
  (filter (fn [(p String)] -> Bool (> (sizeOf p) 0)) paths)

fn evalPaths roots: (List String) -> (List String)
  (listFlatMap (fn [(r String)] -> (List String)
                 (listFlatMap (fn [(run String)] -> (List String)
                                (map (fn [(c String)] -> String (str r "/.asl/run/agentEval/" run "/" c "/receipt.asn"))
                                     (listDir (str r "/.asl/run/agentEval/" run))))
                              (listDir (str r "/.asl/run/agentEval"))))
               roots)

fn condPaths bases: (List String) -> (List String)
  (listFlatMap (fn [(b String)] -> (List String)
                 (map (fn [(d String)] -> String (str b "/" d "/journal.asn")) (filter (fn [(d String)] -> Bool (stringStartsWith? d "cond")) (listDir b))))
               bases)

fn collectFound! table: (List cl/FailClass) host: String home: String roots: (List String) marks: (Map String Int64) nowMs: Int64 sinceMs: Int64 -> (List Found)
  (let [(runBases (map (fn [(r String)] -> String (str r "/.asl/run")) roots))
        (gw (existing (list (str home "/.asl/run/usage/gatewayCalls.asn") (str home "/.asl/run/gatewayCalls.asn"))))
        (bench (existing (listFlatMap (fn [(b String)] -> (List String) (map (fn [(d String)] -> String (str b "/harnessBench/" d "/benchRun.asn")) (listDir (str b "/harnessBench"))))
                                      (cons (str home "/.asl/run") runBases))))
        (fresh (listFlatMap (fn [(r String)] -> (List String) (filesIn (str r "/.asl/tmp/fresh") ".log")) roots))
        (cond (existing (condPaths (cons (str home "/.asl/run") runBases))))
        (journals (filter (fn [(p String)] -> Bool (>= (mtimeMs p) sinceMs)) (listFlatMap (fn [(r String)] -> (List String) (filesIn (str r "/.asl/run/agentLoop") ".journal")) roots)))
        (evals (existing (evalPaths roots)))
        (cals (listFlatMap (fn [(r String)] -> (List String) (filesIn (str r "/.asl/mem/work/CAL") ".asn")) roots))]
    (list
      (foldLines! "gateway" gw marks (fn [(p String)] -> src/Ctx (ctxOf table host "" p)) src/gatewayRow)
      (foldLines! "bench" bench marks (fn [(p String)] -> src/Ctx (ctxOf table host (parentName p) p)) src/benchRow)
      (foldLines! "fresh" fresh marks (fn [(p String)] -> src/Ctx (ctxOf table host (baseName p) p)) src/freshRow)
      (foldLines! "conductor" cond marks (fn [(p String)] -> src/Ctx (ctxOf table host (parentName p) p)) src/condRow)
      (foldFiles! "leon" journals marks (fn [(p String) (t String)] -> (List ob/Obs) (one (src/journalObs (ctxOf table host "" p) nowMs t))))
      (foldFiles! "agentEval" evals marks
        (fn [(p String) (t String)] -> (List ob/Obs)
          (let [(parts (stringSplit p "/"))
                (run (optionOr (listGet parts (- (listLength parts) 3)) ""))
                (caseName (optionOr (listGet parts (- (listLength parts) 2)) ""))]
            (one (src/receiptObs (ctxOf table host run p) caseName t)))))
      (foldFiles! "cal" cals marks (fn [(p String) (t String)] -> (List ob/Obs) (src/calRows (ctxOf table host (baseName p) p) t)))))

fn mkdirs! path: String -> Unit
  (let [(parts (filter (fn [(s String)] -> Bool (not (stringEmpty? s))) (stringSplit path "/")))
        (_ (fold (fn [(acc String) (s String)] -> String (let [(next (str acc "/" s))] (do (if (isDir? next) () (do (dirCreate next) ())) next))) "" parts))]
    ())

fn readMarks! out: String -> (Map String Int64)
  (fold (fn [(m (Map String Int64)) (l String)] -> (Map String Int64)
          (if (stringStartsWith? l "(:off ")
            (let [(f (sx/topFields l))] (mapSet m (optionOr (sx/field f ":k") "") (sx/intField f ":n")))
            m))
        (mapEmpty) (stringLines (readText (str out "/state.asn"))))

fn writeMarks! out: String marks: (Map String Int64) -> Unit
  (do (fileWrite (str out "/state.asn")
        (str (stringJoin (map (fn [(p (Pair String Int64))] -> String (str "(:off :k " (sx/quoteText (pairFirst p)) " :n " (stringFromInt64 (pairSecond p)) ")"))
                              (listSortBy pairFirst (mapPairs marks))) "\n") "\n"))
      ())

fn dayKey o: ob/Obs -> String
  (if (> o.at 0) (ob/dayOf o.at) "unknown")

fn idOfLine l: String -> String
  (optionOr (stringSlice l 11 27) "")

; (:m :do "appends only rows whose id the day file does not hold yet; returns how many were new")
fn writeDay! out: String day: String rows: (List ob/Obs) -> Int64
  (let [(path (str out "/" day ".asn"))
        (have (map idOfLine (filter (fn [(l String)] -> Bool (stringStartsWith? l "(:obs :id ")) (stringLines (readText path)))))
        (lines (map ob/renderObs rows))
        (seen (fold (fn [(acc (Pair (List String) (List String))) (l String)] -> (Pair (List String) (List String))
                      (let [(id (idOfLine l))]
                        (if (listContains? (pairFirst acc) id) acc (pair (cons id (pairFirst acc)) (cons l (pairSecond acc))))))
                    (pair have (list)) lines))
        (fresh (listReverse (pairSecond seen)))]
    (if (listEmpty? fresh)
      0
      (do (fileAppend path (str (stringJoin fresh "\n") "\n"))
          (listLength fresh))))

fn ! collect! root: String home: String host: String out: String sinceDay: String -> String
  (let [(nowMs (/ (nowNs) 1000000))
        (sinceMs (if (stringEmpty? sinceDay) 0 (ob/dayToMs sinceDay)))
        (_ (mkdirs! out))
        (table (loadTable! root))
        (marks (readMarks! out))
        (roots (discoverRoots root home))
        (found (collectFound! table host home roots marks nowMs sinceMs))
        (kept (map (fn [(f Found)] -> Found (with f :obs (filter (fn [(o ob/Obs)] -> Bool (or (= o.at 0) (>= o.at sinceMs))) f.obs))) found))
        (all (listFlatMap (fn [(f Found)] -> (List ob/Obs) f.obs) kept))
        (days (listSort (uniq (map dayKey all))))
        (added (listSum (map (fn [(d String)] -> Int64 (writeDay! out d (filter (fn [(o ob/Obs)] -> Bool (= (dayKey o) d)) all))) days)))
        (newMarks (fold (fn [(m (Map String Int64)) (f Found)] -> (Map String Int64)
                          (fold (fn [(acc (Map String Int64)) (p (Pair String Int64))] -> (Map String Int64) (mapSet acc (pairFirst p) (pairSecond p))) m f.marks))
                        marks kept))
        (_m (writeMarks! out newMarks))
        (bad (filter (fn [(o ob/Obs)] -> Bool (and (!= o.outcome "ok") (!= o.outcome "agg"))) all))
        (unc (listCount (fn [(o ob/Obs)] -> Bool (= o.failClass (cl/unclassifiedId))) bad))]
    (str "(:corpusCollect :host " (sx/quoteText host) " :since " (sx/quoteText sinceDay) " :out " (sx/quoteText out) " :roots " (stringFromInt64 (listLength roots)) "\n  :sources ("
         (stringJoin (map (fn [(f Found)] -> String
                            (str "(:name " (sx/quoteText f.name) " :files " (stringFromInt64 f.files) " :rows " (stringFromInt64 (listLength f.obs))
                                 " :ok " (stringFromInt64 (listCount (fn [(o ob/Obs)] -> Bool (= o.outcome "ok")) f.obs)) ")"))
                          kept) "\n    ")
         ")\n  :total " (stringFromInt64 (listLength all)) " :new " (stringFromInt64 added) " :nonOk " (stringFromInt64 (listLength bad)) " :unclassified " (stringFromInt64 unc) ")"))

fn dayFiles out: String -> (List String)
  (filter (fn [(f String)] -> Bool (and (stringEndsWith? f ".asn") (not (= f "state.asn")))) (listDir out))

fn loadObs! out: String sinceDay: String -> (List ob/Obs)
  (let [(sinceMs (if (stringEmpty? sinceDay) 0 (ob/dayToMs sinceDay)))]
    (filter (fn [(o ob/Obs)] -> Bool (or (= o.at 0) (>= o.at sinceMs)))
            (listFlatMap (fn [(f String)] -> (List ob/Obs)
                           (map ob/parseObs (filter (fn [(l String)] -> Bool (stringStartsWith? l "(:obs ")) (stringLines (readText (str out "/" f))))))
                         (dayFiles out))))

fn ! reportText! root: String out: String by: String sinceDay: String -> String
  (rp/report by (rp/parseLevers (readText (str root "/asl/tools/obs/levers.asn"))) (loadObs! out sinceDay))

fn usage -> String
  "(:usage \"asl run asl/tools/obs/corpus.asl collect [--since DATE] [--host mac|vps] [--out DIR] [--root DIR] | report --by model|case|card|intent|failClass [--since DATE] [--dir DIR] | classes; --home DIR overrides the home dir\")"

fn ! main args: (List String) -> (Result Int64 String)
  (let [(home (optionOr (flagValue args "--home") (resultOr (getHomeDir) "/tmp")))
        (root (optionOr (flagValue args "--root") (resultOr (realPath ".") ".")))
        (out (optionOr (flagValue args "--out") (optionOr (flagValue args "--dir") (str home "/.asl/run/obs"))))
        (since (optionOr (flagValue args "--since") ""))
        (cmd (optionOr (listHead args) ""))]
    (cond
      ((and (= cmd "collect") (some? (flagValue args "--archive"))) (do (println (collectArchive! root home (optionOr (flagValue args "--host") "mac") out (optionOr (flagValue args "--archive") ""))) (ok 0)))
      ((= cmd "collect") (do (println (collect! root home (optionOr (flagValue args "--host") "mac") out since)) (ok 0)))
      ((= cmd "report") (do (println (reportText! root out (optionOr (flagValue args "--by") "model") since)) (ok 0)))
      ((= cmd "classes") (do (println (stringJoin (cl/selfCheck (loadTable! root)) "\n")) (ok 0)))
      (else (do (println (usage)) (ok 2)))))

fn obsOfMember! table: (List cl/FailClass) host: String home: String nowMs: Int64 m: ar/Member -> (List ob/Obs)
  (match (ar/extractText! home m)
    ((err _) (list))
    ((ok text)
      (let [(ctx (src/Ctx :table table :host host :mtime m.mt :run (parentName m.path)))]
        (cond
          ((= m.source "leon") (one (src/journalObs ctx nowMs text)))
          ((= m.source "gateway") (listFlatMap (fn [(l String)] -> (List ob/Obs) (one (src/gatewayRow ctx l))) (stringLines text)))
          ((= m.source "bench") (listFlatMap (fn [(l String)] -> (List ob/Obs) (one (src/benchRow ctx l))) (stringLines text)))
          (else (list))))))

; (:m :ref OBSCORPUS :do "on-demand read of an archived month: Leon journals, gateway ledger rows and bench outputs packed by retain are extracted one member at a time and fed to the same normalisers, so the day files can be rebuilt after the plain sources are gone; ids keep it idempotent")
fn ! collectArchive! root: String home: String host: String out: String month: String -> String
  (let [(nowMs (/ (nowNs) 1000000))
        (_ (mkdirs! out))
        (table (loadTable! root))
        (members (filter (fn [(m ar/Member)] -> Bool (and (= m.archive (str month ".tar.gz")) (or (= m.source "leon") (or (= m.source "gateway") (= m.source "bench"))))) (ar/readIndex! home)))
        (all (listFlatMap (fn [(m ar/Member)] -> (List ob/Obs) (obsOfMember! table host home nowMs m)) members))
        (days (listSort (uniq (map dayKey all))))
        (added (listSum (map (fn [(d String)] -> Int64 (writeDay! out d (filter (fn [(o ob/Obs)] -> Bool (= (dayKey o) d)) all))) days)))]
    (str "(:corpusCollectArchive :month " (sx/quoteText month) " :members " (stringFromInt64 (listLength members)) " :rows " (stringFromInt64 (listLength all)) " :new " (stringFromInt64 added) ")"))
