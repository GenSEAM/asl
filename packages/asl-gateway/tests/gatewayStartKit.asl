(module aslGateway/tests/gatewayStartKit
  :x [waitReady! waitPort! readyPort! startDeadlineMs tailOf]
  :i [])

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

; (:m :ref GW-TEST-WAITREADY-SWEEP :do "waits for the ready file while the child lives: the port once written (state ready), the child's exit status the moment it ends without one (procWaitPid pid true, non-blocking; state exited N), or deadline when neither happens by deadlineMs")
fn ! waitReady! path: String pid: Int64 deadlineMs: Int64 -> (Pair Int64 String)
  (let [(port (readyPort! path))]
    (cond
      ((> port 0) (pair port "ready"))
      ((<= pid 0) (pair 0 "no child"))
      (else
        (match (procWaitPid pid true)
          ((ok (some code)) (pair (readyPort! path) (str "exited " (stringFromInt64 code))))
          (_ (if (> (nowMs!) deadlineMs)
               (pair 0 "deadline")
               (do (sleepMs 20) (waitReady! path pid deadlineMs))))))))

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
