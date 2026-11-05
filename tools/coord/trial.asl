(module asl-tools/coord/trial
  :x [Spec Head Model TTask Cell emptySpec parseSpec specLines! cellsOf cellId devBranchOf specProblems! headProblems! stageArgv recordText leonFacts runsPath trialDir
      check! run! collect! main]
  :i [(asl-tools/coord/conductor :a cd) (asl-tools/coord/store :a st) (asl-tools/fleet/run :a fr) (asl-syntax/asl/asn :a asn) (aslGateway/subPace :a sp)])

; (:m :ref LEON-TRIAL :do "TRIAL-DRIVER: N pinned writer models on the same tasks through the real stage CLI (conductor.asl stage write|gates|review|merge), one attempt per (task, model) cell, no ladder and no tick; each merge lands on its own scratch branch <devPrefix><cell> in a devRepo that is never main, and the production heads named in the spec are compared before and after so the trial never moves them")

(schema Head (:f repo String) (:f sha String) (:f ref String))
(schema Model (:f tag String) (:f alias String))
(schema TTask (:f id String) (:f owns (List String)) (:f gate String) (:f text String) (:f skipWrite Bool) (:f seed String) (:f known String))
(schema Cell (:f id String) (:f task TTask) (:f model Model))
(schema Spec
  (:f store String) (:f repo String) (:f toolRoot String) (:f devRepo String) (:f devPrefix String) (:f devBase String) (:f worktrees String)
  (:f home String) (:f lanes String) (:f keys String) (:f base String) (:f profile String) (:f leaseSec Int64) (:f writers Int64) (:f gates Int64)
  (:f reviews Int64) (:f stageSec Int64) (:f minFreeMb Int64) (:f minDiskMb Int64) (:f analyzer (List String))
  (:f heads (List Head)) (:f models (List Model)) (:f tasks (List TTask)) (:f corpus (List String)))

fn n i: Int64 -> String
  (stringFromInt64 i)

fn ! nowMs -> Int64
  (/ (nowNs) 1000000)

fn failRes sig: String -> cd/Res
  (cd/Res :tiers "" :ok 0 :wt "" :branch "" :model "" :tokens 0 :costMicro 0 :claimedGreen 0 :sig sig :ms 0 :exit 1 :asserts 0 :verdict "fail")

fn emptySpec -> Spec
  (Spec :store "" :repo "" :toolRoot "" :devRepo "" :devPrefix "trialDev-" :devBase "" :worktrees "" :home "" :lanes "" :keys "" :base "main" :profile "freeBulk"
        :leaseSec 1800 :writers 4 :gates 2 :reviews 4 :stageSec 3600 :minFreeMb 3000 :minDiskMb 15000 :analyzer (list)
        :heads (list) :models (list) :tasks (list) :corpus (list))


fn fieldOf fields: (List asn/AsnField) key: String -> (Option asn/AsnValue)
  (match (listFind (fn [(f asn/AsnField)] -> Bool (= f.key (str ":" key))) fields)
    ((some f) (some f.val))
    ((none) (none)))

fn textOf v: asn/AsnValue -> String
  (match v
    ((asn/asnSym name) name)
    ((asn/asnKw k) (if (stringStartsWith? k ":") (optionOr (stringSlice k 1 (stringLength k)) k) k))
    ((asn/asnBool b) (if b "true" "false"))
    ((asn/asnInt lex) lex)
    (_ (optionOr (asn/asnStringValue v) "")))

fn itemsOf v: asn/AsnValue -> (List String)
  (let [(vals (match v
                ((asn/asnUnit) (list))
                ((asn/asnTuple items) items)
                ((asn/asnVec items) items)
                ((asn/asnPair a b) (list a b))
                (_ (list v))))]
    (filter (fn [(s String)] -> Bool (not (stringEmpty? s))) (map textOf vals)))

fn txt fs: (List asn/AsnField) key: String -> String
  (match (fieldOf fs key) ((some v) (textOf v)) ((none) ""))

fn txtOr fs: (List asn/AsnField) key: String fallback: String -> String
  (let [(v (txt fs key))] (if (stringEmpty? v) fallback v))

fn intOr fs: (List asn/AsnField) key: String fallback: Int64 -> Int64
  (match (fieldOf fs key) ((some v) (optionOr (asn/asnIntValue v) fallback)) ((none) fallback))

fn items fs: (List asn/AsnField) key: String -> (List String)
  (match (fieldOf fs key) ((some v) (itemsOf v)) ((none) (list)))

fn tagOf line: String -> String
  (if (not (stringStartsWith? line "(:")) ""
    (stringReplace (optionOr (listHead (stringSplit (optionOr (stringSlice line 2 (stringLength line)) "") " ")) "") ")" ""))

; (:m :do "a corpus row may name its id bare, (:task T1 :kind ...); it is rewritten to (:task :id \"T1\" ...) before the ASN reader sees it")
fn bareId line: String -> String
  (let [(rest (optionOr (stringSlice line 7 (stringLength line)) ""))
        (tok (optionOr (listHead (stringSplit rest " ")) ""))]
    (if (or (stringEmpty? tok) (or (stringStartsWith? tok ":") (stringStartsWith? tok "\"")))
      line
      (str "(:task :id " (st/q (stringReplace tok ")" "")) (optionOr (stringSlice rest (stringLength tok) (stringLength rest)) ""))))

fn fieldsOf line: String -> (List asn/AsnField)
  (let [(tag (tagOf line))
        (text (if (= tag "task") (bareId line) line))]
    (match (st/rowFields text tag) ((ok fs) fs) ((err _) (list))))

fn taskOf fs: (List asn/AsnField) -> TTask
  (TTask :id (txt fs "id") :owns (items fs "owns") :gate (txt fs "gate") :text (txtOr fs "do" (txt fs "text"))
         :skipWrite (= (txt fs "skipWrite") "true") :seed (txt fs "seed") :known (txt fs "known"))

fn applyRow s: Spec line: String -> Spec
  (let [(tag (tagOf line))
        (fs (fieldsOf line))]
    (cond
      ((= tag "trialSpec")
        (Spec :store (txt fs "store") :repo (txt fs "repo") :toolRoot (txtOr fs "toolRoot" (txt fs "repo")) :devRepo (txt fs "devRepo")
              :devPrefix (txtOr fs "devPrefix" s.devPrefix) :devBase (txt fs "devBase") :worktrees (txt fs "worktrees") :home (txt fs "home")
              :lanes (txt fs "lanes") :keys (txt fs "keys") :base (txtOr fs "base" s.base) :profile (txtOr fs "profile" s.profile)
              :leaseSec (intOr fs "leaseSec" s.leaseSec) :writers (max 1 (intOr fs "writers" s.writers)) :gates (max 1 (intOr fs "gates" s.gates))
              :reviews (max 1 (intOr fs "reviews" s.reviews)) :stageSec (intOr fs "stageSec" s.stageSec) :minFreeMb (intOr fs "minFreeMb" s.minFreeMb)
              :minDiskMb (intOr fs "minDiskMb" s.minDiskMb) :analyzer (items fs "analyzer")
              :heads s.heads :models s.models :tasks s.tasks :corpus s.corpus))
      ((= tag "head") (with s :heads (listAppend s.heads (list (Head :repo (txt fs "repo") :sha (txt fs "sha") :ref (txtOr fs "ref" "HEAD"))))))
      ((= tag "model") (with s :models (listAppend s.models (list (Model :tag (txt fs "tag") :alias (txt fs "alias"))))))
      ((= tag "task") (let [(t (taskOf fs))] (if (stringEmpty? t.id) s (with s :tasks (listAppend s.tasks (list t))))))
      ((= tag "corpus") (with s :corpus (listAppend s.corpus (list (txt fs "path")))))
      (else s)))

fn rowLines text: String -> (List String)
  (filter (fn [(l String)] -> Bool (stringStartsWith? l "(:")) (map stringTrim (stringLines text)))

fn withDevBase s: Spec -> Spec
  (if (stringEmpty? s.devBase) (with s :devBase s.base) s)

fn parseSpec text: String -> Spec
  (withDevBase (fold applyRow (emptySpec) (rowLines text)))

fn rooted root: String p: String -> String
  (if (or (stringStartsWith? p "/") (stringEmpty? root)) p (str root "/" p))

; (:m :do "the spec plus the task rows of every (:corpus :path P) it names (P relative to the tool root); corpus files contribute (:task ...) rows only")
fn ! specLines! path: String -> (Result Spec String)
  (match (fileReadString path)
    ((err e) (err (str "spec unreadable: " e)))
    ((ok text)
      (let [(s0 (parseSpec text))
            (extra (stringJoin (map (fn [(p String)] -> String
                                      (stringJoin (filter (fn [(l String)] -> Bool (= (tagOf l) "task")) (rowLines (resultOr (fileReadString (rooted s0.toolRoot p)) ""))) "\n"))
                                    s0.corpus) "\n"))]
        (ok (parseSpec (str text "\n" extra))))))


fn cellId t: TTask m: Model -> String
  (if t.skipWrite (str t.id "-seed") (str t.id "-" m.tag))

fn cellsOf s: Spec -> (List Cell)
  (fold (fn [(acc (List Cell)) (t TTask)] -> (List Cell)
          (if t.skipWrite
            (listAppend acc (list (Cell :id (cellId t (Model :tag "seed" :alias "")) :task t :model (Model :tag "seed" :alias ""))))
            (listAppend acc (map (fn [(m Model)] -> Cell (Cell :id (cellId t m) :task t :model m)) s.models))))
        (list) s.tasks)

; (:m :do "the scratch branch a cell merges onto; never main or master, whatever the prefix")
fn devBranchOf s: Spec id: String -> String
  (str s.devPrefix id)

fn trialDir s: Spec -> String
  (str s.store "/trial")

fn runsPath s: Spec -> String
  (str (trialDir s) "/runs.asn")

fn wtOf s: Spec id: String -> String
  (str s.worktrees "/asex-" id)


fn ! git dir: String args: (List String) -> fr/Done
  (fr/runOneLimited (fr/job (listAppend (list "git" "-C" dir) args) "." (fr/childEnv (list))) (fr/limits 300 16))

fn ! gitText dir: String args: (List String) -> String
  (let [(d (git dir args))] (if (= d.exit 0) (stringTrim d.out) ""))

fn ! readOr path: String -> String
  (resultOr (fileReadString path) "")

fn ! same? a: String b: String -> Bool
  (and (not (stringEmpty? a)) (= (resultOr (realPath a) a) (resultOr (realPath b) b)))

fn ! inside? p: String root: String -> Bool
  (let [(rp (resultOr (realPath p) p))
        (rr (resultOr (realPath root) root))]
    (and (not (stringEmpty? rr)) (or (= rp rr) (stringStartsWith? rp (str rr "/")))))


fn ! memAvailableMb! -> Int64
  (if (not (fileExists? "/proc/meminfo")) -1
    (match (listFind (fn [(l String)] -> Bool (stringStartsWith? l "MemAvailable:")) (stringLines (readOr "/proc/meminfo")))
      ((none) -1)
      ((some l) (/ (optionOr (stringToInt64 (optionOr (listGet (filter (fn [(x String)] -> Bool (not (stringEmpty? x))) (stringSplit l " ")) 1) "")) -1) 1024))))

fn ! diskFreeMb! dir: String -> Int64
  (let [(d (fr/runOneLimited (fr/job (list "df" "-Pk" dir) "." (fr/childEnv (list))) (fr/limits 60 4)))
        (row (optionOr (listGet (stringLines (stringTrim d.out)) 1) ""))
        (cols (filter (fn [(x String)] -> Bool (not (stringEmpty? x))) (stringSplit row " ")))]
    (if (!= d.exit 0) -1 (/ (optionOr (stringToInt64 (optionOr (listGet cols 3) "")) -1) 1024)))

fn aliasKnown? gateway: String alias: String -> Bool
  (or (stringContains? gateway (str ":id " alias " ")) (or (stringContains? gateway (str ":id " alias ")")) (stringContains? gateway (str ":id \"" alias "\""))))

; (:m :do "a named production head that moved, and a trial path that is or sits inside a production repo, are problems; run calls this before the first stage and after the last")
fn ! headProblems! s: Spec -> (List String)
  (fold (fn [(acc (List String)) (h Head)] -> (List String)
          (let [(now (gitText h.repo (list "rev-parse" h.ref)))
                (moved (if (or (stringEmpty? now) (not (stringStartsWith? now h.sha)) (stringEmpty? h.sha)) (list (str "headMoved:" h.repo "@" h.ref)) (list)))
                (clash (filter (fn [(p String)] -> Bool (and (not (stringEmpty? p)) (inside? p h.repo))) (list s.devRepo s.repo s.store s.worktrees)))]
            (listAppend acc (listAppend moved (map (fn [(p String)] -> String (str "isProduction:" p)) clash)))))
        (list) s.heads)

fn ! specProblems! s: Spec -> (List String)
  (let [(missing (map (fn [(k String)] -> String (str "missing:" k))
                      (filter (fn [(k String)] -> Bool (stringEmpty? (cond ((= k "store") s.store) ((= k "repo") s.repo) ((= k "devRepo") s.devRepo) ((= k "worktrees") s.worktrees) ((= k "home") s.home) (else s.lanes))))
                              (list "store" "repo" "devRepo" "worktrees" "home" "lanes"))))
        (cells (if (listEmpty? (cellsOf s)) (list "noCells") (list)))
        (prefix (if (or (stringEmpty? s.devPrefix) (or (= s.devPrefix "main") (or (= s.devPrefix "master") (stringContains? s.devPrefix " ")))) (list (str "devPrefix:" s.devPrefix)) (list)))
        (devCur (gitText s.devRepo (list "branch" "--show-current")))
        (devMain (if (or (= devCur "main") (or (= devCur "master") (stringEmpty? devCur))) (list (str "devRepoOnMain:" devCur)) (list)))
        (devRemote (if (stringEmpty? (gitText s.devRepo (list "remote"))) (list) (list "devRepoRemote")))
        (repoRemote (if (stringEmpty? (gitText s.repo (list "remote"))) (list) (list "repoRemote")))
        (same (if (same? s.devRepo s.repo) (list "devRepoIsRepo") (list)))
        (tool (if (fileExists? (str s.toolRoot "/bin/asl")) (list) (list "toolRoot")))
        (gateway (readOr (str s.home "/.asl/gateway.asn")))
        (aliases (map (fn [(m Model)] -> String (str "aliasUnknown:" m.alias)) (filter (fn [(m Model)] -> Bool (not (aliasKnown? gateway m.alias))) s.models)))
        (seeds (map (fn [(t TTask)] -> String (str "seedMissing:" t.id)) (filter (fn [(t TTask)] -> Bool (and t.skipWrite (not (fileExists? (rooted s.toolRoot t.seed))))) s.tasks)))
        (mem (if (<= s.minFreeMb 0) (list) (let [(m (memAvailableMb!))] (cond ((< m 0) (list "memUnknown")) ((< m s.minFreeMb) (list (str "memLow:" (n m)))) (else (list))))))
        (disk (if (<= s.minDiskMb 0) (list) (let [(d (diskFreeMb! (if (fileExists? s.store) s.store ".")))] (if (< d s.minDiskMb) (list (str "diskLow:" (n d))) (list)))))]
    (fold listAppend (list) (list missing cells prefix devMain devRemote repoRemote same tool aliases seeds mem disk (headProblems! s))))

fn ! check! s: Spec -> Int64
  (let [(ps (specProblems! s))]
    (do (println (str "(:check :problems " (st/qList ps) ")"))
        (if (listEmpty? ps) 0 1)))


fn stageArgv s: Spec stage: String c: Cell -> (List String)
  (listAppend
    (list (str s.toolRoot "/bin/asl") "run" (str s.toolRoot "/asl/tools/coord/conductor.asl") "stage" stage c.id "--store" s.store "--repo" s.repo
          "--dev-repo" s.devRepo "--dev" (devBranchOf s c.id) "--worktrees" s.worktrees "--home" s.home "--lanes" s.lanes "--profile" s.profile
          "--archive" (str s.store "/archive") "--lease-sec" (n s.leaseSec))
    (listAppend (if (stringEmpty? c.model.alias) (list) (list "--writer-model" c.model.alias "--writer-alias" c.model.alias))
                (if (stringEmpty? s.keys) (list) (list "--keys" s.keys))))

fn ! resOf! s: Spec id: String stage: String d: fr/Done -> cd/Res
  (match (fileReadString (cd/runPath s.store id stage "asn"))
    ((err _) (failRes (str (if (or (>= d.exit 124) (stringContains? d.verdict "timeout")) "stageKilled" "noRow") ": stage " stage " exit " (n d.exit) " " (optionOr (listHead (stringLines (stringTrim d.out))) ""))))
    ((ok raw) (match (cd/parseRes raw) ((ok r) r) ((err e) (failRes (str "badRow: " e))))))

fn passed? stage: String r: cd/Res -> Bool
  (cond
    ((= stage "write") (= r.ok 1))
    ((= stage "gates") (and (= r.exit 0) (> r.asserts 0)))
    ((= stage "review") (= r.verdict "pass"))
    (else (= r.ok 1)))

fn ! stageJobs! s: Spec stage: String cs: (List Cell) -> (List fr/Job)
  (map (fn [(c Cell)] -> fr/Job
         (let [(_ (pathRemove (cd/runPath s.store c.id stage "asn")))]
           (fr/job (stageArgv s stage c) s.toolRoot (fr/childEnv (list)))))
       cs)

fn stageLimit s: Spec stage: String -> Int64
  (if (= stage "write") (+ s.leaseSec 600) s.stageSec)

; (:m :do "one stage for a batch of cells through the pool, at most slots at once; returns (cell id, Res) pairs in cell order")
fn ! stagePool! s: Spec stage: String cs: (List Cell) slots: Int64 -> (List (Pair String cd/Res))
  (if (listEmpty? cs) (list)
    (let [(ds (fr/runPoolLimited (stageJobs! s stage cs) slots (fr/limits (stageLimit s stage) 200)))]
      (map (fn [(i Int64)] -> (Pair String cd/Res)
             (let [(c (optionOr (listGet cs i) (Cell :id "" :task (TTask :id "" :owns (list) :gate "" :text "" :skipWrite false :seed "" :known "") :model (Model :tag "" :alias ""))))
                   (d (optionOr (listFind (fn [(x fr/Done)] -> Bool (= x.idx i)) ds) (fr/Done :idx i :exit 125 :out "not run" :ms 0 :verdict "")))]
               (pair c.id (resOf! s c.id stage d))))
           (range 0 (listLength cs)))))


fn unitOf s: Spec c: Cell -> st/Task
  (st/Task :id c.id :owns c.task.owns :reads (list) :gate c.task.gate :channel "trial" :model c.model.alias :base s.base :after (list) :st "queued" :epoch 0 :receipt "")

fn cuOf id: String stateName: String wt: String branch: String -> cd/CUnit
  (cd/CUnit :id id :st stateName :lane "trial" :fails 0 :sig "" :waited 0 :parked 0 :epoch 0 :branch branch :wt wt :model "" :tokens 0 :costMicro 0 :esc 0 :launched 0 :await "")

; (:m :do "a write cell gets its store row, task text and a writing cond row; a seeded cell gets branch sh/<id> from base with the corpus patch applied and committed, in its own worktree, and a gating cond row")
fn ! seedCell! s: Spec c: Cell -> (Result String String)
  (let [(_ (dirCreate (str s.store "/tasks")))
        (put (st/put! s.store (unitOf s c)))
        (_ (fileWrite (str s.store "/tasks/" c.id ".txt") c.task.text))]
    (match put
      ((err e) (err (str "store put: " e)))
      ((ok _)
        (if (not c.task.skipWrite)
          (match (cd/writeCUnit! s.store (cuOf c.id "writing" "" "")) ((ok _) (ok "")) ((err e) (err e)))
          (let [(wt (wtOf s c.id))
                (add (git s.repo (list "worktree" "add" "-q" "-B" (str "sh/" c.id) wt s.base)))
                (app (if (= add.exit 0) (git wt (list "apply" (rooted s.toolRoot c.task.seed))) add))
                (stg (if (= app.exit 0) (git wt (list "add" "-A")) app))
                (com (if (= stg.exit 0) (git wt (list "-c" "user.email=trial@example.invalid" "-c" "user.name=trial" "commit" "-q" "-m" (str "(:c :a trial :do \"seed " c.id "\")"))) stg))]
            (if (!= com.exit 0) (err (str "seed: " (stringTrim com.out)))
              (match (cd/writeCUnit! s.store (cuOf c.id "gating" wt (str "sh/" c.id))) ((ok _) (ok wt)) ((err e) (err e)))))))))

; (:m :do "after write, before merge can remove the worktree: Leon's journals and patches and the TRIAL-PIN receipt <id>-leon.asn are copied to <store>/trial/<id>/")
fn ! copyEvidence! s: Spec id: String -> Int64
  (let [(dest (str (trialDir s) "/" id))
        (_ (dirCreate dest))
        (src (str (wtOf s id) "/.asl/run/agentLoop"))
        (names (filter (fn [(f String)] -> Bool (or (stringEndsWith? f ".journal") (stringEndsWith? f ".patch"))) (resultOr (dirList src) (list))))
        (copied (fold (fn [(k Int64) (f String)] -> Int64 (if (ok? (fileWrite (str dest "/" f) (readOr (str src "/" f)))) (+ k 1) k)) 0 names))
        (leon (cd/runPath s.store id "leon" "asn"))]
    (if (fileExists? leon) (if (ok? (fileWrite (str dest "/leon.asn") (readOr leon))) (+ copied 1) copied) copied))


fn distinct xs: (List String) -> (List String)
  (fold (fn [(acc (List String)) (x String)] -> (List String) (if (or (stringEmpty? x) (listContains? acc x)) acc (listAppend acc (list x)))) (list) xs)

fn countSub text: String pat: String -> Int64
  (max 0 (- (listLength (stringSplit text pat)) 1))

fn bareTok s: String -> String
  (let [(a (stringTrim (stringReplace (stringReplace (stringReplace s "\\\"" "") "\"" "") ")" "")))]
    (if (stringStartsWith? a ":") (optionOr (stringSlice a 1 (stringLength a)) a) a))

fn wordAt l: String key: String -> String
  (bareTok (sp/tokAfter l key))

; (:m :do "a journal signal row (:turn N :signal :readStreak :cause :notFound ...) becomes (:readStreak :cause notFound), one without a cause its bare name")
fn signalOf l: String -> String
  (match (stringIndexOf l " :signal :")
    ((none) "")
    ((some i)
      (let [(name (bareTok (optionOr (listHead (stringSplit (optionOr (stringSlice l (+ i 10) (stringLength l)) "") " ")) "")))
            (cause (wordAt l ":cause"))]
        (if (stringEmpty? cause) name (str "(:" name " :cause " cause ")")))))

fn bump xs: (List (Pair String Int64)) k: String -> (List (Pair String Int64))
  (if (stringEmpty? k) xs
    (if (listAny? (fn [(p (Pair String Int64))] -> Bool (= (pairFirst p) k)) xs)
      (map (fn [(p (Pair String Int64))] -> (Pair String Int64) (if (= (pairFirst p) k) (pair k (+ (pairSecond p) 1)) p)) xs)
      (listAppend xs (list (pair k 1)))))

fn countsText xs: (List (Pair String Int64)) -> String
  (str "(" (stringJoin (map (fn [(p (Pair String Int64))] -> String (str "(:" (pairFirst p) " " (n (pairSecond p)) ")")) xs) " ") ")")

; (:m :do "step op names of one reply row: every :op token after the first segment")
fn replyOps l: String -> (List String)
  (map (fn [(seg String)] -> String (bareTok (optionOr (listHead (stringSplit (stringTrim seg) " ")) "")))
       (optionOr (listTail (stringSplit l ":op ")) (list)))

; (:m :do "Leon facts in the trialAnalyze plist shape: the receipt from <id>-leon.asn (TRIAL-PIN) else the journal's last (:result ...) row; signals with :cause, :ops and :opErrors as (:name n) counts from (:op ...) rows (TRIAL-LEON-OPROWS) else from the steps of the reply rows, the last (:err ...) and (:gate ...) rows")
fn leonFacts receipt: String journal: String -> String
  (let [(lines (stringLines journal))
        (result (fold (fn [(acc String) (l String)] -> String (if (stringStartsWith? l "(:result ") l acc)) "" lines))
        (fromLeon (not (stringEmpty? (stringTrim receipt))))
        (r (if fromLeon receipt result))
        (turnRows (filter (fn [(l String)] -> Bool (and (stringStartsWith? l "(:turn ") (stringContains? l " :reply "))) lines))
        (turns (let [(t (optionOr (stringToInt64 (wordAt r ":turns")) -1))] (if (< t 0) (listLength turnRows) t)))
        (sigRows (filter (fn [(l String)] -> Bool (stringContains? l " :signal :")) lines))
        (signals (distinct (map signalOf sigRows)))
        (opRows (filter (fn [(l String)] -> Bool (stringStartsWith? l "(:op ")) lines))
        (ops (if (listEmpty? opRows)
               (fold (fn [(acc (List (Pair String Int64))) (l String)] -> (List (Pair String Int64)) (fold bump acc (replyOps l))) (list) turnRows)
               (fold (fn [(acc (List (Pair String Int64))) (l String)] -> (List (Pair String Int64)) (bump acc (wordAt l ":name"))) (list) opRows)))
        (opErrors (fold (fn [(acc (List (Pair String Int64))) (l String)] -> (List (Pair String Int64)) (bump acc (wordAt l ":error")))
                        (list) (filter (fn [(l String)] -> Bool (stringContains? l ":status err")) opRows)))
        (lastErr (fold (fn [(acc String) (l String)] -> String (if (stringStartsWith? l "(:err ") l acc)) "" lines))
        (lastGate (fold (fn [(acc String) (l String)] -> String (if (stringStartsWith? l "(:gate ") l acc)) "" lines))
        (malformed (listLength (filter (fn [(l String)] -> Bool (stringContains? l ":signal :malformedReply")) sigRows)))]
    (str "(:src " (if fromLeon "leon" "journal") " :stop " (st/q (wordAt r ":stop")) " :status " (st/q (wordAt r ":status"))
         " :served " (st/q (sp/quotedAfter r ":servedAlias")) " :turns " (n turns) " :signals (" (stringJoin signals " ") ")"
         " :ops " (countsText ops) " :opErrors " (countsText opErrors)
         " :ownsRejected " (n (countSub r "ERR_OWNS)")) " :needsConfirm " (n (countSub r ":blocked true")) " :malformed " (n malformed)
         (if (stringEmpty? lastErr) "" (str " :err (:class " (wordAt lastErr ":class") " :code " (st/q (wordAt lastErr ":code")) ")"))
         (if (stringEmpty? lastGate) "" (str " :lastGate (:exit " (n (optionOr (stringToInt64 (wordAt lastGate ":exit")) -1)) " :error " (st/q (sp/quotedAfter lastGate ":error")) " :failed " (n (optionOr (stringToInt64 (wordAt lastGate ":failed")) 0)) ")"))
         ")"))

fn tf b: Bool -> String
  (if b "true" "false")

fn clip s: String -> String
  (st/q (optionOr (stringSlice s 0 400) s))

; (:m :do "one stage form of the record in the trialAnalyze shape: write and merge carry :ok true|false, gates :exit :executed and :redBefore (:exit :executed), review :verdict :sig and :reviewers plists")
fn stageText stage: String r: cd/Res red: String reviewers: String -> String
  (cond
    ((= stage "write")
      (str "(:write :ok " (tf (passed? stage r)) " :exit " (n r.exit) " :sig " (clip r.sig) " :ms " (n r.ms) " :tokens " (n r.tokens) " :costMicro " (n r.costMicro)
           " :model " (st/q r.model) (if (stringStartsWith? r.sig "stageKilled") " :killed true" "") ")"))
    ((= stage "gates")
      (str "(:gates :exit " (n r.exit) " :executed " (n r.asserts) (if (stringEmpty? red) "" (str " :redBefore " red)) " :sig " (clip r.sig) " :ms " (n r.ms) ")"))
    ((= stage "review")
      (str "(:review :verdict " (st/q r.verdict) " :sig " (clip r.sig) " :tiers " (st/q r.tiers) " :model " (st/q r.model) " :tokens " (n r.tokens) " :reviewers (" reviewers "))"))
    (else
      (str "(:merge :ok " (tf (passed? stage r)) " :sig " (clip r.sig) " :ms " (n r.ms) ")")))

; (:m :do "the red-before run from the gates receipt, :redBefore ((:gate G :exit E :executed X)), as the plist (:exit E :executed X); the receipt has none when the gate was green on base")
fn redBeforeOf receipt: String -> String
  (match (stringIndexOf receipt ":redBefore ")
    ((none) "")
    ((some i)
      (let [(rest (optionOr (stringSlice receipt i (stringLength receipt)) ""))]
        (str "(:exit " (n (optionOr (stringToInt64 (wordAt rest ":exit")) 0)) " :executed " (n (optionOr (stringToInt64 (wordAt rest ":executed")) 0)) ")"))))

; (:m :do "per-reviewer rows (:reviewCall :unit U ...) from TRIAL-REVIEW-ROWS in the store journal, head dropped so each is a plist")
fn reviewersOf journal: String id: String -> String
  (stringJoin (map (fn [(l String)] -> String (str "(" (optionOr (stringSlice l 13 (stringLength l)) "")))
                   (filter (fn [(l String)] -> Bool (and (stringStartsWith? l "(:reviewCall ") (or (stringContains? l (str ":unit " (st/q id) " ")) (stringContains? l (str ":unit " id " ")))))
                           (stringLines journal)))
              " ")

fn recordText s: Spec c: Cell stages: (List (Pair String cd/Res)) failedAt: String leon: String red: String reviewers: String wallMs: Int64 at: Int64 -> String
  (let [(served (sp/quotedAfter leon ":served"))
        (pinBroken (and (not (stringEmpty? c.model.alias)) (and (not (stringEmpty? served)) (!= served c.model.alias))))]
    (str "(:trialRun :id " (st/q c.id) " :task " (st/q c.task.id) " :model " (st/q c.model.tag) " :alias " (st/q c.model.alias) " :served " (st/q served)
         " :pinBroken " (tf pinBroken) " :known " (st/q c.task.known) " :seeded " (tf (and c.task.skipWrite (or (= c.task.known "reviewFail") (= c.task.known "refuse")))) " :skipWrite " (tf c.task.skipWrite) " :base " (st/q s.base)
         " :stages (" (stringJoin (map (fn [(p (Pair String cd/Res))] -> String (stageText (pairFirst p) (pairSecond p) red reviewers)) stages) " ") ")"
         " :failedAt " (st/q failedAt) " :merged " (tf (stringEmpty? failedAt))
         " :devBranch " (st/q (if (stringEmpty? failedAt) (devBranchOf s c.id) "")) (if c.task.skipWrite "" (str " :leon " leon))
         " :evidence " (st/q (str (trialDir s) "/" c.id)) " :wallMs " (n wallMs) " :at " (n at) ")"))

fn ! doneIds! s: Spec -> (List String)
  (map (fn [(l String)] -> String (sp/quotedAfter l ":id")) (filter (fn [(l String)] -> Bool (stringStartsWith? l "(:trialRun :id ")) (stringLines (readOr (runsPath s)))))

fn lookup ps: (List (Pair String cd/Res)) id: String -> (Option cd/Res)
  (match (listFind (fn [(p (Pair String cd/Res))] -> Bool (= (pairFirst p) id)) ps) ((some p) (some (pairSecond p))) ((none) (none)))

fn okIn ps: (List (Pair String cd/Res)) stage: String cs: (List Cell) -> (List Cell)
  (filter (fn [(c Cell)] -> Bool (match (lookup ps c.id) ((some r) (passed? stage r)) ((none) false))) cs)

; (:m :do "merges run one at a time: devRepo checks out a fresh <devPrefix><id> from devBase, then the merge stage trains the cell branch onto it; the devRepo goes back to its own branch afterwards")
fn ! mergeOne! s: Spec c: Cell -> (Pair String cd/Res)
  (let [(co (git s.devRepo (list "checkout" "-q" "-B" (devBranchOf s c.id) s.devBase)))]
    (if (!= co.exit 0)
      (pair c.id (failRes (str "devCheckout: " (stringTrim co.out))))
      (let [(ds (stagePool! s "merge" (list c) 1))]
        (optionOr (listHead ds) (pair c.id (failRes "merge not run"))))))

fn cuModel c: cd/CUnit model: String -> cd/CUnit
  (with c :model model)

fn ! condAfterWrite! s: Spec id: String r: cd/Res -> Bool
  (ok? (cd/writeCUnit! s.store (cuModel (cuOf id "gating" (if (stringEmpty? r.wt) (wtOf s id) r.wt) (if (stringEmpty? r.branch) (str "sh/" id) r.branch)) r.model)))

fn ! run! s: Spec only: String -> Int64
  (let [(ps (specProblems! s))]
    (if (not (listEmpty? ps))
      (do (println (str "(:refuse :problems " (st/qList ps) ")")) 1)
      (let [(t0 (nowMs))
            (_ (dirCreate (trialDir s)))
            (doneAlready (doneIds! s))
            (cells (filter (fn [(c Cell)] -> Bool (and (not (listContains? doneAlready c.id)) (or (stringEmpty? only) (= c.id only)))) (cellsOf s)))
            (seeded (map (fn [(c Cell)] -> (Pair String (Result String String)) (pair c.id (seedCell! s c))) cells))
            (seedOk (filter (fn [(c Cell)] -> Bool (match (listFind (fn [(p (Pair String (Result String String)))] -> Bool (= (pairFirst p) c.id)) seeded) ((some p) (ok? (pairSecond p))) ((none) false))) cells))
            (writers (filter (fn [(c Cell)] -> Bool (not c.task.skipWrite)) seedOk))
            (wr (stagePool! s "write" writers s.writers))
            (_ (map (fn [(c Cell)] -> Int64 (copyEvidence! s c.id)) writers))
            (wOk (okIn wr "write" writers))
            (_ (map (fn [(c Cell)] -> Bool (match (lookup wr c.id) ((some r) (condAfterWrite! s c.id r)) ((none) false))) wOk))
            (toGate (filter (fn [(c Cell)] -> Bool (or (and c.task.skipWrite (listContains? (map (fn [(x Cell)] -> String x.id) seedOk) c.id)) (listContains? (map (fn [(x Cell)] -> String x.id) wOk) c.id))) cells))
            (gr (stagePool! s "gates" toGate s.gates))
            (toReview (okIn gr "gates" toGate))
            (rr (stagePool! s "review" toReview s.reviews))
            (toMerge (okIn rr "review" toReview))
            (devHome (gitText s.devRepo (list "branch" "--show-current")))
            (mr (map (fn [(c Cell)] -> (Pair String cd/Res) (mergeOne! s c)) toMerge))
            (_ (if (stringEmpty? devHome) (git s.devRepo (list "status")) (git s.devRepo (list "checkout" "-q" devHome))))
            (now (nowMs))
            (records (map (fn [(c Cell)] -> String
                            (let [(seedErr (match (listFind (fn [(p (Pair String (Result String String)))] -> Bool (= (pairFirst p) c.id)) seeded) ((some p) (match (pairSecond p) ((err e) e) ((ok _) ""))) ((none) "notSeeded")))
                                  (chain (filter (fn [(p (Pair String cd/Res))] -> Bool (not (stringEmpty? (pairFirst p))))
                                                 (map (fn [(st (Pair String (List (Pair String cd/Res))))] -> (Pair String cd/Res)
                                                        (match (lookup (pairSecond st) c.id) ((some r) (pair (pairFirst st) r)) ((none) (pair "" (failRes "")))))
                                                      (list (pair "write" wr) (pair "gates" gr) (pair "review" rr) (pair "merge" mr)))))
                                  (failed (cond
                                            ((not (stringEmpty? seedErr)) "seed")
                                            (else (match (listFind (fn [(p (Pair String cd/Res))] -> Bool (not (passed? (pairFirst p) (pairSecond p)))) chain)
                                                    ((some p) (pairFirst p))
                                                    ((none) (if (= (listLength chain) (if c.task.skipWrite 3 4)) "" "incomplete"))))))
                                  (leon (if c.task.skipWrite ""
                                          (leonFacts (readOr (cd/runPath s.store c.id "leon" "asn"))
                                                     (stringJoin (map (fn [(f String)] -> String (readOr (str (trialDir s) "/" c.id "/" f)))
                                                                      (filter (fn [(f String)] -> Bool (stringEndsWith? f ".journal")) (resultOr (dirList (str (trialDir s) "/" c.id)) (list)))) "\n"))))
                                  (receipt (readOr (cd/runPath s.store c.id "receipt" "asn")))
                                  (red (redBeforeOf receipt))
                                  (row (recordText s c chain failed leon red (reviewersOf (readOr (cd/journalPath s.store)) c.id) (- now t0) now))]
                              (let [(_ (fileAppend (runsPath s) (str row "\n")))] row)))
                          cells))
            (after (headProblems! s))
            (merged (listLength (filter (fn [(r String)] -> Bool (stringContains? r " :merged true ")) records)))]
        (do (println (str "(:trialRun :cells " (n (listLength cells)) " :merged " (n merged) " :runs " (st/q (runsPath s)) " :headProblems " (st/qList after) ")"))
            (if (listEmpty? after) 0 1)))))


fn ! collect! s: Spec -> Int64
  (let [(rows (filter (fn [(l String)] -> Bool (stringStartsWith? l "(:trialRun :id ")) (stringLines (readOr (runsPath s)))))
        (merged (listLength (filter (fn [(r String)] -> Bool (stringContains? r " :merged true ")) rows)))
        (stages (list "seed" "write" "gates" "review" "merge" "incomplete"))
        (by (map (fn [(st0 String)] -> String (str "(:" st0 " " (n (listLength (filter (fn [(r String)] -> Bool (stringContains? r (str ":failedAt \"" st0 "\""))) rows))) ")")) stages))
        (report (str (trialDir s) "/report.asn"))
        (argv (if (listEmpty? s.analyzer)
                (list (str s.toolRoot "/bin/asl") "run" (str s.toolRoot "/asl/tools/coord/trialAnalyze.asl"))
                s.analyzer))
        (_ (pathRemove report))
        (d (fr/runOneLimited (fr/job (listAppend argv (list "report" "--in" (runsPath s))) s.toolRoot (fr/childEnv (list))) (fr/limits 900 50)))
        (_ (if (= d.exit 0) (fileWrite report d.out) (ok ())))
        (summary (str "(:trialCollect :runs " (n (listLength rows)) " :merged " (n merged) " :failedAt (" (stringJoin by " ") ")"
                      " :analyzer (:exit " (n d.exit) " :report " (st/q (if (fileExists? report) report "")) "))"))
        (_ (fileWrite (str (trialDir s) "/collect.asn") (str summary "\n")))]
    (do (println summary)
        (if (and (= d.exit 0) (and (fileExists? report) (> (listLength rows) 0))) 0 1)))

fn ! main args: (List String) -> (Result Int64 String)
  (let [(cmd (optionOr (listHead args) ""))
        (path (st/opt args "spec" ""))]
    (match (specLines! path)
      ((err e) (do (eprintln (str "(:trial :error " (st/q e) ")")) (ok 2)))
      ((ok s)
        (cond
          ((= cmd "check") (ok (check! s)))
          ((= cmd "run") (ok (run! s (st/opt args "only" ""))))
          ((= cmd "collect") (ok (collect! s)))
          (else (do (eprintln "usage: trial.asl check|run|collect --spec S [--only CELL]") (ok 2)))))))
