(module aslGateway/tests/codeRouteTest
  :x [runTests]
  :i [(codeRoute :a cr)
      (config :a c)])

; (:m :ref CODE-ROUTE-20261028 :do "the code route proved on its pure step machine with a scripted provider and a scripted gate: writer retry cap 2, the raw gate error verbatim in each retry prompt, one escalation, a 502 retry on the escalation, stop after the escalation, and the declarative row parse")
(schema Seen
  (:f asks (List String))
  (:f prompts (List String))
  (:f timeouts (List Float64))
  (:f gates Int64)
  (:f result cr/RouteResult))

fn emptyResult -> cr/RouteResult
  (cr/RouteResult :passed false :stage "" :text "" :error "out of fuel" :calls 0 :trail (list))

; (:m :do "replies answer asks in order and the last repeats; verdicts answer gates in order and the last repeats")
fn drive step: cr/RouteStep seen: Seen replies: (List cr/RouteReply) verdicts: (List cr/GateVerdict) fuel: Int64 -> Seen
  (if (<= fuel 0)
    seen
    (match step
      ((cr/routeDone r) (Seen :asks seen.asks :prompts seen.prompts :timeouts seen.timeouts :gates seen.gates :result r))
      ((cr/routeAsk alias prompt t k)
        (drive (k (optionOr (listHead replies) (cr/RouteReply :status 200 :text "x")))
               (Seen :asks (listAppend seen.asks (list alias)) :prompts (listAppend seen.prompts (list prompt)) :timeouts (listAppend seen.timeouts (list t)) :gates seen.gates :result seen.result)
               (if (listEmpty? (optionOr (listTail replies) (list))) replies (optionOr (listTail replies) (list))) verdicts (- fuel 1)))
      ((cr/routeGate text k)
        (drive (k (optionOr (listHead verdicts) (cr/GateVerdict :passed false :error "e")))
               (Seen :asks seen.asks :prompts seen.prompts :timeouts seen.timeouts :gates (+ seen.gates 1) :result seen.result)
               replies (if (listEmpty? (optionOr (listTail verdicts) (list))) verdicts (optionOr (listTail verdicts) (list))) (- fuel 1)))))

fn row -> c/CodeRoute
  (c/CodeRoute :id "code" :writer "wr" :retries 2 :escalate "esc" :retryWriter "" :escalateTimeoutSec 240.0 :escalateRetries 2 :escalateRetryStatuses (list 502))

fn run replies: (List cr/RouteReply) verdicts: (List cr/GateVerdict) -> Seen
  (drive (cr/codeRouteStart (row) "TASK") (Seen :asks (list) :prompts (list) :timeouts (list) :gates 0 :result (emptyResult)) replies verdicts 100)

fn ok200 text: String -> cr/RouteReply
  (cr/RouteReply :status 200 :text text)

fn bad msg: String -> cr/GateVerdict
  (cr/GateVerdict :passed false :error msg)

fn good -> cr/GateVerdict
  (cr/GateVerdict :passed true :error "")

fn contains? s: String sub: String -> Bool
  (match (stringIndexOf s sub) ((some _) true) ((none) false))

fn testFirstTryPassNeverRetries -> Bool
  (let [(s (run (list (ok200 "a")) (list (good))))]
    (do
      (assert (= s.asks (list "wr")) "a first-try pass asks the writer once and nothing else")
      (assert (and s.result.passed (= s.result.stage "writer") (= s.result.calls 1)) "passed at stage writer after one call")
      true))

fn testRetryCapAndVerbatimError -> Bool
  (let [(err1 "type error: listHead returns (Option String) at line 4 col 9")
        (s (run (list (ok200 "w1") (ok200 "w2") (ok200 "w3") (ok200 "m1"))
                (list (bad err1) (bad "second \"quoted\"\nmultiline failure") (bad "third failure") (bad "esc failure"))))]
    (do
      (assert (= s.asks (list "wr" "wr" "wr" "esc")) "writer is asked 1+2 times then the escalation alias once")
      (assert (= (listCount (fn [(a String)] -> Bool (= a "wr")) s.asks) 3) "retries are capped at 2")
      (assert (contains? (optionOr (listGet s.prompts 1) "") err1) "retry 1 prompt carries the first gate error verbatim")
      (assert (contains? (optionOr (listGet s.prompts 2) "") "second \"quoted\"\nmultiline failure") "retry 2 prompt carries the second error verbatim with quotes and newline")
      (assert (contains? (optionOr (listGet s.prompts 3) "") "third failure") "escalation prompt carries the last writer error")
      (assert (contains? (optionOr (listGet s.prompts 1) "") "w1") "the retry prompt carries the previous answer")
      (assert (contains? (optionOr (listGet s.prompts 0) "") "TASK") "the first prompt is the task")
      (assert (= (optionOr (listGet s.prompts 0) "") "TASK") "the first prompt is the bare task")
      true))

fn testEscalationOnceThenStop -> Bool
  (let [(s (run (list (ok200 "w") (ok200 "w") (ok200 "w") (ok200 "m")) (list (bad "b1") (bad "b2") (bad "b3") (bad "b4") (bad "b5"))))]
    (do
      (assert (= (listCount (fn [(a String)] -> Bool (= a "esc")) s.asks) 1) "exactly one escalation call")
      (assert (= s.gates 4) "four gate runs: three writer answers and one escalation answer, then stop")
      (assert (and (not s.result.passed) (= s.result.stage "none") (= s.result.error "b4")) "a failing escalation stops with its own gate error")
      (assert (= s.result.calls 4) "four model calls in total")
      (assert (= (optionOr (listGet s.timeouts 3) 0.0) 240.0) "the escalation carries the row timeout 240")
      true))

fn testEscalationPassAndRetries502 -> Bool
  (let [(s (run (list (ok200 "w") (ok200 "w") (ok200 "w") (cr/RouteReply :status 502 :text "bad gateway") (ok200 "m"))
                (list (bad "b1") (bad "b2") (bad "b3") (good))))]
    (do
      (assert (= s.asks (list "wr" "wr" "wr" "esc" "esc")) "a 502 on the escalation is retried once and succeeds")
      (assert (and s.result.passed (= s.result.stage "escalation")) "the escalation answer passes the gate")
      (assert (contains? (optionOr (listGet s.prompts 4) "") "b3") "the 502 retry resends the same prompt with the same error")
      true))

fn testEscalationTransportBounded -> Bool
  (let [(s (run (list (ok200 "w") (ok200 "w") (ok200 "w") (cr/RouteReply :status 502 :text "bad gateway")) (list (bad "b1") (bad "b2") (bad "b3"))))]
    (do
      (assert (= (listCount (fn [(a String)] -> Bool (= a "esc")) s.asks) 3) "502 retries stop after escalateRetries 2: three escalation transport calls")
      (assert (and (not s.result.passed) (contains? s.result.error "502")) "the failure names status 502")
      (assert (= s.gates 3) "no gate runs on a failed transport")
      true))

fn testWriterTransportFailureConsumesRetry -> Bool
  (let [(s (run (list (cr/RouteReply :status 500 :text "boom") (ok200 "w2")) (list (good))))]
    (do
      (assert (= s.asks (list "wr" "wr")) "a writer transport failure spends a retry and asks again")
      (assert (contains? (optionOr (listGet s.prompts 1) "") "status 500") "the transport error is fed back in the retry prompt")
      (assert s.result.passed "the second writer answer passes")
      true))

fn ! testRetryWriter -> Bool
  (let [(rw (c/CodeRoute :id "code" :writer "wr" :retries 2 :escalate "esc" :retryWriter "rw" :escalateTimeoutSec 240.0 :escalateRetries 2 :escalateRetryStatuses (list 502)))
        (seen (run2 rw (list (ok200 "w1") (ok200 "r1") (ok200 "r2") (ok200 "m")) (list (bad "e1") (bad "e2") (bad "e3") (bad "e4"))))
        (pass (run2 rw (list (ok200 "w1") (ok200 "r1")) (list (bad "e1") (good))))]
    (do
      (assert (= seen.asks (list "wr" "rw" "rw" "esc")) (str "first ask goes to the writer, both retries to the retryWriter, then one escalation: " seen.asks))
      (assert (contains? (optionOr (listGet seen.prompts 1) "") "e1") "the retryWriter prompt carries the writer error verbatim")
      (assert (contains? (optionOr (listGet seen.prompts 1) "") "w1") "the retryWriter prompt carries the previous answer")
      (assert (= seen.result.trail (list "wr:fail" "rw:fail" "rw:fail" "esc:fail")) (str "trail names the aliases asked: " seen.result.trail))
      (assert (and pass.result.passed (= pass.asks (list "wr" "rw"))) (str "a retryWriter pass after one retry stops there: " pass.asks))
      true))

fn run2 row: c/CodeRoute replies: (List cr/RouteReply) verdicts: (List cr/GateVerdict) -> Seen
  (drive (cr/codeRouteStart row "TASK") (Seen :asks (list) :prompts (list) :timeouts (list) :gates 0 :result (emptyResult)) replies verdicts 100)

fn testDeclarativeRow -> Bool
  (let [(cfg "(:gateway :v 2 :providers ((:provider :id fp :kind openai :base \"http://127.0.0.1:1\" :keyEnv FP_KEY)) :models ((:model :id wr :provider fp :name \"n1\" :temperature 0.8) (:model :id esc :provider fp :name \"n2\" :temperature 0.2)) :profiles ((:profile :id default :routes ((:intent any :chain (wr))))) :uses ((:use :for default :profile default)) :codeRoutes ((:codeRoute :id code :writer wr :escalate esc) (:codeRoute :id bad :writer nope :escalate esc) (:codeRoute :id rw :writer wr :retryWriter esc :escalate esc) (:codeRoute :id badrw :writer wr :retryWriter nope :escalate esc) (:codeRoute :id deep :writer wr :retries 3 :escalate esc)))")]
    (do
      (match (c/gatewayCodeRoute! cfg "code" "/nonexistent")
        ((ok r) (assert (and (= r.writer "wr") (= r.escalate "esc") (= r.retries 2) (= r.escalateTimeoutSec 240.0) (= r.escalateRetries 2) (= r.escalateRetryStatuses (list 502))) "defaults: retries 2, timeout 240, retry on 502"))
        ((err e) (assert false (str "code row must parse: " e))))
      (match (c/gatewayCodeRoute! cfg "rw" "/nonexistent")
        ((ok r) (assert (and (= r.retryWriter "esc") (= r.writer "wr")) "retryWriter parses as a model alias"))
        ((err e) (assert false (str "rw row must parse: " e))))
      (match (c/gatewayCodeRoute! cfg "badrw" "/nonexistent")
        ((ok _) (assert false "an unknown retryWriter alias must be refused"))
        ((err e) (assert (contains? e "retryWriter: unknown alias nope") (str "retryWriter alias named, got " e))))
      (match (c/gatewayCodeRoute! cfg "code" "/nonexistent")
        ((ok r) (assert (= r.retryWriter "") "absent retryWriter means the writer retries"))
        ((err e) (assert false e)))
      (match (c/gatewayCodeRoute! cfg "bad" "/nonexistent")
        ((ok _) (assert false "an unknown alias must be refused"))
        ((err e) (assert (contains? e "unknown alias nope") (str "unknown alias named, got " e))))
      (match (c/gatewayCodeRoute! cfg "deep" "/nonexistent")
        ((ok _) (assert false "retries above 2 must be refused"))
        ((err e) (assert (contains? e "within 0..2") (str "retry cap named, got " e))))
      (match (c/gatewayCodeRoute! cfg "absent" "/nonexistent")
        ((ok _) (assert false "a missing row must be an error, never a default"))
        ((err e) (assert (contains? e "no codeRoute absent") (str "missing row named, got " e))))
      true))

; (:m :ref CONFIG-CHECK-CODEROUTE :do "gateway configCheck refuses a :codeRoutes row whose writer, retryWriter or escalate alias is not a :model, naming the route and the field, and accepts a sound row")
fn testConfigCheckRoutes -> Bool
  (let [(base "(:gateway :v 2 :providers ((:provider :id fp :kind openai :base \"http://127.0.0.1:1\" :keyEnv FP_KEY)) :models ((:model :id wr :provider fp :name \"n1\" :temperature 0.8) (:model :id esc :provider fp :name \"n2\" :temperature 0.2)) :profiles ((:profile :id default :routes ((:intent any :chain (wr))))) :uses ((:use :for default :profile default)) :codeRoutes (")
        (good (c/gatewayConfigCheckText! (str base "(:codeRoute :id code :writer wr :retryWriter esc :escalate esc)))") "good.asn" "/nonexistent"))
        (bad (c/gatewayConfigCheckText! (str base "(:codeRoute :id code :writer wr :escalate esc) (:codeRoute :id badrw :writer wr :retryWriter nope :escalate esc)))") "bad.asn" "/nonexistent"))
        (cap (c/gatewayConfigCheckText! (str base "(:codeRoute :id deep :writer wr :retries 3 :escalate esc)))") "cap.asn" "/nonexistent"))]
    (do
      (assert (= (pairSecond good) 0) (str "a sound code route passes configCheck: " (pairFirst good)))
      (assert (= (pairSecond bad) 1) "a code route with an unknown retryWriter alias fails configCheck")
      (assert (contains? (pairFirst bad) "codeRoute badrw :retryWriter: unknown alias nope") (str "the bad route and field are named: " (pairFirst bad)))
      (assert (= (pairSecond cap) 1) "a code route outside the retries range fails configCheck")
      (assert (contains? (pairFirst cap) "within 0..2") (str "the range is named: " (pairFirst cap)))
      true))

fn askByAlias alias: String prompt: String t: Float64 -> cr/RouteReply
  (cr/RouteReply :status 200 :text (if (= alias "esc") "m" "w"))

fn gatePassesOnM text: String -> cr/GateVerdict
  (cr/GateVerdict :passed (= text "m") :error (str "bad:" text))

fn gateNever text: String -> cr/GateVerdict
  (cr/GateVerdict :passed false :error (str "bad:" text))

fn gateAlways text: String -> cr/GateVerdict
  (cr/GateVerdict :passed true :error "")

fn ! testDriver -> Bool
  (let [(a (cr/codeRouteDrive! (row) "T" askByAlias gatePassesOnM))
        (b (cr/codeRouteDrive! (row) "T" askByAlias gateAlways))
        (z (cr/codeRouteDrive! (row) "T" askByAlias gateNever))]
    (do
      (assert (and a.passed (= a.stage "escalation") (= a.calls 4) (= a.text "m")) "driver: writer fails the gate 3 times, the escalation passes")
      (assert (= a.trail (list "wr:fail" "wr:fail" "wr:fail" "esc:pass")) "driver trail names each call in order")
      (assert (and b.passed (= b.stage "writer") (= b.calls 1)) "driver: a first-try pass makes one call")
      (assert (and (not z.passed) (= z.stage "none") (= z.calls 4) (= z.error "bad:m")) "driver: all fail stops after the escalation with its last error")
      true))

fn ! runTests -> Bool
  (do
    (assert (testDriver) "testDriver passed")
    (assert (testFirstTryPassNeverRetries) "testFirstTryPassNeverRetries passed")
    (assert (testRetryCapAndVerbatimError) "testRetryCapAndVerbatimError passed")
    (assert (testEscalationOnceThenStop) "testEscalationOnceThenStop passed")
    (assert (testEscalationPassAndRetries502) "testEscalationPassAndRetries502 passed")
    (assert (testEscalationTransportBounded) "testEscalationTransportBounded passed")
    (assert (testWriterTransportFailureConsumesRetry) "testWriterTransportFailureConsumesRetry passed")
    (assert (testRetryWriter) "testRetryWriter passed")
    (assert (testDeclarativeRow) "testDeclarativeRow passed")
    (assert (testConfigCheckRoutes) "testConfigCheckRoutes passed")
    true)
