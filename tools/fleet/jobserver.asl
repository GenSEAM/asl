(module asl-tools/fleet/jobserver
  :x [Grant rootDir snapshot startOf tokenCount classRank want wantWith acquire acquireProc psCommand maxHoldNs bind releaseIdxs releasePid heldCount backoffMs]
  :i [])

; (:m :ref MACHINE-JOBSERVER :do "a machine-wide CPU token pool: N token files under <dir>/tokens claimed with fileCreateExclusive, a dead owner's token reclaimed by pid liveness, and one waiting ticket per waiter under <dir>/wait ordered by class rank then arrival, so a higher class gets the next free token first; the dir is a call argument or ~/.asl/run/jobserver, N is the :tokens row of <dir>/config.asn or half the cores (FABLE-GATE-ADMIT), never env")
(schema Grant
  (:f state String)
  (:f idxs (List Int64))
  (:f startNs Int64))

fn ! rootDir dir: String -> String
  (if (stringEmpty? dir) (str (resultOr (getHomeDir) ".") "/.asl/run/jobserver") dir)

fn ! fieldInt text: String key: String -> (Option Int64)
  (match (stringIndexOf text key)
    ((none) (none))
    ((some i) (let [(rest (stringTrim (optionOr (stringSlice text (+ i (stringLength key)) (stringLength text)) "")))
                    (tok (stringReplace (optionOr (listHead (stringSplit rest " ")) "") ")" ""))]
                (stringToInt64 tok))))

fn ! tokenCount dir: String -> Int64
  (let [(cfg (resultOr (fileReadString (str (rootDir dir) "/config.asn")) ""))]
    (match (fieldInt cfg ":tokens ")
      ((some n) (if (> n 0) n 1))
      ((none) (defaultTokens (resultOr (cpuCount) 1)))))

; (:m :ref FABLE-GATE-ADMIT :do "without a :tokens row the pool is half the cores, at least 1 (adopted 2026-11-13: load 20-166 on 10 cores with a token per core); the row (:jobserver :tokens N) in <dir>/config.asn is read at every claim, so a change reaches every running session at its next claim")
fn defaultTokens cores: Int64 -> Int64
  (if (> cores 1) (/ cores 2) 1)

; (:m :ref FABLE-GATE-ADMIT :do "the slot ledger <dir>/slots.log: one row per claim, release and reclaim of a token with the monotonic time, appended by whoever did it; a claim row is written after the exclusive create and a release or reclaim row carries the time before the token file goes, so the rows of one token never overlap while claims are exclusive and the peak of open claims over the rows sorted by :ns is the peak concurrency; past 4 MB the file moves to slots.log.1")
fn ! slotRow root: String ev: String i: Int64 owner: Int64 ns: Int64 -> Bool
  (let [(path (str root "/slots.log"))
        (_ (if (> (resultOr (fileSize path) 0) 4194304) (ok? (pathRename path (str path ".1"))) false))]
    (ok? (fileAppend path (str "(:slot :ev :" ev " :tok " i " :owner " owner " :ns " ns ")\n"))))

fn idxOfName f: String -> Int64
  (optionOr (stringToInt64 (stringReplace (optionOr (listLast (stringSplit f "/")) f) "tok" "")) -1)

; (:m :ref MACHINE-JOBSERVER :do "train outranks audit outranks writer outranks background; exclusive (bench) queues at audit rank and takes every token; \"\" opts out")
fn classRank cls: String -> Int64
  (cond ((= cls "train") 0) ((= cls "audit") 1) ((= cls "exclusive") 1) ((= cls "writer") 2) ((= cls "background") 3) (else -1))

fn ! alive? pid: Int64 -> Bool
  (resultOr (procAlive? pid) false)

(schema Row
  (:f pid Int64)
  (:f ppid Int64)
  (:f start String))

fn rowOf acc: (List Row) line: String -> (List Row)
  (let [(ws (filter (fn [(w String)] -> Bool (not (stringEmpty? w))) (stringSplit (stringTrim line) " ")))
        (pid (stringToInt64 (optionOr (listGet ws 0) "")))
        (ppid (stringToInt64 (optionOr (listGet ws 1) "")))]
    (match pid
      ((none) acc)
      ((some p) (match ppid
                  ((none) acc)
                  ((some pp) (cons (Row :pid p :ppid pp :start (stringJoin (listDrop ws 2) " ")) acc))))))

; (:m :ref MACHINE-JOBSERVER :do "one ps snapshot of every process with its parent and start time; it answers ancestry, owner liveness and pid reuse in one spawn. An empty list means ps failed, and callers then reclaim nothing")
fn psCommand -> String
  "env LC_ALL=C ps -A -o pid=,ppid=,lstart="

fn ! snapshot -> (List Row)
  (match (processSpawn (psCommand))
    ((err _) (list))
    ((ok h) (match (processWait h 15000)
              ((err _) (list))
              ((ok o) (fold rowOf (list) (stringLines o.stdout))))))

fn startIn snap: (List Row) pid: Int64 -> String
  (match (listFind (fn [(r Row)] -> Bool (= r.pid pid)) snap)
    ((some r) r.start)
    ((none) ""))

fn ! startOf pid: Int64 -> String
  (startIn (snapshot) pid)

fn ancestorsOf snap: (List Row) pid: Int64 depth: Int64 -> (List Int64)
  (if (<= depth 0) (list)
    (match (listFind (fn [(r Row)] -> Bool (= r.pid pid)) snap)
      ((none) (list))
      ((some r) (if (<= r.ppid 1) (list) (cons r.ppid (ancestorsOf snap r.ppid (- depth 1)))))))

fn fieldStr text: String key: String -> String
  (match (stringIndexOf text key)
    ((none) "")
    ((some i) (let [(rest (optionOr (stringSlice text (+ i (stringLength key)) (stringLength text)) ""))]
                (optionOr (listHead (stringSplit rest "\"")) ""))))

fn ! tokPath root: String i: Int64 -> String
  (str root "/tokens/tok" i)

fn tokText owner: Int64 child: Int64 startNs: Int64 cls: String ost: String -> String
  (str "(:tok :ownerPid " owner " :ownerStart \"" ost "\" :childPid " child " :startNs " startNs " :class \"" cls "\")\n")

fn ! breakToken root: String path: String deadPid: Int64 -> Unit
  (let [(stale (str path ".stale." (procSelf)))
        (before (monotonicNs))]
    (match (pathRename path stale)
      ((err _) ())
      ((ok _)
       (let [(moved (resultOr (fileReadString stale) ""))]
         (do (if (= (fieldInt moved ":ownerPid ") (some deadPid))
               (let [(_ (slotRow root "reclaim" (idxOfName path) deadPid before))] ())
               (match (fileCreateExclusive path moved) ((ok _) ()) ((err _) ())))
             (match (pathRemove stale) ((ok _) ()) ((err _) ())))))))

fn ! takeToken root: String i: Int64 owner: Int64 cls: String ost: String startNs: Int64 tries: Int64 -> Bool
  (let [(path (tokPath root i))]
    (match (fileCreateExclusive path (tokText owner 0 startNs cls ost))
      ((ok _) (let [(_ (slotRow root "claim" i owner (monotonicNs)))] true))
      ((err _) (if (<= tries 0) false
                 (match (fileReadString path)
                   ((err _) false)
                   ((ok t) (match (fieldInt t ":ownerPid ")
                             ((none) false)
                             ((some p) (if (alive? p) false
                                         (do (breakToken root path p) (takeToken root i owner cls ost startNs (- tries 1))))))))))))

; (:m :ref MACHINE-JOBSERVER :do "a token is removed only while its file still names this process as owner, so a release after a reclaim and re-take by someone else cannot free the new holder's token")
fn ! dropIdxs root: String idxs: (List Int64) -> Int64
  (fold (fn [(n Int64) (i Int64)] -> Int64
          (let [(t (resultOr (fileReadString (tokPath root i)) ""))]
            (if (= (fieldInt t ":ownerPid ") (some (procSelf)))
              (let [(_ (slotRow root "release" i (procSelf) (monotonicNs)))]
                (match (pathRemove (tokPath root i)) ((ok _) (+ n 1)) ((err _) n)))
              n)))
        0 idxs)

fn ! firstFree root: String n: Int64 i: Int64 owner: Int64 cls: String ost: String startNs: Int64 -> (List Int64)
  (if (>= i n) (list)
    (if (takeToken root i owner cls ost startNs 2) (list i) (firstFree root n (+ i 1) owner cls ost startNs)))

fn ! takeAll root: String n: Int64 i: Int64 owner: Int64 cls: String ost: String startNs: Int64 taken: (List Int64) -> (List Int64)
  (if (>= i n) taken
    (if (takeToken root i owner cls ost startNs 2)
      (takeAll root n (+ i 1) owner cls ost startNs (listAppend taken (list i)))
      (do (dropIdxs root taken) (list))))

; (:m :ref MACHINE-JOBSERVER :do "a token is stale when its owner is gone from the snapshot or runs under a different start time than the one recorded, i.e. the pid was reused; stale tokens are broken so the next take succeeds")
fn ! reapStale root: String snap: (List Row) names: (List String) maxHold: Int64 -> Int64
  (if (listEmpty? snap) 0
    (fold (fn [(n Int64) (f String)] -> Int64
            (let [(path (str root "/tokens/" f))
                  (t (resultOr (fileReadString path) ""))
                  (ost (fieldStr t ":ownerStart \""))]
              (match (fieldInt t ":ownerPid ")
                ((none) n)
                ((some o) (let [(now (startIn snap o))
                                (born (optionOr (fieldInt t ":startNs ") 0))
                                (age (- (monotonicNs) born))
                                (old (and (> maxHold 0) (and (> born 0) (> age maxHold))))]
                            (if (or old (or (stringEmpty? now) (and (not (stringEmpty? ost)) (!= now ost))))
                              (let [(_ (breakToken root path o))
                                    (_ (reclaimNote root f o (if old "age" "owner") (/ age 1000000000)))]
                                (+ n 1))
                              n))))))
          0 names))

fn ! reclaimNote root: String f: String owner: Int64 reason: String ageS: Int64 -> Bool
  (let [(row (str "(:jobserver :reclaimed " f " :ownerPid " owner " :reason :" reason " :ageS " ageS ")"))
        (_ (eprintln row))]
    (ok? (fileAppend (str root "/reclaim.log") (str row "\n"))))

; (:m :ref MACHINE-JOBSERVER :do "a token this very process took for its whole life (asl test, asl build) counts as held for the process's own later calls, which is what keeps a reexec into the same pid from queueing behind itself; pool tokens bound per job do not count, so one process can still hold several")
fn ! holdsSelf root: String snap: (List Row) owner: Int64 names: (List String) -> Bool
  (listAny? (fn [(f String)] -> Bool
              (let [(t (resultOr (fileReadString (str root "/tokens/" f)) ""))
                    (ost (fieldStr t ":ownerStart \""))]
                (and (stringContains? t ":kind \"proc\"")
                     (and (= (fieldInt t ":ownerPid ") (some owner))
                          (or (stringEmpty? ost) (= ost (startIn snap owner)))))))
            names)

fn ! holdsAny root: String snap: (List Row) ancestors: (List Int64) names: (List String) -> Bool
  (listAny? (fn [(f String)] -> Bool
              (let [(t (resultOr (fileReadString (str root "/tokens/" f)) ""))
                    (ost (fieldStr t ":ownerStart \""))]
                (match (fieldInt t ":ownerPid ")
                  ((none) false)
                  ((some o) (and (listContains? ancestors o)
                                 (or (stringEmpty? ost) (= ost (startIn snap o))))))))
            names)

fn ! tokenNames root: String -> (List String)
  (filter (fn [(f String)] -> Bool (and (stringStartsWith? f "tok") (not (stringContains? f ".stale."))))
          (resultOr (dirList (str root "/tokens")) (list)))

fn ! heldCount dir: String -> Int64
  (let [(root (rootDir dir))]
    (fold (fn [(n Int64) (f String)] -> Int64
            (let [(t (resultOr (fileReadString (str root "/tokens/" f)) ""))]
              (match (fieldInt t ":ownerPid ")
                ((some p) (if (alive? p) (+ n 1) n))
                ((none) (+ n 1)))))
          0 (tokenNames root)))

fn ticketName rank: Int64 owner: Int64 key: String -> String
  (str rank "-" owner "-" key)

fn ! ensureTicket root: String rank: Int64 owner: Int64 key: String timeoutMs: Int64 -> Int64
  (let [(path (str root "/wait/" (ticketName rank owner key)))
        (_ (dirCreate (str root "/wait")))
        (_ (dirCreate (str root "/tokens")))]
    (match (fileReadString path)
      ((ok t) (optionOr (fieldInt t ":startNs ") (monotonicNs)))
      ((err _) (let [(now (monotonicNs))
                     (span (* (if (> timeoutMs 0) timeoutMs 3600000) 1000000))
                     (_ (fileWrite path (str "(:tk :rank " rank " :ownerPid " owner " :startNs " now " :deadlineNs " (+ now span) ")\n")))]
                 now))))

; (:m :ref MACHINE-JOBSERVER :do "a ticket of a dead owner or past its deadline is pruned; the rest sort by rank, arrival, name")
fn ! liveTickets root: String -> (List (Pair Int64 String))
  (let [(now (monotonicNs))]
    (fold (fn [(acc (List (Pair Int64 String))) (f String)] -> (List (Pair Int64 String))
            (let [(path (str root "/wait/" f))
                  (t (resultOr (fileReadString path) ""))]
              (match (fieldInt t ":startNs ")
                ((none) acc)
                ((some start)
                 (let [(rank (optionOr (fieldInt t ":rank ") 3))
                       (owner (optionOr (fieldInt t ":ownerPid ") 0))
                       (deadline (optionOr (fieldInt t ":deadlineNs ") 0))]
                   (if (or (not (alive? owner)) (and (> deadline 0) (> now deadline)))
                     (let [(_ (pathRemove path))] acc)
                     (cons (pair (+ (* rank 100000000000000000) start) f) acc)))))))
          (list) (resultOr (dirList (str root "/wait")) (list))))

fn ! head? root: String mine: String start: Int64 rank: Int64 -> Bool
  (let [(myKey (+ (* rank 100000000000000000) start))
        (ahead (filter (fn [(p (Pair Int64 String))] -> Bool
                         (or (< (pairFirst p) myKey)
                             (and (= (pairFirst p) myKey) (< (pairSecond p) mine))))
                       (liveTickets root)))]
    (listEmpty? ahead))

fn ! removeTicket root: String name: String -> Unit
  (match (pathRemove (str root "/wait/" name)) ((ok _) ()) ((err _) ()))

fn backoffMs startNs: Int64 -> Int64
  (let [(waited (/ (- (monotonicNs) startNs) 1000000))
        (ms (+ 25 (/ waited 20)))]
    (if (> ms 500) 500 ms))

; (:m :ref MACHINE-JOBSERVER :do "one non-blocking attempt: state \"none\" for an opted-out class, \"ready\" with the held token indices, \"wait\" while a better or equal ticket is ahead or no token is free, \"expired\" once the wait used the whole timeout")
fn ! takeFor cls: String root: String n: Int64 owner: Int64 ost: String now: Int64 -> (List Int64)
  (if (= cls "exclusive") (takeAll root n 0 owner cls ost now (list)) (firstFree root n 0 owner cls ost now))

fn maxHoldNs dir: String -> Int64
  (* 1000000000 (optionOr (fieldInt (resultOr (fileReadString (str (rootDir dir) "/config.asn")) "") ":maxHoldS ") 14400))

fn ! want dir: String cls: String key: String timeoutMs: Int64 -> Grant
  (if (< (classRank cls) 0) (Grant :state "none" :idxs (list) :startNs 0)
    (wantWith (snapshot) dir cls key timeoutMs))

; (:m :ref MACHINE-JOBSERVER :do "an empty ps snapshot means ps itself failed (process table exhausted): proceed without a token and say so, never queue behind tokens the caller's own parent may hold")
fn ! wantWith snap: (List Row) dir: String cls: String key: String timeoutMs: Int64 -> Grant
  (let [(rank (classRank cls))]
    (if (< rank 0) (Grant :state "none" :idxs (list) :startNs 0)
      (let [(root (rootDir dir))
            (owner (procSelf))
            (usable (and (ok? (dirCreate (str root "/tokens"))) (ok? (dirCreate (str root "/wait")))))
            (names (tokenNames root))]
        (if (not usable)
          (let [(_ (eprintln "(:jobserver :note rootUnwritable :proceeding true)"))] (Grant :state "open" :idxs (list) :startNs 0))
        (if (listEmpty? snap)
          (let [(_ (eprintln "(:jobserver :note psFailed :proceeding true)"))] (Grant :state "open" :idxs (list) :startNs 0))
        (if (or (holdsAny root snap (ancestorsOf snap owner 64) names) (holdsSelf root snap owner names))
          (Grant :state "inherit" :idxs (list) :startNs 0)
          (let [(name (ticketName rank owner key))
                (start (ensureTicket root rank owner key timeoutMs))
                (now (monotonicNs))
                (n (tokenCount dir))
                (ost (startIn snap owner))]
            (cond
              ((and (> timeoutMs 0) (> (/ (- now start) 1000000) timeoutMs))
               (let [(_ (removeTicket root name))] (Grant :state "expired" :idxs (list) :startNs start)))
              ((not (head? root name start rank)) (Grant :state "wait" :idxs (list) :startNs start))
              (else
               (let [(first (takeFor cls root n owner ost now))
                     (idxs (if (and (listEmpty? first) (> (reapStale root snap names (maxHoldNs dir)) 0)) (takeFor cls root n owner ost now) first))]
                 (if (listEmpty? idxs)
                   (Grant :state "wait" :idxs (list) :startNs start)
                   (let [(_ (removeTicket root name))] (Grant :state "ready" :idxs idxs :startNs start)))))))))))))

fn ! acquire dir: String cls: String key: String timeoutMs: Int64 -> Grant
  (let [(g (want dir cls key timeoutMs))]
    (if (= g.state "wait")
      (do (sleepMs (backoffMs g.startNs)) (acquire dir cls key timeoutMs))
      g))

; (:m :ref MACHINE-JOBSERVER :do "acquire for the whole life of this process: the token file is marked :kind proc so later calls by this pid, including after an execv, find it as held")
fn ! acquireProc dir: String cls: String key: String timeoutMs: Int64 -> Grant
  (let [(g (acquire dir cls key timeoutMs))
        (root (rootDir dir))
        (_ (if (= g.state "ready") (markProc root g.idxs) 0))]
    g)

fn ! markProc root: String idxs: (List Int64) -> Int64
  (fold (fn [(n Int64) (i Int64)] -> Int64
          (let [(t (resultOr (fileReadString (tokPath root i)) ""))]
            (match (fileWrite (tokPath root i) (stringReplace t "(:tok " "(:tok :kind \"proc\" ")) ((ok _) (+ n 1)) ((err _) n))))
        0 idxs)

fn ! bind dir: String idxs: (List Int64) child: Int64 cls: String startNs: Int64 -> Int64
  (let [(root (rootDir dir))]
    (fold (fn [(n Int64) (i Int64)] -> Int64
            (let [(old (resultOr (fileReadString (tokPath root i)) ""))]
              (match (fileWrite (tokPath root i) (tokText (procSelf) child startNs cls (fieldStr old ":ownerStart \""))) ((ok _) (+ n 1)) ((err _) n))))
          0 idxs))

fn ! releaseIdxs dir: String idxs: (List Int64) -> Int64
  (dropIdxs (rootDir dir) idxs)

; (:m :ref MACHINE-JOBSERVER :do "frees every token this process bound to the finished child")
fn ! releasePid dir: String cls: String pid: Int64 -> Int64
  (if (< (classRank cls) 0) 0
    (let [(root (rootDir dir))
          (me (procSelf))]
      (fold (fn [(n Int64) (f String)] -> Int64
              (let [(path (str root "/tokens/" f))
                    (t (resultOr (fileReadString path) ""))]
                (if (and (= (fieldInt t ":childPid ") (some pid)) (= (fieldInt t ":ownerPid ") (some me)))
                  (let [(_ (slotRow root "release" (idxOfName f) me (monotonicNs)))]
                    (match (pathRemove path) ((ok _) (+ n 1)) ((err _) n)))
                  n)))
            0 (tokenNames root))))
