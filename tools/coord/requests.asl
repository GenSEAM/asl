(module asl-tools/coord/requests
  :x [Unit Lease Pace Request Decision reqEscalate reqNeedCtx reqNeedOwns reqNeedTime reqSplit decide opName journalRow signature repeatCount secretLike? underRoot? covers?]
  :i [])

(schema Unit
  (:f id String)
  (:f root String)
  (:f owns (List String))
  (:f external Bool)
  (:f requestsLeft Int64)
  (:f escalationsLeft Int64)
  (:f gatesRun Int64)
  (:f wallBudget Int64)
  (:f timeGranted Bool)
  (:f writePersisted Bool))

(schema Lease
  (:f unit String)
  (:f path String))

(schema Pace
  (:f nextLaneAllowance Bool))

(enum Request
  (:c reqEscalate [(reason String) (seen String) (tried String)] "reason class spec or owns skips the gate-ran condition")
  (:c reqNeedCtx [(path String) (symbol String)] "bounded slice by symbol")
  (:c reqNeedOwns [(path String)] "widen the lease")
  (:c reqNeedTime [(sec Int64)] "raise the wall budget")
  (:c reqSplit [(units (List String)) (why String)] "rows for the plan queue"))

(schema Decision
  (:f granted Bool)
  (:f op String)
  (:f why String)
  (:f heldBy String)
  (:f row String)
  (:f unit Unit))

fn opName r: Request -> String
  (match r
    ((reqEscalate _ _ _) "escalate")
    ((reqNeedCtx _ _) "needCtx")
    ((reqNeedOwns _) "needOwns")
    ((reqNeedTime _) "needTime")
    ((reqSplit _ _) "split"))

fn anyIn? text: String needles: (List String) -> Bool
  (some? (listHead (filter (fn [(n String)] -> Bool (stringContains? text n)) needles)))

fn secretLike? path: String -> Bool
  (anyIn? (stringLower path) (list ".env" "secret" "credential" "token" "apikey" "api_key" "password" ".pem" "id_rsa" "keychain" ".key"))

fn memPath? path: String -> Bool
  (or (stringStartsWith? path ".asl/mem") (stringContains? path "/.asl/mem"))

fn dotDot? path: String -> Bool
  (or (= path "..") (stringStartsWith? path "../") (stringContains? path "/../") (stringEndsWith? path "/.."))

fn underRoot? root: String path: String -> Bool
  (cond
    ((stringEmpty? path) false)
    ((dotDot? path) false)
    ((stringStartsWith? path "/") (stringStartsWith? path (str root "/")))
    (else true))

fn covers? lease: String path: String -> Bool
  (or (= lease path) (stringStartsWith? path (str lease "/")))

fn dirOf path: String -> String
  (let [(parts (stringSplit path "/"))]
    (stringJoin (listTake parts (- (listLength parts) 1)) "/"))

fn sameDir? owned: (List String) path: String -> Bool
  (some? (listHead (filter (fn [(o String)] -> Bool (= (dirOf o) (dirOf path))) owned)))

fn leaseHolder leases: (List Lease) path: String -> (Option String)
  (match (listHead (filter (fn [(l Lease)] -> Bool (covers? l.path path)) leases))
    ((some l) (some l.unit))
    ((none) (none)))

fn charged u: Unit -> Unit
  (Unit :id u.id :root u.root :owns u.owns :external u.external :requestsLeft (- u.requestsLeft 1)
        :escalationsLeft u.escalationsLeft :gatesRun u.gatesRun :wallBudget u.wallBudget
        :timeGranted u.timeGranted :writePersisted u.writePersisted)

fn refusal op: String why: String held: String u: Unit -> Decision
  (Decision :granted false :op op :why why :heldBy held
            :row (if (stringEmpty? held)
                   (str "(:refused :op " op " :why " why ")")
                   (str "(:refused :op " op " :heldBy " held ")"))
            :unit (charged u))

fn grant op: String u: Unit -> Decision
  (Decision :granted true :op op :why "ok" :heldBy "" :row (str "(:granted :op " op " :why ok)") :unit u)

fn firstRefusal checks: (List (Option String)) -> (Option String)
  (match (listHead (filter (fn [(c (Option String))] -> Bool (some? c)) checks))
    ((some c) c)
    ((none) (none)))

fn decideEscalate u: Unit pace: Pace reason: String -> Decision
  (let [(c (charged u))
        (why (cond
               ((<= u.escalationsLeft 0) "exhausted")
               ((and (<= u.gatesRun 0) (not (or (= reason "spec") (= reason "owns")))) "noGateRun")
               ((not pace.nextLaneAllowance) "noAllowance")
               (else "")))]
    (if (stringEmpty? why)
      (grant "escalate" (Unit :id c.id :root c.root :owns c.owns :external c.external :requestsLeft c.requestsLeft
                              :escalationsLeft (- c.escalationsLeft 1) :gatesRun c.gatesRun :wallBudget c.wallBudget
                              :timeGranted c.timeGranted :writePersisted c.writePersisted))
      (refusal "escalate" why "" u)))

fn decideCtx u: Unit path: String -> Decision
  (cond
    ((not (underRoot? u.root path)) (refusal "needCtx" "outsideRoot" "" u))
    ((and u.external (memPath? path)) (refusal "needCtx" "memPath" "" u))
    ((and u.external (secretLike? path)) (refusal "needCtx" "secretLike" "" u))
    (else (grant "needCtx" (charged u))))

fn decideOwns u: Unit leases: (List Lease) path: String -> Decision
  (match (leaseHolder leases path)
    ((some h) (refusal "needOwns" "held" h u))
    ((none)
      (cond
        ((not (underRoot? u.root path)) (refusal "needOwns" "outsideRoot" "" u))
        ((not (sameDir? u.owns path)) (refusal "needOwns" "otherPackage" "" u))
        (else
          (let [(c (charged u))]
            (grant "needOwns" (Unit :id c.id :root c.root :owns (listAppend c.owns (list path)) :external c.external
                                    :requestsLeft c.requestsLeft :escalationsLeft c.escalationsLeft :gatesRun c.gatesRun
                                    :wallBudget c.wallBudget :timeGranted c.timeGranted :writePersisted c.writePersisted)))))))

fn decideTime u: Unit sec: Int64 -> Decision
  (cond
    ((<= sec 0) (refusal "needTime" "badArg" "" u))
    (u.timeGranted (refusal "needTime" "alreadyGranted" "" u))
    ((> (* sec 2) u.wallBudget) (refusal "needTime" "overHalf" "" u))
    ((not u.writePersisted) (refusal "needTime" "noWrite" "" u))
    (else
      (let [(c (charged u))]
        (grant "needTime" (Unit :id c.id :root c.root :owns c.owns :external c.external :requestsLeft c.requestsLeft
                                :escalationsLeft c.escalationsLeft :gatesRun c.gatesRun :wallBudget (+ c.wallBudget sec)
                                :timeGranted true :writePersisted c.writePersisted)))))

fn decide u: Unit leases: (List Lease) pace: Pace r: Request -> Decision
  (cond
    ((<= u.requestsLeft 0) (refusal (opName r) "requestsExhausted" "" u))
    (else
      (match r
        ((reqEscalate reason _ _) (decideEscalate u pace reason))
        ((reqNeedCtx path _) (decideCtx u path))
        ((reqNeedOwns path) (decideOwns u leases path))
        ((reqNeedTime sec) (decideTime u sec))
        ((reqSplit _ _) (grant "split" (charged u))))))

fn journalRow unit: String d: Decision -> String
  (str "(:request :unit " unit " :op " d.op " :granted " (if d.granted "true" "false") " :why " (if (stringEmpty? d.heldBy) d.why (str "heldBy:" d.heldBy)) ")")

fn signature d: Decision -> String
  (str d.op "|" d.why "|" d.heldBy)

fn repeatCount history: (List String) d: Decision -> Int64
  (if d.granted 0 (+ 1 (listLength (filter (fn [(s String)] -> Bool (= s (signature d))) history))))
