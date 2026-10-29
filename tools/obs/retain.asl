(module ws/asl/tools/obs/retain
  :x [Item plan! apply! packItem! removeVerified! main]
  :i [(ws/asl/tools/obs/sx :a sx)
      (ws/asl/tools/obs/obs :a ob)
      (ws/asl/tools/obs/archive :a ar)
      (ws/asl/tools/obs/corpus :a co)
      (asl-zip/gzipWriter :a gw)])

; (:m :ref OBSCORPUS :do "retention: sources older than keepDays are packed into one archive per month with an index row per member; originals go only after the member inflates back to its recorded sha; a ledger keeps its newest days as plain rows; build caches (asl1, nativeCli, nativeTest, corpusCache, hosts) are never listed")
(schema Item
  (:f source String)
  (:f path String)
  (:f kind String)
  (:f month String)
  (:f from String)
  (:f to String)
  (:f bytes Int64)
  (:f mt Int64)
  (:f size Int64))

fn dayMs -> Int64
  86400000

fn n v: Int64 -> String
  (stringFromInt64 v)

fn walk dir: String -> (List String)
  (listFlatMap (fn [(e String)] -> (List String)
                 (let [(p (str dir "/" e))]
                   (if (co/isDir? p) (walk p) (list p))))
               (co/listDir dir))

fn fileItem source: String cutoff: Int64 p: String -> (List Item)
  (let [(mt (co/mtimeMs p))
        (size (co/sizeOf p))]
    (if (and (> mt 0) (< mt cutoff))
      (list (Item :source source :path p :kind "file" :month (ar/monthOf (ob/dayOf mt)) :from (ob/dayOf mt) :to (ob/dayOf mt) :bytes size :mt mt :size size))
      (list)))

fn obsItems home: String cutoff: Int64 -> (List Item)
  (let [(dir (str home "/.asl/run/obs"))
        (cutDay (ob/dayOf cutoff))]
    (listFlatMap (fn [(f String)] -> (List Item)
                   (let [(day (optionOr (stringSlice f 0 10) ""))
                         (p (str dir "/" f))]
                     (if (and (stringEndsWith? f ".asn") (and (= (stringLength f) 14) (< day cutDay)))
                       (list (Item :source "obs" :path p :kind "file" :month (ar/monthOf day) :from day :to day :bytes (co/sizeOf p) :mt (co/mtimeMs p) :size (co/sizeOf p)))
                       (list))))
                 (co/listDir dir)))

fn ledgerItems path: String cutoff: Int64 -> (List Item)
  (let [(text (co/readText path))
        (size (co/sizeOf path))
        (rows (filter (fn [(l String)] -> Bool (and (stringStartsWith? l "(:call ") (< (sx/intField (sx/topFields l) ":at") cutoff))) (stringLines text)))
        (byMonth (fold (fn [(m (Map String (List String))) (l String)] -> (Map String (List String))
                         (let [(k (ar/monthOf (ob/dayOf (sx/intField (sx/topFields l) ":at"))))]
                           (mapSet m k (cons l (mapGetOr m k (list))))))
                       (mapEmpty) rows))]
    (map (fn [(p (Pair String (List String)))] -> Item
           (let [(days (listSort (map (fn [(l String)] -> String (ob/dayOf (sx/intField (sx/topFields l) ":at"))) (pairSecond p))))]
             (Item :source "gateway" :path path :kind "rows" :month (pairFirst p) :from (optionOr (listHead days) "") :to (optionOr (listLast days) "")
                   :bytes (listSum (map (fn [(l String)] -> Int64 (+ 1 (stringLength l))) (pairSecond p))) :mt 0 :size size)))
         (listSortBy pairFirst (mapPairs byMonth))))

fn itemKey i: Item -> String
  (str i.source "|" i.path "|" i.month)

; (:m :ref OBSCORPUS :do "candidate list: obs day files, Leon journals and patches, gateway ledger rows, harness receipts, bench outputs and trainlogs, each older than the cutoff; sorted so the same tree always prints the same plan")
fn candidates home: String root: String cutoff: Int64 -> (List Item)
  (let [(run (str home "/.asl/run"))
        (roots (co/discoverRoots root home))]
    (listSortBy itemKey
      (listAppend (obsItems home cutoff)
        (listAppend (listFlatMap (fn [(r String)] -> (List Item)
                                   (listFlatMap (fn [(f String)] -> (List Item)
                                                  (if (or (stringEndsWith? f ".journal") (stringEndsWith? f ".patch")) (fileItem "leon" cutoff (str r "/.asl/run/agentLoop/" f)) (list)))
                                                (co/listDir (str r "/.asl/run/agentLoop"))))
                                 roots)
          (listAppend (listFlatMap (fn [(g String)] -> (List Item) (if (> (co/sizeOf g) 0) (ledgerItems g cutoff) (list)))
                                   (list (str run "/usage/gatewayCalls.asn") (str run "/gatewayCalls.asn")))
            (listAppend (listFlatMap (fn [(p String)] -> (List Item) (fileItem "harness" cutoff p)) (walk (str run "/harness")))
              (listAppend (listFlatMap (fn [(p String)] -> (List Item) (fileItem "bench" cutoff p)) (walk (str run "/harnessBench")))
                          (listFlatMap (fn [(p String)] -> (List Item) (fileItem "trainlog" cutoff p)) (walk (str run "/trainlogs"))))))))))

fn planRow i: Item -> String
  (str "(:item :source " (sx/quoteText i.source) " :path " (sx/quoteText i.path) " :kind " (sx/quoteText i.kind) " :month " (sx/quoteText i.month)
       " :from " (sx/quoteText i.from) " :to " (sx/quoteText i.to) " :bytes " (n i.bytes) ")")

fn plan! home: String root: String keepDays: Int64 nowMs: Int64 -> String
  (let [(cutoff (- nowMs (* keepDays (dayMs))))
        (items (candidates home root cutoff))
        (total (listSum (map (fn [(i Item)] -> Int64 i.bytes) items)))
        (bySource (listSortBy pairFirst (mapPairs (fold (fn [(m (Map String Int64)) (i Item)] -> (Map String Int64) (mapSet m i.source (+ i.bytes (mapGetOr m i.source 0)))) (mapEmpty) items))))]
    (str "(:retainPlan :keepDays " (n keepDays) " :cutoff " (sx/quoteText (ob/dayOf cutoff)) " :items " (n (listLength items)) " :rawBytes " (n total)
         " :bySource (" (stringJoin (map (fn [(p (Pair String Int64))] -> String (str "(" (pairFirst p) " " (n (pairSecond p)) ")")) bySource) " ") ")"
         " :note \"rawBytes is the size before compression; the saving is rawBytes minus the archive growth, printed by apply\"\n  :rows (\n    "
         (stringJoin (map planRow items) "\n    ") "))"))

fn tarName i: Item -> String
  (let [(base (optionOr (listLast (stringSplit i.path "/")) i.path))]
    (str i.source "/" (co/hk (itemKey i)) "-" (if (> (stringLength base) 60) (optionOr (stringSlice base 0 60) base) base)
         (if (= i.kind "rows") (str "." i.month) "")))

fn oldRows path: String cutoff: Int64 month: String -> (List String)
  (filter (fn [(l String)] -> Bool
            (and (stringStartsWith? l "(:call ")
                 (let [(at (sx/intField (sx/topFields l) ":at"))]
                   (and (< at cutoff) (= (ar/monthOf (ob/dayOf at)) month)))))
          (stringLines (co/readText path)))

fn dataOf! i: Item cutoff: Int64 -> (Result Bytes String)
  (if (= i.kind "rows")
    (ok (stringToBytes (str (stringJoin (oldRows i.path cutoff i.month) "\n") "\n")))
    (fileReadBytes i.path))

fn zeros k: Int64 -> Bytes
  (let [(b (bytesAlloc k))
        (_ (fold (fn [(u Unit) (j Int64)] -> Unit (bytesSet b j 0)) () (range 0 k)))]
    b)

fn appendBytes! path: String b: Bytes -> (Result Int64 String)
  (match (fileAppend path b)
    ((err e) (err e))
    ((ok _) (ok (bytesLength b))))

; (:m :ref OBSCORPUS :do "packs one item: header member, data member, padding member are appended to the month archive; the index row is returned for the caller to append only after the member verifies")
fn ! packItem! home: String i: Item cutoff: Int64 -> (Result ar/Member String)
  (match (dataOf! i cutoff)
    ((err e) (err e))
    ((ok data)
      (let [(arc (str (ar/monthOf i.month) ".tar.gz"))
            (path (str (ar/archiveDir home) "/" arc))
            (size (bytesLength data))
            (pad (- 512 (- size (* 512 (/ size 512)))))
            (hdr (ar/tarHeader (tarName i) size (/ (if (> i.mt 0) i.mt (co/mtimeMs i.path)) 1000)))]
        (match (gw/gzip! hdr (ar/gzipLevel))
          ((err e) (err e))
          ((ok zh)
            (match (gw/gzip! data (ar/gzipLevel))
              ((err e) (err e))
              ((ok zd)
                (let [(start (co/sizeOf path))
                      (a (appendBytes! path zh))
                      (b (appendBytes! path zd))
                      (c (if (= pad 512) (ok 0) (match (gw/gzip! (zeros pad) (ar/gzipLevel)) ((ok zp) (appendBytes! path zp)) ((err e) (err e)))))]
                  (match c
                    ((err e) (err e))
                    ((ok _)
                      (ok (ar/Member :archive arc :source i.source :path i.path :kind i.kind :month i.month :bytes size :sha (bytesSha256 data)
                                     :from i.from :to i.to :off (+ start (bytesLength zh)) :len (bytesLength zd) :mt i.mt))))))))))))

; (:m :ref OBSCORPUS :do "removal after verification: a file goes only if it still has the planned size and mtime; a ledger is rewritten to its tail through a temp file and rename, and only if its size did not change since the rows were read, so a concurrent gateway append is never lost")
fn ! removeVerified! home: String i: Item m: ar/Member cutoff: Int64 -> String
  (cond
    ((not (ar/verify! home m)) "unverified")
    ((= i.kind "file")
      (if (and (= (co/sizeOf i.path) i.size) (= (co/mtimeMs i.path) i.mt))
        (match (pathRemove i.path) ((ok _) "removed") ((err e) (str "error " e)))
        "changed"))
    (else
      (let [(text (co/readText i.path))
            (keep (filter (fn [(l String)] -> Bool (not (listContains? (oldRows i.path cutoff i.month) l))) (stringLines text)))
            (tmp (str i.path ".retain-tmp"))]
        (if (!= (co/sizeOf i.path) i.size)
          "changed"
          (match (fileWrite tmp (str (stringJoin keep "\n") (if (listEmpty? keep) "" "\n")))
            ((err e) (str "error " e))
            ((ok _)
              (if (!= (co/sizeOf i.path) i.size)
                (do (pathRemove tmp) "changed")
                (match (pathRename tmp i.path) ((ok _) "removed") ((err e) (str "error " e))))))))))

fn ! apply! home: String root: String keepDays: Int64 nowMs: Int64 collectFirst: Bool -> String
  (let [(cutoff (- nowMs (* keepDays (dayMs))))
        (obsDir (str home "/.asl/run/obs"))
        (_c (if collectFirst (do (println (co/collect! root home "mac" obsDir "")) ()) ()))
        (items (candidates home root cutoff))
        (_d (co/mkdirs! (ar/archiveDir home)))
        (before (listSum (map (fn [(f String)] -> Int64 (co/sizeOf (str (ar/archiveDir home) "/" f))) (filter (fn [(f String)] -> Bool (stringEndsWith? f ".tar.gz")) (co/listDir (ar/archiveDir home))))))
        (results (map (fn [(i Item)] -> (Pair String Int64)
                        (match (packItem! home i cutoff)
                          ((err e) (pair (str "packError " (sx/quoteText e)) 0))
                          ((ok m)
                            (let [(_i (fileAppend (ar/indexPath home) (str (ar/renderMember m) "\n")))
                                  (r (removeVerified! home i m cutoff))]
                              (pair r i.bytes)))))
                      items))
        (count (fn [(k String)] -> Int64 (listCount (fn [(p (Pair String Int64))] -> Bool (= (pairFirst p) k)) results)))
        (after (listSum (map (fn [(f String)] -> Int64 (co/sizeOf (str (ar/archiveDir home) "/" f))) (filter (fn [(f String)] -> Bool (stringEndsWith? f ".tar.gz")) (co/listDir (ar/archiveDir home))))))
        (raw (listSum (map (fn [(p (Pair String Int64))] -> Int64 (if (= (pairFirst p) "removed") (pairSecond p) 0)) results)))]
    (str "(:retainApply :keepDays " (n keepDays) " :items " (n (listLength items)) " :removed " (n (count "removed")) " :unverified " (n (count "unverified"))
         " :changed " (n (count "changed")) " :rawBytesRemoved " (n raw) " :archiveGrew " (n (- after before)) " :savedBytes " (n (- raw (- after before))) ")"))

fn flagValue args: (List String) name: String -> (Option String)
  (match (listIndexOf args name)
    ((some i) (listGet args (+ i 1)))
    ((none) none))

fn ! main args: (List String) -> (Result Int64 String)
  (let [(home (optionOr (flagValue args "--home") (resultOr (getHomeDir) "/tmp")))
        (root (optionOr (flagValue args "--root") (resultOr (realPath ".") ".")))
        (keep (optionOr (stringToInt64 (optionOr (flagValue args "--keepDays") "14")) 14))
        (now (optionOr (stringToInt64 (optionOr (flagValue args "--nowMs") "")) (/ (nowNs) 1000000)))
        (cmd (optionOr (listHead args) ""))]
    (cond
      ((= cmd "plan") (do (println (plan! home root keep now)) (ok 0)))
      ((= cmd "apply") (do (println (apply! home root keep now (not (listContains? args "--noCollect")))) (ok 0)))
      (else (do (println "(:usage \"asl run asl/tools/obs/retain.asl plan|apply --root DIR [--home DIR] [--keepDays N] [--nowMs MS] [--noCollect]\")") (ok 2)))))
