(module aslHarness/auditProtocol :x [AuditFinding AuditVerdict MetaAuditReport makeAuditFinding makeAuditVerdict makeMetaAuditReport isCrutchFinding? isCriticalFinding? evaluateAuditFindings isMetaAuditAdequate? formatFindingAsn formatVerdictAsn] :i [])

(schema AuditFinding (:f category Str) (:f filePath Str) (:f symbol Str) (:f anchor Str) (:f description Str) (:f intentRationale Str) (:f remediationGate Str))

(schema AuditVerdict (:f passed Bool) (:f verdictTag Str) (:f totalFindings I64) (:f crutchCount I64) (:f findings (List AuditFinding)))

(schema MetaAuditReport (:f primaryAuditor Str) (:f isAdequate Bool) (:f adequacyScore I64) (:f checkedCategories (List Str)) (:f missingGaps (List Str)))

fn makeAuditFinding cat: Str file: Str sym: Str anc: Str desc: Str intent: Str gate: Str -> AuditFinding
  (AuditFinding :category cat :filePath file :symbol sym :anchor anc :description desc :intentRationale intent :remediationGate gate)

fn makeAuditVerdict passed: Bool tag: Str total: I64 crutches: I64 findings: (List AuditFinding) -> AuditVerdict
  (AuditVerdict :passed passed :verdictTag tag :totalFindings total :crutchCount crutches :findings findings)

fn makeMetaAuditReport auditor: Str adequate: Bool score: I64 cats: (List Str) gaps: (List Str) -> MetaAuditReport
  (MetaAuditReport :primaryAuditor auditor :isAdequate adequate :adequacyScore score :checkedCategories cats :missingGaps gaps)

fn isCrutchFinding? f: AuditFinding -> Bool
  (= f.category "crutch-scaffolding")

fn isCriticalFinding? f: AuditFinding -> Bool
  (or (= f.category "architectural-drift") (= f.category "vacuous-verification"))

fn evaluateAuditFindings findings: (List AuditFinding) -> AuditVerdict
  (let [(total (listLength findings))] (if (= total 0) (AuditVerdict :passed true :verdictTag "approve" :totalFindings 0 :crutchCount 0 :findings (list)) (let [(crutches (filter (fn [(f AuditFinding)] -> Bool (isCrutchFinding? f)) findings)) (criticals (filter (fn [(f AuditFinding)] -> Bool (isCriticalFinding? f)) findings)) (crutchLen (listLength crutches)) (critLen (listLength criticals)) (hasCritical (> critLen 0)) (hasCrutch (> crutchLen 0)) (verdictTag (if hasCritical "reject" (if hasCrutch "approve-with-amendments" "approve-with-amendments"))) (isPassed (not hasCritical))] (AuditVerdict :passed isPassed :verdictTag verdictTag :totalFindings total :crutchCount crutchLen :findings findings))))

fn isMetaAuditAdequate? report: MetaAuditReport -> Bool
  (and report.isAdequate (and (>= report.adequacyScore 80) (= (listLength report.missingGaps) 0)))

fn formatFindingAsn f: AuditFinding -> Str
  (str "(:finding" " :cat :" f.category " :file \"" f.filePath "\"" " :sym \"" f.symbol "\"" " :anchor \"" f.anchor "\"" " :desc \"" f.description "\"" " :why \"" f.intentRationale "\"" " :gate \"" f.remediationGate "\")")

fn formatVerdictAsn v: AuditVerdict -> Str
  (let [(findingStrs (map (fn [(f AuditFinding)] -> Str (formatFindingAsn f)) v.findings)) (findingsBody (stringJoin findingStrs " ")) (passStr (if v.passed "true" "false"))] (str "(:verdict" " :passed " passStr " :tag :" v.verdictTag " :total " (stringFromInt64 v.totalFindings) " :crutches " (stringFromInt64 v.crutchCount) " :findings [" findingsBody "])"))
