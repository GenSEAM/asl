(module aslAgent/tests/absorbRawCorpusTest
  :x [runTests]
  :i [(aslAgent/reply :a r)])

fn dir -> String
  "asl/packages/asl-agent/tests/fixtures/absorb/corpus/"

; (:m :ref ABSORB-AGENT-K1-K2-K4 :do "116 real replies with :raw fields (60 node2 journals of 2026-11-17, the parity fixtures and STD-BASE64 turn 1, gathered by the grader on 2026-11-18): binding only by place and refusing every doubtful reply whole must not lose a reply the earlier binder bound; 31 bound on 95a56470d")
fn ! runTests -> Bool
  (let [names (listSortBy (fn [x] x) (resultOr (dirList (dir)) (list)))
        bound (filter (fn [nm] (> (r/bindRawBlocks (resultOr (fileReadString (str (dir) nm)) "")).count 0)) names)]
    (do
      (assert (= (listLength names) 116) (str "the corpus holds its 116 replies, got " (stringFromInt64 (listLength names))))
      (assert (>= (listLength bound) 31) (str "at least the 31 replies bound before still bind, got " (stringFromInt64 (listLength bound))))
      true))
