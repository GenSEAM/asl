(module asl-tools/remote/relay
  :x [Link Pend Cli Reply seqOf kindOf resendText execPends stageBytes cliTune cliBreak! newSession newId linkOf helloText execFrame cliNew cliStep! cliDone? cliWait! request! replyOf execVia! pendText connect!]
  :i [(asl-tools/remote/form :a fm) (asl-tools/remote/bridge :a br)])

; (:m :ref RELAY-LINK :do "the byte transport behind one interface: a Link is a loopback tcp port or a unix socket path on this machine; today it is the local end of an ssh tunnel to the bridge's loopback port, later a private network, and nothing above connect! knows which")
(schema Link (:f path String) (:f port Int64) (:f token String) (:f session String))

(schema Pend (:f id String) (:f frame String) (:f done Bool) (:f frames (List String)))

(schema Cli
  (:f link Link)
  (:f fd Int64)
  (:f buf String)
  (:f out String)
  (:f pend (List Pend))
  (:f baseMs Int64)
  (:f capMs Int64)
  (:f backoffMs Int64)
  (:f nextNs Int64)
  (:f lastRxNs Int64)
  (:f pingNs Int64)
  (:f hbMs Int64)
  (:f deadMs Int64)
  (:f connects Int64)
  (:f fatal String)
  (:f healNs Int64)
  (:f dupes Int64))

(schema Reply (:f exit Int64) (:f verdict String) (:f out String) (:f err String) (:f code String) (:f replayed Bool) (:f connects Int64))

fn ! newSession -> String
  (str "s" (procSelf) "-" (mod (nowNs) 1000000000000))

fn ! newId -> String
  (str "r" (mod (nowNs) 1000000000000) "-" (procSelf))

fn linkOf path: String port: Int64 token: String session: String -> Link
  (Link :path path :port port :token token :session session)

fn helloText l: Link -> String
  (str "(:hello :id \"hello\" :v 1 :session " (fm/quoteText l.session)
       (if (stringEmpty? l.token) "" (str " :token " (fm/quoteText l.token))) ")")

; (:m :ref RELAY-EXEC :do "an exec frame names an argv, never a shell line; :wt picks the VPS worktree it runs in, :stdin carries base64 bytes the bridge feeds the child, and :timeout bounds it on the VPS")
fn execFrame id: String unit: String argv: (List String) timeoutS: Int64 stdinB64: String -> String
  (str "(:exec :id " (fm/quoteText id)
       (if (stringEmpty? unit) "" (str " :wt " unit))
       " :argv " (fm/quoteAll argv) " :timeout " timeoutS
       (if (stringEmpty? stdinB64) "" (str " :stdin " (fm/quoteText stdinB64))) ")")

; (:m :ref RELAY-LARGE-FRAME :do "bytesFromBase64 is super-linear (measured 2026-10-28: 12 KB 2 ms, 48 KB 13 ms, 192 KB 902 ms), so a piece is 48 KiB of base64; a request whose stdin is larger than one frame may carry is sent as bounded (:stage) frames (each at most stageBytes of base64, far below the bridge's :maxLine) that the bridge answers one by one, followed by an exec frame naming :stdinParts N; every frame is its own pend, so a link that breaks mid-upload resends only the stage frames without an answer, in order, and the exec last; cause found 2026-10-28: one exec frame over :maxLine 1 MiB made the bridge close the link with an oversize error, which the client treats as a dropped link and redials with the same frame forever")
fn stageBytes -> Int64
  49152

fn stageFrame id: String for: String n: Int64 data: String -> String
  (str "(:stage :id " (fm/quoteText id) " :for " (fm/quoteText for) " :n " n ") " data)

fn execPartsFrame id: String unit: String argv: (List String) timeoutS: Int64 parts: Int64 -> String
  (str "(:exec :id " (fm/quoteText id)
       (if (stringEmpty? unit) "" (str " :wt " unit))
       " :argv " (fm/quoteAll argv) " :timeout " timeoutS " :stdinParts " parts ")")

fn stagePends id: String data: String n: Int64 acc: (List Pend) -> (List Pend)
  (if (stringEmpty? data)
    (listReverse acc)
    (let [(len (stringLength data))
          (take (min len (stageBytes)))
          (cid (str id ".c" n))]
      (stagePends id (optionOr (stringSlice data take len) "") (+ n 1)
                  (cons (pendText cid (stageFrame cid id n (optionOr (stringSlice data 0 take) ""))) acc))))

; (:m :ref RELAY-LARGE-FRAME :do "the pends of one exec: a single frame while the stdin fits, else the stage pends followed by the exec pend, which is always the last one")
fn execPends id: String unit: String argv: (List String) timeoutS: Int64 stdinB64: String -> (List Pend)
  (if (<= (stringLength stdinB64) (stageBytes))
    (list (pendText id (execFrame id unit argv timeoutS stdinB64)))
    (let [(stages (stagePends id stdinB64 0 (list)))]
      (listAppend stages (list (pendText id (execPartsFrame id unit argv timeoutS (listLength stages)))))))

fn cliNew link: Link pend: (List Pend) -> Cli
  (Cli :link link :fd -1 :buf "" :out "" :pend pend :baseMs 250 :capMs 8000 :backoffMs 250 :nextNs 0 :lastRxNs 0 :pingNs 0
       :hbMs 10000 :deadMs 20000 :connects 0 :fatal "" :healNs 0 :dupes 0)

fn cliTune c: Cli hbMs: Int64 deadMs: Int64 capMs: Int64 -> Cli
  (with c :hbMs hbMs :deadMs deadMs :capMs capMs)

; (:m :ref RELAY-RESUME :do "cliBreak! drops the link on purpose (a caller that knows the network changed, or a test): the next step redials and resends what is open")
fn ! cliBreak! c: Cli -> Cli
  (drop! c)

fn pendText id: String frame: String -> Pend
  (Pend :id id :frame frame :done false :frames (list))

fn ! connect! l: Link -> (Result Int64 String)
  (if (> l.port 0) (br/clientTcp! l.port) (br/clientUnix! l.path))

fn cliDone? c: Cli -> Bool
  (or (not (stringEmpty? c.fatal)) (listAll? (fn [(p Pend)] -> Bool p.done) c.pend))

fn idOf frame: String -> String
  (match (fm/parseForm frame) ((ok n) (br/frameId n)) ((err _) ""))

fn kindOf frame: String -> String
  (match (fm/parseForm frame) ((ok n) (br/frameKind n)) ((err _) ""))

fn ! drop! c: Cli -> Cli
  (let [(_ (if (>= c.fd 0) (ok? (fdClose c.fd)) false))
        (now (monotonicNs))]
    (with c :fd -1 :buf "" :out "" :pingNs 0 :nextNs (+ now (* c.backoffMs 1000000)) :backoffMs (min c.capMs (* c.backoffMs 2))))

; (:m :ref RELAY-RESUME :do "on every (re)connect the client says hello with its session and resends each request that has no terminal frame yet, with the same id; it keeps only the frames of the current attempt, so a request replayed or rejoined by the bridge is neither lost nor counted twice")
; (:m :ref NET-SEQ-RESUME :do "out frames carry :seq; a pend keeps the frames of every attempt, and the resend names :from = last seen seq + 1 so the bridge streams only the missing ones; a frame whose seq was already seen is dropped, and a frame marked :reset (a replay from the stored result, whose chunking may differ) clears what was kept")
fn seqOf frame: String -> Int64
  (optionOr (stringToInt64 (br/replyOf frame ":seq")) 0)

fn maxSeq p: Pend -> Int64
  (fold (fn [(a Int64) (f String)] -> Int64 (max a (seqOf f))) 0 p.frames)

fn resendText p: Pend -> String
  (let [(n (maxSeq p))]
    (if (<= n 0) p.frame
      (str (optionOr (stringSlice p.frame 0 (- (stringLength p.frame) 1)) p.frame) " :from " (+ n 1) ")")))

fn ! dial! c: Cli now: Int64 -> Cli
  (match (connect! c.link)
    ((err _) (with c :nextNs (+ now (* c.backoffMs 1000000)) :backoffMs (min c.capMs (* c.backoffMs 2))))
    ((ok fd)
      (let [(open (filter (fn [(p Pend)] -> Bool (not p.done)) c.pend))]
        (with c :fd fd :buf "" :lastRxNs now :pingNs 0 :connects (+ c.connects 1)
                :out (str (helloText c.link) "\n" (stringJoin (map (fn [(p Pend)] -> String (str (resendText p) "\n")) open) ""))))))

; (:m :ref NET-SEQ-RESUME :do "dupes counts frames the bridge sent again although the resend named :from, so a test can tell an exact resume from a full replay the client merely hid")
fn dupeFrame? p: Pend frame: String -> Bool
  (let [(n (seqOf frame))]
    (and (> n 0) (and (<= n (maxSeq p)) (!= (br/replyOf frame ":reset") "true"))))

fn keepFrame p: Pend frame: String id: String -> Pend
  (let [(base (if (= (br/replyOf frame ":reset") "true") (with p :frames (list)) p))
        (n (seqOf frame))]
    (if (and (> n 0) (<= n (maxSeq base))) base
      (with base :frames (listAppend base.frames (list frame)) :done (br/terminal? frame id))))

fn fatalCode? code: String -> Bool
  (listContains? (list "badToken" "badVersion" "needHello" "dupHello" "badFrame") code)

fn route c: Cli frame: String -> Cli
  (let [(id (idOf frame))
        (kind (kindOf frame))
        (code (br/replyOf frame ":code"))]
    (cond
      ((and (= kind "pong") (= id "hb")) (with c :pingNs 0))
      ((and (= kind "ready") (= id "hello")) (with c :backoffMs c.baseMs))
      ((and (= kind "err") (or (= id "hello") (= id "?")))
        (if (fatalCode? code) (with c :fatal (str code ": " (br/replyOf frame ":msg"))) c))
      (else
        (with c :dupes (+ c.dupes (listCount (fn [(p Pend)] -> Bool (and (= p.id id) (and (not p.done) (dupeFrame? p frame)))) c.pend)) :pend (map (fn [(p Pend)] -> Pend
                             (if (and (= p.id id) (not p.done))
                               (keepFrame p frame id)
                               p))
                           c.pend)))))

fn ! flushOut! c: Cli -> Cli
  (if (or (< c.fd 0) (stringEmpty? c.out)) c
    (match (fdWrite c.fd (if (> (stringLength c.out) 65536) (optionOr (stringSlice c.out 0 65536) c.out) c.out))
      ((err _) c)
      ((ok n) (with c :out (optionOr (stringSlice c.out n (stringLength c.out)) "")))))

; (:m :ref RELAY-HEARTBEAT :do "a link that is silent for hbMs gets a (:ping :id hb); no pong within deadMs means the path is dead even though the socket looks open (a VPN that dropped, a tunnel whose far side is gone), so the client drops it and redials with backoff capped at capMs")
fn received c: Cli buf: String rx: Int64 -> Cli
  (with c :buf buf :lastRxNs rx)

fn routeAll c: Cli frames: (List String) -> Cli
  (fold route c frames)

fn queuePing c: Cli now: Int64 -> Cli
  (with c :pingNs now :out (str c.out "(:ping :id hb)\n"))

fn ! cliStep! c: Cli -> Cli
  (let [(now (monotonicNs))]
    (cond
      ((cliDone? c) c)
      ((< c.fd 0) (if (>= now c.nextNs) (dial! c now) c))
      (else
        (let [(c1 (flushOut! c))
              (rp (br/clientPoll! c1.fd c1.buf))
              (c2 (routeAll (received c1 rp.buf (if (listEmpty? rp.frames) c1.lastRxNs now)) rp.frames))]
          (cond
            ((cliDone? c2) c2)
            (rp.closed (drop! c2))
            ((and (> c2.pingNs 0) (> (- now c2.pingNs) (* c2.deadMs 1000000))) (drop! c2))
            ((and (= c2.pingNs 0) (> (- now c2.lastRxNs) (* c2.hbMs 1000000))) (queuePing c2 now))
            (else c2))))))

; (:m :ref RELAY-HEAL :do "while the link is down the caller's heal hook runs at most every 5s, so the transport under the relay (a tunnel today) is rebuilt by the client that needs it")
fn ! cliWait! c: Cli untilNs: Int64 heal: (fn [] -> Bool) -> Cli
  (cond
    ((cliDone? c) c)
    ((> (monotonicNs) untilNs) c)
    (else
      (let [(now (monotonicNs))
            (c1 (if (and (< c.fd 0) (> (- now c.healNs) 5000000000)) (do (heal) (with c :healNs now)) c))
            (_ (cond ((stringEmpty? c1.out) (if (>= c1.fd 0) (fdPoll (list (pair c1.fd 1)) 100) (do (sleepMs 50) (ok (list))))) (else (do (sleepMs 2) (ok (list))))))]
        (cliWait! (cliStep! c1) untilNs heal))))

; (:m :ref RELAY-RESUME :do "request! sends every frame and waits until each has its terminal frame or the deadline passes, reconnecting as often as the link breaks; a request that never got its terminal frame comes back without done, which the caller reports as not known to have run")
fn ! request! link: Link pend: (List Pend) waitMs: Int64 heal: (fn [] -> Bool) -> Cli
  (let [(c (cliWait! (cliNew link pend) (+ (monotonicNs) (* waitMs 1000000)) heal))
        (_ (if (>= c.fd 0) (ok? (fdClose c.fd)) false))]
    (with c :fd -1))

fn textOfStream frames: (List String) stream: String -> String
  (stringJoin (map (fn [(f String)] -> String (br/replyOf f ":text"))
                   (filter (fn [(f String)] -> Bool (and (= (kindOf f) "out") (= (br/replyOf f ":stream") stream))) frames))
              "")

fn replyOf c: Cli p: Pend -> Reply
  (let [(last (optionOr (listLast p.frames) ""))
        (kind (kindOf last))]
    (cond
      ((not (stringEmpty? c.fatal)) (Reply :exit -1 :verdict "fatal" :out "" :err c.fatal :code "fatal" :replayed false :connects c.connects))
      ((not p.done) (Reply :exit -1 :verdict "noAnswer" :out (textOfStream p.frames "out") :err "no terminal frame before the deadline; the request may or may not have run, and a retry with the same id is safe" :code "noAnswer" :replayed false :connects c.connects))
      ((= kind "err") (Reply :exit -1 :verdict "err" :out "" :err (br/replyOf last ":msg") :code (br/replyOf last ":code") :replayed false :connects c.connects))
      (else (Reply :exit (optionOr (stringToInt64 (br/replyOf last ":exit")) -1) :verdict (br/replyOf last ":verdict")
                   :out (textOfStream p.frames "out") :err (textOfStream p.frames "err") :code ""
                   :replayed (= (br/replyOf last ":replayed") "true") :connects c.connects))))

fn ! execVia! link: Link id: String unit: String argv: (List String) timeoutS: Int64 stdinB64: String waitMs: Int64 heal: (fn [] -> Bool) -> Reply
  (let [(pends (execPends id unit argv timeoutS stdinB64))
        (c (request! link pends waitMs heal))]
    (replyOf c (optionOr (listLast c.pend) (pendText id ""))))
