(module aslGateway/admission
  :x [concurrency429After! holdUntil! Lane laneInit parseLane renderLane parseLeases renderLeases baseOf maxCapOf laneCap effectiveLimits
      dropOnConcurrency429 dropGuardMs raiseOnSuccess tryAdmit growStreak growQuietMs
      admitShared! releaseShared! concurrency429! admissionDir]
  :i [(aslGateway/config :a c)
      (aslGateway/limits :a lim)
      (aslGateway/usage :a g)])

; (:m :ref GW-ADAPTIVE-ADMISSION :do "one lane is one provider and alias; its cap starts at the covering :concurrency row, halves to max(1, inFlight/2) on an upstream 429 that names concurrency, and rises by 1 after growStreak successes with no such 429 for growQuietMs, up to the row's :max (default twice the row). cap 0 means not yet learned. Adopted: 20 successes, 600 s")
(schema Lane
  (:f cap Int64)
  (:f ok Int64)
  (:f last429 Int64))

fn growStreak -> Int64
  20

fn growQuietMs -> Int64
  600000

fn laneInit -> Lane
  (Lane :cap 0 :ok 0 :last429 0)

fn renderLane l: Lane -> String
  (str "gwAdmission1\t" (stringFromInt64 l.cap) "\t" (stringFromInt64 l.ok) "\t" (stringFromInt64 l.last429) "\n")

fn parseLane text: String -> (Result Lane String)
  (let [(p (stringSplit (stringTrim text) "\t"))]
    (if (and (= (listLength p) 4) (= (optionOr (listGet p 0) "") "gwAdmission1"))
      (match (stringToInt64 (optionOr (listGet p 1) ""))
        ((none) (err "lane state: bad cap"))
        ((some cap)
         (match (stringToInt64 (optionOr (listGet p 2) ""))
           ((none) (err "lane state: bad ok"))
           ((some okN)
            (match (stringToInt64 (optionOr (listGet p 3) ""))
              ((none) (err "lane state: bad last429"))
              ((some at) (if (and (>= cap 0) (and (>= okN 0) (>= at 0))) (ok (Lane :cap cap :ok okN :last429 at)) (err "lane state: negative field"))))))))
      (err "lane state: malformed")))

fn renderLease x: lim/Lease -> String
  (stringJoin (cons x.provider (cons x.alias (cons (stringFromInt64 x.atMs) x.keys))) "\t")

fn renderLeases ls: (List lim/Lease) -> String
  (str "gwAdmission1\n" (stringJoin (map renderLease ls) "\n") (if (listEmpty? ls) "" "\n"))

fn parseLease line: String -> (Option lim/Lease)
  (let [(p (stringSplit line "\t"))]
    (if (< (listLength p) 3)
      none
      (match (stringToInt64 (optionOr (listGet p 2) ""))
        ((none) none)
        ((some at) (some (lim/Lease :provider (optionOr (listGet p 0) "") :alias (optionOr (listGet p 1) "") :keys (listDrop p 3) :atMs at))))))

fn parseLeases text: String -> (Result (List lim/Lease) String)
  (let [(lines (filter (fn [(s String)] -> Bool (not (stringEmpty? s))) (stringSplit text "\n")))]
    (if (or (listEmpty? lines) (!= (optionOr (listHead lines) "") "gwAdmission1"))
      (err "lease registry: malformed header")
      (let [(rows (map parseLease (listDrop lines 1)))]
        (if (listAny? (fn [(r (Option lim/Lease))] -> Bool (match r ((none) true) ((some _) false))) rows)
          (err "lease registry: malformed row")
          (ok (fold (fn [(acc (List lim/Lease)) (r (Option lim/Lease))] -> (List lim/Lease) (match r ((some x) (listAppend acc (list x))) ((none) acc))) (list) rows))))))

; (:m :ref GW-ADAPTIVE-ADMISSION :do "the row whose count the lane cap replaces: the covering model-scope concurrency row, else the first covering one")
fn baseOf lims: (List c/GatewayLimit) -> (Option c/GatewayLimit)
  (match (listHead (filter (fn [(l c/GatewayLimit)] -> Bool (= l.scope "model")) lims))
    ((some l) (some l))
    ((none) (listHead lims)))

fn maxCapOf base: c/GatewayLimit -> Int64
  (if (> base.max 0) (max base.max base.concurrency) (* 2 base.concurrency))

fn laneCap lane: Lane base: c/GatewayLimit -> Int64
  (if (> lane.cap 0) (min lane.cap (maxCapOf base)) base.concurrency)

fn effectiveLimits lims: (List c/GatewayLimit) lane: Lane -> (List c/GatewayLimit)
  (match (baseOf lims)
    ((none) lims)
    ((some b)
     (let [(cap (laneCap lane b))]
       (map (fn [(l c/GatewayLimit)] -> c/GatewayLimit (if (= (lim/limitKey l) (lim/limitKey b)) (with l :concurrency cap) l)) lims))))

fn inFlightOf leases: (List lim/Lease) provider: String alias: String -> Int64
  (listLength (filter (fn [(x lim/Lease)] -> Bool (and (= x.provider provider) (= x.alias alias))) leases))

; (:m :ref GW-SYN-ADMISSION :do "one multiplicative decrease per burst: calls that fail together on one overload cut the cap once, a 429 within dropGuardMs of the last cut leaves it as it is. Adopted: 2000 ms")
fn dropGuardMs -> Int64
  2000

fn dropOnConcurrency429 lane: Lane base: c/GatewayLimit inFlight: Int64 now: Int64 -> Lane
  (let [(cur (laneCap lane base))
        (target (max 1 (/ (min cur inFlight) 2)))]
    (if (and (> lane.last429 0) (< (- now lane.last429) (dropGuardMs)))
      lane
      (Lane :cap (min cur target) :ok 0 :last429 now)))

fn raiseOnSuccess lane: Lane base: c/GatewayLimit now: Int64 -> Lane
  (let [(cur (laneCap lane base))
        (n (+ lane.ok 1))]
    (if (and (>= n (growStreak)) (and (>= (- now lane.last429) (growQuietMs)) (< cur (maxCapOf base))))
      (Lane :cap (+ cur 1) :ok 0 :last429 lane.last429)
      (Lane :cap cur :ok n :last429 lane.last429)))

; (:m :ref GW-ADAPTIVE-ADMISSION :do "all or nothing: expired leases are pruned, then every applicable limit under the lane's learned cap must have room, else nothing is taken")
fn tryAdmit leases: (List lim/Lease) lane: Lane lims: (List c/GatewayLimit) provider: String alias: String now: Int64 leaseMs: Int64 -> (Pair Bool (List lim/Lease))
  (let [(live (lim/liveLeases leases now leaseMs))
        (eff (effectiveLimits lims lane))]
    (if (lim/full? eff live)
      (pair false live)
      (pair true (lim/admit live eff provider alias now))))

fn admissionDir home: String -> String
  (g/posixJoin home ".asl/run/gwAdmission")

fn lanePath home: String provider: String alias: String -> String
  (str (admissionDir home) "/" (stringReplace provider "/" "_") "-" (stringReplace alias "/" "_") ".asn")

fn leasesPath home: String -> String
  (str (admissionDir home) "/leases.tsv")

fn ! lockHome! home: String tries: Int64 -> (Result Int64 String)
  (match (dirCreate (admissionDir home))
    ((err e) (err (str "admission dir: " e)))
    ((ok _)
     (match (fileLock (str (admissionDir home) "/.lock") true)
       ((ok fd) (ok fd))
       ((err e)
        (if (and (= e "busy") (> tries 0))
          (do (sleepMs 5) (lockHome! home (- tries 1)))
          (err (str "admission lock: " e)))))))

fn ! readOr! path: String empty: String -> (Result String String)
  (if (fileExists? path) (fileReadString path) (ok empty))

fn ! writeAtomic! path: String text: String -> (Result Unit String)
  (match (fileWrite (str path ".tmp") text)
    ((err e) (err e))
    ((ok _) (pathRename (str path ".tmp") path)))

fn ! loadState! home: String provider: String alias: String -> (Result (Pair (List lim/Lease) Lane) String)
  (match (readOr! (leasesPath home) "gwAdmission1\n")
    ((err e) (err e))
    ((ok lt)
     (match (parseLeases lt)
       ((err e) (err e))
       ((ok ls)
        (match (readOr! (lanePath home provider alias) (renderLane (laneInit)))
          ((err e) (err e))
          ((ok nt) (match (parseLane nt) ((err e) (err e)) ((ok lane) (ok (pair ls lane))))))))))

fn ! saveState! home: String provider: String alias: String leases: (List lim/Lease) lane: Lane -> (Result Unit String)
  (match (writeAtomic! (leasesPath home) (renderLeases leases))
    ((err e) (err e))
    ((ok _) (writeAtomic! (lanePath home provider alias) (renderLane lane))))

fn holdPath home: String provider: String alias: String -> String
  (str (lanePath home provider alias) ".hold")

; (:m :ref GW-SYN-ADMISSION :do "a 429 Retry-After pauses its lane: the epoch ms before which nothing is admitted, a plain integer file beside the lane state; unreadable text means no hold")
fn ! holdUntil! home: String provider: String alias: String -> Int64
  (match (readOr! (holdPath home provider alias) "0")
    ((err _) 0)
    ((ok t) (optionOr (stringToInt64 (stringTrim t)) 0)))

fn maxHoldMs -> Int64
  300000

; (:m :ref GW-ADAPTIVE-ADMISSION :do "ok true plus the admitted flag; err when the shared state is locked out, unreadable or malformed, which the caller parks on, never falling back to its own list. A lane inside its Retry-After hold admits nothing")
fn ! admitShared! home: String lims: (List c/GatewayLimit) provider: String alias: String now: Int64 leaseMs: Int64 -> (Result Bool String)
  (match (lockHome! home 400)
    ((err e) (err e))
    ((ok fd)
     (let [(res (if (< now (holdUntil! home provider alias))
                  (ok false)
                  (match (loadState! home provider alias)
                    ((err e) (err e))
                    ((ok st)
                     (let [(r (tryAdmit (pairFirst st) (pairSecond st) lims provider alias now leaseMs))]
                       (match (saveState! home provider alias (pairSecond r) (pairSecond st))
                         ((err e) (err e))
                         ((ok _) (ok (pairFirst r)))))))))
           (closed (fdClose fd))]
       res)))

fn dropOne leases: (List lim/Lease) provider: String alias: String -> (List lim/Lease)
  (lim/release leases provider alias)

; (:m :ref GW-ADAPTIVE-ADMISSION :do "frees the oldest lease of the lane; a call that ended ok counts toward raising the cap")
fn ! releaseShared! home: String lims: (List c/GatewayLimit) provider: String alias: String now: Int64 ended: Bool -> (Result Bool String)
  (match (lockHome! home 400)
    ((err e) (err e))
    ((ok fd)
     (let [(res (match (loadState! home provider alias)
                  ((err e) (err e))
                  ((ok st)
                   (let [(lane (match (baseOf lims) ((some b) (if ended (raiseOnSuccess (pairSecond st) b now) (pairSecond st))) ((none) (pairSecond st))))]
                     (match (saveState! home provider alias (dropOne (pairFirst st) provider alias) lane)
                       ((err e) (err e))
                       ((ok _) (ok true)))))))
           (closed (fdClose fd))]
       res)))

; (:m :ref GW-ADAPTIVE-ADMISSION :do "an upstream 429 naming concurrency: the failed call frees its lease and the lane cap halves to max(1, min(cap, inFlight) / 2), inFlight counting the failed call, at most once per dropGuardMs; the new cap is returned")
fn ! concurrency429! home: String lims: (List c/GatewayLimit) provider: String alias: String now: Int64 -> (Result Int64 String)
  (match (baseOf lims)
    ((none) (ok 0))
    ((some b)
     (match (lockHome! home 400)
       ((err e) (err e))
       ((ok fd)
        (let [(res (match (loadState! home provider alias)
                     ((err e) (err e))
                     ((ok st)
                      (let [(lane (dropOnConcurrency429 (pairSecond st) b (inFlightOf (pairFirst st) provider alias) now))]
                        (match (saveState! home provider alias (dropOne (pairFirst st) provider alias) lane)
                          ((err e) (err e))
                          ((ok _) (ok lane.cap)))))))
              (closed (fdClose fd))]
          res)))))

; (:m :ref GW-SYN-ADMISSION :do "concurrency429! that also honours the upstream's Retry-After: retryAfterMs above 0 holds the lane for min(retryAfterMs, 300000) ms from now, never shortening a longer hold already set; 0 holds nothing")
fn ! concurrency429After! home: String lims: (List c/GatewayLimit) provider: String alias: String now: Int64 retryAfterMs: Int64 -> (Result Int64 String)
  (match (concurrency429! home lims provider alias now)
    ((err e) (err e))
    ((ok cap)
     (if (<= retryAfterMs 0)
       (ok cap)
       (match (lockHome! home 400)
         ((err e) (err e))
         ((ok fd)
          (let [(until (max (holdUntil! home provider alias) (+ now (min retryAfterMs (maxHoldMs)))))
                (res (match (writeAtomic! (holdPath home provider alias) (stringFromInt64 until))
                       ((err e) (err e))
                       ((ok _) (ok cap))))
                (closed (fdClose fd))]
            res))))))
