(module asl-tools/coord/janitor
  :x [Cfg Scratch WtFact Listing Row defaultCfg digitsOnly? scratchPid levelOpen? planRows renderRow renderPlan plan applyAllowed? modeApply? gatherScratch! gatherWts! gather! apply! tick! main]
  :i [(asl-tools/coord/worktree :a w) (asl-tools/coord/sched :a sc) (asl-tools/coord/store :a st) (asl-tools/fleet/run :a fr) (aslGateway/subPace :a sp)])

; (:m :ref RES-JANITOR :do "the node reclaims only its own leftovers: (a) test scratch dirs of a dead pid under TMPDIR and (b) worktrees of conductor units whose state is merged, clean and not ahead of main; plan is pure over a listing, dry-run is the default and writes ~/.asl/run/janitor.asn, deletion needs `:mode apply` in ~/.asl/conductor/janitor.asn; no caches, no nativeCli, no journals")
(schema Cfg
  (:f tmp String)
  (:f runDir String)
  (:f modePath String)
  (:f storeDir String)
  (:f repo String)
  (:f wtBase String)
  (:f minAgeS Int64)
  (:f forceAgeS Int64)
  (:f maxPaths Int64)
  (:f walkTimeoutS Int64))

(schema Scratch
  (:f name String)
  (:f path String)
  (:f bytes Int64)
  (:f mtimeS Int64))

(schema WtFact
  (:f unit String)
  (:f path String)
  (:f bytes Int64)
  (:f dirty Int64)
  (:f merged Bool)
  (:f st String))

(schema Listing
  (:f nowS Int64)
  (:f level String)
  (:f scratch (List Scratch))
  (:f alive (List Int64))
  (:f wts (List WtFact)))

(schema Row
  (:f class String)
  (:f path String)
  (:f bytes Int64)
  (:f why String)
  (:f unit String))

fn ! home! -> String
  (optionOr (envGet "HOME") "/tmp")

fn ! defaultCfg -> Cfg
  (let [(h (home!))]
    (Cfg :tmp (optionOr (envGet "TMPDIR") "/tmp") :runDir (str h "/.asl/run") :modePath (str h "/.asl/conductor/janitor.asn")
         :storeDir (str h "/.asl/run/conductor") :repo (str h "/wt/main") :wtBase (str h "/wt/worktrees")
         :minAgeS 3600 :forceAgeS 86400 :maxPaths 20 :walkTimeoutS 20))

fn digitsOnly? s: String -> Bool
  (and (not (stringEmpty? s))
    (listAll? (fn [(c String)] -> Bool (stringContains? "0123456789" c)) (stringChars s)))

; (:m :ref RES-JANITOR :do "the pid of a scratch dir name, -1 when the name is not exactly one of the runner patterns: aslRun-PID-x, formsPin-PID-x, fkCacheTest-PID-x (dash kind, non-empty suffix) and cmdTest-PID, aslOpsTest_PID, aslNCacheLockTest_PID, loopRunTest_PID (exact kind); a lookalike such as cmdTestX or cmdTest-12x is -1, and so is a pid of 1 or less")
fn scratchTable -> (List (Pair String String))
  (list (pair "aslRun-" "dash") (pair "formsPin-" "dash") (pair "fkCacheTest-" "dash")
        (pair "cmdTest-" "exact") (pair "aslOpsTest_" "exact") (pair "aslNCacheLockTest_" "exact") (pair "loopRunTest_" "exact"))

fn pidOfTail kind: String rest: String -> Int64
  (cond
    ((= kind "exact") (if (digitsOnly? rest) (optionOr (stringToInt64 rest) -1) -1))
    (else
      (let [(parts (stringSplit rest "-"))]
        (if (and (>= (listLength parts) 2)
                 (and (digitsOnly? (optionOr (listHead parts) ""))
                      (not (stringEmpty? (stringJoin (listDrop parts 1) "-")))))
          (optionOr (stringToInt64 (optionOr (listHead parts) "")) -1)
          -1))))

fn scratchPid name: String -> Int64
  (let [(pid (fold (fn [(acc Int64) (p (Pair String String))] -> Int64
                     (if (and (< acc 0) (stringStartsWith? name (pairFirst p)))
                       (pidOfTail (pairSecond p) (optionOr (stringSlice name (stringLength (pairFirst p)) (stringLength name)) ""))
                       acc))
                   -1 (scratchTable)))]
    (if (> pid 1) pid -1))

; (:m :ref RES-JANITOR :do "eligibility by the disk level of sched (RES-GUARD): low or stop opens every class, ok opens only scratch older than forceAgeS")
fn levelOpen? level: String -> Bool
  (or (= level "low") (= level "stop"))

fn scratchRows cfg: Cfg l: Listing -> (List Row)
  (map (fn [(s Scratch)] -> Row
         (Row :class "a" :path s.path :bytes s.bytes :unit ""
              :why (str "deadPid " (stringFromInt64 (scratchPid s.name)) " ageS " (stringFromInt64 (- l.nowS s.mtimeS)))))
       (filter (fn [(s Scratch)] -> Bool
                 (let [(pid (scratchPid s.name))
                       (age (- l.nowS s.mtimeS))]
                   (and (> pid 1)
                     (and (not (listContains? l.alive pid))
                       (and (> age cfg.minAgeS)
                         (or (levelOpen? l.level) (> age cfg.forceAgeS)))))))
               l.scratch))

fn wtRows cfg: Cfg l: Listing -> (List Row)
  (if (not (levelOpen? l.level)) (list)
    (map (fn [(x WtFact)] -> Row (Row :class "b" :path x.path :bytes x.bytes :unit x.unit :why "mergedClean"))
         (filter (fn [(x WtFact)] -> Bool
                   (and (= x.st "merged")
                     (and (= x.dirty 0)
                       (and x.merged
                         (and (w/safeUnit? x.unit) (not (w/protectedUnit? x.unit)))))))
                 l.wts)))

; (:m :ref RES-JANITOR :do "the pure plan: reclaim rows for class a (dead pid and older than minAgeS, both) and class b (conductor state merged, clean, head merged into main), biggest first, cut at maxPaths; nothing else is ever a row")
fn planRows cfg: Cfg l: Listing -> (List Row)
  (listTake (listSortBy (fn [(r Row)] -> Int64 (- 0 r.bytes)) (listAppend (scratchRows cfg l) (wtRows cfg l))) cfg.maxPaths)

fn plan cfg: Cfg l: Listing -> (List Row)
  (planRows cfg l)

fn q s: String -> String
  (str "\"" s "\"")

fn renderRow r: Row -> String
  (str "(:reclaim :path " (q r.path) " :bytes " (stringFromInt64 r.bytes) " :why " (q r.why) " :class " r.class (if (stringEmpty? r.unit) "" (str " :unit " (q r.unit))) ")")

fn totalOf rows: (List Row) class: String -> Int64
  (fold (fn [(a Int64) (r Row)] -> Int64 (+ a r.bytes)) 0 (filter (fn [(r Row)] -> Bool (= r.class class)) rows))

fn countOf rows: (List Row) class: String -> Int64
  (listLength (filter (fn [(r Row)] -> Bool (= r.class class)) rows))

fn renderPlan mode: String level: String nowS: Int64 rows: (List Row) -> String
  (str "(:janitor :at " (stringFromInt64 (* nowS 1000)) " :mode " mode " :level " level
       " :a (:n " (stringFromInt64 (countOf rows "a")) " :bytes " (stringFromInt64 (totalOf rows "a")) ")"
       " :b (:n " (stringFromInt64 (countOf rows "b")) " :bytes " (stringFromInt64 (totalOf rows "b")) "))"
       (stringJoin (map (fn [(r Row)] -> String (str "\n" (renderRow r))) rows) ""))

fn ! modeApply? cfg: Cfg -> Bool
  (= (sp/tokAfter (resultOr (fileReadString cfg.modePath) "") ":mode") "apply")

fn applyAllowed? mode: String -> Bool
  (= mode "apply")

fn ! run! argv: (List String) secs: Int64 -> fr/Done
  (fr/runOneLimited (fr/job argv "." (fr/childEnv (list))) (fr/limits secs 16))

; (:m :ref RES-JANITOR :do "sizes come from one bounded du call over the candidate paths; a timeout or failure leaves unknown sizes as 0, never an unbounded walk")
fn ! sizesOf! cfg: Cfg paths: (List String) -> (List (Pair String Int64))
  (if (listEmpty? paths) (list)
    (let [(r (run! (cons "du" (cons "-sk" paths)) cfg.walkTimeoutS))]
      (filter (fn [(p (Pair String Int64))] -> Bool (not (stringEmpty? (pairFirst p))))
        (map (fn [(l String)] -> (Pair String Int64)
               (let [(parts (stringSplit l "\t"))]
                 (pair (stringJoin (listDrop parts 1) "\t") (* 1024 (optionOr (stringToInt64 (optionOr (listHead parts) "")) 0)))))
             (stringLines r.out)))))

fn sizeFor sizes: (List (Pair String Int64)) path: String -> Int64
  (optionOr (listHead (map pairSecond (filter (fn [(p (Pair String Int64))] -> Bool (= (pairFirst p) path)) sizes))) 0)

fn ! gatherScratch! cfg: Cfg nowS: Int64 -> (Pair (List Scratch) (List Int64))
  (match (dirList cfg.tmp)
    ((err _) (pair (list) (list)))
    ((ok names)
      (let [(cands (listTake (filter (fn [(n String)] -> Bool (> (scratchPid n) 1)) (listSort names)) 500))
            (paths (map (fn [(n String)] -> String (str cfg.tmp "/" n)) cands))
            (dirs (filter (fn [(p String)] -> Bool (match (fileStat p) ((ok s) s.isDir) ((err _) false))) paths))
            (sizes (sizesOf! cfg dirs))
            (items (map (fn [(p String)] -> Scratch
                          (let [(name (optionOr (listLast (stringSplit p "/")) ""))]
                            (Scratch :name name :path p :bytes (sizeFor sizes p) :mtimeS (match (fileStat p) ((ok s) s.mtime) ((err _) nowS)))))
                        dirs))
            (pids (fold (fn [(a (List Int64)) (x Int64)] -> (List Int64) (if (listContains? a x) a (cons x a))) (list) (map (fn [(s Scratch)] -> Int64 (scratchPid s.name)) items)))
            (alive (filter (fn [(pid Int64)] -> Bool (resultOr (procAlive? pid) true)) pids))]
        (pair items alive))))

fn ! cuState! cfg: Cfg id: String -> String
  (match (fileReadString (str cfg.storeDir "/cond/" id ".asn"))
    ((err _) "unknown")
    ((ok raw) (match (st/rowFields raw "cu") ((err _) "unknown") ((ok fs) (st/textField fs "st")))))

fn ! gatherWts! cfg: Cfg -> (List WtFact)
  (match (w/listWt! (w/Cfg :repo cfg.repo :base cfg.wtBase :prefix "asex-" :archive (str cfg.runDir "/janitorArchive") :mainRef "main"))
    ((err _) (list))
    ((ok ws)
      (let [(merged (filter (fn [(x w/Wt)] -> Bool (and (w/safeUnit? x.unit) (= (cuState! cfg x.unit) "merged"))) ws))
            (sizes (sizesOf! cfg (map (fn [(x w/Wt)] -> String x.path) merged)))]
        (map (fn [(x w/Wt)] -> WtFact (WtFact :unit x.unit :path x.path :bytes (sizeFor sizes x.path) :dirty x.dirty :merged x.merged :st "merged")) merged))))

fn ! gather! cfg: Cfg nowS: Int64 level: String -> Listing
  (let [(sa (gatherScratch! cfg nowS))]
    (Listing :nowS nowS :level level :scratch (pairFirst sa) :alive (pairSecond sa)
             :wts (if (levelOpen? level) (gatherWts! cfg) (list))))

fn ! removeScratch! cfg: Cfg r: Row -> Bool
  (let [(name (optionOr (listLast (stringSplit r.path "/")) ""))
        (real (resultOr (realPath r.path) ""))
        (tmpReal (resultOr (realPath cfg.tmp) ""))]
    (if (and (> (scratchPid name) 1)
             (and (not (stringEmpty? tmpReal)) (= real (str tmpReal "/" name))))
      (ok? (pathRemove r.path))
      false))

; (:m :ref RES-JANITOR :do "apply removes exactly the planned rows: a scratch row only while its name still matches a runner pattern and its real path is a direct child of TMPDIR; a worktree row only through worktree.removeWt! without force (git worktree remove, which keeps anything dirty or unmerged), never rm")
fn ! apply! cfg: Cfg rows: (List Row) -> (List (Pair String Bool))
  (map (fn [(r Row)] -> (Pair String Bool)
         (pair r.path
           (if (= r.class "a") (removeScratch! cfg r)
             (match (w/removeWt! (w/Cfg :repo cfg.repo :base cfg.wtBase :prefix "asex-" :archive (str cfg.runDir "/janitorArchive") :mainRef "main") r.unit false)
               ((ok s) (stringStartsWith? s "(:wtRemoved"))
               ((err _) false)))))
       rows)

; (:m :ref RES-JANITOR :do "one tick: the level comes from sched (levelRead! of the store dir), the plan is written to <runDir>/janitor.asn; deletes only when the mode file says apply, and then appends one (:removed :path :ok) row per path")
fn ! tick! cfg: Cfg -> String
  (let [(nowS (/ (nowNs) 1000000000))
        (level (sc/levelRead! cfg.storeDir))
        (l (gather! cfg nowS level))
        (rows (plan cfg l))
        (apply (modeApply? cfg))
        (head (renderPlan (if apply "apply" "dry") level nowS rows))
        (done (if apply (apply! cfg rows) (list)))
        (tail (stringJoin (map (fn [(d (Pair String Bool))] -> String (str "\n(:removed :path " (q (pairFirst d)) " :ok " (if (pairSecond d) "true" "false") ")")) done) ""))
        (_ (dirCreate cfg.runDir))
        (_ (fileWrite (str cfg.runDir "/janitor.asn") (str head tail "\n")))]
    (str head tail))

fn ! main args: (List String) -> (Result Int64 String)
  (do (println (tick! (defaultCfg)))
      (ok 0))
