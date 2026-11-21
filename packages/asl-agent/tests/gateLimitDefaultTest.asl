(module aslAgent/tests/gateLimitDefaultTest
  :x [runTests]
  :i [(aslAgent/main :a m) (aslAgent/gateLimit :a gl) (aslAgent/gitOps :a go)])

; (:m :ref WALL-SLOW-GATES :do "the default gateTimeout of a run is the one gateLimit constant, an explicit one is kept, and the gate child sees the run's limit as ASL_GATE_LIMIT_SEC")
fn ! limitOf form: String -> Int64
  (m/runArgsOf (m/parseInvocation form ".").params 600 1200 false).gateTimeout

fn ! runTests -> Bool
  (let [tmp (str (optionOr (envGet "TMPDIR") "/tmp") "/gateLimitDefault" (stringFromInt64 (nowNs)))
        made (dirCreate tmp)
        real (resultOr (realPath tmp) tmp)
        recs (go/runGatesIn! (list (pair "g1" "test \"$ASL_GATE_LIMIT_SEC\" = 7")) real 7 (none) (none) (str real "/gateTimes.asn"))
        r1 (optionOr (listGet recs 0) (list))
        removed (pathRemove real)]
    (do
      (assert (= (limitOf "(:agent :task \"x\")") (gl/gateLimitSec)) "the default gateTimeout is gl/gateLimitSec")
      (assert (= (limitOf "(:agent :task \"x\" :gateTimeout 77)") 77) "an explicit gateTimeout is kept")
      (assert (= (go/recGet r1 "exit") (some (go/rInt 0))) "the gate child sees ASL_GATE_LIMIT_SEC equal to the run's timeout")
      true))
