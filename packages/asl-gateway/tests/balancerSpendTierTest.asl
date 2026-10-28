(module aslGateway/tests/balancerSpendTierTest
  :x [runTests]
  :i [(aslGateway/balancer :a bl)])

; (:m :ref SPEND-TIERS-20261026 :do "free and subscription lanes go before paid ones: three http models of equal fitness (same declared quality, same zero cost, identical budgets at the same use), the paid one listed first so a tie would pick it")

fn noon -> Int64 43200000

fn budget id: String -> bl/Budget
  (bl/Budget :id id :windowMs 86400000 :anchorMs 0 :headerWindowMs 0 :unit "req" :size 10 :softPct 100 :hardPct 100 :useOrLose false :source "declared")

fn model id: String tier: bl/Tier -> bl/PoolModel
  (bl/PoolModel :id id :provider id :tier tier :why "fixture" :budgets (list (str id "Day")) :costMicros 0 :declaredQuality (some 700))

fn bal models: (List bl/PoolModel) -> bl/Balancer
  (bl/makeBalancer models (map (fn [(m bl/PoolModel)] -> bl/Budget (budget (str m.id "Day"))) models) (list)
                   (bl/Policy :mode (bl/modeBalanced) :exploreEvery 0 :softFactor 100))

fn pickedId p: bl/Pick -> String
  (match p ((bl/picked id _ _ _) id) ((bl/refused r) (str "refused " r)))

fn pickOf b: bl/Balancer use: (Map String bl/Window) -> String
  (pickedId (bl/pick b use (bl/Request :seq 1 :atMs (noon) :intent "any" :tokens 10)))

fn fill b: bl/Balancer id: String -> (Map String bl/Window)
  (fold (fn [(acc (Map String bl/Window)) (i Int64)] -> (Map String bl/Window) (bl/chargeUse b acc id (noon) 10)) (bl/emptyUse) (range 0 10))

fn runTests -> Bool
  (let [(paidFree (bal (list (model "pPaid" (bl/tierPaid)) (model "pFree" (bl/tierFree)))))
        (paidSub (bal (list (model "pPaid" (bl/tierPaid)) (model "pSub" (bl/tierSub)))))]
    (do
      (assert (= (pickOf paidFree (bl/emptyUse)) "pFree") "of equal fitness the free lane is picked before the paid one listed first")
      (assert (= (pickOf paidSub (bl/emptyUse)) "pSub") "a subscription lane is picked before an equal paid one")
      (assert (= (pickOf paidFree (fill paidFree "pFree")) "pPaid") "the paid lane serves once the free one is at its hard cap")
      true))
