(module asl-cli/cacheGc
  :x [GcPlan GcArgs parseArgs sizeValue ageValue originFile recordOrigin! deadOrigin? gcEntries! planGc applyGc! receipt cacheCmd!]
  :i [(asl/packages/asl-cli/src/system :a sys) (asl/packages/asl-cli/src/nativeCli :a ncli) (asl-tools/nativeTest :a nt) (asl/packages/asl-cli/src/nativeBuild :a nb)])

; (:m :ref DS-NATIVECACHEGC :do "asl cache gc bounds a native test cache: an outsidePkg mirror whose recorded source root is gone goes first, then every unleased entry older than --older-than, then the oldest unleased entries until the store fits --cap; an entry a live run leases (a slot lock, a module claim lock) or that changed within the store's :native :storeMinAge (a concurrent stager) is never removed, and each entry is re-stamped right before it is removed; one receipt names what was freed and what stayed")
(schema GcArgs (:f dir String) (:f capBytes Int64) (:f olderNs Int64) (:f dryRun Bool) (:f error String))

(schema GcPlan (:f drop (List ncli/StoreEntry)) (:f keep (List ncli/StoreEntry)) (:f deadOrigin Int64) (:f pinned Int64))

fn noLimit -> Int64
  4611686018427387904

; (:m :ref DS-NATIVECACHEGC :do "a size is digits with an optional K, M or G suffix (powers of 1024); an age is digits with s, m, h or d; anything else is none")
fn unitOf s: String -> (Pair String String)
  (let [(n (stringLength s))]
    (if (= n 0) (pair "" "") (pair (optionOr (stringSlice s 0 (- n 1)) "") (optionOr (stringSlice s (- n 1) n) ""))))

fn scaled digits: String mult: Int64 -> (Option Int64)
  (match (stringToInt64 digits)
    ((some v) (if (< v 0) (none) (some (* v mult))))
    ((none) (none)))

fn sizeValue s: String -> (Option Int64)
  (let [(u (unitOf (stringTrim s))) (head (pairFirst u)) (last (pairSecond u))]
    (cond
      ((= last "K") (scaled head 1024))
      ((= last "M") (scaled head 1048576))
      ((= last "G") (scaled head 1073741824))
      (else (scaled (stringTrim s) 1))))

fn ageValue s: String -> (Option Int64)
  (let [(u (unitOf (stringTrim s))) (head (pairFirst u)) (last (pairSecond u))]
    (cond
      ((= last "s") (scaled head 1000000000))
      ((= last "m") (scaled head 60000000000))
      ((= last "h") (scaled head 3600000000000))
      ((= last "d") (scaled head 86400000000000))
      (else (none))))

fn argErr a: GcArgs msg: String -> GcArgs
  (with a :error msg)

; (:m :ref DS-NATIVECACHEGC :do "a release name is one path component: not empty, not . or .., no slash, so --release cannot reach outside ~/.asl/releases")
fn releaseName? v: String -> Bool
  (and (not (stringEmpty? v)) (and (not (stringContains? v "/")) (not (or (= v ".") (= v "..")))))

fn parseFrom args: (List String) a: GcArgs -> GcArgs
  (match (listHead args)
    ((none) a)
    ((some flag)
      (let [(value (optionOr (listGet args 1) ""))
            (rest2 (listDrop args 2))]
        (cond
          ((= flag "--dry-run") (parseFrom (listDrop args 1) (with a :dryRun true)))
          ((= flag "--dir") (if (stringEmpty? value) (argErr a "--dir needs a directory") (parseFrom rest2 (with a :dir value))))
          ((= flag "--release") (if (not (releaseName? value)) (argErr a (str "--release takes a version name without / or .., got " value)) (parseFrom rest2 (with a :dir (str (optionOr (envGet "HOME") "") "/.asl/releases/" value "/.asl/cache/nativeTest")))))
          ((= flag "--cap") (match (sizeValue value) ((some v) (parseFrom rest2 (with a :capBytes v))) ((none) (argErr a (str "--cap takes a size like 2G, got " value)))))
          ((= flag "--older-than") (match (ageValue value) ((some v) (parseFrom rest2 (with a :olderNs v))) ((none) (argErr a (str "--older-than takes an age like 7d, got " value)))))
          (else (argErr a (str "unknown argument " flag)))))))

; (:m :ref DS-NATIVECACHEGC :do "with no --dir the tree's own .asl/cache/nativeTest is swept, never the shared ~/.asl/run/nativeTest store: that one is named explicitly with --dir; with no --cap the store's configured :storeCap applies")
fn parseArgs root: String args: (List String) capDefault: Int64 -> GcArgs
  (parseFrom args (GcArgs :dir (str root "/.asl/cache/nativeTest") :capBytes capDefault :olderNs (noLimit) :dryRun false :error ""))

fn originFile -> String
  ".origin"

; (:m :ref DS-NATIVECACHEGC :do "a staged outsidePkg mirror records the source root it was staged from, so gc can tell a retired worktree's mirror from a live one; its digest is the sha256 of that root")
fn ! recordOrigin! mirrorDir: String root: String -> Bool
  (let [(path (str mirrorDir "/" (originFile)))]
    (if (= (resultOr (fileReadString path) "") (str root "\n"))
      true
      (ok? (fileWrite path (str root "\n")))))

fn ! deadOrigin? mirrorDir: String -> Bool
  (match (fileReadString (str mirrorDir "/" (originFile)))
    ((err _) false)
    ((ok text) (let [(root (stringTrim text))]
                 (and (not (stringEmpty? root)) (not (sys/isDir? root))))))

fn ! liveLockIn? paths: (List String) -> Bool
  (listAny? (fn [(p String)] -> Bool (and (stringEndsWith? p ".lock") (nt/lockLive? p))) paths)

; (:m :ref DS-NATIVECACHEGC :do "a module object is claimed while a live KEY.o.lock sits beside it: moduleEntries! groups by the stem before the last dot, so KEY.o and KEY.o.lock fall in different groups and the lock must be looked up per path")
fn ! claimedIn? paths: (List String) -> Bool
  (listAny? (fn [(p String)] -> Bool (nt/lockLive? (str p ".lock"))) paths)

fn ! dirEntries! dir: String -> (List ncli/StoreEntry)
  (map (fn [(n String)] -> ncli/StoreEntry (ncli/storeEntry! (list (str dir "/" n)) false))
       (filter (fn [(n String)] -> Bool (not (stringStartsWith? n "."))) (resultOr (dirList dir) (list))))

; (:m :ref DS-NATIVECACHEGC :do "the entries of one store: build slots (leased by slot/lock), module objects grouped by key (leased by a live KEY.o.lock), staged outsidePkg mirrors and outside files, and eval sources")
fn ! gcEntries! dir: String -> (List ncli/StoreEntry)
  (let [(mods (map (fn [(e ncli/StoreEntry)] -> ncli/StoreEntry (with e :pinned (or e.pinned (or (liveLockIn? e.paths) (claimedIn? e.paths))))) (nt/moduleEntries! (str dir "/modules"))))]
    (listAppend (nt/slotEntries! dir)
      (listAppend mods
        (listAppend (dirEntries! (str dir "/outsidePkg"))
          (listAppend (dirEntries! (str dir "/outside")) (dirEntries! (str dir "/evals")))))))

fn ! underDir? e: ncli/StoreEntry dir: String -> Bool
  (listAny? (fn [(p String)] -> Bool (stringStartsWith? p (str dir "/"))) e.paths)

fn ! deadEntry? dir: String e: ncli/StoreEntry -> Bool
  (and (underDir? e (str dir "/outsidePkg")) (deadOrigin? (optionOr (listHead e.paths) "")))

; (:m :ref DS-NATIVECACHEGC :do "the plan is pure over stamped entries: protected = leased or changed within minAgeNs (the store's :storeMinAge); dead-origin and older-than entries drop first, then the oldest of the rest until the kept bytes fit the cap")
fn planGc tagged: (List (Pair ncli/StoreEntry Bool)) now: Int64 capBytes: Int64 olderNs: Int64 minAgeNs: Int64 -> GcPlan
  (let [(entries (map pairFirst tagged))
        (protected? (fn [(e ncli/StoreEntry)] -> Bool (or e.pinned (< (- now e.stamp) minAgeNs))))
        (split (fold (fn [(acc (Pair (List ncli/StoreEntry) (List ncli/StoreEntry))) (t (Pair ncli/StoreEntry Bool))] -> (Pair (List ncli/StoreEntry) (List ncli/StoreEntry))
                       (let [(e (pairFirst t))]
                         (if (and (not (protected? e)) (or (pairSecond t) (> (- now e.stamp) olderNs)))
                           (pair (cons e (pairFirst acc)) (pairSecond acc))
                           (pair (pairFirst acc) (cons e (pairSecond acc))))))
                     (pair (list) (list)) tagged))
        (rest (listSortBy (fn [(e ncli/StoreEntry)] -> Int64 e.stamp) (pairSecond split)))
        (capped (fold (fn [(acc (Pair (Pair (List ncli/StoreEntry) (List ncli/StoreEntry)) Int64)) (e ncli/StoreEntry)] -> (Pair (Pair (List ncli/StoreEntry) (List ncli/StoreEntry)) Int64)
                        (let [(lists (pairFirst acc)) (total (pairSecond acc))]
                          (if (and (> total capBytes) (not (protected? e)))
                            (pair (pair (cons e (pairFirst lists)) (pairSecond lists)) (- total e.bytes))
                            (pair (pair (pairFirst lists) (cons e (pairSecond lists))) total))))
                      (pair (pair (pairFirst split) (list)) (ncli/storeBytes (pairSecond split))) rest))]
    (GcPlan :drop (pairFirst (pairFirst capped)) :keep (pairSecond (pairFirst capped))
            :deadOrigin (listLength (filter (fn [(t (Pair ncli/StoreEntry Bool))] -> Bool (and (pairSecond t) (not (protected? (pairFirst t))))) tagged))
            :pinned (listLength (filter protected? entries))))

; (:m :ref DS-NATIVECACHEGC :do "each planned entry is re-stamped right before removal, as sweepEntries! does: one changed within minAgeNs since the plan (a stager or a build reusing it) stays")
fn ! applyGc! plan: GcPlan minAgeNs: Int64 -> (Pair Int64 Int64)
  (fold (fn [(acc (Pair Int64 Int64)) (e ncli/StoreEntry)] -> (Pair Int64 Int64)
          (if (and (> (- (nowNs) (ncli/storeEntry! e.paths false).stamp) minAgeNs) (ncli/dropEntry! e)) (pair (+ (pairFirst acc) 1) (+ (pairSecond acc) e.bytes)) acc))
        (pair 0 0) plan.drop)

fn receipt a: GcArgs plan: GcPlan removed: Int64 freed: Int64 -> String
  (let [(kept (ncli/storeBytes plan.keep))]
    (str "(:cacheGc :dir \"" a.dir "\" :dryRun " (if a.dryRun "true" "false")
         " :entries " (stringFromInt64 (+ (listLength plan.drop) (listLength plan.keep)))
         " :removed " (stringFromInt64 removed) " :freedBytes " (stringFromInt64 freed)
         " :keptBytes " (stringFromInt64 kept) " :capBytes " (stringFromInt64 a.capBytes)
         " :deadOrigin " (stringFromInt64 plan.deadOrigin) " :protected " (stringFromInt64 plan.pinned)
         (if (> kept a.capBytes) " :note \"over cap: the rest is leased or changed within :storeMinAge\"" "") ")"))

; (:m :ref DS-NATIVECACHEGC :do "one gc at a time per store and never beside nativeTest's own sweep: both take DIR/sweep.lock; a held lock is a :busy receipt and exit 1")
fn ! cacheCmd! ctx: sys/Context args: (List String) -> Int64
  (if (!= (optionOr (listHead args) "") "gc")
    (do (sys/say! "(:cache :status :failed :error ERR_USAGE :message \"asl cache gc [--dir D | --release V] [--cap SIZE] [--older-than AGE] [--dry-run]\")") 2)
    (let [(a (parseArgs ctx.root (listDrop args 1) (nb/storeCapFor! ctx.root)))]
      (cond
        ((not (stringEmpty? a.error)) (do (sys/say! (str "(:cache :status :failed :error ERR_USAGE :message \"" a.error "\")")) 2))
        ((not (sys/isDir? a.dir)) (do (sys/say! (str "(:cacheGc :dir \"" a.dir "\" :entries 0 :removed 0 :freedBytes 0 :note \"no cache here\")")) 0))
        ((not (nt/takeLock! (str a.dir "/sweep.lock") 1)) (do (sys/say! (str "(:cacheGc :dir \"" a.dir "\" :status :busy :message \"another sweep holds sweep.lock\")")) 1))
        (else
          (let [(minAge (nb/storeMinAgeNs! ctx.root))
                (entries (gcEntries! a.dir))
                (tagged (map (fn [(e ncli/StoreEntry)] -> (Pair ncli/StoreEntry Bool) (pair e (deadEntry? a.dir e))) entries))
                (plan (planGc tagged (nowNs) a.capBytes a.olderNs minAge))
                (done (if a.dryRun (pair (listLength plan.drop) (ncli/storeBytes plan.drop)) (applyGc! plan minAge)))
                (_ (pathRemove (str a.dir "/sweep.lock")))]
            (do (sys/say! (receipt a plan (pairFirst done) (pairSecond done))) 0))))))
