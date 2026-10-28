(module aslGateway/codeRoute
  :x [RouteReply
      GateVerdict
      RouteResult
      RouteStep
      routeAsk
      routeGate
      routeDone
      codeRouteStart
      codeRouteDrive!
      retryPrompt]
  :i [(config :a c)])

; (:m :ref CODE-ROUTE-20261028 :do "writer, caller gate, raw error fed back to the writer up to :retries times, then one escalation to the :escalate alias with the same error, then stop; evidence CAL/ensemble-20261028.asn variant d (10/12 against 8/12 alone) and the finding that a second same-tier model adds nothing; aliases come from the c/CodeRoute row, so no model id lives here")
(schema RouteReply
  (:f status Int64)
  (:f text String))

(schema GateVerdict
  (:f passed Bool)
  (:f error String))

; (:m :do "stage is writer or escalation for a pass, none for a failure; error is the last gate error or transport status verbatim; trail lists one alias:outcome per model call in order")
(schema RouteResult
  (:f passed Bool)
  (:f stage String)
  (:f text String)
  (:f error String)
  (:f calls Int64)
  (:f trail (List String)))

(enum RouteStep
  (:c routeAsk [(alias String) (prompt String) (timeoutSec Float64) (k (fn [RouteReply] -> RouteStep))])
  (:c routeGate [(text String) (k (fn [GateVerdict] -> RouteStep))])
  (:c routeDone [(result RouteResult)]))

; (:m :do "the error text is carried verbatim, unedited and untruncated, after the previous answer")
fn retryPrompt task: String previous: String error: String -> String
  (str task "\n\nYour previous answer:\n" previous "\n\nThe checker reported this error, verbatim:\n" error "\n\nFix the error and answer again.")

fn done passed: Bool stage: String text: String error: String calls: Int64 trail: (List String) -> RouteStep
  (routeDone (RouteResult :passed passed :stage stage :text text :error error :calls calls :trail trail))

fn noteCall trail: (List String) alias: String outcome: String -> (List String)
  (listAppend trail (list (str alias ":" outcome)))

fn replyError r: RouteReply -> String
  (str "model call failed with status " (stringFromInt64 r.status) (if (stringEmpty? r.text) "" (str ": " r.text)))

; (:m :do "second and last stage: escalation retries only a transport status the row lists, at most :escalateRetries times, then the route stops whatever the answer")
fn escalate row: c/CodeRoute prompt: String tries: Int64 calls: Int64 trail: (List String) -> RouteStep
  (routeAsk row.escalate prompt row.escalateTimeoutSec
    (fn [(r RouteReply)] -> RouteStep
      (cond
        ((= r.status 200)
          (routeGate r.text
            (fn [(v GateVerdict)] -> RouteStep
              (if v.passed
                (done true "escalation" r.text "" (+ calls 1) (noteCall trail row.escalate "pass"))
                (done false "none" r.text v.error (+ calls 1) (noteCall trail row.escalate "fail"))))))
        ((and (listContains? row.escalateRetryStatuses r.status) (< tries row.escalateRetries))
          (escalate row prompt (+ tries 1) (+ calls 1) (noteCall trail row.escalate (str "retry" (stringFromInt64 r.status)))))
        (else (done false "none" "" (replyError r) (+ calls 1) (noteCall trail row.escalate (str "status" (stringFromInt64 r.status))))))))

; (:m :do "the first ask goes to :writer; every retry goes to :retryWriter when the row names one, else to :writer again; the prompt always carries the previous answer and the raw error")
fn askerFor row: c/CodeRoute attempt: Int64 -> String
  (if (and (> attempt 0) (not (stringEmpty? row.retryWriter))) row.retryWriter row.writer)

fn writer row: c/CodeRoute task: String prompt: String attempt: Int64 calls: Int64 trail: (List String) -> RouteStep
  (let [(who (askerFor row attempt))]
  (routeAsk who prompt 0.0
    (fn [(r RouteReply)] -> RouteStep
      (let [(failed (fn [(text String) (error String) (outcome String)] -> RouteStep
                      (let [(next (retryPrompt task text error))
                            (trail2 (noteCall trail who outcome))]
                        (if (< attempt row.retries)
                          (writer row task next (+ attempt 1) (+ calls 1) trail2)
                          (escalate row next 0 (+ calls 1) trail2)))))]
        (if (= r.status 200)
          (routeGate r.text
            (fn [(v GateVerdict)] -> RouteStep
              (if v.passed
                (done true "writer" r.text "" (+ calls 1) (noteCall trail who "pass"))
                (failed r.text v.error "fail"))))
          (failed "" (replyError r) (str "status" (stringFromInt64 r.status))))))))

; (:m :do "entry for a caller that drives the steps itself (Leon's loop, a test transport): the first step asks the writer alias with the task text; timeoutSec 0.0 means the alias row's own timeout")
fn codeRouteStart row: c/CodeRoute task: String -> RouteStep
  (writer row task task 0 0 (list))

; (:m :do "synchronous driver: ask sends one model call to the gateway for an alias and returns its status and text, gate runs the caller's checker or test on an answer; at most retries+1 writer calls and escalateRetries+1 escalation calls happen, bounded by fuel")
fn ! codeRouteDrive! row: c/CodeRoute task: String ask: (fn [String String Float64] -> RouteReply) gate: (fn [String] -> GateVerdict) -> RouteResult
  (driveLoop! (codeRouteStart row task) ask gate 64)

fn ! driveLoop! step: RouteStep ask: (fn [String String Float64] -> RouteReply) gate: (fn [String] -> GateVerdict) fuel: Int64 -> RouteResult
  (if (<= fuel 0)
    (RouteResult :passed false :stage "none" :text "" :error "route out of fuel" :calls 0 :trail (list))
    (match step
      ((routeDone r) r)
      ((routeAsk alias prompt timeoutSec k) (driveLoop! (k (ask alias prompt timeoutSec)) ask gate (- fuel 1)))
      ((routeGate text k) (driveLoop! (k (gate text)) ask gate (- fuel 1)))))
