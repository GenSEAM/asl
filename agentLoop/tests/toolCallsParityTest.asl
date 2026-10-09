(module asl/agentLoop/tests/toolCallsParityTest
  :x [runTests]
  :i [(asl/agentLoop/toolCalls :a tc) (asl/agentLoop/tests/parity :a t) (asl/agentLoop/core :a c)])

fn dispatch fname: String args: (List p/SexpNode) -> String
  (let [raw (t/argStr (t/argAt args 0))
        got (tc/untagToolCalls raw)]
    (t/sPair (t/sStr (pairFirst got)) (t/sInt (pairSecond got))))

fn ! runTests -> Bool
  (let [root (resultOr (realPath ".") ".")
        passed (t/replay! (str root "/asl/agentLoop/tests/toolCallsFixture.asn")
                  (list "untagToolCalls") (fn [f a] (dispatch f a)))]
    (> passed 0))
