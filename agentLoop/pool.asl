(module asl/agentLoop/pool
  :x [PoolTask PoolSlot Refusal Admission PoolLimits defaultLimits claimOf claimsOverlap? taskOf! admit admitWith lanesOf runPool! runPoolWith! runTask! receiptStatus receiptJournal poolSummary poolExit poolMain! poolMainWith! main]
  :i [(asl/agentLoop/main :a m)
      (asl/agentLoop/core :a c)
      (asl/agentLoop/poolChannel :a ch)
      (asl-tools/fleet/run :a fr)
      (asl-json/json :a j)])

; (:m :ref LEON-POOL-20261026 :do "stage 1 needs no runtime change: a single-threaded reactor in this process forks one child per running task through foreign fork, so lanes run truly at once while each task keeps its own journal under its root and its own receipt; tasks sharing a git root share a lane and run in order there, because the loop's git index, commit and hand-back are per root")
(schema PoolTask
  (:f idx Int64)
  (:f form String)
  (:f root String)
  (:f owns (List String))
  (:f claims (List String))
  (:f wallMs Int64)
  (:f waitsFor (List Int64))
  (:f chan String))

(schema PoolSlot
  (:f idx Int64)
  (:f lane Int64)
  (:f root String)
  (:f status String)
  (:f exit Int64)
  (:f startNs Int64)
  (:f endNs Int64)
  (:f end String)
  (:f waitedFor (List Int64))
  (:f receipt String))

(schema Refusal
  (:f idx Int64)
  (:f error String)
  (:f with (List Int64))
  (:f message String))

(schema Admission
  (:f admitted (List PoolTask))
  (:f refused (List Refusal)))

fn normParts parts: (List String) acc: (List String) -> (List String)
  (match (listHead parts)
    ((none) (listReverse acc))
    ((some p)
      (cond
        ((or (stringEmpty? p) (= p ".")) (normParts (listDrop parts 1) acc))
        ((= p "..") (normParts (listDrop parts 1) (listDrop acc 1)))
        (else (normParts (listDrop parts 1) (cons p acc))))))

fn normPath p: String -> String
  (str "/" (stringJoin (normParts (stringSplit p "/") (list)) "/"))

fn globAt s: String i: Int64 -> Int64
  (cond
    ((>= i (stringLength s)) i)
    ((listContains? (list "*" "?" "[" "{") (c/sliceOf s i (+ i 1))) i)
    (else (globAt s (+ i 1))))

fn lastSlash s: String i: Int64 -> Int64
  (cond
    ((< i 0) 0)
    ((= (c/sliceOf s i (+ i 1)) "/") i)
    (else (lastSlash s (- i 1))))

; (:m :ref LEON-POOL-20261026 :do "a glob claims the directory before its first wildcard, so a pattern can only widen a claim, never let two writers share a file")
fn claimOf root: String own: String -> String
  (let [(full (if (stringStartsWith? own "/") own (str root "/" own)))
        (g (globAt full 0))]
    (normPath (if (= g (stringLength full)) full (c/sliceOf full 0 (lastSlash full g)))))

fn under? a: String b: String -> Bool
  (or (= a b) (or (= b "/") (stringStartsWith? a (str b "/"))))

fn claimsOverlap? xs: (List String) ys: (List String) -> Bool
  (listAny? (fn [(x String)] -> Bool (listAny? (fn [(y String)] -> Bool (or (under? x y) (under? y x))) ys)) xs)

fn strings v: (Option j/Json) -> (List String)
  (match v
    ((some (j/jarr xs)) (map (fn [(x j/Json)] -> String (match x ((j/jstr s) s) (_ ""))) xs))
    (_ (list)))

fn ! resolved! path: String -> String
  (normPath (resultOr (realPath path) path))

fn intOf ps: (List (Pair String j/Json)) key: String fallback: Int64 -> Int64
  (match (m/paramGet ps key) ((some (j/jint n)) n) (_ fallback))

; (:m :ref LEON-POOL-BOUND :do "the same wall a single Leon run gets: :wallBudget when given, else :timeout plus :queueTimeout (600 + 1200 by default), at most a day")
fn wallSeconds ps: (List (Pair String j/Json)) -> Int64
  (let [(w (intOf ps "wallBudget" 0))]
    (if (> w 0) w (min 86400 (+ (intOf ps "timeout" 600) (intOf ps "queueTimeout" 1200)))))

fn ! taskOf! idx: Int64 form: String rootDir: String -> PoolTask
  (let [(inv (m/parseInvocation form rootDir))
        (raw (match (m/paramGet inv.params "root") ((some (j/jstr s)) s) (_ "")))
        (root (resolved! (cond ((stringEmpty? raw) rootDir) ((stringStartsWith? raw "/") raw) (else (str rootDir "/" raw)))))
        (owns (filter (fn [(o String)] -> Bool (not (stringEmpty? o))) (strings (m/paramGet inv.params "owns"))))]
    (PoolTask :idx idx :form form :root root :owns owns
              :claims (if (listEmpty? owns) (list root) (map (fn [(o String)] -> String (claimOf root o)) owns))
              :wallMs (* 1000 (wallSeconds inv.params)) :waitsFor (list) :chan ""))

fn partners t: PoolTask ts: (List PoolTask) -> (List Int64)
  (map (fn [(o PoolTask)] -> Int64 o.idx)
       (filter (fn [(o PoolTask)] -> Bool (and (!= o.idx t.idx) (claimsOverlap? t.claims o.claims))) ts))

fn withWaits t: PoolTask waits: (List Int64) -> PoolTask
  (PoolTask :idx t.idx :form t.form :root t.root :owns t.owns :claims t.claims :wallMs t.wallMs :waitsFor waits :chan t.chan)

; (:m :ref LEON-POOL-WIRE :do "wait: every task is admitted and one whose claims overlap an earlier task's waits for it (lanesOf puts both in one lane, which runs in argv order); refuse: both members of an overlapping pair are refused and nothing of either runs, the stage 1 rule")
fn admitWith ts: (List PoolTask) mode: String -> Admission
  (if (= mode "refuse")
    (Admission
      :admitted (filter (fn [(t PoolTask)] -> Bool (listEmpty? (partners t ts))) ts)
      :refused (map (fn [(t PoolTask)] -> Refusal
                      (Refusal :idx t.idx :error "ERR_OWNS_OVERLAP" :with (partners t ts)
                               :message (str "claims " (c/joinSep t.claims " ") " overlap another task's :owns")))
                    (filter (fn [(t PoolTask)] -> Bool (not (listEmpty? (partners t ts)))) ts)))
    (Admission
      :admitted (map (fn [(t PoolTask)] -> PoolTask (withWaits t (filter (fn [(i Int64)] -> Bool (< i t.idx)) (partners t ts)))) ts)
      :refused (list)))

fn admit ts: (List PoolTask) -> Admission
  (admitWith ts "refuse")

fn sameRepo? a: PoolTask b: PoolTask -> Bool
  (or (under? a.root b.root) (under? b.root a.root))

fn byIdx ts: (List PoolTask) -> (List PoolTask)
  (listSortBy (fn [(t PoolTask)] -> Int64 t.idx) ts)

fn addLane lanes: (List (List PoolTask)) t: PoolTask -> (List (List PoolTask))
  (let [(touch (fn [(lane (List PoolTask))] -> Bool (listAny? (fn [(o PoolTask)] -> Bool (or (sameRepo? t o) (claimsOverlap? t.claims o.claims))) lane)))
        (joined (fold (fn [(acc (List PoolTask)) (lane (List PoolTask))] -> (List PoolTask) (listAppend acc lane))
                      (list t) (filter touch lanes)))]
    (listAppend (filter (fn [(lane (List PoolTask))] -> Bool (not (touch lane))) lanes) (list (byIdx joined))))

fn lanesOf ts: (List PoolTask) -> (List (List PoolTask))
  (listSortBy (fn [(lane (List PoolTask))] -> Int64 (match (listHead lane) ((some t) t.idx) ((none) 0)))
              (fold addLane (list) ts))

fn wordAfter s: String key: String -> String
  (match (stringIndexOf s key)
    ((none) "")
    ((some i) (let [(rest (c/sliceOf s (+ i (stringLength key)) (stringLength s)))
                    (end (optionOr (stringIndexOf rest " ") (stringLength rest)))]
                (stringReplace (c/sliceOf rest 0 end) ")" ""))))

fn receiptStatus receipt: String -> String
  (let [(w (wordAfter receipt ":status :"))] (if (stringEmpty? w) "failed" w))

fn receiptJournal receipt: String -> String
  (match (stringIndexOf receipt ":journal \"")
    ((none) "")
    ((some i) (let [(rest (c/sliceOf receipt (+ i 10) (stringLength receipt)))]
                (c/sliceOf rest 0 (optionOr (stringIndexOf rest "\"") 0)))))

(schema PoolLimits
  (:f slots Int64)
  (:f laneMs Int64)
  (:f graceMs Int64)
  (:f maxDesc Int64)
  (:f onOverlap String))

(schema Live
  (:f task PoolTask)
  (:f fork fr/Forked)
  (:f startNs Int64))

(schema Lane
  (:f id Int64)
  (:f pending (List PoolTask))
  (:f live (Option Live))
  (:f deadlineNs Int64))

(schema Tick
  (:f lanes (List Lane))
  (:f slots (List PoolSlot))
  (:f active Int64)
  (:f asks (Map Int64 Int64)))

fn defaultLimits -> PoolLimits
  (PoolLimits :slots 0 :laneMs 0 :graceMs 30000 :maxDesc 64 :onOverlap "wait")

fn outPath dir: String t: PoolTask ext: String -> String
  (str dir "/" (stringFromInt64 t.idx) "." ext)

; (:m :ref LEON-POOL-TRAP :do "the child is the trap boundary: fleet/run forkLimited! runs one task in its own process group with stdout and stderr in the task's log, under the fleet lease, timeout and descendant limit, and the task leaves its receipt in a file, so a trap ends only that child (no receipt file, nonzero exit)")
fn ! startTask! dir: String repoRoot: String t: PoolTask runner: (fn [String PoolTask] -> m/MainResult) lim: PoolLimits -> (Result fr/Forked String)
  (fr/forkLimited! (outPath dir t "log") (fr/Limits :timeoutMs (+ t.wallMs lim.graceMs) :maxDesc lim.maxDesc :class "" :jsDir "")
    (fn [] -> Int64
      (let [(res (runner repoRoot (PoolTask :idx t.idx :form t.form :root t.root :owns t.owns :claims t.claims :wallMs t.wallMs :waitsFor t.waitsFor :chan dir)))]
        (do (fileWrite (outPath dir t "receipt") res.stdout)
            (fileWrite (outPath dir t "exit") (stringFromInt64 res.exitCode))
            0))))

; (:m :ref LEON-POOL-TRAP :do "the trap's own ERR_ line, not the last one: a runtime that prints a summary after the trap (the test runner does) would otherwise hide it")
fn ! trapLine path: String -> String
  (let [(lines (filter (fn [(l String)] -> Bool (not (stringEmpty? (stringTrim l)))) (stringLines (resultOr (fileReadString path) ""))))]
    (match (listHead (filter (fn [(l String)] -> Bool (stringContains? l "ERR_")) lines))
      ((some l) l)
      ((none) (match (listHead (listReverse lines)) ((some l) l) ((none) "")))))

fn slotOf lane: Int64 t: PoolTask status: String exit: Int64 t0: Int64 t1: Int64 end: String receipt: String -> PoolSlot
  (PoolSlot :idx t.idx :lane lane :root t.root :status status :exit exit :startNs t0 :endNs t1 :end end :waitedFor t.waitsFor :receipt receipt)

fn ! reaped! dir: String lane: Int64 l: Live code: Int64 -> PoolSlot
  (let [(now (monotonicNs))]
    (match (fileReadString (outPath dir l.task "receipt"))
      ((ok receipt)
        (slotOf lane l.task (receiptStatus receipt)
                (optionOr (stringToInt64 (stringTrim (resultOr (fileReadString (outPath dir l.task "exit")) ""))) code)
                l.startNs now "returned" receipt))
      ((err _)
        (slotOf lane l.task "failed" (if (= code 0) 1 code) l.startNs now "trap"
                (str "(:agentReceipt :status :failed :error ERR_TRAP :exit " (stringFromInt64 code)
                     " :message \"" (c/escapeAsn (trapLine (outPath dir l.task "log"))) "\")")))))

fn ! ended! lane: Int64 l: Live e: fr/ForkEnd -> PoolSlot
  (if (= e.verdict "runaway")
    (slotOf lane l.task "failed" -1 l.startNs (monotonicNs) "runaway"
            (str "(:agentReceipt :status :failed :error ERR_POOL_RUNAWAY :note \"" (c/escapeAsn e.note) "\")"))
    (slotOf lane l.task "timeout" -1 l.startNs (monotonicNs) (if (= e.verdict "timeout") "task" "lane")
            (str "(:agentReceipt :status :timeout :error ERR_POOL_DEADLINE :deadline :" (if (= e.verdict "timeout") "task" "lane") ")")))

fn notStarted lane: Int64 now: Int64 ts: (List PoolTask) -> (List PoolSlot)
  (map (fn [(t PoolTask)] -> PoolSlot
         (slotOf lane t "timeout" -1 now now "notStarted" "(:agentReceipt :status :timeout :error ERR_POOL_DEADLINE :deadline :lane :started false)"))
       ts)

fn idle lane: Lane -> Lane
  (Lane :id lane.id :pending lane.pending :live none :deadlineNs lane.deadlineNs)

; (:m :ref LEON-POOL-BOUND :do "a live task ends at the earlier of its own deadline (its wallBudget plus grace) and its lane's; once the lane's deadline passes its unstarted tasks are not started, so a hung lane ends with :timeout slots while the others keep running")
fn ! pollLane! dir: String now: Int64 lane: Lane -> (Pair Lane (List PoolSlot))
  (match lane.live
    ((none) (pair lane (list)))
    ((some l)
      (if (>= now lane.deadlineNs)
        (pair (idle lane) (list (ended! lane.id l (fr/forkKill! l.fork "lane"))))
        (let [(step (fr/forkAdvance! l.fork))
              (l2 (Live :task l.task :fork step.fork :startNs l.startNs))]
          (match step.end
            ((none) (pair (Lane :id lane.id :pending lane.pending :live (some l2) :deadlineNs lane.deadlineNs) (list)))
            ((some e) (pair (idle lane) (list (if (stringEmpty? e.verdict) (reaped! dir lane.id l2 e.exit) (ended! lane.id l2 e))))))))))

fn ! fillLane! dir: String repoRoot: String runner: (fn [String PoolTask] -> m/MainResult) lim: PoolLimits cap: Int64 now: Int64 acc: Tick lane: Lane -> Tick
  (match (listHead lane.pending)
    ((none) (Tick :lanes (listAppend acc.lanes (list lane)) :slots acc.slots :active acc.active :asks acc.asks))
    ((some t)
      (cond
        ((some? lane.live) (Tick :lanes (listAppend acc.lanes (list lane)) :slots acc.slots :active acc.active :asks acc.asks))
        ((>= now lane.deadlineNs)
          (Tick :lanes (listAppend acc.lanes (list (Lane :id lane.id :pending (list) :live none :deadlineNs lane.deadlineNs)))
                :slots (listAppend acc.slots (notStarted lane.id now lane.pending)) :active acc.active :asks acc.asks))
        ((>= acc.active cap) (Tick :lanes (listAppend acc.lanes (list lane)) :slots acc.slots :active acc.active :asks acc.asks))
        (else
          (let [(rest (listDrop lane.pending 1))
                (t0 (monotonicNs))]
            (match (startTask! dir repoRoot t runner lim)
              ((ok f)
                (Tick :lanes (listAppend acc.lanes (list (Lane :id lane.id :pending rest :deadlineNs lane.deadlineNs
                                                               :live (some (Live :task t :fork f :startNs t0)))))
                      :slots acc.slots :active (+ acc.active 1) :asks acc.asks))
              ((err e)
                (Tick :lanes (listAppend acc.lanes (list (Lane :id lane.id :pending rest :live none :deadlineNs lane.deadlineNs)))
                      :slots (listAppend acc.slots (list (slotOf lane.id t "failed" -1 now now "notStarted"
                                                                 (str "(:agentReceipt :status :failed :error ERR_POOL_FORK :message \"" (c/escapeAsn e) "\")"))))
                      :active acc.active :asks acc.asks))))))))

fn liveCount lanes: (List Lane) -> Int64
  (listLength (filter (fn [(l Lane)] -> Bool (some? l.live)) lanes))

fn finished? lanes: (List Lane) -> Bool
  (listAll? (fn [(l Lane)] -> Bool (and (none? l.live) (listEmpty? l.pending))) lanes)

fn livePairs lanes: (List Lane) -> (List (Pair Int64 Int64))
  (fold (fn [(acc (List (Pair Int64 Int64))) (l Lane)] -> (List (Pair Int64 Int64)) (match l.live ((some x) (cons (pair x.task.idx l.id) acc)) ((none) acc))) (list) lanes)

fn queuedPairs lanes: (List Lane) -> (List (Pair Int64 Int64))
  (fold (fn [(acc (List (Pair Int64 Int64))) (l Lane)] -> (List (Pair Int64 Int64)) (listAppend acc (map (fn [(t PoolTask)] -> (Pair Int64 Int64) (pair t.idx l.id)) l.pending))) (list) lanes)

fn ! reactor! dir: String repoRoot: String runner: (fn [String PoolTask] -> m/MainResult) lim: PoolLimits cap: Int64 lanes: (List Lane) done: (List PoolSlot) asks: (Map Int64 Int64) -> (List PoolSlot)
  (let [(now (monotonicNs))
        (polled (map (fn [(l Lane)] -> (Pair Lane (List PoolSlot)) (pollLane! dir now l)) lanes))
        (after (map pairFirst polled))
        (reaped (fold (fn [(acc (List PoolSlot)) (p (Pair Lane (List PoolSlot)))] -> (List PoolSlot) (listAppend acc (pairSecond p))) done polled))
        (tick (fold (fn [(acc Tick) (l Lane)] -> Tick (fillLane! dir repoRoot runner lim cap now acc l))
                    (Tick :lanes (list) :slots reaped :active (liveCount after) :asks asks) after))
        (routed (ch/route! dir (livePairs tick.lanes) (queuedPairs tick.lanes) tick.asks))]
    (if (finished? tick.lanes)
      tick.slots
      (do (sleepMs 20) (reactor! dir repoRoot runner lim cap tick.lanes tick.slots routed))))

fn laneBudgetMs ts: (List PoolTask) graceMs: Int64 -> Int64
  (fold (fn [(a Int64) (t PoolTask)] -> Int64 (+ a (+ t.wallMs graceMs))) 0 ts)

; (:m :ref LEON-POOL-ASK-OP :do "the task's own form gains :poolChan and :poolIdx, so its Leon run can send (:ask) ops and serve the asks of its peers")
fn pooledForm t: PoolTask -> String
  (let [(f (stringTrim t.form))]
    (if (stringEndsWith? f ")")
      (str (c/sliceOf f 0 (- (stringLength f) 1)) " :poolChan \"" t.chan "\" :poolIdx " (stringFromInt64 t.idx) ")")
      f))

fn ! runTask! repoRoot: String t: PoolTask -> m/MainResult
  (m/mainWithRoots (list (pooledForm t)) repoRoot t.root)

fn ! runPoolWith! repoRoot: String lanes: (List (List PoolTask)) lim: PoolLimits runner: (fn [String PoolTask] -> m/MainResult) -> (List PoolSlot)
  (let [(dir (str (optionOr (envGet "TMPDIR") "/tmp") "/leonPool-" (stringFromInt64 (procSelf)) "-" (stringFromInt64 (nowNs))))
        (made (and (ok? (dirCreate dir))
                   (ch/openChannel! dir (fold (fn [(acc (List Int64)) (l (List PoolTask))] -> (List Int64) (listAppend acc (map (fn [(t PoolTask)] -> Int64 t.idx) l))) (list) lanes))))
        (now (monotonicNs))
        (state (map (fn [(p (Pair Int64 (List PoolTask)))] -> Lane
                      (Lane :id (pairFirst p) :pending (pairSecond p) :live none
                            :deadlineNs (+ now (* 1000000 (if (> lim.laneMs 0) lim.laneMs (laneBudgetMs (pairSecond p) lim.graceMs))))))
                    (zip (range 0 (listLength lanes)) lanes)))
        (done (if made
                (reactor! dir repoRoot runner lim (if (> lim.slots 0) lim.slots (listLength lanes)) state (list) (mapEmpty))
                (fold (fn [(acc (List PoolSlot)) (l Lane)] -> (List PoolSlot) (listAppend acc (notStarted l.id now l.pending))) (list) state)))
        (removed (pathRemove dir))]
    (listSortBy (fn [(s PoolSlot)] -> Int64 s.idx) done))

fn ! runPool! repoRoot: String lanes: (List (List PoolTask)) lim: PoolLimits -> (List PoolSlot)
  (runPoolWith! repoRoot lanes lim runTask!)

fn quoted s: String -> String
  (str "\"" (c/escapeAsn s) "\"")

fn slotLine s: PoolSlot -> String
  (str "(:slot :idx " (stringFromInt64 s.idx) " :lane " (stringFromInt64 s.lane) " :root " (quoted s.root)
       " :status :" s.status
       (cond ((= s.end "trap") " :trap true") ((= s.end "runaway") " :verdict :runaway") ((= s.status "timeout") (str " :deadline :" (if (= s.end "task") "task" "lane") (if (= s.end "notStarted") " :started false" ""))) (else ""))
       (if (listEmpty? s.waitedFor) "" (str " :waitedFor (" (c/joinSep (map stringFromInt64 s.waitedFor) " ") ")"))
       " :exit " (stringFromInt64 s.exit)
       " :startNs " (stringFromInt64 s.startNs) " :endNs " (stringFromInt64 s.endNs)
       " :ms " (stringFromInt64 (/ (- s.endNs s.startNs) 1000000))
       " :journal " (quoted (receiptJournal s.receipt)) " :receipt " (quoted s.receipt) ")")

fn refusalLine r: Refusal -> String
  (str "(:refused :idx " (stringFromInt64 r.idx) " :error " r.error
       " :with (" (c/joinSep (map stringFromInt64 r.with) " ") ") :message " (quoted r.message) ")")

fn countStatus slots: (List PoolSlot) ok: Bool -> Int64
  (listLength (filter (fn [(s PoolSlot)] -> Bool (= (= s.status "ok") ok)) slots))

fn poolSummary tasks: Int64 lanes: Int64 slots: (List PoolSlot) refused: (List Refusal) wallNs: Int64 -> String
  (str "(:poolReceipt :tasks " (stringFromInt64 tasks) " :admitted " (stringFromInt64 (listLength slots))
       " :lanes " (stringFromInt64 lanes) " :ok " (stringFromInt64 (countStatus slots true))
       " :failed " (stringFromInt64 (countStatus slots false)) " :refused " (stringFromInt64 (listLength refused))
       " :wallMs " (stringFromInt64 (/ wallNs 1000000))
       " :sumMs " (stringFromInt64 (/ (fold (fn [(a Int64) (s PoolSlot)] -> Int64 (+ a (- s.endNs s.startNs))) 0 slots) 1000000))
       " :slots (" (stringJoin (map slotLine slots) " ") ")"
       " :refusals (" (stringJoin (map refusalLine refused) " ") "))")

fn poolExit slots: (List PoolSlot) refused: (List Refusal) -> Int64
  (cond
    ((not (listEmpty? refused)) 2)
    ((> (countStatus slots false) 0) 1)
    (else 0))

fn ! poolMain! forms: (List String) repoRoot: String rootDir: String slots: Int64 -> m/MainResult
  (poolMainWith! forms repoRoot rootDir (PoolLimits :slots slots :laneMs 0 :graceMs (defaultLimits).graceMs :maxDesc (defaultLimits).maxDesc :onOverlap (defaultLimits).onOverlap) runTask!)

fn ! poolMainWith! forms: (List String) repoRoot: String rootDir: String lim: PoolLimits runner: (fn [String PoolTask] -> m/MainResult) -> m/MainResult
  (let [(t0 (monotonicNs))
        (tasks (map (fn [(p (Pair Int64 String))] -> PoolTask (taskOf! (pairFirst p) (pairSecond p) rootDir))
                    (zip (range 0 (listLength forms)) forms)))
        (adm (admitWith tasks lim.onOverlap))
        (lanes (lanesOf adm.admitted))
        (done (runPoolWith! repoRoot lanes lim runner))
        (t1 (monotonicNs))]
    (m/MainResult :stdout (poolSummary (listLength tasks) (listLength lanes) done adm.refused (- t1 t0))
                  :exitCode (poolExit done adm.refused)))

; (:m :ref LEON-POOL-20261026 :do "argv is one (:agent ...) form per task; ASL_POOL_SLOTS is not read (rule no-env-config): a lane count above the processor count is the caller's choice")
fn ! main argv: (List String) -> Int64
  (let [(repoRoot (resultOr (realPath ".") "."))
        (res (if (listEmpty? argv)
               (m/MainResult :stdout "(:poolReceipt :status :rejected :error ERR_MISSING_ARG :message \"no task forms\")" :exitCode 2)
               (poolMain! argv repoRoot repoRoot 0)))]
    (do (println res.stdout) res.exitCode))
