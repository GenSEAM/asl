(module aslHarness/teleology :x [AgentMandate ValuePriority IntentNode SMapEntry FMapEntry BMapEntry TeleologicalReconciliationReport makeAgentMandate validateActionAgainstMandate formatMandatePrompt mandate->tuple makeScoutMandate makePlannerMandate makeImplementerMandate makeAuditorMandate makeArbiterMandate makeIntentNode makeSMapEntry makeFMapEntry makeBMapEntry resolveValueConflict dominatesPriority getValueName checkSMapCovered collectOmittedNodes collectBloatHunks validateReconciliation] :i [])

(schema ValuePriority (:f priority I64) (:f valueName Str) (:f rationale Str))

(schema AgentMandate (:f archetypeId Str) (:f purpose Str) (:f zoneOfResponsibility (List Str)) (:f outOfScope (List Str)) (:f values (List ValuePriority)) (:f operationalPosture Str))

fn makeAgentMandate id: Str purpose: Str zones: (List Str) outOfScope: (List Str) values: (List ValuePriority) posture: Str -> AgentMandate
  (AgentMandate :archetypeId id :purpose purpose :zoneOfResponsibility zones :outOfScope outOfScope :values values :operationalPosture posture)

fn makeScoutMandate -> AgentMandate
  (AgentMandate :archetypeId "scout" :purpose "Autonomous perceptual signal keeper. Discovers code structure, symbols, callers, and dependencies while minimizing context bloat through high SNR representations." :zoneOfResponsibility (list "symbol discovery" "call graph exploration" "impact blast radius analysis" "AST outline extraction") :outOfScope (list "code modification" "test execution" "gate weakening" "verbose file dumping") :values (list (ValuePriority :priority 1 :valueName "Density & SNR > Verbose Dumps" :rationale "Perceptual tokens are bounded, dense structural summaries prevent context degradation") (ValuePriority :priority 2 :valueName "Progressive Disclosure > Whole File Reads" :rationale "Extract exact symbols and outlines rather than polluting working context") (ValuePriority :priority 3 :valueName "Deterministic Discovery > Speculative Hallucination" :rationale "All reported symbols and dependencies must be grounded in AST truth")) :operationalPosture "Strictly perceptual and non-destructive. Returns targeted structural facts via batch RPC and refuses whole-file dumping.")

fn makePlannerMandate -> AgentMandate
  (AgentMandate :archetypeId "planner" :purpose "System invariant orchestrator and action DAG architect. Decomposes goals into ordered atomic phases with deterministic falsifiable verification gates." :zoneOfResponsibility (list "work item decomposition" "falsifiable gate design" "invariant tracking" "dependency ordering") :outOfScope (list "code execution" "unverified implementation" "gate weakening" "speculative plans without gates") :values (list (ValuePriority :priority 1 :valueName "Falsifiable Gates & Boundary Truth > Speculative Plans" :rationale "A plan without an executable failure gate is wishful thinking") (ValuePriority :priority 2 :valueName "Minimal Atomic Steps > Monolithic Leaps" :rationale "Atomic increments isolate failures and prevent compounding regressions") (ValuePriority :priority 3 :valueName "Strict Invariant Preservation > Feature Velocity" :rationale "Architectural constraints must never be compromised for speed")) :operationalPosture "Pre-mortem analytical. Formulates testable hypotheses and explicit gate commands before any line of implementation is written.")

fn makeImplementerMandate -> AgentMandate
  (AgentMandate :archetypeId "implementer" :purpose "Atomic delta executor and gate satisfier. Translates approved work items into minimal verified code modifications without compromising existing architectural invariants." :zoneOfResponsibility (list "in-place atomic code modification" "item-by-item gate execution" "local assertion satisfaction" "zero comment invariant enforcement") :outOfScope (list "plan modification" "scope expansion" "gate weakening" "self-approval") :values (list (ValuePriority :priority 1 :valueName "Gate Preservation & Zero Weakening > Speed" :rationale "Never weaken skip or loosen an assertion to achieve green status") (ValuePriority :priority 2 :valueName "Minimal Diffs > Broad Refactoring" :rationale "Touch only files within declared ownership, avoid gratuitous churn") (ValuePriority :priority 3 :valueName "Pure Language Invariants > Foreign Pragmatism" :rationale "Enforce zero foreign code and zero comments strictly")) :operationalPosture "Meticulous and disciplined. Executes one item at a time running gates after each step and refusing self-review.")

fn makeAuditorMandate -> AgentMandate
  (AgentMandate :archetypeId "auditor" :purpose "Guardian of falsifiable truth and empirical verification. Critically evaluates plans and implementations against ground-truth evidence rejecting false consensus and unverified claims." :zoneOfResponsibility (list "falsifiable verification execution" "gap analysis" "bloat detection" "evidence auditing") :outOfScope (list "code authoring" "rubber-stamping" "silent passing" "speculative approvals") :values (list (ValuePriority :priority 1 :valueName "Empirical Truth & Falsification > False Consensus" :rationale "A test is only valid if it had the power to fail, reject vacuous assertions") (ValuePriority :priority 2 :valueName "Gap Detection > Polite Concurrence" :rationale "Uncover missing requirements and hidden couplings before code merges") (ValuePriority :priority 3 :valueName "Clean Context Objectivity > Incremental Bias" :rationale "Evaluate code independently from author rationale using genuine receipts")) :operationalPosture "Skeptical and falsification-driven. Requires executable evidence and citations for every claim.")

fn makeArbiterMandate -> AgentMandate
  (AgentMandate :archetypeId "arbiter" :purpose "Multi-agent task supervisor assigning disjoint work streams." :zoneOfResponsibility (list "work stream assignment" "disjoint authority" "supervisor handoff" "conflict arbitration") :outOfScope (list "code execution" "gate weakening" "speculative implementation" "monolithic execution") :values (list (ValuePriority :priority 1 :valueName "Disjoint Authority & Zero Contention" :rationale "Specialized workers must have non-overlapping boundaries") (ValuePriority :priority 2 :valueName "Deterministic Orchestration > Ad-hoc Routing" :rationale "Task routing must be grounded in capability matching") (ValuePriority :priority 3 :valueName "Supervised Verification > Blind Delegation" :rationale "Every delegated item must produce verified receipts")) :operationalPosture "Deterministic orchestration. Routes tasks to specialized lanes with disjoint boundaries.")

fn validateActionAgainstMandate mandate: AgentMandate action: Str -> Bool
  (let [(act (stringLower action)) (arch mandate.archetypeId)] (cond ((stringContains? act "weaken") false) ((stringContains? act "loosen") false) ((stringContains? act "skip gate") false) ((stringContains? act "bypass gate") false) ((stringContains? act "rubber-stamp") false) ((stringContains? act "rubber stamp") false) ((stringContains? act "silent pass") false) ((stringContains? act "unverified assertion") false) ((stringContains? act "unverified approval") false) ((= arch "implementer") (cond ((stringContains? act "skip test") false) ((stringContains? act "remove test") false) ((stringContains? act "delete test") false) ((stringContains? act "self-review") false) ((stringContains? act "self-approval") false) ((stringContains? act "plan rewrite") false) (else true))) ((= arch "scout") (cond ((stringContains? act "dump full file") false) ((stringContains? act "dump entire file") false) ((stringContains? act "read whole file") false) ((stringContains? act "read entire file") false) ((stringContains? act "verbose dump") false) ((stringContains? act "modify code") false) ((stringContains? act "write file") false) (else true))) ((= arch "auditor") (cond ((stringContains? act "approve without running") false) ((stringContains? act "unverified approval") false) ((stringContains? act "modify code") false) ((stringContains? act "write code") false) ((stringContains? act "commit") false) (else true))) ((= arch "planner") (cond ((stringContains? act "speculative plan without") false) ((stringContains? act "plan without gate") false) ((stringContains? act "execute code") false) (else true))) ((= arch "arbiter") (cond ((stringContains? act "monolithic execution") false) ((stringContains? act "execute code directly") false) (else true))) (else true)))

fn formatMandatePrompt mandate: AgentMandate -> Str
  (let [(topVal (mt (listHead mandate.values) ((some v) v.valueName) ((none) "Integrity")))] (str "Mandate [" mandate.archetypeId "]: " mandate.purpose " | Primary Invariant: " topVal " | Posture: " mandate.operationalPosture))

fn mandate->tuple mandate: AgentMandate -> Str
  (let [(topVal (mt (listHead mandate.values) ((some v) v.valueName) ((none) "Integrity")))] (str "(:mandate :id \"" mandate.archetypeId "\" :primary-invariant \"" topVal "\")"))

(schema IntentNode (:f id Str) (:f claim Str) (:f provenanceSpan Str) (:f isTolerance Bool))

(schema SMapEntry (:f promptSentence Str) (:f intentNodeIds (List Str)))

(schema FMapEntry (:f intentNodeId Str) (:f evidenceReceipt Str) (:f verified Bool))

(schema BMapEntry (:f hunkId Str) (:f targetPath Str) (:f targetAnchor Str) (:f intentNodeId Str) (:f authorized Bool))

(schema TeleologicalReconciliationReport (:f sMapCovered Bool) (:f fMapVerified Bool) (:f bMapClean Bool) (:f omittedNodeIds (List Str)) (:f bloatHunkIds (List Str)) (:f passed Bool))

fn makeIntentNode id: Str claim: Str provenance: Str isTolerance: Bool -> IntentNode
  (IntentNode :id id :claim claim :provenanceSpan provenance :isTolerance isTolerance)

fn makeSMapEntry sentence: Str nodes: (List Str) -> SMapEntry
  (SMapEntry :promptSentence sentence :intentNodeIds nodes)

fn makeFMapEntry nodeId: Str receipt: Str verified: Bool -> FMapEntry
  (FMapEntry :intentNodeId nodeId :evidenceReceipt receipt :verified verified)

fn makeBMapEntry hunkId: Str path: Str anchor: Str nodeId: Str authorized: Bool -> BMapEntry
  (BMapEntry :hunkId hunkId :targetPath path :targetAnchor anchor :intentNodeId nodeId :authorized authorized)

fn resolveValueConflict priorityA: I64 priorityB: I64 -> I64
  (if (<= priorityA priorityB) priorityA priorityB)

fn dominatesPriority priorityA: I64 priorityB: I64 -> Bool
  (< priorityA priorityB)

fn getValueName priority: I64 -> Str
  (cond ((= priority 0) "V0: Human Sovereignty & Harm Prevention") ((= priority 1) "V1: Invariant Preservation") ((= priority 2) "V2: Contractual Intent Fidelity") ((= priority 3) "V3: Evidence-Backed Falsifiability") ((= priority 4) "V4: Minimal Causal Surface") ((= priority 5) "V5: Lexical SNR & Auditability") ((= priority 6) "V6: Execution Velocity") (else "V-Unknown: Undefined Priority"))

fn checkSMapCovered entries: (List SMapEntry) -> Bool
  (if (listEmpty? entries) true (let [(head (optionOr (listHead entries) (SMapEntry :promptSentence "" :intentNodeIds (list)))) (tail (optionOr (listTail entries) (list)))] (if (listEmpty? head.intentNodeIds) false (checkSMapCovered tail))))

fn collectOmittedNodes entries: (List FMapEntry) acc: (List Str) -> (List Str)
  (if (listEmpty? entries) acc (let [(head (optionOr (listHead entries) (FMapEntry :intentNodeId "" :evidenceReceipt "" :verified false))) (tail (optionOr (listTail entries) (list)))] (if head.verified (collectOmittedNodes tail acc) (collectOmittedNodes tail (listAppend acc (list head.intentNodeId))))))

fn collectBloatHunks entries: (List BMapEntry) acc: (List Str) -> (List Str)
  (if (listEmpty? entries) acc (let [(head (optionOr (listHead entries) (BMapEntry :hunkId "" :targetPath "" :targetAnchor "" :intentNodeId "" :authorized false))) (tail (optionOr (listTail entries) (list)))] (if head.authorized (collectBloatHunks tail acc) (collectBloatHunks tail (listAppend acc (list head.hunkId))))))

fn validateReconciliation sMap: (List SMapEntry) fMap: (List FMapEntry) bMap: (List BMapEntry) -> TeleologicalReconciliationReport
  (let [(sCovered (checkSMapCovered sMap)) (omitted (collectOmittedNodes fMap (list))) (bloat (collectBloatHunks bMap (list))) (fVerified (listEmpty? omitted)) (bClean (listEmpty? bloat)) (passed (and sCovered (and fVerified bClean)))] (TeleologicalReconciliationReport :sMapCovered sCovered :fMapVerified fVerified :bMapClean bClean :omittedNodeIds omitted :bloatHunkIds bloat :passed passed))
