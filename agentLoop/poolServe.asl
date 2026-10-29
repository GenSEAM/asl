(module asl/agentLoop/poolServe
  :x [Serve newServe serveStep! serveWatch handleLine! validId? quotedAfter asnQuote receiptPath]
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

fn asnQuote text: String -> String
  (sp/asnQuote text)

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

fn ! handleLine! s: Serve line: String -> (Pair Serve String)
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
fn ! stepConn! s: Serve c: Conn ready: (List (Pair Int64 Int64)) -> Serve
  (if (not (ready? ready c.fd)) (withConns s (listAppend s.conns (list c)))
    (match (fdRead c.fd 65536)
      ((err _) (do (fdClose c.fd) s))
      ((ok chunk)
        (if (stringEmpty? chunk) (do (fdClose c.fd) s)
          (let [(buf (str c.buf chunk))]
            (match (stringIndexOf buf "\n")
              ((none) (if (> (stringLength buf) 262144) (do (fdClose c.fd) s) (withConns s (listAppend s.conns (list (Conn :fd c.fd :buf buf))))))
              ((some at)
                (let [(out (handleLine! s (optionOr (stringSlice buf 0 at) "")))]
                  (do (writeAll! c.fd (pairSecond out)) (fdClose c.fd) (pairFirst out))))))))))

fn ! drainDone! s: Serve -> Serve
  (let [(taken (sp/poolTakeDone s.pool))
        (_ (map (fn [(d (Pair String String))] -> Bool
                  (ok? (fileWrite (receiptPath s.receiptDir (pairFirst d)) (str "(:receipt :unit " (asnQuote (pairFirst d)) " :state \"done\" :result " (asnQuote (pairSecond d)) ")\n"))))
                (pairSecond taken)))]
    (withPool s (pairFirst taken)))

fn ! serveStep! s: Serve ready: (List (Pair Int64 Int64)) turn: (fn [String String] -> sp/Turn) now: Int64 -> Serve
  (let [(accepted (if (ready? ready s.listener)
                    (match (sockAccept s.listener)
                      ((ok fd) (withConns s (listAppend s.conns (list (Conn :fd fd :buf "")))))
                      ((err _) s))
                    s))
        (conned (fold (fn [(acc Serve) (c Conn)] -> Serve (stepConn! acc c ready)) (withConns accepted (list)) accepted.conns))
        (stepped (withPool conned (sp/poolStep! conned.pool ready turn now)))]
    (drainDone! stepped))
