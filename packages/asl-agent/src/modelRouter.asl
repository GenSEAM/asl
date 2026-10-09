(module aslAgent/modelRouter
  :x [TaskRole ModelEndpoint RoutingMatrix roleDesign roleCoding roleReview roleTriage makeEndpoint defaultRoutingMatrix resolveModelForRole formatRouteDecision CognitiveIntent AttractorGuidance DispatchFrame makeDispatchFrame makeTriadDispatchFrame resolveEndpointForIntent formatDispatchFrame]
  :i [])

(enum TaskRole
  (:c roleDesign [] "Creative visual composition, UI architecture, and VDOM design")
  (:c roleCoding [] "Deterministic code emission, AST editing, and assertion satisfaction")
  (:c roleReview [] "Deep reasoning, gap analysis, pre-commit audit, and invariant defense")
  (:c roleTriage [] "Zero-latency outline scanning, formatting, and lightweight routing"))

(enum CognitiveIntent
  (:c intentDiscover [] "Symbol graph exploration and unmapped export detection")
  (:c intentFormulate [] "Action DAG formulation, invariant contract specification, and risk modeling")
  (:c intentConstruct [] "Algorithmic synthesis, test authoring, and in-memory AST mutations")
  (:c intentFalsify [] "Adversarial cross-examination, counterexample generation, and boundary refutation")
  (:c intentReconcile [] "Tri-Map reconciliation and gap closure across intent, gate, and diff")
  (:c intentDeliberate [] "Multi-agent deliberative consensus and Chief Justice formal adjudication"))

(enum AttractorGuidance
  (:c attractorVerification [] "Every claim backed by an executable gate that can fail; strictly positive executed asserts (>0)")
  (:c attractorNonVacuity [] "Direct operational execution without mocks or tautological self-confirmation")
  (:c attractorReversibility [] "Stage in RAM VFS first (:edit -> :diff -> :flush | :discard); branch before merge")
  (:c attractorContainment [] "Monorepo sovereignty; zero git remotes; write set strictly contained within :owns")
  (:c attractorSanctuary [] "Legacy alias for attractorContainment; monorepo sovereignty")
  (:c attractorSimplicity [] "Minimal AST perturbation; lowest causal diff hunk count; eliminate decorative bloat")
  (:c attractorAttentionDensity [] "Byte-stable prompt prefixes, symbol-slice addressing, and minimal token noise")
  (:c attractorContractPrecision [] "Explicit typed preconditions and closed boundary specifications")
  (:c attractorResilience [] "Bounded circuit breakers, atomic crash recovery, and graceful degradation")
  (:c attractorConvergence [] "Deterministic monotonic advancement toward formal closure; limit cycle cutoff")
  (:c attractorMvpVelocity [] "Permit conscious pragmatic concessions for rapid validation with explicit :validUntil horizons"))

(schema ModelEndpoint
  (:f modelId Str)
  (:f baseUrl Str)
  (:f temperature F64)
  (:f thinkingBudget I64)
  (:f isLocal Bool))

(schema RoutingMatrix
  (:f designEndpoint ModelEndpoint)
  (:f codingEndpoint ModelEndpoint)
  (:f reviewEndpoint ModelEndpoint)
  (:f triageEndpoint ModelEndpoint)
  (:f localFallback ModelEndpoint)
  (:f preferLocal Bool))

(schema DispatchFrame
  (:f intent Str)
  (:f attractor Str)
  (:f affordances (List Str))
  (:f ownsBoundaries (List Str))
  (:f endpoint ModelEndpoint))

fn makeEndpoint id: Str url: Str temp: F64 budget: I64 local: Bool -> ModelEndpoint
  (ModelEndpoint :modelId id :baseUrl url :temperature temp :thinkingBudget budget :isLocal local)

fn defaultRoutingMatrix -> RoutingMatrix
  (let [(gatewayUrl "http://127.0.0.1:8765/v1")
        (localGemma (makeEndpoint "gemma-4-31b-it" gatewayUrl 0.1 0 true))
        (creativeDesign (makeEndpoint "gemini-2.5-flash" gatewayUrl 0.4 0 false))
        (codingImpl (makeEndpoint "gemma-4-31b-it" gatewayUrl 0.0 0 true))
        (deepReview (makeEndpoint "gemini-2.5-pro" gatewayUrl 0.2 4096 false))
        (triageFast (makeEndpoint "gemma-4-31b-it" gatewayUrl 0.0 0 true))]
    (RoutingMatrix
      :designEndpoint creativeDesign
      :codingEndpoint codingImpl
      :reviewEndpoint deepReview
      :triageEndpoint triageFast
      :localFallback localGemma
      :preferLocal false))

fn resolveModelForRole role: TaskRole matrix: RoutingMatrix offline: Bool -> ModelEndpoint
  (if (or offline matrix.preferLocal)
    matrix.localFallback
    (mt role
      ((roleDesign) matrix.designEndpoint)
      ((roleCoding) matrix.codingEndpoint)
      ((roleReview) matrix.reviewEndpoint)
      ((roleTriage) matrix.triageEndpoint)))

fn formatRouteDecision role: TaskRole ep: ModelEndpoint -> Str
  (let [(roleName (mt role
                    ((roleDesign) "design")
                    ((roleCoding) "coding")
                    ((roleReview) "review")
                    ((roleTriage) "triage")))
        (locFlag (if ep.isLocal "local" "cloud"))]
    (str "Role [" roleName "] routed to " ep.modelId " (" locFlag ", budget: " (stringFromInt64 ep.thinkingBudget) ")"))

fn resolveEndpointForIntent intentStr: Str matrix: RoutingMatrix offline: Bool -> ModelEndpoint
  (if (or offline matrix.preferLocal)
    matrix.localFallback
    (if (or (= intentStr ":falsify") (= intentStr ":deliberate"))
      matrix.reviewEndpoint
      (if (= intentStr ":construct")
        matrix.codingEndpoint
        (if (= intentStr ":formulate")
          matrix.designEndpoint
          matrix.triageEndpoint))))

fn makeDispatchFrame intentStr: Str attractorStr: Str affordances: (List Str) owns: (List Str) matrix: RoutingMatrix offline: Bool -> DispatchFrame
  (let [(ep (resolveEndpointForIntent intentStr matrix offline))]
    (DispatchFrame
      :intent intentStr
      :attractor attractorStr
      :affordances affordances
      :ownsBoundaries owns
      :endpoint ep))

fn makeTriadDispatchFrame intentStr: Str triad: (List Str) affordances: (List Str) owns: (List Str) matrix: RoutingMatrix offline: Bool -> DispatchFrame
  (let [(ep (resolveEndpointForIntent intentStr matrix offline))
        (attractorStr (stringJoin triad " "))]
    (DispatchFrame
      :intent intentStr
      :attractor attractorStr
      :affordances affordances
      :ownsBoundaries owns
      :endpoint ep))

fn formatDispatchFrame frame: DispatchFrame -> Str
  (str "(:dispatch-frame\n"
       "  :intent \"" frame.intent "\"\n"
       "  :attractor \"" frame.attractor "\"\n"
       "  :affordances [" (stringJoin frame.affordances " ") "]\n"
       "  :owns [" (stringJoin frame.ownsBoundaries " ") "]\n"
       "  :endpoint \"" frame.endpoint.modelId "\")")
