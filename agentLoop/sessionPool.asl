(module asl/agentLoop/sessionPool
  :x [Sess Pool Turn Exec asnQuote newPool poolSubmit! poolStep! poolWatch poolIdle? poolDone poolTakeDone poolKnown? pickNext poolMemCount spilledCount httpRequest execReply]
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
  (:f result (Option String)))

(schema Sess
  (:f id String)
  (:f state String)
  (:f request String)
  (:f fd Int64)
  (:f buf String)
  (:f lastMs Int64)
  (:f tries Int64)
  (:f holdMs Int64)
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

fn httpRequest id: String body: String -> String
  (str "POST /v1/chat/completions HTTP/1.1\r\nHost: hub\r\nContent-Type: application/json\r\nX-Asl-Unit: " id "\r\nContent-Length: "
       (stringFromInt64 (stringLength body)) "\r\n\r\n" body)

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
      (match (fileWrite path (str s.request "\n" s.state))
        ((ok _) (with s :state "" :request "" :spill path))
        ((err _) s))))

fn ! unspill! s: Sess -> Sess
  (if (stringEmpty? s.spill) s
    (let [(text (resultOr (fileReadString s.spill) ""))
          (cut (optionOr (stringIndexOf text "\n") 0))
          (back (with s :request (optionOr (stringSlice text 0 cut) "") :state (optionOr (stringSlice text (+ cut 1) (stringLength text)) "") :spill ""))]
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

fn ! settle! p: Pool s: Sess t: Turn turn: (fn [String String] -> Turn) now: Int64 -> Pool
  (match t.result
    ((some r) (with p :done (listAppend p.done (list (pair s.id r)))))
    ((none)
      (match t.exec
        ((some x) (startExec! p (with s :state t.state) x turn now))
        ((none)
          (match t.request
            ((some body) (with p :waiting (listAppend p.waiting (list (with s :state t.state :request body :fd -1 :buf "" :lastMs now :tries 0 :holdMs 0)))))
            ((none) (with p :done (listAppend p.done (list (pair s.id "(:err \"turn gave neither request nor result\")"))))))))))

fn asnQuote text: String -> String
  (str "\"" (stringReplace (stringReplace (stringReplace text "\\" "\\\\") "\"" "\\\"") "\n" "\\n") "\"")

fn execReply o: fr/ProcOut -> String
  (str "(:exec :exit " (stringFromInt64 o.exitCode) " :out " (asnQuote o.stdout) " :err " (asnQuote o.stderr) ")")

fn ! startExec! p: Pool s: Sess x: Exec turn: (fn [String String] -> Turn) now: Int64 -> Pool
  (match (fr/guardStart! x.argv x.cwd x.env (fr/limits (max 1 x.timeoutS) (max 0 x.maxDesc)))
    ((err d) (settle! p s (turn s.state (execReply d)) turn now))
    ((ok g) (with p :execs (listAppend p.execs (list (with s :guard (some g)))))))

fn ! advanceExec! p: Pool s: Sess turn: (fn [String String] -> Turn) now: Int64 -> Pool
  (match s.guard
    ((none) p)
    ((some g)
      (let [(step (fr/guardAdvance! g))]
        (match step.out
          ((some o) (settle! p (with s :guard none) (turn s.state (execReply o)) turn now))
          ((none) (with p :execs (listAppend p.execs (list (with s :guard (some step.guard))))))))))

fn connected s: Sess fd: Int64 -> Sess
  (with s :fd fd :buf "")

fn ! launch! p: Pool s: Sess turn: (fn [String String] -> Turn) now: Int64 -> Pool
  (let [(live (unspill! s))]
    (if (stringEmpty? live.request)
      (settle! p live (turn live.state "") turn now)
      (match (unixConnect p.sock)
        ((err e) (retry! p live now))
        ((ok fd)
          (if (writeAll! fd (httpRequest live.id live.request))
            (with p :active (listAppend p.active (list (connected live fd))))
            (do (fdClose fd) (retry! p live now)))))))

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

fn ! readOne! p: Pool s: Sess ready: (List (Pair Int64 Int64)) turn: (fn [String String] -> Turn) now: Int64 -> Pool
  (if (not (ready? ready s.fd)) (with p :active (listAppend p.active (list s)))
    (match (fdRead s.fd 65536)
      ((err _) (do (fdClose s.fd) (retry! p s now)))
      ((ok chunk)
        (if (stringEmpty? chunk) (do (fdClose s.fd) (retry! p s now))
          (let [(raw (str s.buf chunk))]
            (match (bodyOf raw)
              ((none) (with p :active (listAppend p.active (list (with s :buf raw)))))
              ((some body) (do (fdClose s.fd) (settle! p s (turn s.state body) turn now)))))))))

fn ! admit! p: Pool turn: (fn [String String] -> Turn) now: Int64 -> Pool
  (if (>= (listLength p.active) p.slots) p
    (match (pickNext p.waiting now p.ttlMs)
      ((none) p)
      ((some s)
        (admit! (launch! (with p :waiting (filter (fn [(w Sess)] -> Bool (!= w.id s.id)) p.waiting)) s turn now) turn now))))

fn clearExecs p: Pool -> Pool
  (with p :execs (list))

fn ! poolStep! p: Pool ready: (List (Pair Int64 Int64)) turn: (fn [String String] -> Turn) now: Int64 -> Pool
  (let [(reading0 (fold (fn [(acc Pool) (s Sess)] -> Pool (readOne! acc s ready turn now)) (with p :active (list)) p.active))
        (reading (fold (fn [(acc Pool) (s Sess)] -> Pool (advanceExec! acc s turn now)) (clearExecs reading0) reading0.execs))
        (admitted (admit! reading turn now))]
    (notePeaks (enforceCap! admitted now)))
