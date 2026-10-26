(module asl/agentLoop/tests/retryClassTest
  :x [runTests]
  :i [(asl/agentLoop/retry :a r) (asl/agentLoop/providers :a pv)])

; (:m :ref LEON-CAPS :do "the fake transport is a scripted list of replies keyed by attempt number: it proves the retry router's decisions (which errors are retried, how often, with which pause) and nothing about real HTTP, curl exit codes or what a gateway puts in its error text")
fn failing code: String message: String -> (fn [pv/Provider Int64] -> pv/Turn)
  (fn [p attempt] (pv/Turn :provider p :reply (err (pv/providerError code message)) :meta (pv/emptyMeta)))

fn failsThenOk code: String message: String failures: Int64 -> (fn [pv/Provider Int64] -> pv/Turn)
  (fn [p attempt]
    (if (< attempt failures)
      (pv/Turn :provider p :reply (err (pv/providerError code message)) :meta (pv/emptyMeta))
      (pv/Turn :provider p :reply (ok (some "(:done)")) :meta (pv/emptyMeta))))

fn provider -> pv/Provider
  (pv/scriptProvider "fake" (list) 0)

fn noSleep seconds: Int64 -> Bool
  true

fn clock -> Float64
  (/ (int64ToFloat64 (monotonicNs)) 1000000000.0)

fn attemptsOf call: (fn [pv/Provider Int64] -> pv/Turn) -> Int64
  (pairSecond (r/retryTurn! (provider) call 3 (list 1 2 4) none noSleep clock))

; (:m :ref LEON-CAPS :do "a provider that times out after about a second per call, real clock, pauses skipped: with 3 s left the first attempt is charged 2 s rounded up, the pause 1 s, and the retry starts nothing further")
fn slowTimeout -> (fn [pv/Provider Int64] -> pv/Turn)
  (fn [p attempt]
    (do (sleepMs 1100)
        (pv/Turn :provider p :reply (err (pv/providerError "ERR_VENDOR" "svc timed out waiting for reply")) :meta (pv/emptyMeta))))

fn budgetedAttempts budget: Int64 -> Int64
  (pairSecond (r/retryTurn! (provider) (slowTimeout) 3 (list 1 2 4) (some budget) noSleep clock))

fn replyOk call: (fn [pv/Provider Int64] -> pv/Turn) -> Bool
  (match (pairFirst (r/retryTurn! (provider) call 3 (list 1 2 4) none noSleep clock)).reply
    ((ok _) true)
    ((err _) false))

fn ! runTests -> Bool
  (do
    (assert (= (r/errorClass "ERR_VENDOR" "Gateway error 429: slow down") "transient") "429 is transient")
    (assert (= (r/errorClass "ERR_VENDOR" "svc HTTP error 503: Service Unavailable") "transient") "5xx is transient")
    (assert (= (r/errorClass "ERR_VENDOR" "svc timed out waiting for reply: curl exit 28") "transient") "a timeout is transient")
    (assert (= (r/errorClass "ERR_IO" "read failed: Connection reset by peer") "transient") "a connection reset is transient on a transport code")
    (assert (= (r/errorClass "ERR_NO_REPLY" "Empty content in gateway response") "transient") "an empty body is transient")
    (assert (= (r/errorClass "ERR_VENDOR" "svc HTTP error 401: Unauthorized") "permanent") "401 is permanent")
    (assert (= (r/errorClass "ERR_VENDOR" "svc HTTP error 400: Bad Request") "permanent") "400 is permanent")
    (assert (= (r/errorClass "ERR_VENDOR" "svc HTTP error 408: Request Timeout") "transient") "408 is transient")
    (assert (= (r/errorClass "ERR_CONTEXT_TOO_LONG" "svc 413: too large") "permanent") "413 is permanent")
    (assert (= (r/errorClass "ERR_VALUE" "Unknown backend: x") "permanent") "an unknown code with no marker is permanent")
    (assert (= (r/errorClass "ERR_VENDOR" "Failed to parse gateway ASN response: x") "transient") "a statusless vendor error keeps the prior retry")
    (assert (= (r/httpStatusIn "svc HTTP error 502: bad") 502) "the status is read from the HTTP error prefix")
    (assert (= (r/errorClass "ERR_VENDOR" "svc timed out waiting for reply: curl: (28) Failed to connect to api.example.com port 443 after 300 ms: Timeout was reached") "transient") "a port in curl text does not make a timeout permanent")
    (assert (= (r/errorClass "ERR_VENDOR" "svc reply unreadable: Connection reset by peer at host:443") "transient") "a port does not make a connection reset permanent")
    (assert (= (r/httpStatusIn "HTTP error ?: max_tokens 512 exceeds") 0) "a number outside the status prefix is not a status")
    (assert (= (r/errorClass "ERR_VALUE" "invalid timeout parameter") "permanent") "a text marker does not make a non-transport code transient")
    (assert (= (budgetedAttempts 3) 1) "elapsed attempt time is charged to the wall budget, so a 3 s budget allows one retry")
    (assert (= (budgetedAttempts 2) 0) "a budget spent by the first attempt allows no retry")
    (assert (= (attemptsOf (failsThenOk "ERR_NO_REPLY" "Empty content in gateway response" 2)) 2) "an empty body is retried until the call succeeds")
    (assert (replyOk (failsThenOk "ERR_NO_REPLY" "Empty content in gateway response" 2)) "the retried call returns the successful reply")
    (assert (= (attemptsOf (failing "ERR_IO" "Connection reset by peer")) 3) "a transient error stops at the retry cap")
    (assert (= (attemptsOf (failing "ERR_VENDOR" "svc HTTP error 401: Unauthorized")) 0) "a permanent vendor error is not retried")
    (assert (= (attemptsOf (failing "ERR_VENDOR" "svc HTTP error 429: Too Many Requests")) 3) "429 is retried to the cap")
    (assert (= (r/providerRetryPause true 2 (list 1 2 4) none) 2) "a transient retry backs off by the configured step")
    (assert (= (r/providerRetryPause true 3 (list 1 2 4) (some 1)) 1) "the backoff is cut to the wall budget left")
    (assert (= (r/providerRetryPause false 2 (list 1 2 4) none) 0) "a permanent error has no pause")
    true)
