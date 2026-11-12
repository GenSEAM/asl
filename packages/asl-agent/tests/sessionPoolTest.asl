(module aslAgent/tests/sessionPoolTest
  :x [runTests]
  :i [(aslAgent/sessionPool :a sp) (asl-tools/fleet/run :a fr)])

; (:m :ref POOL-SERVE :do "a scripted hub on a unix socket in this process answers every request after delayMs. 8 sessions of 5 turns over 8 slots finish in under twice the wall of one such session alone (turns overlap, none blocks the reactor); 64 sessions over 8 slots with memCap 16 all finish while waiting sessions spill to files (peak in memory <= memCap) and the spill files are gone at the end; pickNext prefers the oldest warm session and falls back to the oldest cold one; an unreachable hub gives up after three tries")
(schema Stub
  (:f fd Int64)
  (:f input String)
  (:f replyAt Int64))

(schema Hub
  (:f listener Int64)
  (:f stubs (List Stub))
  (:f seen Int64))

fn ! nowMs! -> Int64
  (/ (monotonicNs) 1000000)

fn ready? ready: (List (Pair Int64 Int64)) fd: Int64 -> Bool
  (listAny? (fn [(r (Pair Int64 Int64))] -> Bool (= (pairFirst r) fd)) ready)

fn contentLength head: String -> Int64
  (fold (fn [(acc Int64) (line String)] -> Int64
          (if (stringStartsWith? (stringLower line) "content-length:")
            (optionOr (stringToInt64 (stringTrim (optionOr (stringSlice line 15 (stringLength line)) ""))) acc) acc))
    0 (stringSplit head "\r\n"))

fn complete? raw: String -> Bool
  (match (stringIndexOf raw "\r\n\r\n")
    ((none) false)
    ((some end) (>= (- (stringLength raw) (+ end 4)) (contentLength (optionOr (stringSlice raw 0 end) "")))))

fn okReply -> String
  (let [(body "ok")]
    (str "HTTP/1.1 200 OK\r\nContent-Length: " (stringFromInt64 (stringLength body)) "\r\nConnection: close\r\n\r\n" body))

fn withStubs h: Hub stubs: (List Stub) -> Hub
  (with h :stubs stubs)

fn withSeen h: Hub seen: Int64 -> Hub
  (with h :seen seen)

fn ! stepStub! h: Hub s: Stub ready: (List (Pair Int64 Int64)) delayMs: Int64 -> Hub
  (cond
    ((> s.replyAt 0)
      (if (>= (nowMs!) s.replyAt)
        (do (fdWrite s.fd (okReply)) (fdClose s.fd) (withSeen h (+ h.seen 1)))
        (withStubs h (listAppend h.stubs (list s)))))
    ((not (ready? ready s.fd)) (withStubs h (listAppend h.stubs (list s))))
    (else
      (match (fdRead s.fd 65536)
        ((err _) (do (fdClose s.fd) h))
        ((ok chunk)
          (if (stringEmpty? chunk) (do (fdClose s.fd) h)
            (let [(input (str s.input chunk))]
              (withStubs h (listAppend h.stubs (list (Stub :fd s.fd :input input :replyAt (if (complete? input) (+ (nowMs!) delayMs) 0)))))))))))

fn ! stepHub! h: Hub ready: (List (Pair Int64 Int64)) delayMs: Int64 -> Hub
  (let [(accepted (if (ready? ready h.listener)
                    (match (sockAccept h.listener)
                      ((ok fd) (withStubs h (listAppend h.stubs (list (Stub :fd fd :input "" :replyAt 0)))))
                      ((err _) h))
                    h))]
    (fold (fn [(acc Hub) (s Stub)] -> Hub (stepStub! acc s ready delayMs)) (withStubs accepted (list)) accepted.stubs))

fn hubWatch h: Hub -> (List (Pair Int64 Int64))
  (cons (pair h.listener 1) (map (fn [(s Stub)] -> (Pair Int64 Int64) (pair s.fd 1)) h.stubs))

; (:m :ref POOL-SERVE :do "scripted turn function: state left:K counts the turns still to send, the reply content is ignored")
fn doneWith r: String -> sp/Turn
  (sp/Turn :state "end" :request none :exec none :result (some r))

fn shellExec script: String timeoutS: Int64 -> sp/Exec
  (sp/Exec :argv (list "/bin/sh" "-c" script) :cwd "/tmp" :env (list (str "PATH=" (optionOr (envGet "PATH") "/usr/bin:/bin"))) :timeoutS timeoutS :maxDesc 8)

fn turnFn state: String reply: String -> sp/Turn
  (cond
    ((= state "gate") (sp/Turn :state "gated" :request none :exec (some (shellExec "sleep 1; echo gate" 20)) :result none))
    ((= state "gated") (doneWith reply))
    ((= state "kill") (sp/Turn :state "killed" :request none :exec (some (shellExec "sleep 30" 1)) :result none))
    ((= state "killed") (doneWith reply))
    ((= state "fork") (sp/Turn :state "forked" :request none :exec (some (shellExec "for i in 1 2 3 4 5 6 7 8 9 10 11 12; do sleep 20 & done; wait" 20)) :result none))
    ((= state "forked") (doneWith reply))
    ((= state "nobin") (sp/Turn :state "nobinDone" :request none :exec (some (sp/Exec :argv (list "/nonexistent/binary") :cwd "/tmp" :env (list) :timeoutS 5 :maxDesc 0)) :result none))
    ((= state "nobinDone") (doneWith reply))
    (else
      (let [(left (optionOr (stringToInt64 (optionOr (stringSlice state 5 (stringLength state)) "0")) 0))]
        (if (<= left 0) (doneWith "(:ok)")
          (sp/Turn :state (str "left:" (stringFromInt64 (- left 1))) :request (some "{\"m\":1}") :exec none :result none)))))

fn ! submitAll! p: sp/Pool n: Int64 turns: Int64 -> sp/Pool
  (fold (fn [(acc sp/Pool) (i Int64)] -> sp/Pool (sp/poolSubmit! acc (str "s" (stringFromInt64 i)) (str "left:" (stringFromInt64 turns)) (nowMs!))) p (range 0 n))

fn ! pump! p: sp/Pool h: Hub delayMs: Int64 deadline: Int64 -> (Pair sp/Pool Hub)
  (if (or (sp/poolIdle? p) (>= (nowMs!) deadline)) (pair p h)
    (match (fdPoll (listAppend (hubWatch h) (sp/poolWatch p)) 10)
      ((err _) (pump! p h delayMs deadline))
      ((ok ready) (pump! (sp/poolStep! p ready turnFn (nowMs!)) (stepHub! h ready delayMs) delayMs deadline))))

fn ! drivePool! temp: String name: String n: Int64 turns: Int64 slots: Int64 memCap: Int64 -> (Pair sp/Pool Int64)
  (let [(sock (str temp "/" name ".sock"))
        (spill (str temp "/" name "-spill"))
        (made (dirCreate spill))
        (listener (resultOr (unixListen sock) -1))
        (h0 (Hub :listener listener :stubs (list) :seen 0))
        (p0 (submitAll! (sp/newPool sock slots memCap 60000 spill) n turns))
        (t0 (nowMs!))
        (out (pump! p0 h0 60 (+ t0 20000)))
        (wall (- (nowMs!) t0))
        (closed (do (map (fn [(s Stub)] -> Bool (do (fdClose s.fd) true)) (pairSecond out).stubs) (fdClose listener) (pathRemove sock) true))]
    (pair (pairFirst out) wall))

fn ! stepUntilIdle! p: sp/Pool deadline: Int64 -> sp/Pool
  (if (or (sp/poolIdle? p) (>= (nowMs!) deadline)) p
    (do (sleepMs 20) (stepUntilIdle! (sp/poolStep! p (list) turnFn (nowMs!)) deadline)))

fn doneOf p: sp/Pool id: String -> (Option String)
  (optionMap (fn [(d (Pair String String))] -> String (pairSecond d)) (listFind (fn [(d (Pair String String))] -> Bool (= (pairFirst d) id)) (sp/poolDone p)))

fn ! pumpUntil! p: sp/Pool h: Hub delayMs: Int64 stop: (fn [sp/Pool] -> Bool) deadline: Int64 -> (Pair sp/Pool Hub)
  (if (or (stop p) (>= (nowMs!) deadline)) (pair p h)
    (match (fdPoll (listAppend (hubWatch h) (sp/poolWatch p)) 10)
      ((err _) (pumpUntil! p h delayMs stop deadline))
      ((ok ready) (pumpUntil! (sp/poolStep! p ready turnFn (nowMs!)) (stepHub! h ready delayMs) delayMs stop deadline))))

; (:m :ref SE4-ASYNC-EXEC :do "a session in a 1 s local process (gate) and one in a killed 30 s process (timeout 1 s) and one with a missing binary share the pool with a hub session of 5 turns: the hub session finishes in under 600 ms while the gate is still running (SESSIONPOOL-LOWS-20261112: 900 let a blocking guardStart! pass), the gate then returns exit 0 with its output, the timeout kills the long one, the missing binary is an error reply")
fn withDoneRows p: sp/Pool rows: (List (Pair String String)) -> sp/Pool
  (with p :done rows)

fn ! execRun! temp: String -> (Pair sp/Pool Int64)
  (let [(sock (str temp "/exec.sock"))
        (spill (str temp "/exec-spill"))
        (made (dirCreate spill))
        (listener (resultOr (unixListen sock) -1))
        (h0 (Hub :listener listener :stubs (list) :seen 0))
        (p0 (fold (fn [(acc sp/Pool) (pair0 (Pair String String))] -> sp/Pool (sp/poolSubmit! acc (pairFirst pair0) (pairSecond pair0) (nowMs!)))
              (sp/newPool sock 2 8 60000 spill)
              (list (pair "x" "gate") (pair "k" "kill") (pair "n" "nobin") (pair "h" "left:5"))))
        (t0 (nowMs!))
        (first (pumpUntil! p0 h0 60 (fn [(p sp/Pool)] -> Bool (some? (doneOf p "h"))) (+ t0 20000)))
        (hubWall (- (nowMs!) t0))
        (gateAtThatTime (doneOf (pairFirst first) "x"))
        (rest (pumpUntil! (pairFirst first) (pairSecond first) 60 (fn [(p sp/Pool)] -> Bool (sp/poolIdle? p)) (+ (nowMs!) 20000)))
        (closed (do (map (fn [(s Stub)] -> Bool (do (fdClose s.fd) true)) (pairSecond rest).stubs) (fdClose listener) (pathRemove sock) true))]
    (pair (withDoneRows (pairFirst rest) (listAppend (sp/poolDone (pairFirst rest)) (list (pair "_hubWallMs" (stringFromInt64 hubWall)) (pair "_gateEarly" (match gateAtThatTime ((some _) "no") ((none) "yes")))))) hubWall))

; (:m :ref SESSIONPOOL-HUB-STALL :do "a guardBegin! run writes its lease at once with no owner start time and its first polled snapshot rewrites it with one; a ps snapshot past its 10 s bound is killed and judged as no check, so recorded escapee groups survive")
fn ! pollToEnd! g: fr/Guarded deadline: Int64 -> Bool
  (let [(s (fr/guardPoll! g))]
    (match s.out
      ((some _) true)
      ((none) (if (>= (nowMs!) deadline) (do (fr/stopGuard! s.guard) false) (do (sleepMs 20) (pollToEnd! s.guard deadline))))))

fn ! pollFresh! g: fr/Guarded deadline: Int64 -> fr/Guarded
  (if (or (not g.fresh) (>= (nowMs!) deadline)) g
    (do (sleepMs 20) (pollFresh! (fr/guardPoll! g).guard deadline)))

fn ! leaseProbe! -> (Pair String String)
  (match (fr/guardBegin! (list "/bin/sh" "-c" "sleep 1") "/tmp" (list) (fr/limits 20 0))
    ((err o) (pair (str "begin failed " o.stderr) ""))
    ((ok g) (let [(path (fr/leasePath g.run.pid))
                  (before (resultOr (fileReadString path) ""))
                  (g2 (pollFresh! g (+ (nowMs!) 5000)))
                  (after (resultOr (fileReadString path) ""))
                  (_ (pollToEnd! g2 (+ (nowMs!) 5000)))]
              (pair before after))))

fn ! staleSnapProbe! -> Bool
  (match (fr/guardBegin! (list "/bin/sh" "-c" "sleep 2") "/tmp" (list) (fr/limits 20 8))
    ((err _) false)
    ((ok g)
      (match (fr/guardBegin! (list "/bin/sh" "-c" "sleep 30") "/tmp" (list) (fr/limits 20 0))
        ((err _) (do (fr/stopGuard! g) false))
        ((ok fake)
          (let [(gg fr/Guarded g)
                (run0 fr/RunningSep gg.run)
                (run1 fr/RunningSep (with run0 :groups (list run0.pid 999999)))
                (frun fr/RunningSep fake.run)
                (staged fr/Guarded (with gg :run run1 :fresh false :snapPid frun.pid :snapFd frun.outFd :snapText "" :snapStart (- (monotonicNs) 11000000000)))
                (step (fr/guardPoll! staged))
                (kept (listContains? step.guard.run.groups 999999))
                (fakeGone (<= step.guard.snapPid 0))
                (_ (fdClose frun.errFd))
                (_ (fr/stopGuard! fake))
                (_ (pathRemove (fr/leasePath frun.pid)))
                (fakeTmpGone (or (stringEmpty? frun.tmp) (not (fileExists? frun.tmp))))
                (_ (pollToEnd! step.guard (+ (nowMs!) 5000)))]
            (and kept (and fakeGone fakeTmpGone)))))))

; (:m :ref SESSIONPOOL-LOWS-20261112 :do "a guard stopped while its polled ps snapshot is still running leaves no ps child: the ps pid is reaped (a zombie still answers kill 0) and its fd is closed")
fn ! stopMidSnapProbe! -> (Pair Bool Bool)
  (match (fr/guardBegin! (list "/bin/sh" "-c" "sleep 5") "/tmp" (list) (fr/limits 20 8))
    ((err _) (pair false false))
    ((ok g) (let [(step (fr/guardPoll! g))
                  (pending (> step.guard.snapPid 0))
                  (psPid step.guard.snapPid)
                  (psFd step.guard.snapFd)
                  (_ (fr/stopGuard! step.guard))
                  (_ (pathRemove (fr/leasePath step.guard.run.pid)))
                  (_ (sleepMs 300))
                  (gone (not (resultOr (procAlive? psPid) false)))
                  (closed (not (ok? (fdClose psFd))))]
              (pair pending (and gone closed)))))

fn ! rssKb! -> Int64
  (let [(text (resultOr (fileReadString "/proc/self/status") ""))]
    (fold (fn [(acc Int64) (line String)] -> Int64
            (if (stringStartsWith? line "VmRSS:")
              (optionOr (stringToInt64 (stringTrim (stringReplace (stringReplace line "VmRSS:" "") "kB" ""))) acc) acc))
      0 (stringSplit text "\n")))

fn ! runTests -> Bool
  (let [(temp (stringTrim (resultOr (fr/shellOut "/usr/bin/mktemp -d /tmp/sessionPoolTest.XXXXXX" 5000) "")))
        (single (drivePool! temp "one" 1 5 1 100))
        (eight (drivePool! temp "eight" 8 5 8 100))
        (many (drivePool! temp "many" 64 2 8 16))
        (manyPool (pairFirst many))
        (leftover (resultOr (fr/shellOut (str "/bin/ls " temp "/many-spill | /usr/bin/wc -l") 5000) "x"))
        (dead (stepUntilIdle! (submitAll! (sp/newPool (str temp "/none.sock") 2 4 1000 (str temp "/many-spill")) 2 1) (+ (nowMs!) 4000)))
        (cold1 (sp/Sess :id "c1" :state "" :request "r" :fd -1 :buf "" :lastMs 100 :tries 0 :holdMs 0 :guard none :spill ""))
        (cold2 (sp/Sess :id "c2" :state "" :request "r" :fd -1 :buf "" :lastMs 50 :tries 0 :holdMs 0 :guard none :spill ""))
        (warmNew (sp/Sess :id "w1" :state "" :request "r" :fd -1 :buf "" :lastMs 9000 :tries 0 :holdMs 0 :guard none :spill ""))
        (warmOld (sp/Sess :id "w2" :state "" :request "r" :fd -1 :buf "" :lastMs 7500 :tries 0 :holdMs 0 :guard none :spill ""))
        (pickWarm (sp/pickNext (list cold2 warmNew cold1 warmOld) 10000 3000))
        (pickCold (sp/pickNext (list cold1 cold2) 10000 3000))
        (ex (execRun! temp))
        (forkT0 (nowMs!))
        (forked (stepUntilIdle! (sp/poolSubmit! (sp/newPool (str temp "/fork.sock") 1 4 60000 (str temp "/fork-spill")) "f" "fork" (nowMs!)) (+ (nowMs!) 15000)))
        (forkMs (- (nowMs!) forkT0))
        (forkOut (optionOr (doneOf forked "f") ""))
        (exDone (sp/poolDone (pairFirst ex)))
        (exGet (fn [(id String)] -> String (optionOr (optionMap (fn [(d (Pair String String))] -> String (pairSecond d)) (listFind (fn [(d (Pair String String))] -> Bool (= (pairFirst d) id)) exDone)) "")))
        (lease (leaseProbe!))
        (staleKept (staleSnapProbe!))
        (midStop (stopMidSnapProbe!))
        (rss (rssKb!))
        (removed (ok? (fr/shellOut (str "/bin/rm -rf " temp) 5000)))]
    (do
      (assert (and (= (listLength (sp/poolDone (pairFirst single))) 1) (= (listLength (sp/poolDone (pairFirst eight))) 8)) "one and eight sessions all finished")
      (assert (< (pairSecond eight) (* 2 (pairSecond single))) (str "8 slots over 8 sessions finish in under twice one session's wall: " (stringFromInt64 (pairSecond eight)) "ms vs " (stringFromInt64 (pairSecond single)) "ms"))
      (assert (= (listLength (sp/poolDone manyPool)) 64) (str "64 sessions over 8 slots all finish: " (stringFromInt64 (listLength (sp/poolDone manyPool)))))
      (assert (and (> manyPool.peakSpilled 0) (<= manyPool.peakMem 16)) (str "waiting sessions spilled past memCap 16: peak in memory " (stringFromInt64 manyPool.peakMem) ", peak spilled " (stringFromInt64 manyPool.peakSpilled)))
      (assert (= (stringTrim leftover) "0") (str "spill files are removed as sessions resume: " leftover))
      (assert (and (= (listLength (sp/poolDone dead)) 2) (listAll? (fn [(d (Pair String String))] -> Bool (stringContains? (pairSecond d) "unreachable")) (sp/poolDone dead))) "an unreachable hub ends both sessions after bounded tries")
      (assert (match pickWarm ((some s) (= s.id "w2")) ((none) false)) "oldest warm session resumes first")
      (assert (match pickCold ((some s) (= s.id "c2")) ((none) false)) "with no warm session the oldest cold one resumes first")
      (assert (and (< (pairSecond ex) 600) (= (exGet "_gateEarly") "yes")) (str "the hub session finished in " (stringFromInt64 (pairSecond ex)) "ms while the 1 s gate was still running"))
      (assert (and (stringContains? (exGet "x") ":exit 0") (stringContains? (exGet "x") "gate")) (str "the gate returned its exit and output: " (exGet "x")))
      (assert (and (stringStartsWith? (exGet "k") "(:exec :exit ") (not (stringContains? (exGet "k") ":exit 0 "))) (str "the 30 s process was killed at its 1 s timeout: " (exGet "k")))
      (assert (and (stringContains? forkOut ":verdict :runaway") (< forkMs 15000)) (str "a child forking 12 sleeps past maxDesc 8 is killed as runaway by the polled snapshot, not left to its 20 s timeout: " (stringFromInt64 forkMs) "ms " forkOut))
      (assert (not (stringContains? (exGet "n") ":exit 0 ")) (str "a missing binary is an error reply: " (exGet "n")))
      (assert (and (stringContains? (pairFirst lease) ":ownerBorn 0)") (and (stringContains? (pairSecond lease) ":ownerBorn ") (not (stringContains? (pairSecond lease) ":ownerBorn 0)")))) (str "guardBegin! writes its lease at once and the first polled snapshot adds the owner start time: " (pairFirst lease) " then " (pairSecond lease)))
      (assert staleKept "a ps snapshot past its 10 s bound is killed and judged as no check: the recorded escapee group survives, and the fake guard is stopped with its scratch dir removed")
      (assert (pairFirst midStop) "the stop probe caught a ps snapshot still running")
      (assert (pairSecond midStop) "stopGuard! with a ps snapshot running reaps the ps child and closes its fd")
      (assert (or (= rss 0) (< rss 524288)) (str "pool RSS stays under 512 MB: " (stringFromInt64 rss) " kB"))
      (assert removed "temp dir removed")
      true))
