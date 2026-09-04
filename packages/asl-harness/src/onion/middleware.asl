(module asl-harness/onion/middleware
  :d "Epistemic Onion Middleware integration for AgentScript Harness."
  :x [make-grounding-middleware make-cache-middleware make-audit-middleware create-harness-pipeline]
  :i [(onion :a on)])

(df make-grounding-middleware [] -> on/Middleware
  :d "Constructs grounding verification filter middleware."
  (on/make-middleware "mw-grounding" "Epistemic Grounding Firewall" (on/kind-filter) 200 (list) (list "mw-cache")))

(df make-cache-middleware [] -> on/Middleware
  :d "Constructs prompt cache lookup middleware."
  (on/make-middleware "mw-cache" "Namespace Prompt Cache" (on/kind-pre-call) 100 (list) (list)))

(df make-audit-middleware [] -> on/Middleware
  :d "Constructs audit telemetry middleware."
  (on/make-middleware "mw-audit" "Execution Audit Logger" (on/kind-audit) 500 (list) (list "mw-grounding")))

(df create-harness-pipeline [] -> on/OnionPipeline
  :d "Initializes an onion pipeline with standard harness middlewares."
  (let [(p0 (on/make-pipeline))
        (p1 (on/add-middleware p0 (make-cache-middleware)))
        (p2 (on/add-middleware p1 (make-grounding-middleware)))
        (p3 (on/add-middleware p2 (make-audit-middleware)))]
    p3))
