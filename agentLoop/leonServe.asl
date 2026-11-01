(module asl/agentLoop/leonServe
  :x [openRun! serveLoop! hubSockOf freeCtl! cfgInt lockCtl! bindCtl! probeCtl! ctlStaleError? main]
  :i [(asl/agentLoop/main :a m) (asl/agentLoop/leonPool :a lp) (asl/agentLoop/poolServe :a ps)
      (asl/agentLoop/sessionPool :a sp) (asl/agentLoop/providers :a pv)])

; (:m :ref SE5B-LEON-SERVE :do "a routed run (a code route declared for its intent) answers exit 125 and is dropped: its model call would block every other session of the process, so the conductor spawns it instead. One Leon process serving many units: a control socket takes (:run :unit U :form F :repo R :root D), every run is a session of leonPool in one sessionPool, and a receipt file per unit carries its exit and the Leon receipt. The pool socket is the hub socket of HOME/.asl/hub.asn (the same one a blocking Leon posts to), so the hub still owns pacing and the learned rates; the process ends at :stop or at its deadline and is never a service")
fn ! openRun! book: (List (Pair String lp/Live)) id: String form: String repo: String root: String -> (Pair (List (Pair String lp/Live)) (Option (Pair Int64 String)))
  (let [(opened (lp/leonOpen! book id form repo root (pv/providerEnv! root)))]
    (if (and (none? (pairSecond opened)) (or (lp/leonRouted? (pairFirst opened) id) (not (lp/leonViaHub? (pairFirst opened) id))))
      (pair (lp/leonDrop (pairFirst opened) id) (some (pair 125 "(:declined :why \"only a hub-ask provider on a plain route shares the pool; a routed, script, replay or CLI run blocks it, so spawn it\")")))
      (pair (pairFirst opened) (optionMap (fn [(r m/MainResult)] -> (Pair Int64 String) (pair r.exitCode r.stdout)) (pairSecond opened)))))

fn ! nowMs! -> Int64
  (/ (monotonicNs) 1000000)

fn hubSockOf text: String -> String
  (optionOr (ps/quotedAfter text ":sock") "")

; (:m :ref SE5B-LEON-SERVE :do "the serve loop: poll the control socket, the hub sockets of the pool and the pool's exec children, step the server with the Leon driver, until :stop or the deadline")
fn ! serveLoop! s: ps/Serve book: (List (Pair String lp/Live)) deadlineMs: Int64 -> (Pair ps/Serve (List (Pair String lp/Live)))
  (if (or s.stop (>= (nowMs!) deadlineMs)) (pair s book)
    (match (fdPoll (ps/serveWatch s) 20)
      ((err _) (serveLoop! s book deadlineMs))
      ((ok ready)
        (let [(stepped (ps/serveStepG! s ready lp/leonTurn! book openRun! lp/leonExit (nowMs!)))]
          (serveLoop! (pairFirst stepped) (pairSecond stepped) deadlineMs)))))

fn argOr args: (List String) key: String fallback: String -> String
  (match (listFind (fn [(i Int64)] -> Bool (= (optionOr (listGet args i) "") key)) (range 0 (listLength args)))
    ((some i) (optionOr (listGet args (+ i 1)) fallback))
    ((none) fallback))

; (:m :ref LEONSERVE-STALE-SOCKET :do "a killed pool leaves its control socket file behind and the next start failed at unixListen with io:98 (address in use), so the service restarted forever and no run was pooled. Only a connect that is refused (ECONNREFUSED: 111 Linux, 61 macOS) or finds no file (ENOENT: 2) proves the file stale; any other error (a listener whose backlog is full answers EAGAIN, EINTR, EMFILE) is retried 5 times 100 ms apart and then the start is refused with the file left in place")
fn ctlStaleError? e: String -> Bool
  (listAny? (fn [(c String)] -> Bool (= e c)) (list "io:111" "io:61" "io:2" "ECONNREFUSED" "ENOENT"))

; (:m :ref LEONSERVE-STALE-SOCKET :do "retry count and delay come from .asl.config.asn :leonPool (:ctlProbeRetries :ctlProbeDelayMs), overridable by --probe-retries and --probe-delay-ms")
fn cfgToken text: String key: String -> String
  (match (stringIndexOf text (str ":" key " "))
    ((none) "")
    ((some i) (let [(rest (stringTrim (optionOr (stringSlice text (+ i (+ (stringLength key) 2)) (stringLength text)) "")))]
                (stringReplace (optionOr (listHead (stringSplit (optionOr (listHead (stringLines rest)) "") " ")) "") ")" ""))))

fn cfgInt text: String key: String fallback: Int64 -> Int64
  (optionOr (stringToInt64 (cfgToken text key)) fallback)

fn ! probeCtl! ctl: String tries: Int64 delayMs: Int64 -> String
  (match (unixConnect ctl)
    ((ok fd) (do (fdClose fd) "live"))
    ((err e) (cond
               ((ctlStaleError? e) "stale")
               ((<= tries 1) "busy")
               (else (do (sleepMs delayMs) (probeCtl! ctl (- tries 1) delayMs))))))

; (:m :ref LEONSERVE-STALE-SOCKET :do "the path must be a socket (lstat mode type 0xC000, never followed, never a directory or a regular file) before anything is removed, and what is removed is logged; a live peer is refused, never taken over")
fn ! freeCtl! ctl: String tries: Int64 delayMs: Int64 -> (Result Unit String)
  (match (fileLstat ctl)
    ((err _) (ok ()))
    ((ok st)
      (if (!= (/ st.mode 4096) 12)
        (err (str "(:ctlNotSocket " ctl ")"))
        (let [(verdict (probeCtl! ctl tries delayMs))]
          (cond
            ((= verdict "live") (err (str "another pool answers on " ctl)))
            ((= verdict "busy") (err (str "control socket busy, not taken over: " ctl)))
            (else (match (pathRemove ctl)
                    ((err e) (err e))
                    ((ok _) (do (eprintln (str "leonServe: removed stale control socket " ctl)) (ok ()))))))))))

; (:m :ref LEONSERVE-STALE-SOCKET :do "two pools started together would both pass the stale check: a lock file beside the socket, created exclusively with the starter's pid, spans check and listen. A lock whose pid is gone or unreadable is a crashed starter's and is replaced once; a live holder refuses this start")
fn ! lockCtl! ctl: String -> (Result String String)
  (let [(lock (str ctl ".lock"))]
    (match (fileCreateExclusive lock (str (stringFromInt64 (procSelf)) "\n"))
      ((ok _) (ok lock))
      ((err _)
        (let [(held (optionOr (stringToInt64 (stringTrim (resultOr (fileReadString lock) ""))) 0))]
          (if (and (> held 1) (resultOr (procAlive? held) false))
            (err (str "another pool is starting on " ctl " (pid " (stringFromInt64 held) ")"))
            (do (pathRemove lock)
                (match (fileCreateExclusive lock (str (stringFromInt64 (procSelf)) "\n"))
                  ((ok _) (ok lock))
                  ((err e) (err (str "cannot take " lock ": " e))))))))))

fn ! bindCtl! ctl: String tries: Int64 delayMs: Int64 -> (Result Int64 String)
  (match (lockCtl! ctl)
    ((err e) (err e))
    ((ok lock) (let [(bound (match (freeCtl! ctl tries delayMs) ((err e) (err e)) ((ok _) (unixListen ctl))))
                     (_ (pathRemove lock))]
                 bound)))

fn ! main args: (List String) -> (Result Int64 String)
  (let [(home (optionOr (envGet "HOME") ""))
        (ctl (argOr args "--ctl" ""))
        (rdir (argOr args "--receipts" ""))
        (cfg (resultOr (fileReadString (argOr args "--config" ".asl.config.asn")) ""))
        (spill (argOr args "--spill" (str rdir "/spill")))
        (slots (optionOr (stringToInt64 (argOr args "--slots" "8")) 8))
        (deadline (optionOr (stringToInt64 (argOr args "--deadline" "3600")) 3600))
        (hub (argOr args "--hub" (hubSockOf (resultOr (fileReadString (str home "/.asl/hub.asn")) ""))))]
    (cond
      ((or (stringEmpty? ctl) (stringEmpty? rdir)) (err "usage: leonServe --ctl SOCK --receipts DIR [--slots N] [--deadline SEC] [--hub SOCK] [--spill DIR]"))
      ((stringEmpty? hub) (err "no hub socket: pass --hub or name :sock in HOME/.asl/hub.asn"))
      (else
        (match (bindCtl! ctl (optionOr (stringToInt64 (argOr args "--probe-retries" (stringFromInt64 (cfgInt cfg "ctlProbeRetries" 5)))) 5) (optionOr (stringToInt64 (argOr args "--probe-delay-ms" (stringFromInt64 (cfgInt cfg "ctlProbeDelayMs" 100)))) 100))
          ((err e) (err (str "control socket: " e)))
          ((ok listener)
            (let [(made (and (ok? (dirCreate rdir)) (ok? (dirCreate spill))))
                  (s0 (ps/newServe listener (sp/newPool hub slots 64 300000 spill) rdir))
                  (out (serveLoop! s0 (list) (+ (nowMs!) (* 1000 deadline))))
                  (closed (do (fdClose listener) (pathRemove ctl) true))]
              (ok 0)))))))
