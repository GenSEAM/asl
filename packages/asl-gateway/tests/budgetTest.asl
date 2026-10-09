(module aslGateway/tests/budgetTest
  :x [runTests]
  :i [(budget :a bgt)
      (asl-parser/reader :a rd)])

fn paidLine cap: Int64 approved: Bool -> bgt/BudgetLine
  (bgt/BudgetLine :id "paid-hour" :scope (bgt/scopeEndpoint "paid-api") :period (bgt/periodHour) :cap cap :approved approved)

fn freeGlobal cap: Int64 period: bgt/Period -> bgt/BudgetLine
  (bgt/BudgetLine :id "global" :scope (bgt/scopeGlobal) :period period :cap cap :approved false)

fn approval cap: Int64 -> bgt/Approval
  (bgt/Approval :endpoint "paid-api" :cap cap)

fn event atMs: Int64 cost: Int64 -> bgt/Charge
  (bgt/Charge :endpoint "paid-api" :provider "p1" :unit "u1" :atMs atMs :cost cost)

fn ledger lines: (List bgt/BudgetLine) approvals: (List bgt/Approval) maxBuckets: Int64 -> bgt/Ledger
  (bgt/makeLedger lines approvals maxBuckets)

fn allowed action: bgt/Action nowMs: Int64 lines: (List bgt/BudgetLine) approvals: (List bgt/Approval) -> Bool
  (mt (bgt/gate (ledger lines approvals 8) action nowMs)
    ((allow) true)
    ((deny _) false))

fn testActionAllowanceAndDenial -> Bool
  (do
    (assert (allowed (bgt/actionRequest "paid-api" "p1" "u1" 40) 1000 [(paidLine 100 false)] []) "request within cap is allowed")
    (assert (not (allowed (bgt/actionRequest "paid-api" "p1" "u1" 101) 1000 [(paidLine 100 false)] [])) "request above cap denied")
    (assert (allowed (bgt/actionScaleDown "paid-api") 1000 [(paidLine 0 false)] []) "scale down always allowed")
    (assert (allowed (bgt/actionStop "paid-api") 1000 [(paidLine 0 false)] []) "stop always allowed")
    (assert (allowed (bgt/actionScaleUp "paid-api" "p1" "u1" 10) 1000 [(paidLine 100 false)] []) "scale up within cap allowed")
    (assert (not (allowed (bgt/actionScaleUp "paid-api" "p1" "u1" 101) 1000 [(paidLine 100 false)] [])) "scale up over cap denied")
    (assert (allowed (bgt/actionTierChange "paid-api" "p1" "u1" 10) 1000 [(paidLine 100 false)] []) "tier change within cap allowed")
    (assert (not (allowed (bgt/actionTierChange "paid-api" "p1" "u1" 101) 1000 [(paidLine 100 false)] [])) "tier change over cap denied")
    (assert (not (allowed (bgt/actionRequest "paid-api" "p1" "u1" -1) 1000 [(paidLine 100 false)] [])) "negative expected cost is denied")
    (assert (allowed (bgt/actionRequest "paid-api" "p1" "u1" 101) 1000 [(bgt/BudgetLine :id "provider" :scope (bgt/scopeProvider "p2") :period (bgt/periodHour) :cap 10 :approved false)] []) "nonmatching provider scope does not constrain route")
    (assert (not (allowed (bgt/actionRequest "paid-api" "p2" "u1" 11) 1000 [(bgt/BudgetLine :id "provider" :scope (bgt/scopeProvider "p2") :period (bgt/periodHour) :cap 10 :approved false)] [])) "provider scope constrains matching route")
    (assert (not (allowed (bgt/actionRequest "paid-api" "p1" "u1" 11) 1000 [(bgt/BudgetLine :id "unit" :scope (bgt/scopeUnit "u1") :period (bgt/periodHour) :cap 10 :approved false)] [])) "unit scope constrains matching route")
    true)

fn testApprovalAndRaisedCap -> Bool
  (do
    (assert (not (allowed (bgt/actionDeploy "paid-api") 0 [(paidLine 100 false)] [])) "first paid deploy requires approval record")
    (assert (allowed (bgt/actionDeploy "paid-api") 0 [(paidLine 100 false)] [(approval 100)]) "approval record permits first paid deploy")
    (assert (not (allowed (bgt/actionRequest "paid-api" "p1" "u1" 1) 0 [(paidLine 200 true)] [(approval 100)])) "raised cap without approval for new cap denied")
    (assert (not (allowed (bgt/actionRequest "paid-api" "p1" "u1" 1) 0 [(paidLine 200 false)] [(approval 100)])) "unapproved raised cap cannot bypass approval")
    (assert (allowed (bgt/actionRequest "paid-api" "p1" "u1" 1) 0 [(paidLine 200 true)] [(approval 200)]) "raised cap with approval for new cap allowed")
    true)

fn testPeriodsAndTightestLine -> Bool
  (let [(hour (bgt/periodHour))
        (day (bgt/periodDay))
        (hourLedger (ledger [(paidLine 50 false)] [] 8))
        (charged (bgt/charge hourLedger (event 3599999 40)))
        (atBoundary (mt charged ((ok l) l) ((err _) hourLedger)))
        (twoLines [(paidLine 100 false) (freeGlobal 30 hour)])]
    (do
      (assert (mt (bgt/gate atBoundary (bgt/actionRequest "paid-api" "p1" "u1" 20) 3599999) ((deny _) true) (_ false)) "hour bucket blocks excess before boundary")
      (assert (mt (bgt/gate atBoundary (bgt/actionRequest "paid-api" "p1" "u1" 20) 3600000) ((allow) true) (_ false)) "hour bucket rolls at exact boundary")
      (assert (not (allowed (bgt/actionRequest "paid-api" "p1" "u1" 31) 1 twoLines [])) "tightest matching line wins")
      (assert (= (bgt/periodStart hour 3600000) 3600000) "hour start exact boundary")
      (assert (= (bgt/periodStart day 86400000) 86400000) "day start exact boundary")
      (assert (= (bgt/periodStart day 86399999) 0) "day bucket before boundary")
      (assert (= (bgt/periodStart (bgt/periodUnit) 99) 0) "unit period retains single bucket")
      true))

fn testChargeOverflowAndBound -> Bool
  (let [(l (ledger [(paidLine 100 false)] [] 2))
        (tooBig (bgt/charge l (event 0 9223372036854775807)))
        (one (bgt/charge l (event 0 10)))
        (l1 (mt one ((ok x) x) ((err _) l)))
        (two (bgt/charge l1 (event 3600000 10)))
        (l2 (mt two ((ok x) x) ((err _) l1)))
        (three (bgt/charge l2 (event 7200000 10)))
        (l3 (mt three ((ok x) x) ((err _) l2)))
        (multiLines (ledger [(paidLine 100 false) (freeGlobal 30 (bgt/periodHour))] [] 8))
        (multiCharge (bgt/charge multiLines (event 0 20)))
        (multiLedger (mt multiCharge ((ok x) x) ((err _) multiLines)))
        (unitLines (ledger [(bgt/BudgetLine :id "endpoint-unit" :scope (bgt/scopeEndpoint "paid-api") :period (bgt/periodUnit) :cap 10 :approved false)
                            (bgt/BudgetLine :id "provider-unit" :scope (bgt/scopeProvider "p1") :period (bgt/periodUnit) :cap 10 :approved false)] [] 1))
        (zeroCapacity (bgt/charge (ledger [(paidLine 100 false)] [] 0) (event 0 1)))]
    (do
      (assert (err? tooBig) "overflowing or over-cap charge is rejected without integer overflow")
      (assert (err? (bgt/charge l (event 0 -1))) "negative charge is rejected")
      (assert (ok? one) "first charge succeeds")
      (assert (ok? two) "second period bucket succeeds")
      (assert (err? three) "charge fails closed when a new period would exceed bucket capacity")
      (assert (= (bgt/bucketCount l3) 2) "rejected charge preserves bounded ledger")
      (assert (= (bgt/bucketCount multiLedger) 2) "charge updates each matching budget line")
      (assert (err? (bgt/charge multiLedger (event 0 11))) "charge rejects when any matching line would exceed its cap")
      (assert (err? (bgt/charge unitLines (event 0 8))) "active unit buckets are not evicted when capacity cannot retain them")
      (assert (err? zeroCapacity) "zero bucket capacity fails closed instead of forgetting spend")
      true))

fn ! testCandidateFilteringAndFixture -> Bool
  (let [(candidates [(bgt/Candidate :endpoint "paid-api" :provider "p1" :unit "u1" :expectedCost 10) (bgt/Candidate :endpoint "paid-api" :provider "p2" :unit "u2" :expectedCost 101) (bgt/Candidate :endpoint "paid-api" :provider "p3" :unit "u3" :expectedCost 20)])
        (fixture (fileReadString "asl/packages/asl-gateway/tests/fixtures/budget/config.asn"))
        (parsed (mt fixture ((ok text) (rd/parseSexpr text)) ((err _) (rd/makeAtom ""))))
        (configured (bgt/parseBudgetConfig parsed 4))
        (filtered (bgt/withinBudget (ledger [(paidLine 100 false)] [] 4) candidates 0))]
    (do
      (assert (= (listLength filtered) 2) "routing keeps only affordable candidates")
      (assert (= (optionOr (listHead filtered) (bgt/Candidate :endpoint "" :provider "" :unit "" :expectedCost 0)).provider "p1") "routing preserves input order")
      (assert (= (optionOr (listGet filtered 1) (bgt/Candidate :endpoint "" :provider "" :unit "" :expectedCost 0)).provider "p3") "routing preserves order across a rejected middle candidate")
      (assert (mt parsed ((sexprList _) true) (_ false)) "ASN budget fixture parses as a form")
      (assert (= (rd/sexprHead parsed) ":budgetConfig") "fixture declares budget config")
      (assert (stringContains? (rd/renderSexpr parsed) ":approved false") "config marks approval false rather than granting it")
      (assert (mt configured ((ok l) (= (listLength l.lines) 2)) ((err _) false)) "ASN config lines become two budget rules")
      (assert (mt configured ((ok l) (mt (bgt/gate l (bgt/actionDeploy "paid-api") 0) ((allow) true) ((deny _) false))) ((err _) false)) "ASN approval is consumed by paid deploy policy")
      (assert (mt configured ((ok l) (mt (bgt/gate l (bgt/actionRequest "paid-api" "p1" "u1" 1000001) 0) ((deny _) true) ((allow) false))) ((err _) false)) "ASN cap constrains requests through the budget gate")
      true))

fn denyReason action: bgt/Action lines: (List bgt/BudgetLine) approvals: (List bgt/Approval) -> String
  (mt (bgt/gate (ledger lines approvals 8) action 1000)
    ((allow) "")
    ((deny reason) reason))

fn ! testDefaultDenySpend -> Bool
  (let [(other (bgt/BudgetLine :id "other" :scope (bgt/scopeEndpoint "other-api") :period (bgt/periodHour) :cap 100 :approved false))
        (global (bgt/BudgetLine :id "global" :scope (bgt/scopeGlobal) :period (bgt/periodDay) :cap 100 :approved false))
        (provider (bgt/BudgetLine :id "provider" :scope (bgt/scopeProvider "p1") :period (bgt/periodHour) :cap 100 :approved false))]
    (do
      (assert (not (allowed (bgt/actionDeploy "paid-api") 0 [] [])) "deploy without any budget line is denied")
      (assert (= (denyReason (bgt/actionDeploy "paid-api") [] []) "deploy lacks a budget line and approval for its endpoint") "deploy denial names the missing line and approval")
      (assert (not (allowed (bgt/actionDeploy "paid-api") 0 [other] [(approval 100)])) "deploy under another endpoint's line is denied")
      (assert (not (allowed (bgt/actionDeploy "paid-api") 0 [global] [])) "deploy under a global line still needs an approval for its endpoint")
      (assert (allowed (bgt/actionDeploy "paid-api") 0 [global] [(approval 100)]) "deploy under a global line with an endpoint approval is allowed")
      (assert (not (allowed (bgt/actionScaleUp "paid-api" "p1" "u1" 10) 1000 [] [])) "scale up without any budget line is denied")
      (assert (= (denyReason (bgt/actionScaleUp "paid-api" "p1" "u1" 10) [] []) "no budget line covers this spend") "scale-up denial names the missing line")
      (assert (not (allowed (bgt/actionScaleUp "paid-api" "p1" "u1" 10) 1000 [other] [])) "scale up under another endpoint's line is denied")
      (assert (allowed (bgt/actionScaleUp "paid-api" "p1" "u1" 10) 1000 [provider] []) "scale up under a matching provider line is allowed within cap")
      (assert (not (allowed (bgt/actionTierChange "paid-api" "p1" "u1" 10) 1000 [] [])) "tier change without any budget line is denied")
      (assert (allowed (bgt/actionScaleDown "paid-api") 1000 [] []) "scale down needs no line")
      (assert (allowed (bgt/actionStop "paid-api") 1000 [] []) "stop needs no line")
      (assert (allowed (bgt/actionRequest "paid-api" "p1" "u1" 10) 1000 [] []) "a request without a line stays allowed: unmetered routes are not spend actions")
      true))

fn ! runTests -> Bool
  (do
    (assert (testActionAllowanceAndDenial) "action decisions")
    (assert (testApprovalAndRaisedCap) "approval policy")
    (assert (testPeriodsAndTightestLine) "periods and matching limits")
    (assert (testChargeOverflowAndBound) "charge safety and bounded buckets")
    (assert (testCandidateFilteringAndFixture) "routing and ASN fixture")
    (assert (testDefaultDenySpend) "default deny for spend actions")
    true)
