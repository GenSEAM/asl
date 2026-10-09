(module aslGateway/budget
  :x [BudgetScope Period BudgetLine Approval Charge Bucket Ledger Action Decision BudgetError Candidate
      scopeEndpoint scopeProvider scopeUnit scopeGlobal periodHour periodDay periodUnit
      actionDeploy actionScaleUp actionTierChange actionRequest actionScaleDown actionStop
      makeLedger parseBudgetConfig periodStart bucketCount charge gate withinBudget]
  :i [(asl-parser/reader :a rd)
      (aslGateway/config :a cfg)])

(enum BudgetScope
  (:c scopeEndpoint [(key String)])
  (:c scopeProvider [(key String)])
  (:c scopeUnit [(key String)])
  (:c scopeGlobal []))

(enum Period
  (:c periodHour [])
  (:c periodDay [])
  (:c periodUnit []))

(schema BudgetLine
  (:f id String)
  (:f scope BudgetScope)
  (:f period Period)
  (:f cap Int64)
  (:f approved Bool))

(schema Approval
  (:f endpoint String)
  (:f cap Int64))

(schema Charge
  (:f endpoint String)
  (:f provider String)
  (:f unit String)
  (:f atMs Int64)
  (:f cost Int64))

(schema Bucket
  (:f lineId String)
  (:f periodStart Int64)
  (:f amount Int64))

(schema Ledger
  (:f lines (List BudgetLine))
  (:f approvals (List Approval))
  (:f buckets (List Bucket))
  (:f maxBuckets Int64))

(enum Action
  (:c actionDeploy [(endpoint String)])
  (:c actionScaleUp [(endpoint String) (provider String) (unit String) (expectedCost Int64)])
  (:c actionTierChange [(endpoint String) (provider String) (unit String) (expectedCost Int64)])
  (:c actionRequest [(endpoint String) (provider String) (unit String) (expectedCost Int64)])
  (:c actionScaleDown [(endpoint String)])
  (:c actionStop [(endpoint String)]))

(enum Decision
  (:c allow [])
  (:c deny [(reason String)]))

(enum BudgetError
  (:c overCap []))

(schema Candidate
  (:f endpoint String)
  (:f provider String)
  (:f unit String)
  (:f expectedCost Int64))

fn requiredBudgetField props: (Map String rd/SExpr) key: String -> (Result rd/SExpr String)
  (mt (mapGet props key)
    ((some expr) (ok expr))
    ((none) (err (str "budget config missing :" key))))

fn budgetString expr: rd/SExpr what: String -> (Result String String)
  (mt (cfg/asnScalar expr)
    ((cfg/scalarStr value) (ok value))
    (_ (err (str "budget config " what " must be a string"))))

fn budgetQuotedString expr: rd/SExpr what: String -> (Result String String)
  (mt expr
    ((rd/sexprAtom raw)
      (if (and (stringStartsWith? raw "\"") (stringEndsWith? raw "\""))
        (budgetString expr what)
        (err (str "budget config " what " must be quoted"))))
    (_ (err (str "budget config " what " must be quoted"))))

fn budgetInt expr: rd/SExpr what: String -> (Result Int64 String)
  (mt (cfg/asnScalar expr)
    ((cfg/scalarInt value) (ok value))
    (_ (err (str "budget config " what " must be an integer"))))

fn budgetBool expr: rd/SExpr what: String -> (Result Bool String)
  (mt (cfg/asnScalar expr)
    ((cfg/scalarBool value) (ok value))
    (_ (err (str "budget config " what " must be a boolean"))))

fn budgetScope scopeExpr: rd/SExpr keyExpr: rd/SExpr -> (Result BudgetScope String)
  (mt (budgetString scopeExpr "line scope")
    ((err e) (err e))
    ((ok scopeName)
      (if (= scopeName "global")
        (ok (scopeGlobal))
        (mt (budgetQuotedString keyExpr "scope key")
          ((err e) (err e))
          ((ok key)
            (cond
              ((and (= scopeName "endpoint") (not (stringEmpty? key))) (ok (scopeEndpoint key)))
              ((and (= scopeName "provider") (not (stringEmpty? key))) (ok (scopeProvider key)))
              ((and (= scopeName "unit") (not (stringEmpty? key))) (ok (scopeUnit key)))
              (else (err "budget config has invalid scope or empty scope key"))))))))

fn budgetPeriod expr: rd/SExpr -> (Result Period String)
  (mt (budgetString expr "line period")
    ((err e) (err e))
    ((ok name)
      (cond
        ((= name "hour") (ok (periodHour)))
        ((= name "day") (ok (periodDay)))
        ((= name "unit") (ok (periodUnit)))
        (else (err (str "budget config has unknown period " name))))))

fn parseBudgetLine form: rd/SExpr -> (Result BudgetLine String)
  (mt (cfg/asnProps form (some ":line"))
    ((err e) (err e))
    ((ok props)
      (mt (requiredBudgetField props "id")
        ((err e) (err e))
        ((ok idExpr)
          (mt (budgetQuotedString idExpr "line id")
            ((err e) (err e))
            ((ok id)
              (mt (requiredBudgetField props "scope")
                ((err e) (err e))
                ((ok scopeExpr)
                  (mt (requiredBudgetField props "key")
                    ((err e) (err e))
                    ((ok keyExpr)
                      (mt (budgetScope scopeExpr keyExpr)
                        ((err e) (err e))
                        ((ok scope)
                          (mt (requiredBudgetField props "period")
                            ((err e) (err e))
                            ((ok periodExpr)
                              (mt (budgetPeriod periodExpr)
                                ((err e) (err e))
                                ((ok period)
                                  (mt (requiredBudgetField props "cap")
                                    ((err e) (err e))
                                    ((ok capExpr)
                                      (mt (budgetInt capExpr "line cap")
                                        ((err e) (err e))
                                        ((ok cap)
                                          (mt (requiredBudgetField props "approved")
                                            ((err e) (err e))
                                            ((ok approvedExpr)
                                              (mt (budgetBool approvedExpr "line approval")
                                                ((err e) (err e))
                                                ((ok approved)
                                                  (if (or (stringEmpty? id) (< cap 0))
                                                    (err "budget config line id must be nonempty and cap nonnegative")
                                                    (ok (BudgetLine :id id :scope scope :period period :cap cap :approved approved)))))))))))))))))))))))))))

fn parseBudgetLines forms: (List rd/SExpr) -> (Result (List BudgetLine) String)
  (mt (listHead forms)
    ((none) (ok []))
    ((some form)
      (mt (parseBudgetLine form)
        ((err e) (err e))
        ((ok line)
          (mt (parseBudgetLines (optionOr (listTail forms) []))
            ((err e) (err e))
            ((ok rest) (ok (cons line rest))))))))

fn parseBudgetApproval form: rd/SExpr -> (Result Approval String)
  (mt (cfg/asnProps form (some ":approval"))
    ((err e) (err e))
    ((ok props)
      (mt (requiredBudgetField props "endpoint")
        ((err e) (err e))
        ((ok endpointExpr)
          (mt (budgetQuotedString endpointExpr "approval endpoint")
            ((err e) (err e))
            ((ok endpoint)
              (mt (requiredBudgetField props "cap")
                ((err e) (err e))
                ((ok capExpr)
                  (mt (budgetInt capExpr "approval cap")
                    ((err e) (err e))
                    ((ok cap)
                      (if (or (stringEmpty? endpoint) (< cap 0))
                        (err "budget config approval endpoint must be nonempty and cap nonnegative")
                        (ok (Approval :endpoint endpoint :cap cap)))))))))))))

fn parseBudgetApprovals forms: (List rd/SExpr) -> (Result (List Approval) String)
  (mt (listHead forms)
    ((none) (ok []))
    ((some form)
      (mt (parseBudgetApproval form)
        ((err e) (err e))
        ((ok approval)
          (mt (parseBudgetApprovals (optionOr (listTail forms) []))
            ((err e) (err e))
            ((ok rest) (ok (cons approval rest))))))))

fn parseBudgetVector expr: rd/SExpr what: String -> (Result (List rd/SExpr) String)
  (mt expr
    ((rd/sexprVect items) (ok items))
    (_ (err (str "budget config :" what " must be a vector"))))

fn parseBudgetConfig form: rd/SExpr maxBuckets: Int64 -> (Result Ledger String)
  (mt (cfg/asnProps form (some ":budgetConfig"))
    ((err e) (err e))
    ((ok props)
      (mt (requiredBudgetField props "lines")
        ((err e) (err e))
        ((ok linesExpr)
          (mt (parseBudgetVector linesExpr "lines")
            ((err e) (err e))
            ((ok lineForms)
              (mt (parseBudgetLines lineForms)
                ((err e) (err e))
                ((ok lines)
                  (mt (requiredBudgetField props "approvals")
                    ((err e) (err e))
                    ((ok approvalsExpr)
                      (mt (parseBudgetVector approvalsExpr "approvals")
                        ((err e) (err e))
                        ((ok approvalForms)
                          (mt (parseBudgetApprovals approvalForms)
                            ((err e) (err e))
                            ((ok approvals)
                              (if (< maxBuckets 0)
                                (err "budget config maxBuckets must be nonnegative")
                                (ok (makeLedger lines approvals maxBuckets)))))))))))))))))

fn makeLedger lines: (List BudgetLine) approvals: (List Approval) maxBuckets: Int64 -> Ledger
  (Ledger :lines lines :approvals approvals :buckets [] :maxBuckets (if (> maxBuckets 0) maxBuckets 0))

fn periodStart period: Period nowMs: Int64 -> Int64
  (mt period
    ((periodHour) (* (/ nowMs 3600000) 3600000))
    ((periodDay) (* (/ nowMs 86400000) 86400000))
    ((periodUnit) 0))

fn bucketCount ledger: Ledger -> Int64
  (listLength ledger.buckets)

fn scopeMatches scope: BudgetScope endpoint: String provider: String unit: String -> Bool
  (mt scope
    ((scopeEndpoint key) (= key endpoint))
    ((scopeProvider key) (= key provider))
    ((scopeUnit key) (= key unit))
    ((scopeGlobal) true))

fn lineMatches line: BudgetLine event: Charge -> Bool
  (scopeMatches line.scope event.endpoint event.provider event.unit)

fn endpointApprovalScopeMatches scope: BudgetScope endpoint: String -> Bool
  (mt scope
    ((scopeEndpoint key) (= key endpoint))
    (_ false))

fn spentFor buckets: (List Bucket) lineId: String start: Int64 -> Int64
  (mt (listHead buckets)
    ((none) 0)
    ((some bucket)
      (if (and (= bucket.lineId lineId) (= bucket.periodStart start))
        bucket.amount
        (spentFor (optionOr (listTail buckets) []) lineId start))))

fn allWithin lines: (List BudgetLine) buckets: (List Bucket) event: Charge -> Bool
  (mt (listHead lines)
    ((none) true)
    ((some line)
      (if (lineMatches line event)
        (let [(start (periodStart line.period event.atMs))
              (spent (spentFor buckets line.id start))]
          (and (>= line.cap 0)
               (<= spent line.cap)
               (<= event.cost (- line.cap spent))
               (allWithin (optionOr (listTail lines) []) buckets event)))
        (allWithin (optionOr (listTail lines) []) buckets event))))

fn upsertBucket buckets: (List Bucket) lineId: String start: Int64 cost: Int64 -> (List Bucket)
  (mt (listHead buckets)
    ((none) [(Bucket :lineId lineId :periodStart start :amount cost)])
    ((some bucket)
      (if (and (= bucket.lineId lineId) (= bucket.periodStart start))
        (listAppend [(Bucket :lineId lineId :periodStart start :amount (+ bucket.amount cost))] (optionOr (listTail buckets) []))
        (listAppend [bucket] (upsertBucket (optionOr (listTail buckets) []) lineId start cost)))))

fn updateBuckets ledger: Ledger lines: (List BudgetLine) event: Charge -> (List Bucket)
  (mt (listHead lines)
    ((none) ledger.buckets)
    ((some line)
      (if (lineMatches line event)
        (let [(start (periodStart line.period event.atMs))
              (next (upsertBucket ledger.buckets line.id start event.cost))]
          (updateBuckets (with ledger :buckets next) (optionOr (listTail lines) []) event))
        (updateBuckets ledger (optionOr (listTail lines) []) event))))

fn charge ledger: Ledger event: Charge -> (Result Ledger BudgetError)
  (if (or (< event.cost 0) (not (allWithin ledger.lines ledger.buckets event)))
    (err (overCap))
    (let [(updated (updateBuckets ledger ledger.lines event))]
      (if (> (listLength updated) ledger.maxBuckets)
        (err (overCap))
        (ok (with ledger :buckets updated)))))

fn approvalExists approvals: (List Approval) endpoint: String cap: Int64 -> Bool
  (mt (listHead approvals)
    ((none) false)
    ((some approval)
      (or (and (= approval.endpoint endpoint) (= approval.cap cap))
          (approvalExists (optionOr (listTail approvals) []) endpoint cap))))

fn approvalForEndpointExists approvals: (List Approval) endpoint: String -> Bool
  (mt (listHead approvals)
    ((none) false)
    ((some approval)
      (or (= approval.endpoint endpoint)
          (approvalForEndpointExists (optionOr (listTail approvals) []) endpoint))))

fn approvalForPaidEndpoint lines: (List BudgetLine) approvals: (List Approval) endpoint: String -> Bool
  (mt (listHead lines)
    ((none) true)
    ((some line)
      (if (and (> line.cap 0) (endpointApprovalScopeMatches line.scope endpoint))
        (and (approvalExists approvals endpoint line.cap)
             (approvalForPaidEndpoint (optionOr (listTail lines) []) approvals endpoint))
        (approvalForPaidEndpoint (optionOr (listTail lines) []) approvals endpoint))))

fn approvedRaisedCaps lines: (List BudgetLine) approvals: (List Approval) endpoint: String -> Bool
  (mt (listHead lines)
    ((none) true)
    ((some line)
      (if (and (> line.cap 0) (endpointApprovalScopeMatches line.scope endpoint))
        (and (if line.approved
               (approvalExists approvals endpoint line.cap)
               (or (not (approvalForEndpointExists approvals endpoint))
                   (approvalExists approvals endpoint line.cap)))
             (approvedRaisedCaps (optionOr (listTail lines) []) approvals endpoint))
        (approvedRaisedCaps (optionOr (listTail lines) []) approvals endpoint))))

fn decisionForCost ledger: Ledger endpoint: String provider: String unit: String cost: Int64 nowMs: Int64 -> Decision
  (if (< cost 0)
    (deny "negative expected cost")
    (if (not (approvedRaisedCaps ledger.lines ledger.approvals endpoint))
      (deny "raised cap lacks approval")
      (let [(candidate (Charge :endpoint endpoint :provider provider :unit unit :atMs nowMs :cost cost))]
        (if (allWithin ledger.lines ledger.buckets candidate)
          (allow)
          (deny "budget cap exceeded")))))

fn lineCovers lines: (List BudgetLine) endpoint: String provider: String unit: String -> Bool
  (listAny? (fn [(line BudgetLine)] -> Bool (scopeMatches line.scope endpoint provider unit)) lines)

fn deployCovered ledger: Ledger endpoint: String -> Bool
  (and (listAny? (fn [(line BudgetLine)] -> Bool (mt line.scope ((scopeEndpoint key) (= key endpoint)) ((scopeGlobal) true) (_ false))) ledger.lines)
       (approvalForEndpointExists ledger.approvals endpoint))

fn spendDecision ledger: Ledger endpoint: String provider: String unit: String cost: Int64 nowMs: Int64 -> Decision
  (if (not (lineCovers ledger.lines endpoint provider unit))
    (deny "no budget line covers this spend")
    (decisionForCost ledger endpoint provider unit cost nowMs))

fn gate ledger: Ledger action: Action nowMs: Int64 -> Decision
  (mt action
    ((actionDeploy endpoint)
      (if (not (deployCovered ledger endpoint))
        (deny "deploy lacks a budget line and approval for its endpoint")
        (if (or (not (approvalForPaidEndpoint ledger.lines ledger.approvals endpoint))
                (not (approvedRaisedCaps ledger.lines ledger.approvals endpoint)))
          (deny "paid deploy lacks endpoint/cap approval")
          (allow))))
    ((actionScaleDown _) (allow))
    ((actionStop _) (allow))
    ((actionScaleUp endpoint provider unit cost) (spendDecision ledger endpoint provider unit cost nowMs))
    ((actionTierChange endpoint provider unit cost) (spendDecision ledger endpoint provider unit cost nowMs))
    ((actionRequest endpoint provider unit cost) (decisionForCost ledger endpoint provider unit cost nowMs)))

fn filterCandidates ledger: Ledger candidates: (List Candidate) nowMs: Int64 -> (List Candidate)
  (mt (listHead candidates)
    ((none) [])
    ((some candidate)
      (let [(rest (filterCandidates ledger (optionOr (listTail candidates) []) nowMs))
            (decision (gate ledger (actionRequest candidate.endpoint candidate.provider candidate.unit candidate.expectedCost) nowMs))]
        (mt decision
          ((allow) (listAppend [candidate] rest))
          ((deny _) rest)))))

fn withinBudget ledger: Ledger candidates: (List Candidate) nowMs: Int64 -> (List Candidate)
  (filterCandidates ledger candidates nowMs)
