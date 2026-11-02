(module asl/agentLoop/tests/allDownWaitTest
  :x [runTests]
  :i [(asl/agentLoop/retry :a r) (asl/agentLoop/providers :a pv) (asl/agentLoop/context :a ctx)])

; (:m :ref LEON-TURN-ALLDOWN-WAIT :do "a turn that got the gateway's 502 no model answered after its quick retries ended the whole unit with :stop provider; this suite drives a fake gateway that is all down for two rounds of quick retries and holds that the turn waits for the hint, or the configured pause, inside the all-down budget and the wall budget, and resumes the same call")

fn allDownMessage -> String
  "Gateway HTTP error 502: Bad Gateway profile freeWriter: no model answered (a, b)"

fn fakeGateway failures: Int64 message: String -> (fn [pv/Provider Int64] -> pv/Turn)
  (fn [p attempt]
    (if (< attempt failures)
      (pv/Turn :provider p :reply (err (pv/providerError "ERR_VENDOR" message)) :meta (pv/emptyMeta))
      (pv/Turn :provider p :reply (ok (some "(:done)")) :meta (pv/emptyMeta))))

fn provider -> pv/Provider
  (pv/scriptProvider "fake" (list) 0)

fn clock -> Float64
  0.0

fn noSleep seconds: Int64 -> Bool
  true

fn longSleep seconds: Int64 -> Bool
  (>= seconds 30)

fn okOf res: (Pair pv/Turn Int64) -> Bool
  (match (pairFirst res).reply ((ok _) true) ((err _) false))

fn ! runTests -> Bool
  (let [rounds (* 2 4)
        waited (r/retryTurnWaiting! (provider) (fakeGateway rounds (allDownMessage)) 3 (list 1 2 4) (some 3000) noSleep clock 600 60)
        hinted (r/retryTurnWaiting! (provider) (fakeGateway rounds (str (allDownMessage) " [retry-after=45]")) 3 (list 1 2 4) (some 3000) longSleep clock 600 60)
        noBudget (r/retryTurnWaiting! (provider) (fakeGateway rounds (allDownMessage)) 3 (list 1 2 4) (some 3000) noSleep clock 0 60)
        shortWall (r/retryTurnWaiting! (provider) (fakeGateway rounds (allDownMessage)) 3 (list 1 2 4) (some 30) noSleep clock 600 60)
        oneRound (r/retryTurnWaiting! (provider) (fakeGateway rounds (allDownMessage)) 3 (list 1 2 4) (some 3000) noSleep clock 60 60)
        notAllDown (r/retryTurnWaiting! (provider) (fakeGateway rounds "svc HTTP error 401: Unauthorized") 3 (list 1 2 4) (some 3000) noSleep clock 600 60)
        cfg "(:aslConfig :agentLoop (:allDownWaitSec 900 :allDownPauseSec 30))"]
    (do
      (assert (okOf waited) "a turn all down for two rounds of quick retries waits and gets the reply")
      (assert (= (pairSecond waited) rounds) "the resumed call counts every attempt of every round")
      (assert (okOf hinted) "a [retry-after=45] hint of the all-down reply is the pause, slept whole (the sleep refuses any other length)")
      (assert (not (okOf noBudget)) "an all-down budget of 0 ends the turn after the quick retries, as before")
      (assert (= (pairSecond noBudget) 3) "without a budget only the quick retries run")
      (assert (not (okOf shortWall)) "no wait starts when the pause does not fit the wall budget left")
      (assert (not (okOf oneRound)) "a 60 s all-down budget covers one 60 s pause, not the second round")
      (assert (not (okOf notAllDown)) "an error that is not all down never waits")
      (assert (r/allDown? (allDownMessage)) "the gateway's no model answered is all down")
      (assert (r/allDown? "providers a, b are in circuit-breaker cooldown after quota or timeout failures; retry in 40s") "a circuit-breaker cooldown of every pool is all down")
      (assert (not (r/allDown? "svc HTTP error 401: Unauthorized")) "an auth error is not all down")
      (assert (= (pv/retryAfterSec (pairSecond (pv/withRetryAfter (pair 502 "Bad Gateway") "45"))) 45) "a 502's Retry-After header reaches the error text")
      (assert (= (ctx/allDownWaitSecIn cfg) (some 900)) "allDownWaitSecIn reads the :agentLoop row")
      (assert (= (ctx/allDownPauseSecIn cfg) (some 30)) "allDownPauseSecIn reads the :agentLoop row")
      (assert (= (ctx/allDownWaitSecFor! "/nonexistent-root-allDownWait") 1200) "no config file keeps the default 1200 s")
      true))
