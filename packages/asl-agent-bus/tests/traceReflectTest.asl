(module asl-agent-bus/tests/traceReflectTest :x [runTests] :i [(aslAgentBus/mesh :a m) (aslAgentBus/cluster :a cl)])

; (:m :ref COVBATCH5 :do "pathInList? is exact membership; a causal trace frame renders as one trace-entry form")
fn runTests -> Bool
  (let [(f (m/makeCausalTraceFrame "f1" "s1" "browser" "snd" "p" 3 7 99 "write" "a.txt" "ok" "d"))
        (g (m/makeCausalTraceFrame "f2" "s1" "browser" "snd" "d" 4 8 100 "read" "b.txt" "ok" "e"))]
    (do (assert (cl/pathInList? "a" (list "a" "b")) "first element is a member")
        (assert (cl/pathInList? "b" (list "a" "b")) "last element is a member")
        (assert (not (cl/pathInList? "c" (list "a" "b"))) "a missing path is not a member")
        (assert (not (cl/pathInList? "a" (list))) "the empty list has no member")
        (assert (not (cl/pathInList? "a" (list "a/b" "ab"))) "a prefix is not membership")
        (assert (not (cl/pathInList? "a/b" (list "a"))) "a longer path is not a member of its parent")
        (assert (= (m/formatFrameForReflect f) "(:trace-entry :timestamp 99 :step 3 :sessionId \"s1\" :runtimeTarget \"browser\" :seq 3 :parentDigest \"p\" :op \"write\" :target \"a.txt\" :status \"ok\" :digest \"d\" :durationMs 0)") "frame renders as a trace-entry")
        (assert (stringContains? (m/formatFrameForReflect g) ":timestamp 100 :step 4") "timestamp and step come from the frame")
        (assert (stringContains? (m/formatFrameForReflect g) ":parentDigest \"d\"") "parent digest is quoted")
        true))
