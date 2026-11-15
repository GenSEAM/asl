(module aslAgent/tests/providerJunkRetryTest
  :x [runTests]
  :i [(aslAgent/retry :a r) (aslAgent/providers :a pv)])

; (:m :ref PROVIDER-JUNK-RETRY :do "the four junk samples are the measured node replies verbatim; the fake transport scripts a reply by attempt number")
fn provider -> pv/Provider
  (pv/scriptProvider "fake" (list) 0)

fn noSleep seconds: Int64 -> Bool
  true

fn clock -> Float64
  (/ (int64ToFloat64 (monotonicNs)) 1000000000.0)

fn okTurn p: pv/Provider text: String -> pv/Turn
  (pv/Turn :provider p :reply (ok (some text)) :meta (pv/emptyMeta))

fn junkThenOk junk: String -> (fn [pv/Provider Int64] -> pv/Turn)
  (fn [p attempt] (if (< attempt 1) (okTurn p junk) (okTurn p "(:done)")))

fn alwaysJunk junk: String -> (fn [pv/Provider Int64] -> pv/Turn)
  (fn [p attempt] (okTurn p junk))

fn run call: (fn [pv/Provider Int64] -> pv/Turn) -> (Pair pv/Turn Int64)
  (r/retryTurn! (provider) call 3 (list 1 2 4) none noSleep clock)

fn replyText res: (Pair pv/Turn Int64) -> String
  (match (pairFirst res).reply ((ok (some t)) t) ((ok _) "") ((err _) "ERR"))

fn errCode res: (Pair pv/Turn Int64) -> String
  (match (pairFirst res).reply ((ok _) "ok") ((err e) (pv/errorCode e)))

fn ! runTests -> Bool
  (do
    (assert (r/junkReply? "step<ifm|tool_calls>\n<ifm|too") "sample 1 is junk")
    (assert (r/junkReply? "run</ifm|arg_value>") "sample 2 is junk")
    (assert (r/junkReply? "<ds_safety>blocked</ds_safety>") "ds_safety is junk")
    (assert (r/junkReply? "step<|tool_call_begin|>") "control token after first word is junk")
    (assert (r/junkReply? "<|im_start|>assistant") "control token at start is junk")
    (assert (r/junkReply? "(:step :say \"ok\")\n<ifm|tool_calls>") "valid text then ifm marker is junk")
    (assert (not (r/junkReply? "(:step :tool :read :file \"a.asl\")")) "a normal step is not junk")
    (assert (not (r/junkReply? "check a < b here")) "a < b is not junk")
    (assert (not (r/junkReply? "(:done :note \"(< x 1)\")")) "(< x 1) is not junk")
    (assert (not (r/junkReply? "<html><body>x</body></html>")) "html is not junk")
    (assert (not (r/junkReply? "")) "empty is not junk")
    (assert (not (r/junkReply? "the file says x <| y later")) "<| after several words is not junk")
    (assert (= (pairSecond (run (junkThenOk "step<ifm|tool_calls>\n<ifm|too"))) 1) "junk then valid retries exactly once")
    (assert (= (replyText (run (junkThenOk "run</ifm|arg_value>"))) "(:done)") "the valid turn is returned")
    (assert (= (pairSecond (run (junkThenOk "<ds_safety>x"))) 1) "ds_safety junk retried once")
    (assert (= (errCode (run (alwaysJunk "run</ifm|arg_value>"))) "ERR_PROVIDER_JUNK") "persistent junk ends as ERR_PROVIDER_JUNK")
    (assert (= (pairSecond (run (alwaysJunk "<ds_safety>"))) 3) "persistent junk spends the retry budget")
    (assert (= (r/errorClass "ERR_PROVIDER_JUNK" "x") "transient") "junk code is transient")
    (assert (= (pairSecond (r/retryTurn! (provider) (alwaysJunk "<ds_safety>") 3 (list 1 2 4) (some 0) noSleep clock)) 0) "a spent wall budget allows no junk retry")
    true)
