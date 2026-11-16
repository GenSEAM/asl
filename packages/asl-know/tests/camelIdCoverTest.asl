(module asl-know/tests/camelIdCoverTest
  :x [runTests]
  :i [(asl-know/render :a r)])

; (:m :ref KNOW-CAMEL-ID :do "camelId is the example file stem of a card id: slashes and dashes split words, empty parts drop, the first word stays lower and the rest are upper-firsted")
fn ! runTests -> Bool
  (do
    (assert (= (r/camelId "asl-agent-core") "aslAgentCore") "dashes become camelCase")
    (assert (= (r/camelId "a/b") "aB") "a slash splits like a dash")
    (assert (= (r/camelId "asl-json") "aslJson") "asl-json becomes aslJson")
    (assert (= (r/camelId "core/list") "coreList") "core/list becomes coreList")
    (assert (= (r/camelId "a--b") "aB") "empty parts are dropped")
    (assert (= (r/camelId "solo") "solo") "a single word is unchanged")
    (assert (= (r/camelId "") "") "an empty id stays empty")
    true)
