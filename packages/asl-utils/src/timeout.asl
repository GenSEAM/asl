(module asl-utils/timeout
  :x [main parseTimeout timeoutMsOf exitOfStatus timeoutRun! drainFd! readRest! cmdOf brokenPipe? closure startOf Run]
  :i [(asl-tools/fleet/run :a fr)])

; (:m :ref PROCSHIM :do "asl timeout SECS -- argv...: GNU timeout convention without perl or coreutils; procSpawnv has no inherit-stdio or process-group option, so the child's pipes are pumped to our stdout/stderr and our stdin into the child, and the tree is tracked by parentage with each pid pinned to its process start time, re-swept while the child runs so an orphan stays known")
(schema Run
  (:f pid Int64)
  (:f outFd Int64)
  (:f errFd Int64)
  (:f inFd Int64)
  (:f outOpen Bool)
  (:f errOpen Bool)
  (:f inOpen Bool)
  (:f srcOpen Bool)
  (:f pending String)
  (:f known (List (Pair Int64 String)))
  (:f sweptNs Int64)
  (:f deadlineNs Int64))

fn parseTimeout text: String -> (Option Int64)
  (match (stringToFloat64 text)
    ((none) (none))
    ((some f) (if (< f 0.0) (none) (float64ToInt64 (* f 1000.0)))))

fn timeoutMsOf text: String -> Int64
  (optionOr (parseTimeout text) -1)

fn exitOfStatus status: Int64 -> Int64
  (if (< status 0) (- 128 status) status)

fn brokenPipe? e: String -> Bool
  (stringContains? e ":32")

fn cmdOf args: (List String) -> (List String)
  (let [(tail (optionOr (listTail args) (list)))]
    (if (= (optionOr (listHead tail) "") "--") (optionOr (listTail tail) (list)) tail))

fn ! writeAll! fd: Int64 text: String -> Bool
  (if (stringEmpty? text)
    true
    (match (fdWrite fd text)
      ((ok n) (if (<= n 0) false (writeAll! fd (optionOr (stringSlice text n (stringLength text)) ""))))
      ((err e) (if (brokenPipe? e) false (do (sleepMs 2) (writeAll! fd text))))))

; (:m :ref PROCSHIM :do "the process table row of every live process with its start time, so a pid is only ours while it still has the start time recorded for it")
fn ! startMap! -> (List (Pair Int64 String))
  (fold (fn [(acc (List (Pair Int64 String))) (line String)] -> (List (Pair Int64 String))
          (let [(t (stringTrim line))
                (sp (optionOr (stringIndexOf t " ") -1))]
            (match (stringToInt64 (if (> sp 0) (optionOr (stringSlice t 0 sp) "") ""))
              ((some pid) (cons (pair pid (stringTrim (optionOr (stringSlice t sp (stringLength t)) ""))) acc))
              ((none) acc))))
        (list) (stringLines (resultOr (fr/shellOut "ps -A -o pid= -o lstart=" 10000) "")))

fn startOf starts: (List (Pair Int64 String)) pid: Int64 -> String
  (match (listHead (filter (fn [(r (Pair Int64 String))] -> Bool (= (pairFirst r) pid)) starts))
    ((some r) (pairSecond r))
    ((none) ""))

fn closure procs: (List fr/Proc) members: (List Int64) self: Int64 rounds: Int64 -> (List Int64)
  (let [(more (map (fn [(p fr/Proc)] -> Int64 p.pid)
                   (filter (fn [(p fr/Proc)] -> Bool (and (> p.pid 1) (and (!= p.pid self) (and (not (listContains? members p.pid)) (listContains? members p.ppid)))))
                           procs)))]
    (if (or (listEmpty? more) (<= rounds 0))
      members
      (closure procs (listAppend members more) self (- rounds 1))))

; (:m :ref PROCSHIM :do "every live process of the tree: the pinned ones whose start time still matches, plus whatever hangs off them by parentage")
fn ! sweep! known: (List (Pair Int64 String)) root: Int64 -> (List (Pair Int64 String))
  (let [(procs (fr/procSnapshot))
        (starts (startMap!))
        (alive (fn [(pid Int64)] -> Bool (and (> pid 1) (not (stringEmpty? (startOf starts pid))) (listContains? (map (fn [(p fr/Proc)] -> Int64 p.pid) procs) pid))))
        (pinned (map pairFirst (filter (fn [(r (Pair Int64 String))] -> Bool (and (alive (pairFirst r)) (= (startOf starts (pairFirst r)) (pairSecond r)))) known)))
        (seeds (if (and (empty? known) (alive root)) (list root) pinned))
        (members (closure procs seeds (procSelf) 50))]
    (map (fn [(pid Int64)] -> (Pair Int64 String) (pair pid (startOf starts pid))) members))

fn ! signalAll! tree: (List (Pair Int64 String)) sig: String -> Int64
  (fold (fn [(n Int64) (r (Pair Int64 String))] -> Int64 (match (procKill (pairFirst r) sig) ((ok _) (+ n 1)) ((err _) n))) 0 tree)

fn ! reaped? pid: Int64 -> Bool
  (match (procWaitPid pid true) ((ok (some _)) true) ((ok (none)) false) ((err _) true))

; (:m :ref PROCSHIM :do "TERM rounds share one 2 s grace; each round re-sweeps so children born after the previous signal are signalled too")
fn ! termRounds! known: (List (Pair Int64 String)) root: Int64 round: Int64 graceEndNs: Int64 -> (List (Pair Int64 String))
  (let [(live (sweep! known root))
        (_ (reaped? root))]
    (if (or (listEmpty? live) (or (>= round 3) (> (monotonicNs) graceEndNs)))
      live
      (let [(_ (signalAll! live "SIGTERM"))
            (_ (sleepMs 700))]
        (termRounds! (listAppend known live) root (+ round 1) graceEndNs))))

; (:m :ref PROCSHIM :do "STOP before KILL so a respawning member cannot outrun the round")
fn ! killRounds! known: (List (Pair Int64 String)) root: Int64 rounds: Int64 -> Int64
  (let [(live (sweep! known root))]
    (if (listEmpty? live)
      0
      (let [(_ (signalAll! live "SIGSTOP"))
            (_ (signalAll! live "SIGKILL"))
            (_ (reaped? root))
            (_ (sleepMs 50))]
        (if (<= rounds 0) (listLength live) (killRounds! (listAppend known live) root (- rounds 1))))))

fn ! waitReaped! pid: Int64 untilNs: Int64 -> Bool
  (cond ((reaped? pid) true)
        ((> (monotonicNs) untilNs) false)
        (else (do (sleepMs 20) (waitReaped! pid untilNs))))

fn ! terminate! r: Run -> Bool
  (let [(_ (if r.outOpen (fdClose r.outFd) (ok ())))
        (_ (if r.errOpen (fdClose r.errFd) (ok ())))
        (_ (if r.inOpen (fdClose r.inFd) (ok ())))
        (left (termRounds! r.known r.pid 1 (+ (monotonicNs) 2000000000)))
        (_ (killRounds! (listAppend r.known left) r.pid 5))]
    (waitReaped! r.pid (+ (monotonicNs) 2000000000)))

; (:m :ref PROCSHIM :do "one non-blocking read of fd, forwarded to dest; the pair is whether fd stays open and whether forwarding still works")
fn ! pumpFd! fd: Int64 isOpen: Bool dest: Int64 -> (Pair Bool Bool)
  (if (not isOpen)
    (pair false true)
    (match (fdRead fd 65536)
      ((ok chunk) (if (stringEmpty? chunk)
                    (do (fdClose fd) (pair false true))
                    (pair true (writeAll! dest chunk))))
      ((err _) (pair true true))))

; (:m :ref PROCSHIM :do "after the child is gone everything it wrote is already in the pipes: read until empty or EOF")
fn ! readRest! fd: Int64 isOpen: Bool acc: String -> String
  (if (not isOpen)
    acc
    (match (fdRead fd 65536)
      ((ok chunk) (if (stringEmpty? chunk) (do (fdClose fd) acc) (readRest! fd true (str acc chunk))))
      ((err _) (do (fdClose fd) acc))))

fn ! drainFd! fd: Int64 isOpen: Bool dest: Int64 -> Bool
  (writeAll! dest (readRest! fd isOpen ""))


; (:m :ref TIMEOUT-WRAPPER-ORPHAN :do "O_NONBLOCK lives on the open file description, so a sibling shim on the same stdin clears it when it exits; read fd 0 only when poll says it is readable, re-marking it non-blocking first, so a read never blocks after the child is gone")
fn ! stdinChunk! -> (Pair Bool String)
  (match (fdPoll (list (pair 0 1)) 0)
    ((ok ready) (if (listEmpty? ready)
                  (pair true "")
                  (let [(_ (fdNonBlocking 0 true))]
                    (match (fdRead 0 65536)
                      ((ok chunk) (if (stringEmpty? chunk) (pair false "") (pair true chunk)))
                      ((err _) (pair true ""))))))
    ((err _) (pair true "")))

; (:m :ref PROCSHIM :do "stdin of the shim into the child: one chunk at a time, closed at EOF, dropped if the child closes it")
fn ! feed! r: Run -> Run
  (let [(src (if (and r.srcOpen (and r.inOpen (stringEmpty? r.pending)))
               (stdinChunk!)
               (pair (and r.srcOpen r.inOpen) "")))
        (pending (str r.pending (pairSecond src)))
        (wrote (if (and r.inOpen (not (stringEmpty? pending)))
                 (match (fdWrite r.inFd pending)
                   ((ok n) (pair true (optionOr (stringSlice pending (if (< n 0) 0 n) (stringLength pending)) "")))
                   ((err e) (if (brokenPipe? e) (pair false "") (pair true pending))))
                 (pair r.inOpen pending)))
        (open (pairFirst wrote))
        (left (pairSecond wrote))
        (done (and open (and (not (pairFirst src)) (stringEmpty? left))))
        (_ (if done (fdClose r.inFd) (ok ())))]
    (Run :pid r.pid :outFd r.outFd :errFd r.errFd :inFd r.inFd :outOpen r.outOpen :errOpen r.errOpen
         :inOpen (and open (not done)) :srcOpen (and open (pairFirst src)) :pending left :known r.known :sweptNs r.sweptNs :deadlineNs r.deadlineNs))

fn ! resweep! r: Run -> Run
  (if (> (- (monotonicNs) r.sweptNs) 500000000)
    (Run :pid r.pid :outFd r.outFd :errFd r.errFd :inFd r.inFd :outOpen r.outOpen :errOpen r.errOpen
         :inOpen r.inOpen :srcOpen r.srcOpen :pending r.pending :known (sweep! r.known r.pid) :sweptNs (monotonicNs) :deadlineNs r.deadlineNs)
    r)

fn ! watch! r: Run -> Int64
  (let [(o (pumpFd! r.outFd r.outOpen 1))
        (e (pumpFd! r.errFd r.errOpen 2))
        (f (feed! (Run :pid r.pid :outFd r.outFd :errFd r.errFd :inFd r.inFd :outOpen (pairFirst o) :errOpen (pairFirst e)
                       :inOpen r.inOpen :srcOpen r.srcOpen :pending r.pending :known r.known :sweptNs r.sweptNs :deadlineNs r.deadlineNs)))]
    (if (not (and (pairSecond o) (pairSecond e)))
      (do (terminate! f) 141)
      (match (procWaitPid f.pid true)
        ((err _) 1)
        ((ok (some status))
          (let [(a (drainFd! f.outFd f.outOpen 1))
                (b (drainFd! f.errFd f.errOpen 2))
                (_ (if f.inOpen (fdClose f.inFd) (ok ())))]
            (if (and a b) (exitOfStatus status) 141)))
        ((ok (none))
          (if (and (>= f.deadlineNs 0) (> (monotonicNs) f.deadlineNs))
            (do (terminate! f) 124)
            (let [(g (resweep! f))]
              (do (sleepMs 5) (watch! g))))))))

fn ! timeoutRun! ms: Int64 argv: (List String) -> Int64
  (match (procSpawnv argv (none) (none))
    ((err e) (do (eprintln (str "asl timeout: cannot start " (optionOr (listHead argv) "") ": " e)) 127))
    ((ok p) (let [(_ (fdNonBlocking p.stdin true))
                  (_ (fdNonBlocking p.stdout true))
                  (_ (fdNonBlocking p.stderr true))
                  (_ (fdNonBlocking 0 true))
                  (code (watch! (Run :pid p.pid :outFd p.stdout :errFd p.stderr :inFd p.stdin :outOpen true :errOpen true :inOpen true :srcOpen true
                                     :pending "" :known (sweep! (list) p.pid) :sweptNs (monotonicNs)
                                     :deadlineNs (if (> ms 0) (+ (monotonicNs) (* ms 1000000)) -1))))
                  (_ (fdNonBlocking 0 false))]
              code)))

fn ! main all: (List String) -> (Result Int64 String)
  (let [(args (optionOr (listTail all) (list)))
        (ms (timeoutMsOf (optionOr (listHead args) "")))
        (cmd (cmdOf args))]
    (if (or (< ms 0) (listEmpty? cmd))
      (do (eprintln "usage: asl timeout SECS -- argv...") (ok 125))
      (ok (timeoutRun! ms cmd))))
