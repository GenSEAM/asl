(module asl-tools/coord/trial
  :x [Spec Head Model TTask Cell emptySpec parseSpec specLines! taskChunks cellsOf cellId devBranchOf specProblems! headProblems! stageArgv recordText leonFacts runsPath trialDir
      check! run! collect! Setup Step setupOf setupSteps trialLanesText runSpecText setup! main]
  :i [(asl-tools/coord/conductor :a cd) (asl-tools/coord/store :a st) (asl-tools/fleet/run :a fr) (asl-syntax/asl/asn :a asn) (aslGateway/subPace :a sp) (asl-tools/vcs/git :a gv)])

; (:m :ref LEON-TRIAL :do "TRIAL-DRIVER: N pinned writer models on the same tasks through the real stage CLI (conductor.asl stage write|gates|review|merge), one attempt per (task, model) cell, no ladder and no tick; each merge lands on its own scratch branch <devPrefix><cell> in a devRepo that is never main, and the production heads named in the spec are compared before and after so the trial never moves them")

(schema Head (:f repo String) (:f sha String) (:f ref String))
(schema Model (:f tag String) (:f alias String))
(schema TTask (:f id String) (:f owns (List String)) (:f gate String) (:f text String) (:f skipWrite Bool) (:f seed String) (:f known String))
(schema Cell (:f id String) (:f task TTask) (:f model Model))
(schema Scan (:f depth Int64) (:f inStr Bool) (:f esc Bool) (:f n Int64) (:f done Bool))
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

fn scanStep acc: Scan c: String -> Scan
  (cond
    (acc.done acc)
    (acc.esc (with acc :esc false :n (+ acc.n 1)))
    (acc.inStr (with acc :esc (= c "\\") :inStr (!= c "\"") :n (+ acc.n 1)))
    ((= c "\"") (with acc :inStr true :n (+ acc.n 1)))
    ((= c "(") (with acc :depth (+ acc.depth 1) :n (+ acc.n 1)))
    ((= c ")") (with acc :depth (- acc.depth 1) :n (+ acc.n 1) :done (<= acc.depth 1)))
    (else (with acc :n (+ acc.n 1))))

; (:m :do "the first balanced form at the start of s, string-aware; empty when it never closes")
fn balancedHead s: String -> String
  (let [(cs (stringChars s))
        (r (fold scanStep (Scan :depth 0 :inStr false :esc false :n 0 :done false) cs))]
    (if r.done (stringJoin (listTake cs r.n) "") ""))

; (:m :do "every (:task ...) form of a corpus file joined onto one line, so a corpus written as one multi-line (:trialCorpus :tasks (...)) form yields its task rows")
fn taskChunks text: String -> (List String)
  (filter (fn [(t String)] -> Bool (not (stringEmpty? t)))
    (map (fn [(p String)] -> String (stringJoin (map stringTrim (stringLines (balancedHead (str "(:task " p)))) " "))
         (listDrop (stringSplit text "(:task ") 1)))

; (:m :do "the spec plus the task forms of every (:corpus :path P) it names (P relative to the tool root); corpus files contribute their (:task ...) forms only, single- or multi-line, less the ids its :skip lists")
fn ! specLines! path: String -> (Result Spec String)
  (match (fileReadString path)
    ((err e) (err (str "spec unreadable: " e)))
    ((ok text)
      (let [(s0 (parseSpec text))
            (extra (stringJoin (map (fn [(p String)] -> String (stringJoin (taskChunks (resultOr (fileReadString (rooted s0.toolRoot p)) "")) "\n"))
                                    s0.corpus) "\n"))]
        (ok (withoutTasks (parseSpec (str text "\n" extra)) (corpusSkips text))))))

; (:m :do "task ids the (:corpus :path P :skip (ID ...)) rows of a spec leave out")
fn corpusSkips text: String -> (List String)
  (fold listAppend (list) (map (fn [(l String)] -> (List String) (items (fieldsOf l) "skip")) (filter (fn [(l String)] -> Bool (= (tagOf l) "corpus")) (rowLines text))))

fn withoutTasks s: Spec ids: (List String) -> Spec
  (with s :tasks (filter (fn [(t TTask)] -> Bool (not (listContains? ids t.id))) s.tasks))


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

; (:m :do "a path with symlinks resolved and empty or . segments dropped, also when its tail does not exist yet: the longest existing prefix is resolved and the rest appended, so two spellings of one place compare equal before it is created")
fn ! canon! p: String -> String
  (if (or (stringEmpty? p) (= p "/")) p
    (match (realPath p)
      ((ok r) r)
      ((err _)
        (let [(parts (stringSplit p "/"))
              (k (listLength parts))
              (last (optionOr (listGet parts (- k 1)) ""))
              (parentText (stringJoin (listTake parts (- k 1)) "/"))
              (parent (if (and (stringEmpty? parentText) (stringStartsWith? p "/")) "/" parentText))]
          (cond
            ((<= k 1) p)
            ((or (stringEmpty? last) (= last ".")) (canon! parent))
            (else (let [(cp (canon! parent))] (if (= cp "/") (str "/" last) (str cp "/" last)))))))))

fn ! same? a: String b: String -> Bool
  (and (not (stringEmpty? a)) (= (canon! a) (canon! b)))

fn ! inside? p: String root: String -> Bool
  (let [(rp (canon! p))
        (rr (canon! root))]
    (and (not (stringEmpty? rr)) (or (= rp rr) (stringStartsWith? rp (str rr "/")))))

; (:m :ref TRIAL-SETUP :do "the production conductor store and lanes of a home: <home>/.asl/run/conductor (also the conductor's default under this process's HOME) and <home>/.asl/conductor/lanes.asn; a trial store, worktree dir or spec out equal to or inside that store, or a trial lanes file equal to that lanes file, is a problem")
fn ! prodHomes! s: Spec -> (List String)
  (distinct (filter (fn [(h String)] -> Bool (not (stringEmpty? h))) (list s.home (resultOr (getHomeDir) ""))))

fn ! prodPathProblems! s: Spec out: String -> (List String)
  (let [(homes (prodHomes! s))
        (stores (map (fn [(h String)] -> String (str h "/.asl/run/conductor")) homes))
        (laneFiles (map (fn [(h String)] -> String (str h "/.asl/conductor/lanes.asn")) homes))
        (paths (filter (fn [(p String)] -> Bool (not (stringEmpty? p))) (list s.store s.worktrees out)))
        (inStore (filter (fn [(p String)] -> Bool (listAny? (fn [(r String)] -> Bool (inside? p r)) stores)) paths))
        (lanes (if (and (not (stringEmpty? s.lanes)) (listAny? (fn [(l String)] -> Bool (same? s.lanes l)) laneFiles)) (list (str "productionLanes:" s.lanes)) (list)))]
    (listAppend (map (fn [(p String)] -> String (str "productionStore:" p)) (distinct inStore)) lanes))


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

; (:m :ref DEVREPO-BUILD :do "the merge stage runs mergeCheck with <devRepo>/bin/asl, which needs the devRepo's own host build: bin/asl and asl/host/out/aslNativeBuild present and the builder answering its usage line within 30 s")
fn ! devBuildProblems! dev: String -> (List String)
  (let [(nb (str dev "/asl/host/out/aslNativeBuild"))]
    (cond
      ((stringEmpty? dev) (list))
      ((not (fileExists? (str dev "/bin/asl"))) (list "devRepoBuild:noCli"))
      ((not (fileExists? nb)) (list "devRepoBuild:noHostOut"))
      (else (let [(d (fr/runOneLimited (fr/job (list nb) dev (fr/childEnv (list))) (fr/limits 30 4)))]
              (if (stringContains? d.out "usage: nativeBuild") (list) (list (str "devRepoBuild:notRunnable:" (n d.exit))))))))

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
        (dead (let [(nc (noCreditAliases (readOr s.lanes)))] (map (fn [(m Model)] -> String (str "aliasNoCredit:" m.alias)) (filter (fn [(m Model)] -> Bool (listContains? nc m.alias)) s.models))))
        (seeds (map (fn [(t TTask)] -> String (str "seedMissing:" t.id)) (filter (fn [(t TTask)] -> Bool (and (or t.skipWrite (not (stringEmpty? t.seed))) (or (stringEmpty? t.seed) (not (fileExists? (rooted s.toolRoot t.seed)))))) s.tasks)))
        (build (devBuildProblems! s.devRepo))
        (prodPaths (prodPathProblems! s ""))
        (mem (if (<= s.minFreeMb 0) (list) (let [(m (memAvailableMb!))] (cond ((< m 0) (list "memUnknown")) ((< m s.minFreeMb) (list (str "memLow:" (n m)))) (else (list))))))
        (disk (if (<= s.minDiskMb 0) (list) (let [(d (diskFreeMb! (if (fileExists? s.store) s.store ".")))] (if (< d s.minDiskMb) (list (str "diskLow:" (n d))) (list)))))]
    (fold listAppend (list) (list missing cells prefix devMain devRemote repoRemote same tool build prodPaths aliases dead seeds mem disk (headProblems! s))))

; (:m :ref TRIAL-SETUP :do "aliases the trial lanes file lists under :noCredit (written by setup)")
fn noCreditAliases lanes: String -> (List String)
  (match (stringIndexOf lanes ":noCredit (")
    ((none) (list))
    ((some i)
      (let [(rest (optionOr (stringSlice lanes i (stringLength lanes)) ""))
            (parts (stringSplit rest ":aliases ("))]
        (map bareTok (filter (fn [(x String)] -> Bool (not (stringEmpty? (stringTrim x)))) (stringSplit (optionOr (listHead (stringSplit (optionOr (listGet parts 1) "") ")")) "") " "))))))

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


; (:m :ref TRIAL-BASE-SEED :do "a writer task with a :seed starts from trialSeed-<cell>, the spec base plus its seed commit, so the writer sees the bug it must fix; every other cell starts from the spec base")
fn cellBase s: Spec c: Cell -> String
  (if (and (not c.task.skipWrite) (not (stringEmpty? c.task.seed))) (str "trialSeed-" c.id) s.base)

fn unitOf s: Spec c: Cell -> st/Task
  (st/Task :id c.id :owns c.task.owns :reads (list) :gate c.task.gate :channel "trial" :model c.model.alias :base (cellBase s c) :after (list) :st "queued" :epoch 0 :receipt "")

fn cuOf id: String stateName: String wt: String branch: String -> cd/CUnit
  (cd/CUnit :id id :st stateName :lane "trial" :fails 0 :sig "" :waited 0 :parked 0 :epoch 0 :branch branch :wt wt :model "" :tokens 0 :costMicro 0 :esc 0 :launched 0 :await "")

; (:m :do "the paths a patch touches, from git apply --numstat rows (added, deleted, path)")
fn patchPaths numstat: String -> (List String)
  (filter (fn [(p String)] -> Bool (not (stringEmpty? p)))
    (map (fn [(l String)] -> String (stringTrim (optionOr (listGet (stringSplit l "\t") 2) ""))) (stringLines numstat)))

; (:m :do "the seed commit goes through the vcs layer: a private index holding exactly the patch paths, committed on the recorded HEAD")
fn ! seedCommit! wt: String paths: (List String) msg: String -> gv/Out
  (let [(tx (gv/prepare! wt paths))]
    (if (not tx.ok) (gv/Out :exit 1 :out tx.why)
      (let [(o (gv/finish! wt tx msg paths))
            (_ (gv/discard! tx))]
        o)))

; (:m :do "apply the seed patch in worktree wt and commit it through the vcs layer")
fn ! applySeed! s: Spec wt: String c: Cell -> gv/Out
  (let [(patch (rooted s.toolRoot c.task.seed))
        (app (git wt (list "apply" patch)))
        (paths (patchPaths (gitText wt (list "apply" "--numstat" patch))))]
    (if (= app.exit 0) (seedCommit! wt paths (str "(:c :a trial :do \"seed " c.id "\")")) (gv/Out :exit app.exit :out app.out)))

; (:m :ref SEED-RETRY :do "a worktree left at path by an interrupted run is removed (and pruned) before the cell runs again")
fn ! dropWorktree! s: Spec wt: String -> Bool
  (if (not (fileExists? wt)) true
    (let [(rm (git s.repo (list "worktree" "remove" "--force" wt)))
          (_ (git s.repo (list "worktree" "prune")))]
      (= rm.exit 0)))

; (:m :ref TRIAL-BASE-SEED :do "branch trialSeed-<cell> = spec base + seed commit, made in a scratch worktree that is removed afterwards; rerun-safe (-B)")
fn ! seedBase! s: Spec c: Cell -> (Result String String)
  (let [(wt (str s.worktrees "/seed-" c.id))
        (_ (dropWorktree! s wt))
        (add (git s.repo (list "worktree" "add" "-q" "-B" (cellBase s c) wt s.base)))
        (com (if (= add.exit 0) (applySeed! s wt c) (gv/Out :exit add.exit :out add.out)))
        (_ (dropWorktree! s wt))]
    (if (= com.exit 0) (ok (cellBase s c)) (err (str "baseSeed: " (stringTrim com.out)))))

; (:m :do "a write cell gets its store row, task text and a writing cond row; a seeded cell gets branch sh/<id> from base with the corpus patch applied and committed through the vcs layer, in its own worktree, and a gating cond row")
fn ! seedCell! s: Spec c: Cell -> (Result String String)
  (let [(_ (dirCreate (str s.store "/tasks")))
        (stale (dropWorktree! s (wtOf s c.id)))
        (base (if (= (cellBase s c) s.base) (ok "") (seedBase! s c)))
        (put (match base ((err e) (err e)) ((ok _) (if stale (st/put! s.store (unitOf s c)) (err (str "stale worktree " (wtOf s c.id)))))))
        (_ (fileWrite (str s.store "/tasks/" c.id ".txt") c.task.text))]
    (match put
      ((err e) (err (if (stringStartsWith? e "baseSeed") e (str "store put: " e))))
      ((ok _)
        (if (not c.task.skipWrite)
          (match (cd/writeCUnit! s.store (cuOf c.id "writing" "" "")) ((ok _) (ok "")) ((err e) (err e)))
          (let [(wt (wtOf s c.id))
                (add (git s.repo (list "worktree" "add" "-q" "-B" (str "sh/" c.id) wt s.base)))
                (com (if (= add.exit 0) (applySeed! s wt c) (gv/Out :exit add.exit :out add.out)))]
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
         " :pinBroken " (tf pinBroken) " :known " (st/q c.task.known) " :seeded " (tf (and c.task.skipWrite (or (= c.task.known "reviewFail") (= c.task.known "refuse")))) " :skipWrite " (tf c.task.skipWrite) " :base " (st/q (cellBase s c))
         " :stages (" (stringJoin (map (fn [(p (Pair String cd/Res))] -> String (stageText (pairFirst p) (pairSecond p) red reviewers)) stages) " ") ")"
         " :failedAt " (st/q failedAt) " :merged " (tf (stringEmpty? failedAt))
         " :devBranch " (st/q (if (stringEmpty? failedAt) (devBranchOf s c.id) "")) (if c.task.skipWrite "" (str " :leon " leon))
         " :evidence " (st/q (str (trialDir s) "/" c.id)) " :wallMs " (n wallMs) " :at " (n at) ")"))

; (:m :ref SEED-RETRY :do "the last record of each cell decides: an infra failure (failedAt seed or incomplete) is retried on the next run, a task failure or a merge is final")
fn infra? row: String -> Bool
  (or (stringContains? row ":failedAt \"seed\"") (stringContains? row ":failedAt \"incomplete\""))

fn latestRows text: String -> (List String)
  (let [(rows (filter (fn [(l String)] -> Bool (stringStartsWith? l "(:trialRun :id ")) (stringLines text)))
        (ids (distinct (map (fn [(l String)] -> String (sp/quotedAfter l ":id")) rows)))]
    (map (fn [(id String)] -> String (optionOr (listHead (listReverse (filter (fn [(l String)] -> Bool (= (sp/quotedAfter l ":id") id)) rows))) "")) ids))

fn ! doneIds! s: Spec -> (List String)
  (map (fn [(l String)] -> String (sp/quotedAfter l ":id")) (filter (fn [(l String)] -> Bool (not (infra? l))) (latestRows (readOr (runsPath s)))))

fn ! retryIds! s: Spec -> (List String)
  (map (fn [(l String)] -> String (sp/quotedAfter l ":id")) (filter infra? (latestRows (readOr (runsPath s)))))

; (:m :ref SEED-RETRY :do "a retried cell starts clean: its stage results, TRIAL-PIN receipt, copied evidence, worktree and branch sh/<id> from the failed attempt are removed")
fn ! forgetAttempt! s: Spec id: String -> Int64
  (let [(dir (cd/runsDir s.store))
        (mine (filter (fn [(f String)] -> Bool (stringStartsWith? f (str id "-"))) (resultOr (dirList dir) (list))))
        (_ (map (fn [(f String)] -> Bool (ok? (pathRemove (str dir "/" f)))) mine))
        (_ (fr/runOneLimited (fr/job (list "rm" "-rf" (str (trialDir s) "/" id)) "." (fr/childEnv (list))) (fr/limits 60 4)))
        (_ (dropWorktree! s (wtOf s id)))
        (_ (git s.repo (list "branch" "-D" (str "sh/" id))))]
    (listLength mine))

fn lookup ps: (List (Pair String cd/Res)) id: String -> (Option cd/Res)
  (match (listFind (fn [(p (Pair String cd/Res))] -> Bool (= (pairFirst p) id)) ps) ((some p) (some (pairSecond p))) ((none) (none)))

fn okIn ps: (List (Pair String cd/Res)) stage: String cs: (List Cell) -> (List Cell)
  (filter (fn [(c Cell)] -> Bool (match (lookup ps c.id) ((some r) (passed? stage r)) ((none) false))) cs)

; (:m :do "merges run one at a time: devRepo checks out a fresh <devPrefix><id> from devBase, then the merge stage trains the cell branch onto it; the devRepo goes back to its own branch afterwards")
fn ! mergeOne! s: Spec c: Cell -> (Pair String cd/Res)
  (let [(co (gv/switch! s.devRepo (devBranchOf s c.id) s.devBase))]
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
            (retried (retryIds! s))
            (_ (map (fn [(id String)] -> Int64 (forgetAttempt! s id)) retried))
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
            (_ (if (stringEmpty? devHome) (gv/Out :exit 0 :out "") (gv/switch! s.devRepo devHome devHome)))
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
  (let [(rows (latestRows (readOr (runsPath s))))
        (latest (str (trialDir s) "/runsLatest.asn"))
        (_ (fileWrite latest (stringJoin (map (fn [(r String)] -> String (str r "\n")) rows) "")))
        (merged (listLength (filter (fn [(r String)] -> Bool (stringContains? r " :merged true ")) rows)))
        (stages (list "seed" "write" "gates" "review" "merge" "incomplete"))
        (by (map (fn [(st0 String)] -> String (str "(:" st0 " " (n (listLength (filter (fn [(r String)] -> Bool (stringContains? r (str ":failedAt \"" st0 "\""))) rows))) ")")) stages))
        (report (str (trialDir s) "/report.asn"))
        (argv (if (listEmpty? s.analyzer)
                (list (str s.toolRoot "/bin/asl") "run" (str s.toolRoot "/asl/tools/coord/trialAnalyze.asl"))
                s.analyzer))
        (_ (pathRemove report))
        (d (fr/runOneLimited (fr/job (listAppend argv (list "report" "--in" latest)) s.toolRoot (fr/childEnv (list))) (fr/limits 900 50)))
        (_ (if (= d.exit 0) (fileWrite report d.out) (ok ())))
        (summary (str "(:trialCollect :runs " (n (listLength rows)) " :merged " (n merged) " :failedAt (" (stringJoin by " ") ")"
                      " :analyzer (:exit " (n d.exit) " :report " (st/q (if (fileExists? report) report "")) "))"))
        (_ (fileWrite (str (trialDir s) "/collect.asn") (str summary "\n")))]
    (do (println summary)
        (if (and (= d.exit 0) (and (fileExists? report) (> (listLength rows) 0))) 0 1)))

(schema Setup
  (:f src String) (:f ref String) (:f seed String) (:f lanesFrom String) (:f reviewers (List String)) (:f noCredit (List String))
  (:f noCreditPrefix (List String)) (:f heads (List String)) (:f out String) (:f date String) (:f build (List String)))

fn outOr u: Setup out: String -> Setup
  (if (stringEmpty? u.out) (with u :out out) u)

; (:m :do "op is empty for a command run as argv in cwd; switch (argv branch base) and seedCommit (argv patch message) are vcs-layer operations on the repo in cwd")
(schema Step (:f argv (List String)) (:f cwd String) (:f sec Int64) (:f op String))

; (:m :ref TRIAL-SETUP :do "the (:setup ...) row of a spec: the production source checkout and ref the trial source is cut from, an optional seed patch, the production lanes file the trial panel is read from, the panel, the noCredit providers and alias prefixes, the production repos whose heads the run spec pins, and the run spec it writes")
fn setupOf text: String -> Setup
  (let [(fs (match (listFind (fn [(l String)] -> Bool (= (tagOf l) "setup")) (rowLines text)) ((some l) (fieldsOf l)) ((none) (list))))]
    (Setup :src (txt fs "src") :ref (txtOr fs "ref" "main") :seed (txt fs "seed") :lanesFrom (txt fs "lanesFrom") :reviewers (items fs "reviewers")
           :noCredit (items fs "noCredit") :noCreditPrefix (items fs "noCreditPrefix") :heads (items fs "heads") :out (txt fs "out") :date (txt fs "date")
           :build (let [(b (items fs "build"))] (if (listEmpty? b) (list "sh" "asl/host/build.sh") b))))

fn step argv: (List String) cwd: String -> Step
  (Step :argv argv :cwd cwd :sec 600 :op "")

fn vcsStep op: String repo: String args: (List String) -> Step
  (Step :argv args :cwd repo :sec 600 :op op)

; (:m :do "the host build of one tree, by default sh asl/host/build.sh, run in the tree with the caller's ASL_ROOT and ASL_PRELUDE removed")
fn buildStep u: Setup dir: String -> Step
  (Step :argv (listAppend (list "env" "-u" "ASL_ROOT" "-u" "ASL_PRELUDE") u.build) :cwd dir :sec 3600 :op "")

fn identity dir: String -> (List Step)
  (list (step (list "git" "-C" dir "config" "user.email" "trial@example.invalid") ".") (step (list "git" "-C" dir "config" "user.name" "trial") "."))

; (:m :ref TRIAL-SETUP :do "the commands of a setup, git and build.sh only: the trial source is a repo with no remote whose main is the production ref plus the seed commit (switch and seed commit through the vcs layer), the dev repo a repo with no remote on devBase at that main; both are fetched by path, never cloned (a clone would add an origin), and each gets its own host build; no deploy!, no systemctl, nothing is pushed")
fn setupSteps s: Spec u: Setup sha: String repoNew: Bool devNew: Bool -> (List Step)
  (fold listAppend (list)
    (list (if repoNew (list (step (list "git" "init" "-q" "-b" "main" s.repo) ".")) (list))
          (identity s.repo)
          (list (step (list "git" "-C" s.repo "fetch" "-q" "--no-tags" u.src sha) ".")
                (vcsStep "switch" s.repo (list "main" sha)))
          (if (stringEmpty? u.seed) (list)
            (list (step (list "git" "-C" s.repo "apply" (rooted s.toolRoot u.seed)) ".")
                  (vcsStep "seedCommit" s.repo (list (rooted s.toolRoot u.seed) "(:c :a trial :do \"trial seed\")"))))
          (list (buildStep u s.repo))
          (if devNew (list (step (list "git" "init" "-q" "-b" s.devBase s.devRepo) ".")) (list))
          (identity s.devRepo)
          (list (step (list "git" "-C" s.devRepo "fetch" "-q" "--no-tags" s.repo "main") ".")
                (vcsStep "switch" s.devRepo (list s.devBase "FETCH_HEAD"))
                (buildStep u s.devRepo)
                (step (list "mkdir" "-p" s.store (str s.store "/trial") s.worktrees) "."))))

fn stepText x: Step -> String
  (if (stringEmpty? x.op)
    (str "(:cmd :cwd " (st/q x.cwd) " :argv " (st/qList x.argv) ")")
    (str "(:vcs :op " x.op " :repo " (st/q x.cwd) " :args " (st/qList x.argv) ")"))

fn laneRowsOf text: String -> (List String)
  (fold (fn [(acc (List String)) (l String)] -> (List String)
          (match (stringIndexOf l "(:lane :alias ")
            ((none) acc)
            ((some i)
              (let [(rest (optionOr (stringSlice l i (stringLength l)) ""))
                    (row (str (optionOr (listHead (stringSplit rest ")")) "") ")"))]
                (listAppend acc (list row))))))
        (list) (stringLines text))

fn providerOf gateway: String alias: String -> String
  (match (stringIndexOf gateway (str "(:model :id " alias " "))
    ((none) "")
    ((some i) (wordAt (optionOr (listHead (stringSplit (optionOr (stringSlice gateway i (stringLength gateway)) "") ")")) "") ":provider")))

fn noCredit? u: Setup gateway: String alias: String -> Bool
  (or (listContains? u.noCredit (providerOf gateway alias)) (listAny? (fn [(p String)] -> Bool (stringStartsWith? alias p)) u.noCreditPrefix))

; (:m :ref TRIAL-SETUP :do "the trial lanes file: the production lane rows of the fixed panel only, noCredit lanes (commandCode, cc*) dropped and listed under :noCredit, so review never rotates onto a lane without credit and check refuses a pinned writer on one")
fn trialLanesText u: Spec setup: Setup src: String gateway: String -> String
  (let [(rows (laneRowsOf src))
        (dead (distinct (map (fn [(r String)] -> String (wordAt r ":alias")) (filter (fn [(r String)] -> Bool (noCredit? setup gateway (wordAt r ":alias"))) rows))))
        (keep (filter (fn [(r String)] -> Bool (and (listContains? setup.reviewers (wordAt r ":alias")) (not (noCredit? setup gateway (wordAt r ":alias"))))) rows))
        (fam (sp/quotedAfter src ":familyExtra"))]
    (str "(:reviewLanes :v 1 :date " (st/q setup.date) " :by trialSetup :from " (st/q setup.lanesFrom)
         " :method \"fixed trial review panel from the production lanes; noCredit lanes dropped\""
         (if (stringEmpty? fam) "" (str " :familyExtra " (st/q fam)))
         " :noCredit (:providers " (st/qList setup.noCredit) " :prefixes " (st/qList setup.noCreditPrefix) " :aliases " (st/qList dead) ")"
         "\n  :lanes (" (stringJoin keep "\n          ") "))\n"))

fn ! headRows! u: Setup -> (List String)
  (map (fn [(h String)] -> String (str "(:head :repo " (st/q h) " :sha " (st/q (gitText h (list "rev-parse" "HEAD"))) ")")) u.heads)

; (:m :ref TRIAL-SETUP :do "the run spec setup writes: every row of the setup spec but its (:head ...) and (:setup ...) rows, plus one (:head ...) row per production repo pinned at its current HEAD")
fn runSpecText text: String heads: (List String) -> String
  (str (stringJoin (filter (fn [(l String)] -> Bool (not (or (= (tagOf l) "head") (= (tagOf l) "setup")))) (rowLines text)) "\n") "\n" (stringJoin heads "\n") "\n")

fn ! setupProblems! s: Spec u: Setup sha: String lanesSrc: String gateway: String -> (List String)
  (let [(prod (listAppend (list u.src) u.heads))
        (paths (filter (fn [(p String)] -> Bool (not (stringEmpty? p))) (list s.repo s.devRepo s.store s.worktrees s.lanes u.out)))
        (inProd (fold listAppend (list) (map (fn [(h String)] -> (List String) (map (fn [(p String)] -> String (str "isProduction:" p)) (filter (fn [(p String)] -> Bool (inside? p h)) paths))) prod)))
        (rows (laneRowsOf lanesSrc))
        (aliases (map (fn [(r String)] -> String (wordAt r ":alias")) rows))]
    (fold listAppend (list)
      (list (if (stringEmpty? u.src) (list "missing:setup.src") (list))
            (if (stringEmpty? sha) (list (str "srcRef:" u.ref)) (list))
            (if (or (stringEmpty? s.repo) (or (stringEmpty? s.devRepo) (same? s.repo s.devRepo))) (list "repoDevRepo") (list))
            (if (or (stringEmpty? s.devBase) (or (= s.devBase "main") (= s.devBase "master"))) (list (str "devBase:" s.devBase)) (list))
            (if (or (stringEmpty? s.lanes) (same? s.lanes u.lanesFrom)) (list "lanesOverwrite") (list))
            (if (listEmpty? rows) (list (str "lanesFrom:" u.lanesFrom)) (list))
            (map (fn [(a String)] -> String (str "reviewerMissing:" a)) (filter (fn [(a String)] -> Bool (not (listContains? aliases a))) u.reviewers))
            (map (fn [(a String)] -> String (str "reviewerNoCredit:" a)) (filter (fn [(a String)] -> Bool (noCredit? u gateway a)) u.reviewers))
            (map (fn [(m Model)] -> String (str "writerNoCredit:" m.alias)) (filter (fn [(m Model)] -> Bool (noCredit? u gateway m.alias)) s.models))
            (if (and (not (stringEmpty? u.seed)) (not (fileExists? (rooted s.toolRoot u.seed)))) (list (str "seedMissing:" u.seed)) (list))
            inProd
            (prodPathProblems! s u.out)
            (if (and (fileExists? s.repo) (not (stringEmpty? (gitText s.repo (list "remote"))))) (list "repoRemote") (list))
            (if (and (fileExists? s.devRepo) (not (stringEmpty? (gitText s.devRepo (list "remote"))))) (list "devRepoRemote") (list)))))

fn doneOf o: gv/Out -> fr/Done
  (fr/Done :idx 0 :exit o.exit :out o.out :ms 0 :verdict "")

fn ! runStep! x: Step -> fr/Done
  (cond
    ((= x.op "switch") (doneOf (gv/switch! x.cwd (optionOr (listGet x.argv 0) "") (optionOr (listGet x.argv 1) ""))))
    ((= x.op "seedCommit") (let [(patch (optionOr (listGet x.argv 0) ""))] (doneOf (seedCommit! x.cwd (patchPaths (gitText x.cwd (list "apply" "--numstat" patch))) (optionOr (listGet x.argv 1) "")))))
    (else (fr/runOneLimited (fr/job x.argv x.cwd (fr/childEnv (list))) (fr/limits x.sec 200))))

fn ! runSteps! xs: (List Step) -> (Option (Pair Step fr/Done))
  (match (listHead xs)
    ((none) (none))
    ((some x)
      (let [(d (runStep! x))]
        (if (!= d.exit 0) (some (pair x d)) (runSteps! (optionOr (listTail xs) (list)))))))

; (:m :ref TRIAL-SETUP :do "setup --spec S [--dry-run]: refuses on any setup problem; --dry-run prints the commands, the files it would write and the pinned heads and changes nothing (its only reads are git rev-parse and the lanes and gateway files); without it the commands run in order through fleet/run.asl, the trial lanes file and the run spec are written, then check runs on the run spec")
fn ! setup! path: String dry: Bool -> Int64
  (match (specLines! path)
    ((err e) (do (println (str "(:setup :error " (st/q e) ")")) 2))
    ((ok s)
      (let [(text (readOr path))
            (u0 (setupOf text))
            (u (outOr u0 (str s.store "/trialSpec.asn")))
            (sha (gitText u.src (list "rev-parse" "--verify" (str u.ref "^{commit}"))))
            (lanesSrc (readOr u.lanesFrom))
            (gateway (readOr (str s.home "/.asl/gateway.asn")))
            (ps (setupProblems! s u sha lanesSrc gateway))]
        (if (not (listEmpty? ps))
          (do (println (str "(:setup :refuse :problems " (st/qList ps) ")")) 1)
          (let [(xs (setupSteps s u sha (not (fileExists? (str s.repo "/.git"))) (not (fileExists? (str s.devRepo "/.git")))))
                (lanes (trialLanesText s u lanesSrc gateway))
                (_ (map (fn [(x Step)] -> Unit (println (stepText x))) xs))]
            (if dry
              (let [(heads (headRows! u))]
                (do (println (str "(:write :path " (st/q s.lanes) " :lanes " (n (listLength (laneRowsOf lanes))) ")"))
                    (println (str "(:write :path " (st/q u.out) " :heads " (st/qList heads) ")"))
                    (println (str "(:setup :dryRun true :src " (st/q u.src) " :sha " (st/q sha) " :steps " (n (listLength xs)) ")"))
                    0))
              (match (runSteps! xs)
                ((some p) (do (println (str "(:setup :failed " (stepText (pairFirst p)) " :exit " (n (pairSecond p).exit) " :out " (clip (pairSecond p).out) ")")) 1))
                ((none)
                  (let [(heads (headRows! u))
                        (w1 (fileWrite s.lanes lanes))
                        (w2 (fileWrite u.out (runSpecText text heads)))
                        (c (match (specLines! u.out) ((ok s2) (check! s2)) ((err _) 1)))]
                    (do (println (str "(:setup :done true :src " (st/q u.src) " :sha " (st/q sha) " :steps " (n (listLength xs)) " :lanes " (st/q s.lanes) " :spec " (st/q u.out) " :check " (n c) ")"))
                        (if (and (ok? w1) (and (ok? w2) (= c 0))) 0 1)))))))))))

fn ! main args: (List String) -> (Result Int64 String)
  (let [(cmd (optionOr (listHead args) ""))
        (path (st/opt args "spec" ""))]
    (if (= cmd "setup")
      (ok (setup! path (listContains? args "--dry-run")))
      (match (specLines! path)
        ((err e) (do (eprintln (str "(:trial :error " (st/q e) ")")) (ok 2)))
        ((ok s)
          (cond
            ((= cmd "check") (ok (check! s)))
            ((= cmd "run") (ok (run! s (st/opt args "only" ""))))
            ((= cmd "collect") (ok (collect! s)))
            (else (do (eprintln "usage: trial.asl setup|check|run|collect --spec S [--dry-run] [--only CELL]") (ok 2))))))))
