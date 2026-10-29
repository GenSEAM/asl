(module asl-tools/hub/tests/measureTest
  :x [runTests]
  :i [(asl-tools/hub/measure :a m)])

; (:m :ref ORCH-NODE2-CUTOVER-PREP :do "measure over a synthetic ledger at a fixed now: 10 rows in the 10 minute window (6 ok, 2 throttled, 1 real 429, 1 5xx), one row before it and one after now are ignored, a cut first line and a non-call line are skipped")
fn row at: Int64 outcome: String -> String
  (str "(:call :at " (stringFromInt64 at) " :profile \"\" :intent \"code\" :alias \"a\" :provider \"p\" :model \"m\" :in 1 :cached 0 :out 1 :reasoning 0 :ttftMs absent :ms 5 :outcome \"" outcome "\" :charge 0)")

fn ledger -> String
  (stringJoin (list "ql\" :charge 0)"
                    (row 9000000 "429")
                    (row 9500000 "ok") (row 9550000 "ok") (row 9600000 "ok") (row 9650000 "ok") (row 9700000 "ok") (row 9750000 "ok")
                    (row 9800000 "throttled") (row 9850000 "throttled")
                    (row 9900000 "429") (row 9950000 "5xx")
                    "(:note :at 9700000 :outcome \"429\")"
                    (row 10500000 "ok")) "\n")

fn ! runTests -> Bool
  (let [(out (m/measureText (ledger) 10000000 10))
        (empty (m/measureText "" 10000000 10))]
    (do
      (assert (stringContains? out ":calls 10 ") (str "10 call rows fall in the window: " out))
      (assert (stringContains? out ":ok 6 ") (str "6 ok: " out))
      (assert (stringContains? out ":real429 1 ") (str "1 real 429: " out))
      (assert (stringContains? out ":throttled 2 ") (str "2 own throttles: " out))
      (assert (stringContains? out ":callsPerMin 1.0 ") (str "10 calls over 10 minutes: " out))
      (assert (stringContains? out ":real429Share 0.1 ") (str "1 of 10: " out))
      (assert (stringContains? out ":ownThrottleShare 0.2 ") (str "2 of 10: " out))
      (assert (stringContains? out ":admitWait absent") "the ledger has no admit wait")
      (assert (stringContains? empty ":calls 0 ") (str "an empty ledger counts nothing and divides by nothing: " empty))
      true))
