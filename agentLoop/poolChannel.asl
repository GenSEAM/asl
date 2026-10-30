(module asl/agentLoop/poolChannel
  :x [PoolMsg maxBodyBytes maxAsks maxWaitMs asnForm? inboxDir outboxDir openChannel! msgLine parseMsg ask! asks! answer! route!]
  :i [(asl/agentLoop/core :a c)])

; (:m :ref LEON-POOL-WIRE :do "ask/answer between pool tasks over the pool's scratch dir: a task drops one ASN line in the outbox, the pool's reactor (one thread, the only router) moves an ask to a running peer's inbox and an answer back to the asker's, or answers an ask itself with an error; bodies are single ASN forms of at most maxBodyBytes, a task may ask at most maxAsks times and waits at most maxWaitMs for an answer")
(schema PoolMsg
  (:f kind String)
  (:f id String)
  (:f from Int64)
  (:f to Int64)
  (:f error String)
  (:f body String))

fn maxBodyBytes -> Int64
  4096

fn maxAsks -> Int64
  32

fn maxWaitMs -> Int64
  120000

fn formEnd cs: (List String) i: Int64 depth: Int64 inStr: Bool esc: Bool -> Int64
  (match (listGet cs i)
    ((none) -1)
    ((some ch)
      (cond
        (esc (formEnd cs (+ i 1) depth inStr false))
        ((and inStr (= ch "\\")) (formEnd cs (+ i 1) depth true true))
        ((= ch "\"") (formEnd cs (+ i 1) depth (not inStr) false))
        (inStr (formEnd cs (+ i 1) depth true false))
        ((= ch "(") (formEnd cs (+ i 1) (+ depth 1) false false))
        ((= ch ")") (if (= depth 1) i (formEnd cs (+ i 1) (- depth 1) false false)))
        (else (formEnd cs (+ i 1) depth false false)))))

fn asnForm? s: String -> Bool
  (let [(cs (stringChars s))]
    (and (not (stringContains? s "\n"))
         (and (stringStartsWith? s "(")
              (= (formEnd cs 0 0 false false) (- (listLength cs) 1)))))

fn inboxDir dir: String idx: Int64 -> String
  (str dir "/" (stringFromInt64 idx) ".inbox")

fn outboxDir dir: String -> String
  (str dir "/out")

fn ! openChannel! dir: String idxs: (List Int64) -> Bool
  (and (ok? (dirCreate (outboxDir dir)))
       (listAll? (fn [(i Int64)] -> Bool (ok? (dirCreate (inboxDir dir i)))) idxs))

fn msgLine m: PoolMsg -> String
  (str "(:" m.kind " :id " m.id " :from " (stringFromInt64 m.from) " :to " (stringFromInt64 m.to)
       (if (stringEmpty? m.error) "" (str " :error " m.error))
       " :body " (if (stringEmpty? m.body) "()" m.body) ")")

fn wordAfter s: String key: String -> String
  (match (stringIndexOf s key)
    ((none) "")
    ((some i) (let [(rest (c/sliceOf s (+ i (stringLength key)) (stringLength s)))]
                (c/sliceOf rest 0 (optionOr (stringIndexOf rest " ") (stringLength rest))))))

fn parseMsg line: String -> (Option PoolMsg)
  (let [(s (stringTrim line))]
    (match (stringIndexOf s " :body ")
      ((none) none)
      ((some b)
        (let [(head (c/sliceOf s 0 b))
              (body (c/sliceOf s (+ b 7) (- (stringLength s) 1)))
              (kind (wordAfter head "(:"))
              (from (stringToInt64 (wordAfter head " :from ")))
              (to (stringToInt64 (wordAfter head " :to ")))]
          (if (and (stringEndsWith? s ")") (and (or (= kind "ask") (= kind "answer")) (and (some? from) (some? to))))
            (some (PoolMsg :kind kind :id (wordAfter head " :id ") :from (optionOr from -1) :to (optionOr to -1)
                           :error (wordAfter head " :error ") :body (if (= body "()") "" body)))
            none)))))

fn ! put! path: String line: String -> Bool
  (and (ok? (fileWrite (str path ".tmp") (str line "\n"))) (ok? (pathRename (str path ".tmp") path)))

fn bodyError body: String -> String
  (cond
    ((> (stringLength body) (maxBodyBytes)) "ERR_ASK_TOO_LARGE")
    ((not (asnForm? body)) "ERR_ASK_NOT_ASN")
    (else ""))

fn ! awaitAnswer! path: String deadline: Int64 -> (Result String String)
  (match (fileReadString path)
    ((ok text)
      (let [(_ (pathRemove path))]
        (match (parseMsg text)
          ((none) (err "ERR_ASK_MALFORMED"))
          ((some m) (if (stringEmpty? m.error) (ok m.body) (err m.error))))))
    ((err _) (if (> (monotonicNs) deadline) (err "ERR_ASK_TIMEOUT") (do (sleepMs 20) (awaitAnswer! path deadline)))))

; (:m :ref LEON-POOL-WIRE :do "called from inside a task's child: blocks this task only, at most waitMs (clamped to 1..maxWaitMs), and returns the peer's ASN answer or an ERR_ code")
fn ! ask! dir: String from: Int64 to: Int64 body: String waitMs: Int64 -> (Result String String)
  (let [(bad (bodyError body))]
    (if (not (stringEmpty? bad))
      (err bad)
      (let [(id (str (stringFromInt64 from) "x" (stringFromInt64 (monotonicNs))))
            (sent (put! (str (outboxDir dir) "/" id ".ask.msg") (msgLine (PoolMsg :kind "ask" :id id :from from :to to :error "" :body body))))
            (deadline (+ (monotonicNs) (* 1000000 (max 1 (min waitMs (maxWaitMs))))))]
        (if sent (awaitAnswer! (str (inboxDir dir from) "/answer-" id ".msg") deadline) (err "ERR_ASK_SEND")))))

fn ! asks! dir: String idx: Int64 -> (List PoolMsg)
  (let [(inbox (inboxDir dir idx))
        (names (filter (fn [(n String)] -> Bool (and (stringStartsWith? n "ask-") (stringEndsWith? n ".msg"))) (resultOr (dirList inbox) (list))))]
    (fold (fn [(acc (List PoolMsg)) (n String)] -> (List PoolMsg)
            (let [(path (str inbox "/" n))
                  (text (resultOr (fileReadString path) ""))
                  (_ (pathRemove path))]
              (match (parseMsg text) ((some m) (listAppend acc (list m))) ((none) acc))))
          (list) (listSort names)))

fn ! answer! dir: String idx: Int64 q: PoolMsg body: String -> (Result Bool String)
  (let [(bad (bodyError body))]
    (cond
      ((not (stringEmpty? bad)) (err bad))
      ((put! (str (outboxDir dir) "/" q.id ".answer.msg") (msgLine (PoolMsg :kind "answer" :id q.id :from idx :to q.from :error "" :body body))) (ok true))
      (else (err "ERR_ASK_SEND"))))

fn ! refuse! dir: String m: PoolMsg code: String -> Bool
  (put! (str (inboxDir dir m.from) "/answer-" m.id ".msg") (msgLine (PoolMsg :kind "answer" :id m.id :from -1 :to m.from :error code :body "")))

fn laneOf xs: (List (Pair Int64 Int64)) idx: Int64 -> (Option Int64)
  (match (listHead (filter (fn [(p (Pair Int64 Int64))] -> Bool (= (pairFirst p) idx)) xs))
    ((some p) (some (pairSecond p)))
    ((none) none))

; (:m :ref LEON-POOL-WAIT-DEADLOCK :do "an ask to a task still queued in another lane stays in the outbox until that task starts, bounded by the asker's own wait; an ask to a task queued behind the asker in its own lane could only start after the asker ends, so it is refused at once with ERR_PEER_QUEUED_BEHIND; a held ask whose asker has ended is dropped")
fn ! routeOne! dir: String live: (List (Pair Int64 Int64)) queued: (List (Pair Int64 Int64)) counts: (Map Int64 Int64) name: String -> (Map Int64 Int64)
  (let [(path (str (outboxDir dir) "/" name))
        (msg (parseMsg (resultOr (fileReadString path) "")))
        (sent (optionOr (match msg ((some m) (mapGet counts m.from)) ((none) none)) 0))
        (liveIdx (map pairFirst live))]
    (match msg
      ((none) (do (pathRemove path) counts))
      ((some m)
        (cond
          ((= m.kind "answer")
            (do (if (listContains? liveIdx m.to)
                  (pathRename path (str (inboxDir dir m.to) "/answer-" m.id ".msg"))
                  (pathRemove path))
                counts))
          ((not (listContains? liveIdx m.from)) (do (pathRemove path) counts))
          ((>= sent (maxAsks)) (do (refuse! dir m "ERR_ASK_LIMIT") (pathRemove path) counts))
          ((and (!= m.to m.from) (listContains? liveIdx m.to))
            (do (pathRename path (str (inboxDir dir m.to) "/ask-" m.id ".msg")) (mapSet counts m.from (+ sent 1))))
          ((and (some? (laneOf queued m.to)) (= (laneOf queued m.to) (laneOf live m.from)))
            (do (refuse! dir m "ERR_PEER_QUEUED_BEHIND") (pathRemove path) (mapSet counts m.from (+ sent 1))))
          ((some? (laneOf queued m.to)) counts)
          (else (do (refuse! dir m "ERR_PEER_NOT_RUNNING") (pathRemove path) (mapSet counts m.from (+ sent 1))))))))

; (:m :ref LEON-POOL-WIRE :do "the router runs in the pool's reactor between polls; live and queued pair each running or not yet started task index with its lane, counts holds the asks each task has had routed so far")
fn ! route! dir: String live: (List (Pair Int64 Int64)) queued: (List (Pair Int64 Int64)) counts: (Map Int64 Int64) -> (Map Int64 Int64)
  (fold (fn [(acc (Map Int64 Int64)) (n String)] -> (Map Int64 Int64) (routeOne! dir live queued acc n))
        counts
        (listSort (filter (fn [(n String)] -> Bool (stringEndsWith? n ".msg")) (resultOr (dirList (outboxDir dir)) (list)))))
