(module aslGateway/tests/gatewayStartKit
  :x [waitReady! waitPort! readyPort! startDeadlineMs tailOf]
  :i [(asl-tools/fleet/run :a fr)])

; (:m :ref GW-TEST-WAITREADY-SWEEP :do "the one wait every gateway suite uses for its scratch-HOME gateway child (RETRYCONC-FLAKE): the child compiles server.asl to native on a cold cache before it writes its --ready file, silently, measured 8.8 to 22.5 s and once over 120 s at load 120-154 on the Mac, 2026-11-12; the fixed 10 to 30 s polls each suite carried failed there with an empty stderr")

fn ! nowMs! -> Int64
  (/ (monotonicNs) 1000000)

fn ! readyPort! path: String -> Int64
  (optionOr (optionOr (resultToOption (resultMap (fileReadString path) (fn [(t String)] -> (Option Int64) (stringToInt64 (stringTrim t))))) none) 0)

; (:m :ref GW-TEST-WAITREADY-SWEEP :do "the cap on a child that lives without answering; waitReady! returns at once when the child exits, so this is not the wait")
fn startDeadlineMs -> Int64
  300000

fn tailOf text: String n: Int64 -> String
  (if (<= (stringLength text) n) text (optionOr (stringSlice text (- (stringLength text) n) (stringLength text)) text))

; (:m :ref GW-TEST-KILLTREE-PIDREUSE :do "the child ended when kill 0 fails or ps shows it a zombie; it is never reaped here, so its pid stays held until the suite's own teardown (killTree!, guard settle, waitpid): a reap here freed the pid, and a later killTree! of it could hit whatever process the kernel gave it next")
fn ! ended? pid: Int64 -> Bool
  (or (not (resultOr (procAlive? pid) false))
      (stringStartsWith? (stringTrim (fr/runOneLimited (fr/job (list "ps" "-o" "stat=" "-p" (stringFromInt64 pid)) "/" (fr/childEnv (list))) (fr/limits 10 8)).out) "Z"))

; (:m :ref GW-TEST-WAITREADY-SWEEP :do "waits for the ready file while the child lives: the port once written (state ready), state exited the moment the child ends without one (judged every 500 ms by ended?, the child left unreaped), or deadline when neither happens by deadlineMs")
fn ! waitReady! path: String pid: Int64 deadlineMs: Int64 -> (Pair Int64 String)
  (waitTick! path pid deadlineMs 0)

fn ! waitTick! path: String pid: Int64 deadlineMs: Int64 tick: Int64 -> (Pair Int64 String)
  (let [(port (readyPort! path))]
    (cond
      ((> port 0) (pair port "ready"))
      ((<= pid 0) (pair 0 "no child"))
      ((and (= (mod tick 25) 0) (ended? pid)) (pair (readyPort! path) "exited"))
      ((> (nowMs!) deadlineMs) (pair 0 "deadline"))
      (else (do (sleepMs 20) (waitTick! path pid deadlineMs (+ tick 1))))))

fn dirOf path: String -> String
  (let [(parts (stringSplit path "/"))]
    (stringJoin (listTake parts (- (listLength parts) 1)) "/"))

; (:m :ref GW-TEST-WAITREADY-SWEEP :do "the port of the child pid's ready file, 0 when it never came; a miss prints one (:gatewayStart ...) line to stderr with the state, the elapsed ms and the tail of gateway.err next to the ready file, so a red start names its cause")
fn ! waitPort! path: String pid: Int64 -> Int64
  (let [(start (nowMs!))
        (w (waitReady! path pid (+ start (startDeadlineMs))))]
    (if (> (pairFirst w) 0)
      (pairFirst w)
      (do (eprintln (str "(:gatewayStart :state \"" (pairSecond w) "\" :ms " (stringFromInt64 (- (nowMs!) start)) " :ready \"" path "\" :stderr \"" (stringReplace (stringReplace (tailOf (resultOr (fileReadString (str (dirOf path) "/gateway.err")) "") 600) "\"" "'") "\n" " ") "\")"))
          0)))
