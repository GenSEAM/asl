(module asl/agentLoop/leonServe
  :x [openRun! serveLoop! hubSockOf freeCtl! cfgInt groupText lockCtl! bindCtl! probeCtl! ctlStaleError? startOf! ownerState! ownerPath main]
  :i [(asl/agentLoop/main :a m) (asl/agentLoop/leonPool :a lp) (asl/agentLoop/poolServe :a ps)
      (asl/agentLoop/sessionPool :a sp) (asl/agentLoop/providers :a pv) (asl-tools/fleet/run :a fr)])

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

; (:m :ref LEONSERVE-STALE-SOCKET :do "a killed pool leaves its control socket file behind and the next start failed at unixListen with io:98 (address in use), so the service restarted forever and no run was pooled. A connect proves the file stale only when it is refused (ECONNREFUSED, named per platform: 111 on Linux, 61 on macOS where 61 is not ENODATA) or finds no file (ENOENT 2); any other error (EAGAIN, EINTR, EMFILE of a busy listener) is retried and then refused. A refusal alone removes nothing: a live pool whose backlog is full is refused too on macOS, so the owner record decides")
fn ctlRefusedCode os: String -> String
  (if (= os "Darwin") "io:61" "io:111")

fn ctlStaleError? os: String e: String -> Bool
  (or (= e (ctlRefusedCode os)) (or (= e "io:2") (or (= e "ECONNREFUSED") (= e "ENOENT"))))

fn ! hostOs! -> String
  (match (platformInfo) ((ok p) p.os) ((err _) ""))

; (:m :ref LEONSERVE-STALE-SOCKET :do "the text of the first group named group of a config text, parens included, empty when absent (quoted parens do not count), so a key of another group with the same name is never read through it")
fn groupEnd text: String i: Int64 depth: Int64 quoted: Bool -> Int64
  (if (>= i (stringLength text)) i
    (let [(c (optionOr (stringSlice text i (+ i 1)) ""))]
      (cond
        (quoted (groupEnd text (+ i 1) depth (not (= c "\""))))
        ((= c "\"") (groupEnd text (+ i 1) depth true))
        ((= c "(") (groupEnd text (+ i 1) (+ depth 1) false))
        ((= c ")") (if (<= depth 1) (+ i 1) (groupEnd text (+ i 1) (- depth 1) false)))
        (else (groupEnd text (+ i 1) depth false)))))

fn groupText text: String group: String -> String
  (match (stringIndexOf text (str ":" group " ("))
    ((none) "")
    ((some i) (let [(start (+ i (+ (stringLength group) 2)))]
                (optionOr (stringSlice text start (groupEnd text start 0 false)) ""))))

; (:m :ref LEONSERVE-STALE-SOCKET :do "retry count and delay come from the :leonPool group of .asl.config.asn (:ctlProbeRetries :ctlProbeDelayMs), overridable by --probe-retries and --probe-delay-ms")
fn cfgToken text: String key: String -> String
  (match (stringIndexOf text (str ":" key " "))
    ((none) "")
    ((some i) (let [(rest (stringTrim (optionOr (stringSlice text (+ i (+ (stringLength key) 2)) (stringLength text)) "")))]
                (stringReplace (optionOr (listHead (stringSplit (optionOr (listHead (stringLines rest)) "") " ")) "") ")" ""))))

fn cfgInt text: String key: String fallback: Int64 -> Int64
  (optionOr (stringToInt64 (cfgToken text key)) fallback)

fn ! probeCtl! ctl: String tries: Int64 delayMs: Int64 os: String -> String
  (match (unixConnect ctl)
    ((ok fd) (do (fdClose fd) "live"))
    ((err e) (cond
               ((ctlStaleError? os e) "stale")
               ((<= tries 1) "busy")
               (else (do (sleepMs delayMs) (probeCtl! ctl (- tries 1) delayMs os))))))

; (:m :ref LEONSERVE-STALE-SOCKET :do "the owner record ctl.sock.pid, written by the pool after it binds: (:owner :pid N :start S) with the process start time of ps -o lstart=, which is the same text on Linux and macOS. A pid that was reused by another process has another start time")
fn ownerPath ctl: String -> String
  (str ctl ".pid")

fn ! startOf! pid: Int64 -> String
  (let [(d (fr/runOneLimited (fr/job (list "ps" "-o" "lstart=" "-p" (stringFromInt64 pid)) "." (fr/childEnv (list))) (fr/limits 5 16)))]
    (if (= d.exit 0) (stringJoin (filter (fn [(w String)] -> Bool (not (stringEmpty? w))) (stringSplit (stringTrim d.out) " ")) " ") ""))

fn ! writeOwner! ctl: String -> Bool
  (let [(me (procSelf))]
    (ok? (fileWrite (ownerPath ctl) (str "(:owner :pid " (stringFromInt64 me) " :start \"" (startOf! me) "\")\n"))))

; (:m :ref LEONSERVE-STALE-SOCKET :do "alive: the recorded pid runs and (when ps answers) has the recorded start time; gone: no such process or another start time; unknown: no readable record. Only alive refuses a refused socket")
fn ! ownerState! ctl: String -> String
  (let [(raw (resultOr (fileReadString (ownerPath ctl)) ""))
        (pid (cfgInt raw "pid" 0))
        (start (optionOr (ps/quotedAfter raw ":start") ""))]
    (cond
      ((or (stringEmpty? raw) (<= pid 1)) "unknown")
      ((not (resultOr (procAlive? pid) false)) "gone")
      (else (let [(now (startOf! pid))]
              (if (or (stringEmpty? now) (= now start)) "alive" "gone")))))

; (:m :ref LEONSERVE-STALE-SOCKET :do "the path must be a socket (lstat mode type 0xC000, never followed, never a directory or a regular file) before anything is removed; a live peer is refused, and so is a refused connect whose recorded owner is alive; a refused connect (no listener) whose owner is gone or was never recorded (a pool of before the record, or one that died between listen and record) removes the socket and its record, and what is removed is logged")
fn ! freeCtl! ctl: String tries: Int64 delayMs: Int64 -> (Result Unit String)
  (match (fileLstat ctl)
    ((err _) (ok ()))
    ((ok st)
      (if (!= (/ st.mode 4096) 12)
        (err (str "(:ctlNotSocket " ctl ")"))
        (let [(verdict (probeCtl! ctl tries delayMs (hostOs!)))]
          (cond
            ((= verdict "live") (err (str "another pool answers on " ctl)))
            ((= verdict "busy") (err (str "control socket busy, not taken over: " ctl)))
            (else (let [(owner (ownerState! ctl))]
                    (cond
                      ((= owner "alive") (err (str "(:ctlOwnerAlive " ctl ")")))
                      (else (match (pathRemove ctl)
                              ((err e) (err e))
                              ((ok _) (do (pathRemove (ownerPath ctl)) (eprintln (str "leonServe: removed stale control socket " ctl)) (ok ())))))))))))))

; (:m :ref LEONSERVE-STALE-SOCKET :do "two pools started together would both pass the stale check: a lock file beside the socket, created exclusively with the starter's pid, spans check and listen. A lock whose pid is gone or unreadable is a crashed starter's: it is removed only if it still holds the text just read (a starter that replaced it meanwhile keeps it) and then created exclusively once more; a live holder refuses this start")
fn ! lockCtl! ctl: String -> (Result String String)
  (let [(lock (str ctl ".lock"))
        (mine (str (stringFromInt64 (procSelf)) "\n"))]
    (match (fileCreateExclusive lock mine)
      ((ok _) (ok lock))
      ((err _)
        (let [(text (resultOr (fileReadString lock) ""))
              (held (optionOr (stringToInt64 (stringTrim text)) 0))]
          (if (and (> held 1) (resultOr (procAlive? held) false))
            (err (str "another pool is starting on " ctl " (pid " (stringFromInt64 held) ")"))
            (do (if (= (resultOr (fileReadString lock) "") text) (pathRemove lock) (ok ()))
                (match (fileCreateExclusive lock mine)
                  ((ok _) (ok lock))
                  ((err e) (err (str "cannot take " lock ": " e))))))))))

fn ! bindCtl! ctl: String tries: Int64 delayMs: Int64 -> (Result Int64 String)
  (match (lockCtl! ctl)
    ((err e) (err e))
    ((ok lock) (let [(bound (match (freeCtl! ctl tries delayMs) ((err e) (err e)) ((ok l) (unixListen ctl))))
                     (recorded (match bound ((ok _) (writeOwner! ctl)) ((err _) true)))
                     (_ (if recorded (ok ()) (do (match bound ((ok fd) (fdClose fd)) ((err _) (ok ()))) (pathRemove ctl))))
                     (_ (pathRemove lock))]
                 (if recorded bound (err (str "(:ctlOwnerRecord " (ownerPath ctl) ") cannot write the owner record; socket removed"))))))

fn ! main args: (List String) -> (Result Int64 String)
  (let [(home (optionOr (envGet "HOME") ""))
        (ctl (argOr args "--ctl" ""))
        (rdir (argOr args "--receipts" ""))
        (cfg (groupText (resultOr (fileReadString (argOr args "--config" ".asl.config.asn")) "") "leonPool"))
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
                  (closed (do (fdClose listener) (pathRemove ctl) (pathRemove (ownerPath ctl)) true))]
              (ok 0)))))))
