(module asl-gates/ruleCheckers :x [RuleCheckResult makeRuleCheckResult auditGradingRule auditConceptsRule auditOwnershipDisjointness auditHiddenTestsRule auditBoundedRule auditOutputRule auditRuntimeOnlyRules auditC3Duplicates auditD51Convergence auditCheckScriptExistence] :i [])

(schema RuleCheckResult (:f ruleId Str) (:f passed Bool) (:f message Str))

fn makeRuleCheckResult ruleId: Str passed: Bool message: Str -> RuleCheckResult
  (RuleCheckResult :ruleId ruleId :passed passed :message message)

fn pathsOverlap? p: Str vp: Str -> Bool
  (or (= p vp) (or (stringStartsWith? p (str vp "/")) (stringStartsWith? vp (str p "/"))))

fn auditGradingRule ownerRole: Str verifierRole: Str authorPaths: (List Str) verifierPaths: (List Str) -> RuleCheckResult
  (if (= ownerRole verifierRole) (makeRuleCheckResult "grading" false "author cannot grade its own work: ownerRole equals verificationRole") (let [(overlap (filter (fn [(p Str)] -> Bool (not (listEmpty? (filter (fn [(vp Str)] -> Bool (pathsOverlap? p vp)) verifierPaths)))) authorPaths))] (if (not (listEmpty? overlap)) (makeRuleCheckResult "grading" false "author paths intersect verifier paths") (makeRuleCheckResult "grading" true "grading separation verified"))))

fn auditConceptsRule citations: (List Str) existingFiles: (List Str) -> RuleCheckResult
  (let [(missing (filter (fn [(c Str)] -> Bool (listEmpty? (filter (fn [(f Str)] -> Bool (= f c)) existingFiles))) citations))] (if (not (listEmpty? missing)) (makeRuleCheckResult "concepts" false "concept claim cites nonexistent source") (makeRuleCheckResult "concepts" true "all concept citations grounded")))

fn ownsCollide? a: (List Str) b: (List Str) -> Bool
  (not (listEmpty? (filter (fn [(p Str)] -> Bool (not (listEmpty? (filter (fn [(q Str)] -> Bool (pathsOverlap? p q)) b)))) a)))

fn anyOwnsCollision? tasksOwns: (List (List Str)) -> Bool
  (mt (listHead tasksOwns) ((none) false) ((some h) (let [(rest (optionOr (listTail tasksOwns) (list)))] (if (not (listEmpty? (filter (fn [(o (List Str))] -> Bool (ownsCollide? h o)) rest))) true (anyOwnsCollision? rest)))))

fn auditOwnershipDisjointness tasksOwns: (List (List Str)) -> RuleCheckResult
  (if (anyOwnsCollision? tasksOwns) (makeRuleCheckResult "oneStep" false "a path is owned by two tasks") (makeRuleCheckResult "oneStep" true "ownership disjointness verified"))

fn auditHiddenTestsRule implementerOwns: (List Str) -> RuleCheckResult
  (let [(leaks (filter (fn [(p Str)] -> Bool (stringContains? p "tests/acceptance")) implementerOwns))] (if (not (listEmpty? leaks)) (makeRuleCheckResult "hiddenTests" false "implementer cannot own grader acceptance tests") (makeRuleCheckResult "hiddenTests" true "hidden tests protection verified")))

fn auditBoundedRule callSites: (List Str) -> RuleCheckResult
  (let [(unbounded (filter (fn [(cs Str)] -> Bool (not (stringContains? cs ":limit"))) callSites))] (if (not (listEmpty? unbounded)) (makeRuleCheckResult "bounded" false "read call site missing :limit") (makeRuleCheckResult "bounded" true "all read call sites bounded")))

fn hasPathEvidence? r: Str -> Bool
  (or (stringContains? r ":path ") (or (stringContains? r "(:path ") (or (stringContains? r "(:path\t") (stringContains? r ":path\t"))))

fn hasLineEvidence? r: Str -> Bool
  (or (stringContains? r ":line ") (or (stringContains? r "(:line ") (or (stringContains? r "(:line\t") (stringContains? r ":line\t"))))

fn auditOutputRule receipts: (List Str) -> RuleCheckResult
  (let [(invalid (filter (fn [(r Str)] -> Bool (or (not (hasPathEvidence? r)) (not (hasLineEvidence? r)))) receipts))] (if (not (listEmpty? invalid)) (makeRuleCheckResult "output" false "receipt missing path or line") (makeRuleCheckResult "output" true "typed receipt evidence verified")))

fn auditRuntimeOnlyRules ruleEntries: (List Str) -> RuleCheckResult
  (let [(budgetOk (not (listEmpty? (filter (fn [(e Str)] -> Bool (and (stringContains? e ":id budget") (stringContains? e ":runtimeOnlyReason"))) ruleEntries)))) (edgeOk (not (listEmpty? (filter (fn [(e Str)] -> Bool (and (stringContains? e ":id edge") (stringContains? e ":runtimeOnlyReason"))) ruleEntries))))] (if (and budgetOk edgeOk) (makeRuleCheckResult "runtimeOnly" true "budget and edge explicitly declared runtime-only with reason") (makeRuleCheckResult "runtimeOnly" false "runtime-only rule missing explicit reason")))

fn isC3Violation? def: (List Str) allowlist: (List Str) canonicalHomes: (List (List Str)) -> Bool
  (let [(sym (optionOr (listHead def) ""))] (if (listContains? allowlist sym) false (let [(matchingHome (filter (fn [(ch (List Str))] -> Bool (= (optionOr (listHead ch) "") sym)) canonicalHomes))] (if (not (listEmpty? matchingHome)) (let [(homeEntry (optionOr (listHead matchingHome) (list))) (homePkg (optionOr (listGet homeEntry 1) "")) (defPkgs (optionOr (listTail def) (list))) (outsideHome (filter (fn [(pkg Str)] -> Bool (not (= pkg homePkg))) defPkgs))] (not (listEmpty? outsideHome))) (> (listLength def) 2)))))

fn auditC3Duplicates symbolDefs: (List (List Str)) allowlist: (List Str) canonicalHomes: (List (List Str)) -> RuleCheckResult
  (let [(duplicates (filter (fn [(def (List Str))] -> Bool (isC3Violation? def allowlist canonicalHomes)) symbolDefs))] (if (not (listEmpty? duplicates)) (makeRuleCheckResult "c3" false "duplicate capability outside canonical home detected across packages") (makeRuleCheckResult "c3" true "c3 symbol uniqueness and canonical home invariant verified")))

fn ! auditCheckScriptExistence scriptPaths: (List Str) -> RuleCheckResult
  (let [(missing (filter (fn [(p Str)] -> Bool (mt (fileRead p) ((ok _) false) ((err _) true))) scriptPaths))] (if (not (listEmpty? missing)) (makeRuleCheckResult "checkScriptExistence" false (str "declared verification script not found: " (stringJoin missing ", "))) (makeRuleCheckResult "checkScriptExistence" true "all declared verification check scripts exist on disk")))

fn auditD51Convergence packageName: Str testFns: (List Str) asnKeys: (List Str) currentRatio: I64 baselineFloor: I64 -> RuleCheckResult
  (if (< currentRatio baselineFloor) (makeRuleCheckResult "d51" false (str "package " packageName " regressed below baseline floor")) (let [(kebabTests (filter (fn [(fnName Str)] -> Bool (stringContains? fnName "-")) testFns))] (if (and (> baselineFloor 80) (not (listEmpty? kebabTests))) (makeRuleCheckResult "d51" false (str "kebab-case test function detected in converged package " packageName)) (makeRuleCheckResult "d51" true (str "package " packageName " satisfies D51 convergence floor")))))
