(module asl/agentLoop/leonServe
  :x [openRun! serveLoop! hubSockOf main]
  :i [(asl/agentLoop/main :a m) (asl/agentLoop/leonPool :a lp) (asl/agentLoop/poolServe :a ps)
      (asl/agentLoop/sessionPool :a sp) (asl/agentLoop/providers :a pv)])

; (:m :ref SE5B-LEON-SERVE :do "one Leon process serving many units: a control socket takes (:run :unit U :form F :repo R :root D), every run is a session of leonPool in one sessionPool, and a receipt file per unit carries its exit and the Leon receipt. The pool socket is the hub socket of HOME/.asl/hub.asn (the same one a blocking Leon posts to), so the hub still owns pacing and the learned rates; the process ends at :stop or at its deadline and is never a service")
fn ! openRun! book: (List (Pair String lp/Live)) id: String form: String repo: String root: String -> (Pair (List (Pair String lp/Live)) (Option (Pair Int64 String)))
  (let [(opened (lp/leonOpen! book id form repo root (pv/providerEnv! root)))]
    (pair (pairFirst opened) (optionMap (fn [(r m/MainResult)] -> (Pair Int64 String) (pair r.exitCode r.stdout)) (pairSecond opened))))

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

fn ! main args: (List String) -> (Result Int64 String)
  (let [(home (optionOr (envGet "HOME") ""))
        (ctl (argOr args "--ctl" ""))
        (rdir (argOr args "--receipts" ""))
        (spill (argOr args "--spill" (str rdir "/spill")))
        (slots (optionOr (stringToInt64 (argOr args "--slots" "8")) 8))
        (deadline (optionOr (stringToInt64 (argOr args "--deadline" "3600")) 3600))
        (hub (argOr args "--hub" (hubSockOf (resultOr (fileReadString (str home "/.asl/hub.asn")) ""))))]
    (cond
      ((or (stringEmpty? ctl) (stringEmpty? rdir)) (err "usage: leonServe --ctl SOCK --receipts DIR [--slots N] [--deadline SEC] [--hub SOCK] [--spill DIR]"))
      ((stringEmpty? hub) (err "no hub socket: pass --hub or name :sock in HOME/.asl/hub.asn"))
      (else
        (match (unixListen ctl)
          ((err e) (err (str "control socket: " e)))
          ((ok listener)
            (let [(made (and (ok? (dirCreate rdir)) (ok? (dirCreate spill))))
                  (s0 (ps/newServe listener (sp/newPool hub slots 64 300000 spill) rdir))
                  (out (serveLoop! s0 (list) (+ (nowMs!) (* 1000 deadline))))
                  (closed (do (fdClose listener) (pathRemove ctl) true))]
              (ok 0)))))))
