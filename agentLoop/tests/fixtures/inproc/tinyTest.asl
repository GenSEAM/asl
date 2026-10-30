(module asl/agentLoop/tests/fixtures/inproc/tinyTest :x [runTests])

fn ! runTests -> Bool
  (let [now (nowNs)]
    (do
      (assert (> now 0) "tiny in-process transport fixture runs its assertion")
      true))
