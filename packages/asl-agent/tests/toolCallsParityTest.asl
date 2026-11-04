(module aslAgent/tests/toolCallsParityTest
  :x [runTests]
  :i [(aslAgent/toolCalls :a tc) (aslAgent/tests/parity :a t) (aslAgent/core :a c) (aslAgent/plan :a p)])

fn dispatch fname: String args: (List p/SexpNode) -> String
  (let [raw (t/argStr (t/argAt args 0))
        got (tc/untagToolCalls raw)]
    (t/sPair (t/sStr (pairFirst got)) (t/sInt (pairSecond got))))

fn ! runTests -> Bool
  (let [root (resultOr (realPath ".") ".")
        passed (t/replay! (str root "/asl/packages/asl-agent/tests/toolCallsFixture.asn")
                  (list "untagToolCalls") (fn [f a] (dispatch f a)))]
    (> passed 0))
