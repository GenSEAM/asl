(module asl/agentLoop/tests/coreEchoTest
  :x [runTests]
  :i [(asl/agentLoop/core :a c)])

; (:m :ref LEON-TURN-ECHO :do "VPS session 17a69539c9c7f99b: a reply that echoes the loop frame (:turn N :sent ...) was read as ad-hoc findings; echoed frames are now stripped first and counted")

fn echo -> String
  "(:turn 2 :sent \"I will write the file now\" :got \"x\")"

fn runTests -> Bool
  (do
    (assert (listEmpty? (c/dataFindings (echo) (list))) "an echo-only reply gives zero findings")
    (assert (= (c/echoCount (echo)) 1) "the echo is counted")
    (assert (= (c/malformedLine 2 1) "(:malformed :turn 2 :echo 1)") "the journal line names turn and echo count")
    (assert (= (c/echoCount "(:step :op \"write\" :file \"a\" :content \"b\")") 0) "a real op is not an echo")
    (assert (stringContains? (c/stripEchoes (str (echo) "\n(:step :op \"write\" :file \"a\" :content \"b\")")) ":op \"write\"") "an echo plus a real op keeps the op")
    (assert (not (stringContains? (c/stripEchoes (str (echo) "\n(:step :op \"write\" :file \"a\" :content \"b\")")) ":sent")) "and drops the echo")
    (assert (= (listLength (c/dataFindings (str (echo) "\n(:findings (:claim \"real\"))") (list))) 1) "a real (:findings ...) form beside an echo still counts")
    (assert (= (c/echoCount "(:gate :n 0)") 0) "a model (:gate :n 0) op is not an echo")
    (assert (= (c/echoCount "(:step :op \"read\" :file \"a\")\n(:gate :n 0)") 0) "so a reply with real ops and a gate op counts no echo")
    (assert (= (c/echoCount "(:gate :cmd \"sh g.sh\" :asserts 3 :failed 0)") 1) "a loop-rendered gate line is an echo")
    (assert (= (c/echoCount "(:gate :cmd \"sh g.sh\" :exit 1)") 1) "so is the journal form with :exit")
    (assert (= (c/echoCount "(:receipt :id \"a\" :op \"read\")\n(:poolAsks ())") 2) "receipt and poolAsks frames are echoes too")
    true)
