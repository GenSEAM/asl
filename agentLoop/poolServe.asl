(module asl/agentLoop/poolServe
  :x [Serve newServe serveStep! serveStepG! receiptRow serveWatch handleLine! validId? quotedAfter asnQuote receiptPath]
  :i [(asl/agentLoop/sessionPool :a sp)])

; (:m :ref SE5-SERVE-ENTRY :do "the control face of one pool process: a unix socket taking one ASN line per connection and answering one line. (:submit :unit U :state S) queues a session (:queued / :refused), (:receipt :unit U) answers (:receipt :unit U :state running|done|unknown [:result R]), (:status) the counters, (:stop) ends serve. Finished sessions leave memory at once: their result is a file under receiptDir, so a pool of thousands of sessions holds none of them done in RAM and a restart still answers receipts")
(schema Conn
  (:f fd Int64)
  (:f buf String))

(schema Serve
  (:f listener Int64)
  (:f conns (List Conn))
  (:f pool sp/Pool)
  (:f receiptDir String)
  (:f stop Bool))

fn newServe listener: Int64 pool: sp/Pool receiptDir: String -> Serve
  (Serve :listener listener :conns (list) :pool pool :receiptDir receiptDir :stop false)

fn idByte b: Int64 -> Bool
  (or (and (>= b 48) (<= b 57)) (or (and (>= b 65) (<= b 90)) (or (and (>= b 97) (<= b 122)) (or (= b 45) (or (= b 46) (= b 95))))))

; (:m :ref SE5-SERVE-ENTRY :do "a unit id becomes a file name and a spill name: letters, digits, dot, dash and underscore, 1 to 96 bytes, no leading dot")
fn validId? id: String -> Bool
  (let [(bs (stringToBytes id))
        (n (bytesLength bs))]
    (and (and (> n 0) (<= n 96))
      (and (!= (bytesGet bs 0) 46)
        (listAll? (fn [(i Int64)] -> Bool (idByte (bytesGet bs i))) (range 0 n)))))

; (:m :ref POOL-FORM-MISSING-TASK :do "every control reply is one line: sessionPool.asnQuote writes a newline as a backslash and the newline itself, so a receipt :result with several lines was a several-line reply and the client, which reads to the first newline, cut it; here the newline is written as backslash n (the client's unquote reads both forms back)")
fn asnQuote text: String -> String
  (str "\"" (stringReplace (stringReplace (stringReplace text "\\" "\\\\") "\"" "\\\"") "\n" "\\n") "\"")

fn unquoteLoop s: String i: Int64 acc: (List String) -> (Option String)
  (if (>= i (stringLength s)) none
    (let [(c (optionOr (stringSlice s i (+ i 1)) ""))]
      (cond
        ((= c "\"") (some (stringJoin (listReverse acc) "")))
        ((= c "\\")
          (let [(d (optionOr (stringSlice s (+ i 1) (+ i 2)) ""))]
            (unquoteLoop s (+ i 2) (cons (if (= d "n") "\n" d) acc))))
        (else (unquoteLoop s (+ i 1) (cons c acc))))))

fn quotedAfter line: String key: String -> (Option String)
  (match (stringIndexOf line (str key " \""))
    ((none) none)
    ((some at) (unquoteLoop line (+ at (stringLength key) 2) (list))))

fn receiptPath dir: String id: String -> String
  (str dir "/" id ".asn")

fn reply form: String -> String
  (str form "\n")

; (:m :ref SE5A-SERVE-RUN :do "handleLine! threads the driver value d like the pool does and returns the next one; (:run :unit U :form F :repo R :root D) hands the run to the open hook, which returns the next d and, for a run that ended or was rejected before it started, its exit and receipt text, otherwise the run is submitted to the pool under its id; every other line is the old control form")
fn ! handleLine! s: Serve line: String d: T open: (fn [T String String String String] -> (Pair T (Option (Pair Int64 String)))) -> (Pair (Pair Serve T) String)
  (if (stringStartsWith? line "(:run ")
    (match (quotedAfter line ":unit")
      ((none) (pair (pair s d) (reply "(:refused :why \"no :unit\")")))
      ((some id)
        (cond
          ((not (validId? id)) (pair (pair s d) (reply (str "(:refused :unit " (asnQuote id) " :why \"bad id\")"))))
          ((or (sp/poolKnown? s.pool id) (fileExists? (receiptPath s.receiptDir id))) (pair (pair s d) (reply (str "(:refused :unit " (asnQuote id) " :why \"duplicate\")"))))
          (else (runOpened! s id d (open d id (optionOr (quotedAfter line ":form") "") (optionOr (quotedAfter line ":repo") "") (optionOr (quotedAfter line ":root") "")))))))
    (let [(r (handleOld! s line))]
      (pair (pair (pairFirst r) d) (pairSecond r))))

fn ! runOpened! s: Serve id: String d: T opened: (Pair T (Option (Pair Int64 String))) -> (Pair (Pair Serve T) String)
  (match (pairSecond opened)
    ((some ended)
      (do (fileWrite (receiptPath s.receiptDir id) (receiptRow id (pairFirst ended) (pairSecond ended)))
        (pair (pair s (pairFirst opened)) (reply (str "(:queued :unit " (asnQuote id) ")")))))
    ((none)
      (pair (pair (withPool s (sp/poolSubmit! s.pool id id (nowMs))) (pairFirst opened)) (reply (str "(:queued :unit " (asnQuote id) ")")))))

fn receiptRow id: String exit: Int64 text: String -> String
  (str "(:receipt :unit " (asnQuote id) " :state \"done\" :exit " (stringFromInt64 exit) " :result " (asnQuote text) ")\n")

fn ! handleOld! s: Serve line: String -> (Pair Serve String)
  (cond
    ((stringStartsWith? line "(:submit ")
      (match (quotedAfter line ":unit")
        ((none) (pair s (reply "(:refused :why \"no :unit\")")))
        ((some id)
          (cond
            ((not (validId? id)) (pair s (reply (str "(:refused :unit " (asnQuote id) " :why \"bad id\")"))))
            ((or (sp/poolKnown? s.pool id) (fileExists? (receiptPath s.receiptDir id))) (pair s (reply (str "(:refused :unit " (asnQuote id) " :why \"duplicate\")"))))
            (else
              (let [(state (optionOr (quotedAfter line ":state") ""))]
                (pair (withPool s (sp/poolSubmit! s.pool id state (nowMs))) (reply (str "(:queued :unit " (asnQuote id) ")")))))))))
    ((stringStartsWith? line "(:receipt ")
      (match (quotedAfter line ":unit")
        ((none) (pair s (reply "(:refused :why \"no :unit\")")))
        ((some id)
          (cond
            ((not (validId? id)) (pair s (reply (str "(:refused :unit " (asnQuote id) " :why \"bad id\")"))))
            ((fileExists? (receiptPath s.receiptDir id)) (pair s (reply (stringTrim (resultOr (fileReadString (receiptPath s.receiptDir id)) "")))))
            ((sp/poolKnown? s.pool id) (pair s (reply (str "(:receipt :unit " (asnQuote id) " :state \"running\")"))))
            (else (pair s (reply (str "(:receipt :unit " (asnQuote id) " :state \"unknown\")"))))))))
    ((stringStartsWith? line "(:status")
      (pair s (reply (str "(:pool :active " (stringFromInt64 (listLength s.pool.active)) " :execs " (stringFromInt64 (listLength s.pool.execs))
                          " :waiting " (stringFromInt64 (listLength s.pool.waiting)) " :spilled " (stringFromInt64 (sp/spilledCount s.pool))
                          " :peakMem " (stringFromInt64 s.pool.peakMem) " :slots " (stringFromInt64 s.pool.slots) ")"))))
    ((stringStartsWith? line "(:stop") (pair (withStop s) (reply "(:stopping)")))
    (else (pair s (reply "(:refused :why \"unknown form\")"))))

fn nowMs -> Int64
  (/ (monotonicNs) 1000000)

fn withPool s: Serve pool: sp/Pool -> Serve
  (with s :pool pool)

fn withStop s: Serve -> Serve
  (with s :stop true)

fn withConns s: Serve conns: (List Conn) -> Serve
  (with s :conns conns)

fn serveWatch s: Serve -> (List (Pair Int64 Int64))
  (cons (pair s.listener 1) (listAppend (map (fn [(c Conn)] -> (Pair Int64 Int64) (pair c.fd 1)) s.conns) (sp/poolWatch s.pool)))

fn ready? ready: (List (Pair Int64 Int64)) fd: Int64 -> Bool
  (listAny? (fn [(r (Pair Int64 Int64))] -> Bool (= (pairFirst r) fd)) ready)

fn ! writeAll! fd: Int64 data: String -> Bool
  (if (stringEmpty? data) true
    (match (fdWrite fd data)
      ((err _) false)
      ((ok n) (if (<= n 0) false (writeAll! fd (optionOr (stringSlice data n (stringLength data)) ""))))))

; (:m :ref SE5-SERVE-ENTRY :do "a control line is at most 256 KiB; a connection that sends more, or closes before a newline, is dropped without a reply, so one bad client cannot grow the pool process")
fn ! stepConn! s: Serve c: Conn ready: (List (Pair Int64 Int64)) d: T open: (fn [T String String String String] -> (Pair T (Option (Pair Int64 String)))) -> (Pair Serve T)
  (if (not (ready? ready c.fd)) (pair (withConns s (listAppend s.conns (list c))) d)
    (match (fdRead c.fd 65536)
      ((err _) (do (fdClose c.fd) (pair s d)))
      ((ok chunk)
        (if (stringEmpty? chunk) (do (fdClose c.fd) (pair s d))
          (let [(buf (str c.buf chunk))]
            (match (stringIndexOf buf "\n")
              ((none) (if (> (stringLength buf) 262144) (do (fdClose c.fd) (pair s d)) (pair (withConns s (listAppend s.conns (list (Conn :fd c.fd :buf buf)))) d)))
              ((some at)
                (let [(out (handleLine! s (optionOr (stringSlice buf 0 at) "") d open))]
                  (do (writeAll! c.fd (pairSecond out)) (fdClose c.fd) (pairFirst out))))))))))

fn ! drainDone! s: Serve d: T exitOf: (fn [T String] -> Int64) -> Serve
  (let [(taken (sp/poolTakeDone s.pool))
        (_ (map (fn [(x (Pair String String))] -> Bool
                  (ok? (fileWrite (receiptPath s.receiptDir (pairFirst x)) (receiptRow (pairFirst x) (exitOf d (pairFirst x)) (pairSecond x)))))
                (pairSecond taken)))]
    (withPool s (pairFirst taken)))

; (:m :ref SE5A-SERVE-RUN :do "serveStepG! is serveStep! with the driver value: the turn function, the open hook for (:run ...) and the exit lookup for receipts all take and return it; serveStep! keeps its signature with an unused value")
fn ! serveStepG! s: Serve ready: (List (Pair Int64 Int64)) turn: (fn [T String String] -> (Pair T sp/Turn)) d: T open: (fn [T String String String String] -> (Pair T (Option (Pair Int64 String)))) exitOf: (fn [T String] -> Int64) now: Int64 -> (Pair Serve T)
  (let [(accepted (if (ready? ready s.listener)
                    (match (sockAccept s.listener)
                      ((ok fd) (withConns s (listAppend s.conns (list (Conn :fd fd :buf "")))))
                      ((err _) s))
                    s))
        (conned (fold (fn [(acc (Pair Serve T)) (c Conn)] -> (Pair Serve T) (stepConn! (pairFirst acc) c ready (pairSecond acc) open)) (pair (withConns accepted (list)) d) accepted.conns))
        (stepped (sp/poolStepG! (pairFirst conned).pool ready turn (pairSecond conned) now))]
    (pair (drainDone! (withPool (pairFirst conned) (pairFirst stepped)) (pairSecond stepped) exitOf) (pairSecond stepped)))

fn ! serveStep! s: Serve ready: (List (Pair Int64 Int64)) turn: (fn [String String] -> sp/Turn) now: Int64 -> Serve
  (pairFirst (serveStepG! s ready (fn [(u Int64) (st String) (rp String)] -> (Pair Int64 sp/Turn) (pair u (turn st rp))) 0
    (fn [(u Int64) (a String) (b String) (c String) (e String)] -> (Pair Int64 (Option (Pair Int64 String))) (pair u none))
    (fn [(u Int64) (i String)] -> Int64 0) now))
