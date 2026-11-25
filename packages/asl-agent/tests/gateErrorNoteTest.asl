(module aslAgent/tests/gateErrorNoteTest
  :x [runTests]
  :i [(aslAgent/retry :a r)])

fn countUp from: Int64 to: Int64 -> (List Int64)
  (if (> from to) (list) (cons from (countUp (+ from 1) to)))

fn fortyLines -> String
  (stringJoin (map (fn [n] (if (= n 3)
                             "src/f.py:3:7: ERR_UNKNOWN_SYMBOL nope"
                             (str "line " (stringFromInt64 n) " ok")))
                   (countUp 1 40))
              "\n")

fn ! runTests -> Bool
  (let [g (r/makeGateRec "test.sh" 1 false -1 (fortyLines) "")
        parts (r/gateResultParts (list g))
        timeoutG (r/makeGateRec "slow.sh" 1 true 30 "" "")
        timeoutParts (r/gateResultParts (list timeoutG))
        greenG (r/makeGateRec "test.sh" 0 false -1 "ok" "")
        greenParts (r/gateResultParts (list greenG))
        shortG (r/makeGateRec "test.sh" 1 false -1 "(:gate x :asserts 3 :failed 1)\nFAIL: something broke\n" "")
        shortParts (r/gateResultParts (list shortG))]
    (do
      (assert (= (listLength parts) 3)
        "a failing gate with a cut-off first error yields line1, the first error and the tail")
      (assert (= (optionOr (listGet parts 1) "") "gate 1 first error: src/f.py:3:7: ERR_UNKNOWN_SYMBOL nope")
        "the first error sits between line1 and the tail, verbatim with its path:line:col")
      (assert (stringContains? (optionOr (listGet parts 2) "") "line 40 ok")
        "the tail is kept")
      (assert (= timeoutParts (list "gate 1 of 1: \"slow.sh\", timed out after 30 s (:timeout true :seconds 30): killed by the run's :gateTimeout, not a failing exit"))
        "a timed-out gate yields the same line as before")
      (assert (= greenParts (list "gate 1 of 1: \"test.sh\", exit code: 0"))
        "a green gate yields the same line as before")
      (assert (= (listLength shortParts) 2)
        "an error already shown in the tail is not repeated")
      true))
