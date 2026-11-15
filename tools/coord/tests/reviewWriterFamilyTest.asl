(module asl-tools/coord/tests/reviewWriterFamilyTest
  :x [runTests]
  :i [(asl-tools/coord/ladder :a l) (asl-tools/coord/reviewStage :a rs) (asl-parser/reader :a rd)])

; (:m :ref REVIEW-WRITER-FAMILY :do "the writer family of a gateway profile comes from its writing routes only: the grade routes name reviewers, so a profile that writes on deepseek and grades on moonshot and zhipu is a deepseek writer and the moonshot lane may review it; a profile whose writing routes span three families still gets no lane")
fn gw -> String
  (str "(:gateway :models () :profiles ("
       "(:profile :id leon :routes ((:intent plan :chain (synDs41Flash synDs41Infinite)) (:intent grade :chain (synGlm53 synKimiK31Pro)) (:intent code :chain (synDs41Flash synDs41Infinite)) (:intent any :chain (synDs41Flash synDs41Infinite))))"
       " (:profile :id wide :routes ((:intent code :chain (synDs41Flash synKimiK31Pro synGlm53)))) ))")

fn lt -> String
  (str "(:reviewLanes :v 1 :lanes ((:lane :alias synDs41Flash :tier paid :quality 0 :allowance 5) (:lane :alias synKimiK31Pro :tier strong :quality 0 :allowance 5)))")

fn pool -> (List l/Lane)
  (list (l/Lane :alias "synDs41Flash" :tier "paid" :allowance 5 :quality 0) (l/Lane :alias "synKimiK31Pro" :tier "strong" :allowance 5 :quality 0))

fn picked rows: (List rd/SExpr) writer: String tier: String -> String
  (match (l/selectOne rows writer tier (pool))
    ((l/pickOk ls) (stringJoin (map (fn [(x l/Lane)] -> String x.alias) ls) ","))
    ((l/pickAwait a w) ""))

fn ! runTests -> Bool
  (let [(rows (l/familyRows (rs/tableFor (lt))))
        (w (rs/writerAliasFor (gw) (lt) "leon"))
        (wide (rs/writerAliasFor (gw) (lt) "wide"))]
    (do (assert (= (rs/profileChain (gw) "leon") (list "synDs41Flash" "synDs41Infinite")) (str "the grade route chain is not in the writer chain: " (stringJoin (rs/profileChain (gw) "leon") ",")))
        (assert (= (picked rows w "strong") "synKimiK31Pro") (str "a leon write picks the moonshot strong lane: " w))
        (assert (= (picked rows "synKimiK31Pro" "paid") "synDs41Flash") "a moonshot writer picks the deepseek paid lane")
        (assert (= (picked rows "synDs41Flash" "strong") "synKimiK31Pro") "a deepseek writer picks the moonshot strong lane")
        (assert (and (= (picked rows wide "strong") "") (= (picked rows wide "paid") "")) (str "a profile writing on three families gets no lane: " wide))
        (assert (= (picked rows "unknown" "strong") "") "an unknown writer gets no lane")
        true))
