(module asl/agentLoop/sessionPool
  :x [Sess Pool Turn Exec asnQuote newPool poolSubmit! poolStep! poolStepG! poolWatch poolIdle? poolDone poolTakeDone poolKnown? pickNext poolMemCount spilledCount httpRequest execReply]
  :i [(asl-tools/fleet/run :a fr)])

; (:m :ref POOL-SERVE :do "one process, many sessions: a session is a state string plus the request its next turn sends to the hub socket. At most slots requests are in flight, every other session waits parked in memory and, past memCap, spilled to a file under spillDir. A turn function turns (state, reply) into the next state and either the next request body or the final result, so no turn blocks the reactor and the hub's bucket parking is what meters the rate")
; (:m :ref SE4-ASYNC-EXEC :do "a turn may also ask for a local process (a gate, a tool): it runs through fr/guardStart! with a timeout and a descendant limit and is advanced by poolStep! without waiting, so a long gate holds no hub slot and stalls no other session; the turn function then gets (:exec :exit N :out Q :err Q) as its reply")
(schema Exec
  (:f argv (List String))
  (:f cwd String)
  (:f env (List String))
  (:f timeoutS Int64)
  (:f maxDesc Int64))

(schema Turn
  (:f state String)
  (:f request (Option String))
  (:f exec (Option Exec))
  (:f result (Option String))
  (:f headers (List (Pair String String)) :default (list))
  (:f busy Bool :default false))

(schema Sess
  (:f id String)
  (:f state String)
  (:f request String)
  (:f fd Int64)
  (:f buf String)
  (:f lastMs Int64)
  (:f tries Int64)
  (:f holdMs Int64)
  (:f busyN Int64 :default 0)
  (:f guard (Option fr/Guarded))
  (:f spill String))

(schema Pool
  (:f sock String)
  (:f slots Int64)
  (:f memCap Int64)
  (:f ttlMs Int64)
  (:f spillDir String)
  (:f active (List Sess))
  (:f execs (List Sess))
  (:f waiting (List Sess))
  (:f done (List (Pair String String)))
  (:f peakMem Int64)
  (:f peakSpilled Int64))

fn newPool sock: String slots: Int64 memCap: Int64 ttlMs: Int64 spillDir: String -> Pool
  (Pool :sock sock :slots (max 1 slots) :memCap (max 0 memCap) :ttlMs (max 0 ttlMs) :spillDir spillDir
        :active (list) :execs (list) :waiting (list) :done (list) :peakMem 0 :peakSpilled 0)

fn poolDone p: Pool -> (List (Pair String String))
  p.done

fn poolTakeDone p: Pool -> (Pair Pool (List (Pair String String)))
  (pair (with p :done (list)) p.done)

fn poolKnown? p: Pool id: String -> Bool
  (listAny? (fn [(s Sess)] -> Bool (= s.id id)) (listAppend p.active (listAppend p.execs p.waiting)))

fn poolMemCount p: Pool -> Int64
  (listLength (filter (fn [(s Sess)] -> Bool (stringEmpty? s.spill)) p.waiting))

fn spilledCount p: Pool -> Int64
  (listLength (filter (fn [(s Sess)] -> Bool (not (stringEmpty? s.spill))) p.waiting))

fn poolIdle? p: Pool -> Bool
  (and (listEmpty? p.active) (and (listEmpty? p.execs) (listEmpty? p.waiting)))

; (:m :ref SE3-POOL-DRIVER :do "the request text is built once, when the turn is settled, from the turn's own headers (the hub class, the session, the consumer a provider ask carries), with the framing headers set here and X-Asl-Unit added only when the turn did not name one; a spilled session therefore carries its complete request")
fn framing? name: String -> Bool
  (let [(n (stringLower name))]
    (or (= n "content-length") (or (= n "content-type") (= n "host"))))

fn httpRequest id: String body: String headers: (List (Pair String String)) -> String
  (let [(own (filter (fn [(h (Pair String String))] -> Bool (not (framing? (pairFirst h)))) headers))
        (unit (if (listAny? (fn [(h (Pair String String))] -> Bool (= (stringLower (pairFirst h)) "x-asl-unit")) own) (list) (list (pair "X-Asl-Unit" id))))
        (lines (map (fn [(h (Pair String String))] -> String (str (pairFirst h) ": " (pairSecond h) "\r\n")) (listAppend unit own)))]
    (str "POST /v1/chat/completions HTTP/1.1\r\nHost: hub\r\nContent-Type: application/json\r\n" (stringJoin lines "")
         "Content-Length: " (stringFromInt64 (stringLength body)) "\r\n\r\n" body))

; (:m :ref POOL-IDLE-SESSIONS :do "warm first: a session whose last call is younger than the provider cache ttl resumes before a cold one, and among warm ones the oldest first because its cache expires soonest; cold sessions go in the order they went idle")
fn warm? s: Sess now: Int64 ttlMs: Int64 -> Bool
  (and (> s.lastMs 0) (< (- now s.lastMs) ttlMs))

fn olderOf a: Sess b: Sess -> Sess
  (if (<= a.lastMs b.lastMs) a b)

fn pickNext all: (List Sess) now: Int64 ttlMs: Int64 -> (Option Sess)
  (let [(waiting (filter (fn [(s Sess)] -> Bool (<= s.holdMs now)) all))
        (warmOnes (filter (fn [(s Sess)] -> Bool (warm? s now ttlMs)) waiting))
        (pool (if (listEmpty? warmOnes) waiting warmOnes))]
    (match (listHead pool)
      ((none) none)
      ((some first) (some (fold (fn [(acc Sess) (s Sess)] -> Sess (olderOf acc s)) first pool)))))

fn contentLength head: String -> Int64
  (fold (fn [(acc Int64) (line String)] -> Int64
          (if (stringStartsWith? (stringLower line) "content-length:")
            (optionOr (stringToInt64 (stringTrim (optionOr (stringSlice line 15 (stringLength line)) ""))) acc) acc))
    0 (stringSplit head "\r\n"))

fn bodyOf raw: String -> (Option String)
  (match (stringIndexOf raw "\r\n\r\n")
    ((none) none)
    ((some end)
      (let [(body (optionOr (stringSlice raw (+ end 4) (stringLength raw)) ""))]
        (if (>= (stringLength body) (contentLength (optionOr (stringSlice raw 0 end) ""))) (some body) none))))

fn ! writeAll! fd: Int64 data: String -> Bool
  (if (stringEmpty? data) true
    (match (fdWrite fd data)
      ((err _) false)
      ((ok n) (if (<= n 0) false (writeAll! fd (optionOr (stringSlice data n (stringLength data)) ""))))))

fn spillPath p: Pool id: String -> String
  (str p.spillDir "/" id ".state")

fn ! spillOne! p: Pool s: Sess -> Sess
  (if (not (stringEmpty? s.spill)) s
    (let [(path (spillPath p s.id))]
      (match (fileWrite path (str (stringFromInt64 (stringLength s.request)) "\n" s.request s.state))
        ((ok _) (with s :state "" :request "" :spill path))
        ((err _) s))))

fn ! unspill! s: Sess -> Sess
  (if (stringEmpty? s.spill) s
    (let [(text (resultOr (fileReadString s.spill) ""))
          (nl (optionOr (stringIndexOf text "\n") 0))
          (rlen (optionOr (stringToInt64 (optionOr (stringSlice text 0 nl) "0")) 0))
          (back (with s :request (optionOr (stringSlice text (+ nl 1) (+ nl 1 rlen)) "") :state (optionOr (stringSlice text (+ nl 1 rlen) (stringLength text)) "") :spill ""))]
      (do (pathRemove s.spill) back)))

fn ! enforceCap! p: Pool now: Int64 -> Pool
  (let [(mem (filter (fn [(s Sess)] -> Bool (stringEmpty? s.spill)) p.waiting))
        (over (- (listLength mem) p.memCap))]
    (if (<= over 0) p
      (let [(victims (listTake (listSortBy (fn [(s Sess)] -> Int64 s.lastMs) mem) over))
            (ids (map (fn [(s Sess)] -> String s.id) victims))
            (next (map (fn [(s Sess)] -> Sess (if (listContains? ids s.id) (spillOne! p s) s)) p.waiting))]
        (with p :waiting next))))

fn notePeaks p: Pool -> Pool
  (with p :peakMem (max p.peakMem (poolMemCount p)) :peakSpilled (max p.peakSpilled (spilledCount p)))

; (:m :ref POOL-SERVE :do "a submitted session enters waiting with an empty request: its first turn function call, with an empty reply, is what produces its first request, and it is made at admission so a session that finishes at once never holds a slot")
fn ! poolSubmit! p: Pool id: String state: String now: Int64 -> Pool
  (notePeaks (enforceCap! (with p :waiting (listAppend p.waiting (list (Sess :id id :state state :request "" :fd -1 :buf "" :lastMs 0 :tries 0 :holdMs 0 :guard none :spill "")))) now))

; (:m :ref SE3-POOL-DRIVER :do "every step that calls the turn function threads one caller value d through it and returns it: a driver keeps its typed sessions there (a Leon run is not a string), the pool keeps ids, sockets and queues. The turn function returns the next d with the Turn; poolStep! is the same machinery with d unused")
fn ! settle! p: Pool s: Sess t: Turn turn: (fn [T String String] -> (Pair T Turn)) d: T now: Int64 -> (Pair Pool T)
  (match t.result
    ((some r) (pair (with p :done (listAppend p.done (list (pair s.id r)))) d))
    ((none)
      (match t.exec
        ((some x) (startExec! p (with s :state t.state) x turn d now))
        ((none)
          (match t.request
            ((some body) (pair (with p :waiting (listAppend p.waiting (list (with s :state t.state :request (httpRequest s.id body t.headers) :fd -1 :buf "" :lastMs now :tries 0 :holdMs 0 :busyN 0)))) d))
            ((none)
              (if t.busy
                (parkBusy p (with s :state t.state) d now)
                (pair (with p :done (listAppend p.done (list (pair s.id "(:err \"turn gave neither request nor result\")")))) d))))))))

; (:m :ref SE3-POOL-DRIVER :do "a hub 503 is a wait, not a failure: the same request goes back to waiting for one second, without using up its three connection tries, and the session is given up on after 120 such waits")
fn ! parkBusy p: Pool s: Sess d: T now: Int64 -> (Pair Pool T)
  (if (>= s.busyN 120)
    (pair (with p :done (listAppend p.done (list (pair s.id "(:err \"hub busy for 120 s\")")))) d)
    (pair (with p :waiting (listAppend p.waiting (list (with s :fd -1 :buf "" :holdMs (+ now 1000) :busyN (+ s.busyN 1))))) d))

fn asnQuote text: String -> String
  (str "\"" (stringReplace (stringReplace (stringReplace text "\\" "\\\\") "\"" "\\\"") "\n" "\\n") "\"")

fn execReply o: fr/ProcOut -> String
  (str "(:exec :exit " (stringFromInt64 o.exitCode) " :out " (asnQuote o.stdout) " :err " (asnQuote o.stderr) ")")

fn ! startExec! p: Pool s: Sess x: Exec turn: (fn [T String String] -> (Pair T Turn)) d: T now: Int64 -> (Pair Pool T)
  (match (fr/guardStart! x.argv x.cwd x.env (fr/limits (max 1 x.timeoutS) (max 0 x.maxDesc)))
    ((err o) (let [(r (turn d s.state (execReply o)))] (settle! p s (pairSecond r) turn (pairFirst r) now)))
    ((ok g) (pair (with p :execs (listAppend p.execs (list (with s :guard (some g))))) d)))

fn ! advanceExec! p: Pool s: Sess turn: (fn [T String String] -> (Pair T Turn)) d: T now: Int64 -> (Pair Pool T)
  (match s.guard
    ((none) (pair p d))
    ((some g)
      (let [(step (fr/guardAdvance! g))]
        (match step.out
          ((some o) (let [(r (turn d s.state (execReply o)))] (settle! p (with s :guard none) (pairSecond r) turn (pairFirst r) now)))
          ((none) (pair (with p :execs (listAppend p.execs (list (with s :guard (some step.guard))))) d))))))

fn connected s: Sess fd: Int64 -> Sess
  (with s :fd fd :buf "")

fn ! launch! p: Pool s: Sess turn: (fn [T String String] -> (Pair T Turn)) d: T now: Int64 -> (Pair Pool T)
  (let [(live (unspill! s))]
    (if (stringEmpty? live.request)
      (let [(r (turn d live.state ""))] (settle! p live (pairSecond r) turn (pairFirst r) now))
      (match (unixConnect p.sock)
        ((err e) (pair (retry! p live now) d))
        ((ok fd)
          (if (writeAll! fd live.request)
            (pair (with p :active (listAppend p.active (list (connected live fd)))) d)
            (do (fdClose fd) (pair (retry! p live now) d)))))))

; (:m :ref POOL-SERVE :do "a refused or dropped hub connection is not the session's failure: it goes back to waiting with the same request and is given up on after three tries, so a hub restart costs a pause, not the sessions")
fn ! retry! p: Pool s: Sess now: Int64 -> Pool
  (if (>= s.tries 3)
    (with p :done (listAppend p.done (list (pair s.id "(:err \"hub unreachable\")"))))
    (with p :waiting (listAppend p.waiting (list (with s :fd -1 :buf "" :tries (+ s.tries 1) :holdMs (+ now (* 100 (+ s.tries 1))))))))

fn poolWatch p: Pool -> (List (Pair Int64 Int64))
  (listAppend (map (fn [(s Sess)] -> (Pair Int64 Int64) (pair s.fd 1)) p.active)
    (listFlatMap (fn [(s Sess)] -> (List (Pair Int64 Int64)) (match s.guard ((some g) (fr/guardFds g)) ((none) (list)))) p.execs))

fn ready? ready: (List (Pair Int64 Int64)) fd: Int64 -> Bool
  (listAny? (fn [(r (Pair Int64 Int64))] -> Bool (= (pairFirst r) fd)) ready)

fn ! readOne! p: Pool s: Sess ready: (List (Pair Int64 Int64)) turn: (fn [T String String] -> (Pair T Turn)) d: T now: Int64 -> (Pair Pool T)
  (if (not (ready? ready s.fd)) (pair (with p :active (listAppend p.active (list s))) d)
    (match (fdRead s.fd 65536)
      ((err _) (do (fdClose s.fd) (pair (retry! p s now) d)))
      ((ok chunk)
        (if (stringEmpty? chunk) (do (fdClose s.fd) (pair (retry! p s now) d))
          (let [(raw (str s.buf chunk))]
            (match (bodyOf raw)
              ((none) (pair (with p :active (listAppend p.active (list (with s :buf raw)))) d))
              ((some _) (do (fdClose s.fd) (let [(r (turn d s.state raw))] (settle! p s (pairSecond r) turn (pairFirst r) now))))))))))

fn ! admit! p: Pool turn: (fn [T String String] -> (Pair T Turn)) d: T now: Int64 -> (Pair Pool T)
  (if (>= (listLength p.active) p.slots) (pair p d)
    (match (pickNext p.waiting now p.ttlMs)
      ((none) (pair p d))
      ((some s)
        (let [(r (launch! (with p :waiting (filter (fn [(w Sess)] -> Bool (!= w.id s.id)) p.waiting)) s turn d now))]
          (admit! (pairFirst r) turn (pairSecond r) now)))))

fn clearExecs p: Pool -> Pool
  (with p :execs (list))

fn ! poolStepG! p: Pool ready: (List (Pair Int64 Int64)) turn: (fn [T String String] -> (Pair T Turn)) d: T now: Int64 -> (Pair Pool T)
  (let [(reading0 (fold (fn [(acc (Pair Pool T)) (s Sess)] -> (Pair Pool T) (readOne! (pairFirst acc) s ready turn (pairSecond acc) now)) (pair (with p :active (list)) d) p.active))
        (reading (fold (fn [(acc (Pair Pool T)) (s Sess)] -> (Pair Pool T) (advanceExec! (pairFirst acc) s turn (pairSecond acc) now)) (pair (clearExecs (pairFirst reading0)) (pairSecond reading0)) (pairFirst reading0).execs))
        (admitted (admit! (pairFirst reading) turn (pairSecond reading) now))]
    (pair (notePeaks (enforceCap! (pairFirst admitted) now)) (pairSecond admitted)))

fn ! poolStep! p: Pool ready: (List (Pair Int64 Int64)) turn: (fn [String String] -> Turn) now: Int64 -> Pool
  (pairFirst (poolStepG! p ready (fn [(u Int64) (st String) (rp String)] -> (Pair Int64 Turn) (pair u (turn st rp))) 0 now))
