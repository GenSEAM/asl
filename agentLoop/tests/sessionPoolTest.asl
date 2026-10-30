(module asl/agentLoop/tests/sessionPoolTest
  :x [runTests]
  :i [(asl/agentLoop/sessionPool :a sp) (asl-tools/fleet/run :a fr)])

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

fn ! runPool! temp: String name: String n: Int64 turns: Int64 slots: Int64 memCap: Int64 -> (Pair sp/Pool Int64)
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

; (:m :ref SE4-ASYNC-EXEC :do "a session in a 1 s local process (gate) and one in a killed 30 s process (timeout 1 s) and one with a missing binary share the pool with a hub session of 5 turns: the hub session finishes in under 900 ms while the gate is still running, the gate then returns exit 0 with its output, the timeout kills the long one, the missing binary is an error reply")
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

fn ! rssKb! -> Int64
  (let [(text (resultOr (fileReadString "/proc/self/status") ""))]
    (fold (fn [(acc Int64) (line String)] -> Int64
            (if (stringStartsWith? line "VmRSS:")
              (optionOr (stringToInt64 (stringTrim (stringReplace (stringReplace line "VmRSS:" "") "kB" ""))) acc) acc))
      0 (stringSplit text "\n")))

fn ! runTests -> Bool
  (let [(temp (stringTrim (resultOr (fr/shellOut "/usr/bin/mktemp -d /tmp/sessionPoolTest.XXXXXX" 5000) "")))
        (single (runPool! temp "one" 1 5 1 100))
        (eight (runPool! temp "eight" 8 5 8 100))
        (many (runPool! temp "many" 64 2 8 16))
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
        (exDone (sp/poolDone (pairFirst ex)))
        (exGet (fn [(id String)] -> String (optionOr (optionMap (fn [(d (Pair String String))] -> String (pairSecond d)) (listFind (fn [(d (Pair String String))] -> Bool (= (pairFirst d) id)) exDone)) "")))
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
      (assert (and (< (pairSecond ex) 900) (= (exGet "_gateEarly") "yes")) (str "the hub session finished in " (stringFromInt64 (pairSecond ex)) "ms while the 1 s gate was still running"))
      (assert (and (stringContains? (exGet "x") ":exit 0") (stringContains? (exGet "x") "gate")) (str "the gate returned its exit and output: " (exGet "x")))
      (assert (and (stringStartsWith? (exGet "k") "(:exec :exit ") (not (stringContains? (exGet "k") ":exit 0 "))) (str "the 30 s process was killed at its 1 s timeout: " (exGet "k")))
      (assert (not (stringContains? (exGet "n") ":exit 0 ")) (str "a missing binary is an error reply: " (exGet "n")))
      (assert (or (= rss 0) (< rss 524288)) (str "pool RSS stays under 512 MB: " (stringFromInt64 rss) " kB"))
      (assert removed "temp dir removed")
      true))
