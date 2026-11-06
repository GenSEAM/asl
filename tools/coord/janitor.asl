(module asl-tools/coord/janitor
  :x [Cfg Scratch WtFact Listing Row defaultCfg digitsOnly? scratchPid levelOpen? heldName? foreignIgnored modeOf aliveFrom wtOk? planRows renderRow renderPlan plan applyAllowed? modeApply? gatherScratch! gatherWts! gather! apply! removedTotals leadReport! tick! main]
  :i [(asl-tools/coord/worktree :a w) (asl-tools/coord/sched :a sc) (asl-tools/coord/store :a st) (asl-tools/fleet/run :a fr) (aslGateway/subPace :a sp) (tools/remote/form :a fm) (asl-tools/coord/leadStream :a ls)])

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
  (:f walkTimeoutS Int64)
  (:f budgetS Int64))

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
  (:f detached Bool)
  (:f foreign Int64)
  (:f st String))

(schema Listing
  (:f nowS Int64)
  (:f level String)
  (:f scratch (List Scratch))
  (:f alive (List Int64))
  (:f held (List String))
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
         :minAgeS 3600 :forceAgeS 86400 :maxPaths 20 :walkTimeoutS 20 :budgetS 30))

fn digitsOnly? s: String -> Bool
  (and (not (stringEmpty? s))
    (listAll? (fn [(c String)] -> Bool (stringContains? "0123456789" c)) (stringChars s)))

; (:m :ref RES-JANITOR :do "the pid of a scratch dir name, -1 when the name is not exactly one of the runner patterns: aslRun-PID-x, formsPin-PID-x, fkCacheTest-PID-x (dash kind, non-empty suffix) and cmdTest-PID, loopRunTest_PID; aslOpsTest_ is named by a clock and aslNCacheLockTest_ has no creator, so neither is a pid name (exact kind); a lookalike such as cmdTestX or cmdTest-12x is -1, and so is a pid of 1 or less")
fn scratchTable -> (List (Pair String String))
  (list (pair "aslRun-" "dash") (pair "formsPin-" "dash") (pair "fkCacheTest-" "dash")
        (pair "cmdTest-" "exact") (pair "loopRunTest_" "exact"))

; (:m :ref JANITOR-TMP-PATTERNS :do "test leftovers whose name carries no pid (a clock or a run id): aslRebuildKeepsPriorRtTest-*, conductorTest-*, trialDriver-* with a non-empty suffix; they are reclaimed when older than the grace period and no live process holds a file open inside them (lsof); aslStubHost-* is deliberately absent, its owner fixes the leak at the source")
fn heldPrefixes -> (List String)
  (list "aslRebuildKeepsPriorRtTest-" "conductorTest-" "trialDriver-")

fn heldName? name: String -> Bool
  (listAny? (fn [(p String)] -> Bool (and (stringStartsWith? name p) (> (stringLength name) (stringLength p)))) (heldPrefixes))

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

; (:m :ref RES-JANITOR :do "ignored entries of git status --porcelain --ignored outside the build allowlist (asl/host/out, .asl/build, .asl/cache); a collapsed ignored directory that is not inside the allowlist counts, so unknown content is kept, never deleted")
fn allowedIgnored? path: String -> Bool
  (listAny? (fn [(a String)] -> Bool (or (= path a) (stringStartsWith? path (str a "/"))))
            (list "asl/host/out" ".asl/build" ".asl/cache"))

fn foreignIgnored lines: (List String) -> Int64
  (listLength
    (filter (fn [(l String)] -> Bool
              (and (stringStartsWith? l "!! ")
                   (let [(raw (optionOr (stringSlice l 3 (stringLength l)) ""))
                         (path (if (stringEndsWith? raw "/") (optionOr (stringSlice raw 0 (- (stringLength raw) 1)) raw) raw))]
                     (not (allowedIgnored? path)))))
            lines))

; (:m :ref RES-JANITOR :do "the mode file is parsed as a form: only (:... :mode apply) read as the exact token apply enables deletion; a comment, a different token, a parse failure or no file is dry")
fn modeOf text: String -> String
  (match (fm/parseForm text)
    ((err _) "dry")
    ((ok node)
      (match (fm/formGet node ":mode")
        ((none) "dry")
        ((some m) (stringTrim (optionOr (fm/formText m) ""))))))

; (:m :ref RES-JANITOR :do "a failed liveness probe counts as alive, so an unknown pid is never reclaimed")
fn aliveFrom r: (Result Bool String) -> Bool
  (resultOr r true)

; (:m :ref RES-JANITOR :do "eligibility by the disk level of sched (RES-GUARD): low or stop opens every class, ok opens only scratch older than forceAgeS")
fn levelOpen? level: String -> Bool
  (or (= level "low") (= level "stop"))

fn scratchFree? l: Listing s: Scratch -> Bool
  (if (heldName? s.name)
    (not (listContains? l.held s.path))
    (and (> (scratchPid s.name) 1) (not (listContains? l.alive (scratchPid s.name)))))

fn scratchRows cfg: Cfg l: Listing -> (List Row)
  (map (fn [(s Scratch)] -> Row
         (Row :class "a" :path s.path :bytes s.bytes :unit ""
              :why (str (if (heldName? s.name) "leftover" (str "deadPid " (stringFromInt64 (scratchPid s.name)))) " ageS " (stringFromInt64 (- l.nowS s.mtimeS)))))
       (filter (fn [(s Scratch)] -> Bool
                 (let [(age (- l.nowS s.mtimeS))]
                   (and (scratchFree? l s)
                     (and (> age cfg.minAgeS)
                       (or (levelOpen? l.level) (> age cfg.forceAgeS))))))
               l.scratch))

; (:m :ref RES-JANITOR :do "a worktree is a row only when its conductor state is merged, it is clean, its head is merged into main, it is not detached (no rescue branch is made) and holds no ignored file outside the build allowlist (git worktree remove deletes ignored files: .asl/mem/work, sessions and *.local.asn live there)")
fn wtOk? x: WtFact -> Bool
  (listAll? (fn [(b Bool)] -> Bool b)
    (list (= x.st "merged") (= x.dirty 0) x.merged (not x.detached) (= x.foreign 0)
          (w/safeUnit? x.unit) (not (w/protectedUnit? x.unit))))

fn wtRows cfg: Cfg l: Listing -> (List Row)
  (if (not (levelOpen? l.level)) (list)
    (map (fn [(x WtFact)] -> Row (Row :class "b" :path x.path :bytes x.bytes :unit x.unit :why "mergedClean"))
         (filter wtOk? l.wts)))

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
  (= (modeOf (resultOr (fileReadString cfg.modePath) "")) "apply")

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
      (let [(cands (listTake (filter (fn [(n String)] -> Bool (or (heldName? n) (> (scratchPid n) 1))) (listSort names)) 500))
            (paths (map (fn [(n String)] -> String (str cfg.tmp "/" n)) cands))
            (dirs (filter (fn [(p String)] -> Bool (match (fileStat p) ((ok s) s.isDir) ((err _) false))) paths))
            (sizes (sizesOf! cfg dirs))
            (items (map (fn [(p String)] -> Scratch
                          (let [(name (optionOr (listLast (stringSplit p "/")) ""))]
                            (Scratch :name name :path p :bytes (sizeFor sizes p) :mtimeS (match (fileStat p) ((ok s) s.mtime) ((err _) nowS)))))
                        dirs))
            (pids (fold (fn [(a (List Int64)) (x Int64)] -> (List Int64) (if (listContains? a x) a (cons x a))) (list) (map (fn [(s Scratch)] -> Int64 (scratchPid s.name)) (filter (fn [(s Scratch)] -> Bool (not (heldName? s.name))) items))))
            (alive (filter (fn [(pid Int64)] -> Bool (aliveFrom (procAlive? pid))) pids))]
        (pair items alive))))

; (:m :ref JANITOR-TMP-PATTERNS :do "held means lsof lists a process with a file open under the path; lsof exits 1 with no output when nothing is open, so any other outcome (timeout, lsof missing, error) counts as held and the leftover is kept")
fn ! heldPath! cfg: Cfg path: String -> Bool
  (let [(r (run! (list "lsof" "-t" "+D" path) cfg.walkTimeoutS))]
    (not (and (= r.exit 1) (stringEmpty? (stringTrim r.out)))))

fn ! heldOf! cfg: Cfg nowS: Int64 items: (List Scratch) -> (List String)
  (map (fn [(s Scratch)] -> String s.path)
       (filter (fn [(s Scratch)] -> Bool (and (heldName? s.name) (and (> (- nowS s.mtimeS) cfg.minAgeS) (heldPath! cfg s.path)))) items))

fn ! cuState! cfg: Cfg id: String -> String
  (match (fileReadString (str cfg.storeDir "/cond/" id ".asn"))
    ((err _) "unknown")
    ((ok raw) (match (st/rowFields raw "cu") ((err _) "unknown") ((ok fs) (st/textField fs "st")))))

fn ! gitIn! dir: String args: (List String) secs: Int64 -> fr/Done
  (run! (cons "git" (cons "-C" (cons dir (cons "-c" (cons "core.fsmonitor=" args))))) secs)

fn ! wcfg! cfg: Cfg -> w/Cfg
  (w/Cfg :repo cfg.repo :base cfg.wtBase :prefix "asex-" :archive (str cfg.runDir "/janitorArchive") :mainRef "main")

fn ! foreignOf! cfg: Cfg path: String -> Int64
  (let [(r (gitIn! path (list "status" "--porcelain" "--ignored=matching") cfg.walkTimeoutS))]
    (if (= r.exit 0) (foreignIgnored (stringLines r.out)) 1))

; (:m :ref RES-JANITOR :do "worktrees are listed once per run; only units with a merged conductor row get a fact, and their ignored files are counted outside the build allowlist (an unreadable status counts as one, so the worktree is kept)")
fn ! gatherWts! cfg: Cfg -> (List WtFact)
  (match (w/listWt! (wcfg! cfg))
    ((err _) (list))
    ((ok ws)
      (let [(merged (listTake (filter (fn [(x w/Wt)] -> Bool (and (w/safeUnit? x.unit) (= (cuState! cfg x.unit) "merged"))) ws) 50))
            (sizes (sizesOf! cfg (map (fn [(x w/Wt)] -> String x.path) merged)))]
        (map (fn [(x w/Wt)] -> WtFact
               (WtFact :unit x.unit :path x.path :bytes (sizeFor sizes x.path) :dirty x.dirty :merged x.merged
                       :detached x.detached :foreign (foreignOf! cfg x.path) :st "merged"))
             merged))))

fn ! gather! cfg: Cfg nowS: Int64 level: String -> Listing
  (let [(sa (gatherScratch! cfg nowS))]
    (Listing :nowS nowS :level level :scratch (pairFirst sa) :alive (pairSecond sa) :held (heldOf! cfg nowS (pairFirst sa))
             :wts (if (levelOpen? level) (gatherWts! cfg) (list))))

; (:m :ref RES-JANITOR :do "right before a scratch removal: the name still matches a runner pattern, the real path is a direct child of TMPDIR (a symlink is refused), the pid is not alive and the mtime is older than minAgeS")
fn ! scratchStillOk! cfg: Cfg r: Row -> Bool
  (let [(name (optionOr (listLast (stringSplit r.path "/")) ""))
        (pid (scratchPid name))
        (real (resultOr (realPath r.path) ""))
        (tmpReal (resultOr (realPath cfg.tmp) ""))
        (mt (match (fileStat r.path) ((ok s) s.mtime) ((err _) (/ (nowNs) 1000000000))))]
    (listAll? (fn [(b Bool)] -> Bool b)
      (list (or (heldName? name) (> pid 1)) (not (stringEmpty? tmpReal)) (= real (str tmpReal "/" name))
            (if (heldName? name) (not (heldPath! cfg r.path)) (not (aliveFrom (procAlive? pid))))
            (> (- (/ (nowNs) 1000000000) mt) cfg.minAgeS))))

; (:m :ref RES-JANITOR :do "right before a worktree removal, fresh facts: the conductor row is merged, no store lease is held, status is clean with no ignored file outside the allowlist, the head is on a branch and merged into main")
fn ! wtStillOk! cfg: Cfg r: Row -> Bool
  (let [(st1 (gitIn! r.path (list "status" "--porcelain") cfg.walkTimeoutS))
        (sym (gitIn! r.path (list "symbolic-ref" "-q" "HEAD") cfg.walkTimeoutS))
        (anc (gitIn! r.path (list "merge-base" "--is-ancestor" "HEAD" "main") cfg.walkTimeoutS))]
    (listAll? (fn [(b Bool)] -> Bool b)
      (list (w/safeUnit? r.unit) (not (w/protectedUnit? r.unit)) (= (resultOr (realPath r.path) "") (str (resultOr (realPath cfg.wtBase) "") "/asex-" r.unit))
            (= (cuState! cfg r.unit) "merged") (not (fileExists? (st/leasePath cfg.storeDir r.unit)))
            (= st1.exit 0) (stringEmpty? (stringTrim st1.out)) (= sym.exit 0) (= anc.exit 0) (= (foreignOf! cfg r.path) 0))))

fn ! removeOne! cfg: Cfg r: Row -> Bool
  (if (= r.class "a")
    (if (scratchStillOk! cfg r) (ok? (pathRemove r.path)) false)
    (if (wtStillOk! cfg r) (= (gitIn! cfg.repo (list "worktree" "remove" r.path) cfg.walkTimeoutS).exit 0) false))

fn ! nowMs! -> Int64
  (/ (nowNs) 1000000)

fn removedRow r: Row ok: Bool -> String
  (str "(:removed :path " (q r.path) " :class " r.class " :bytes " (stringFromInt64 r.bytes) " :ok " (if ok "true" "false") ")")

; (:m :ref RES-JANITOR :do "apply removes planned rows one by one until the deadline, each after its fresh re-check, and appends a (:removed ...) row to the plan file as it happens; rows past the deadline are deferred to the next tick; worktrees go only through git worktree remove without force")
fn ! applyLoop! cfg: Cfg rows: (List Row) deadline: Int64 planPath: String -> Int64
  (match (listHead rows)
    ((none) 0)
    ((some r)
      (if (>= (nowMs!) deadline) (listLength rows)
        (let [(ok (removeOne! cfg r))
              (_ (fileAppend planPath (stringToBytes (str (removedRow r ok) "\n"))))]
          (applyLoop! cfg (listDrop rows 1) deadline planPath)))))

fn ! apply! cfg: Cfg rows: (List Row) -> Int64
  (applyLoop! cfg rows (+ (nowMs!) (* cfg.budgetS 1000)) (str cfg.runDir "/janitor.asn"))

; (:m :ref LEAD-STREAM :do "the run's totals from its plan file: the count and the bytes of the (:removed ... :ok true) rows, one pass, so a run is one event and never one per path")
fn removedTotals text: String -> (Pair Int64 Int64)
  (fold (fn [(a (Pair Int64 Int64)) (l String)] -> (Pair Int64 Int64)
          (if (and (stringStartsWith? l "(:removed ") (stringContains? l " :ok true"))
            (pair (+ (pairFirst a) 1)
                  (+ (pairSecond a)
                     (match (stringIndexOf l " :bytes ")
                       ((none) 0)
                       ((some i) (optionOr (stringToInt64 (optionOr (listHead (stringSplit (optionOr (stringSlice l (+ i 8) (stringLength l)) "") " ")) "")) 0)))))
            a))
        (pair 0 0) (stringLines text))

; (:m :ref LEAD-STREAM :do "an apply run that removed something lands one info event (key run) with the count and bytes; a dry run or an empty run lands none")
fn ! leadReport! cfg: Cfg -> Bool
  (let [(t (removedTotals (resultOr (fileReadString (str cfg.runDir "/janitor.asn")) "")))]
    (if (> (pairFirst t) 0)
      (ls/emitAt! cfg.runDir (nowMs!) "janitor" "info" "removed" "run" ""
                  (str "removed " (stringFromInt64 (pairFirst t)) " paths, " (stringFromInt64 (pairSecond t)) " bytes"))
      false))

; (:m :ref RES-JANITOR :do "one tick: the level comes from sched (levelRead! of the store dir), the plan is written to <runDir>/janitor.asn first, then deletes only when the mode file says apply; returns the plan text")
fn ! tick! cfg: Cfg -> String
  (let [(nowS (/ (nowNs) 1000000000))
        (level (sc/levelRead! cfg.storeDir))
        (l (gather! cfg nowS level))
        (rows (plan cfg l))
        (apply (modeApply? cfg))
        (head (renderPlan (if apply "apply" "dry") level nowS rows))
        (_ (dirCreate cfg.runDir))
        (_ (fileWrite (str cfg.runDir "/janitor.asn") (str head "\n")))
        (deferred (if apply (apply! cfg rows) 0))
        (_ (if (> deferred 0) (ok? (fileAppend (str cfg.runDir "/janitor.asn") (stringToBytes (str "(:deferred :n " (stringFromInt64 deferred) ")\n")))) false))
        (_ (if apply (leadReport! cfg) false))]
    head)

fn ! main args: (List String) -> (Result Int64 String)
  (do (println (tick! (defaultCfg)))
      (ok 0))
