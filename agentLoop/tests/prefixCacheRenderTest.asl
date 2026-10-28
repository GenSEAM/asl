(module asl/agentLoop/tests/prefixCacheRenderTest
  :x [runTests]
  :i [(asl/agentLoop/context :a ctx) (asl-json/json :a j)])

; (:m :ref LEON-PREFIX-CACHE-20261026 :do "the rendered transcript of turn N+1 starts with the full bytes of turn N between compaction points, so a provider prefix cache hits; the changing part (advisor, nudge) is appended after it")

fn histEntry turn: Int64 -> j/Json
  (j/jobj (list (pair "turn" (j/jint turn)) (pair "sent" (j/jstr (str "sent" (stringFromInt64 turn)))) (pair "got" (j/jstr (str "got" (stringFromInt64 turn))))
    (pair "ops" (j/jstr "read")) (pair "files" (j/jstr "subject.txt")) (pair "gates" (j/jstr "1/1 green"))))

fn history n: Int64 -> (List j/Json)
  (map (fn [i] (histEntry (+ i 1))) (range 0 n))

fn render n: Int64 -> String
  (ctx/renderTranscriptBounded (history n) 8 1500 50)

; (:m :do "does the render of n+1 turns keep the render of n turns as an exact prefix")
fn prefixKept n: Int64 -> Bool
  (stringStartsWith? (render (+ n 1)) (render n))

fn countKept from: Int64 to: Int64 -> Int64
  (listLength (filter (fn [n] (prefixKept n)) (range from to)))

fn testBetweenPoints -> Bool
  (do
    (assert (prefixKept 12) "turn 13 extends turn 12 byte for byte")
    (assert (prefixKept 13) "turn 14 extends turn 13 byte for byte")
    (assert (prefixKept 14) "turn 15 extends turn 14 byte for byte")
    true)

fn testAcrossARun -> Bool
  (let [kept (countKept 9 41)]
    (do
      (assert (>= kept 24) (str "at least 3 of 4 transitions keep the full prior prefix, got " (stringFromInt64 kept) " of 32"))
      true))

fn testCompactionPointOnly -> Bool
  (do
    (assert (= (ctx/compactionCut 11 8 4) 0) "below the first point nothing is summarised")
    (assert (= (ctx/compactionCut 12 8 4) 4) "the cut moves in steps of 4")
    (assert (= (ctx/compactionCut 15 8 4) 4) "and stays put until the next point")
    (assert (= (ctx/compactionCut 16 8 4) 8) "next point")
    true)

fn ! runTests -> Bool
  (do
    (assert (testBetweenPoints) "testBetweenPoints passed")
    (assert (testAcrossARun) "testAcrossARun passed")
    (assert (testCompactionPointOnly) "testCompactionPointOnly passed")
    true)
