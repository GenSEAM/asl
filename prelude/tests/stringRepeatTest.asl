(module prelude/tests/stringRepeatTest :x [runTests] :i [])

fn runTests -> Bool
  (do
    (assert (= (stringRepeat "xy" -3) "") "negative repeat count returns empty")
    (assert (= (stringRepeat "xy" 0) "") "zero repeat count returns empty")
    (assert (= (stringRepeat "xy" 1) "xy") "one repeat returns input")
    (assert (= (stringRepeat "" 12) "") "empty input remains empty")
    (assert (= (stringRepeat "é界" 3) "é界é界é界") "multibyte input repeats exactly")
    (assert (= (stringRepeat "ab" 5) "ababababab") "five repeats preserve content")
    (assert (= (stringRepeat "ab" 13) "ababababababababababababab") "multi-bit repeat preserves content")
    (let [(large (stringRepeat "ab" 2097152))]
      (assert (= (bytesLength (stringToBytes large)) 4194304) "large repeat is exactly 4 MiB"))
    true)
