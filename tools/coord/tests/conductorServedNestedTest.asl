(module asl-tools/coord/tests/conductorServedNestedTest
  :x [runTests]
  :i [(asl-tools/coord/conductor :a cd)])

; (:m :ref REVIEW-DEFER :do "the real Leon output wraps its receipt as (:agent :receipt (:agentReceipt ... :servedAlias A ...)); node2 2026-11-12 journalled every write as model unknown from it and 10 units deferred on writerFamily")
fn ! runTests -> Bool
  (let [(real "(:agent :receipt (:agentReceipt :status :needsReview :stop needsReview :lastStep (:turn 1 :op \"gate\") :servedAlias \"nimNemotronUltra\" :servedModel \"nvidia/nemotron-3-ultra-550b-a55b\" :phases () :session \"47\" :usage (:input 9420 :cached 0 :output 8) :batching (:opsPerTurn 1.0)))")
        (modelOnly "(:agent :receipt (:agentReceipt :servedModel \"m/x\" :usage (:input 1)))")
        (echoed (str "(:tool :out \":servedAlias evil\")\n" real))
        (none "(:agent :receipt (:agentReceipt :turns 3 :usage (:input 1)))")]
    (do
      (assert (= (cd/servedAliasOf real) "nimNemotronUltra") "a nested receipt names its served alias")
      (assert (= (cd/servedModel real) "nimNemotronUltra") "the journalled model of a nested receipt is the alias")
      (assert (= (cd/servedModel modelOnly) "m/x") "a nested receipt with only :servedModel gives that model")
      (assert (= (cd/servedAliasOf echoed) "nimNemotronUltra") "an echoed line earlier never decides")
      (assert (= (cd/servedModel none) "unknown") "a nested receipt naming nothing stays unknown")
      true))
