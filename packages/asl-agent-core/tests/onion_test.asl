(module asl-agent-core/test
  :d "Unit tests for Unified Agent Core onion middleware pipeline and topological DAG sorting."
  :x [run-tests]
  :i [(core :a core) (onion :a on)])

"run: (run-tests)"

(df extract-ids [(items (List on/Middleware))] -> (List Str)
  :d "Helper extracting middleware IDs into list"
  (map (fn [(m on/Middleware)] -> Str (.-id m)) items))

(df test-priority-sorting [] -> Bool
  :d "Verifies numeric priority ordering of independent middlewares."
  (let [(m-audit (on/make-middleware "mw-audit" "Audit" (on/kind-audit) 500 (list) (list)))
        (m-auth (on/make-middleware "mw-auth" "Auth" (on/kind-pre-call) 100 (list) (list)))
        (m-sanitize (on/make-middleware "mw-sanitize" "Sanitize" (on/kind-post-call) 900 (list) (list)))
        (ids (extract-ids (on/sort-middlewares (list m-audit m-auth m-sanitize))))]
    (= ids (list "mw-auth" "mw-audit" "mw-sanitize"))))

(df test-dependency-override [] -> Bool
  :d "Verifies that explicit before dependency overrides numeric priority."
  (let [(m-logger (on/make-middleware "mw-logger" "Logger" (on/kind-pre-call) 800 (list "mw-auth") (list)))
        (m-auth (on/make-middleware "mw-auth" "Auth" (on/kind-pre-call) 100 (list) (list)))
        (m-sanitize (on/make-middleware "mw-sanitize" "Sanitize" (on/kind-post-call) 900 (list) (list)))
        (ids (extract-ids (on/sort-middlewares (list m-auth m-logger m-sanitize))))]
    (= ids (list "mw-logger" "mw-auth" "mw-sanitize"))))

(df test-after-dependency [] -> Bool
  :d "Verifies that explicit after dependency forces precedence regardless of priority."
  (let [(m-gate (on/make-middleware "mw-gate" "Gate" (on/kind-filter) 900 (list) (list)))
        (m-check (on/make-middleware "mw-check" "Check" (on/kind-pre-call) 100 (list) (list "mw-gate")))
        (ids (extract-ids (on/sort-middlewares (list m-check m-gate))))]
    (= ids (list "mw-gate" "mw-check"))))

(df test-filter-interceptor [] -> Bool
  :d "Verifies filter middleware passes safe inputs and blocks forbidden payloads."
  (let [(mw (on/make-middleware "mw-guard" "Guard" (on/kind-filter) 200 (list) (list)))
        (ctx-safe (on/make-onion-context "c-1" "agent-0" "search" "valid query"))
        (ctx-block (on/make-onion-context "c-2" "agent-0" "delete" "blocked: destructive action"))]
    (let [(dec-safe (on/execute-middleware mw ctx-safe))
          (dec-block (on/execute-middleware mw ctx-block))]
      (and (.-proceed dec-safe)
           (and (not (.-blocked dec-safe))
                (and (not (.-proceed dec-block))
                     (and (.-blocked dec-block)
                          (string-contains? (.-reason dec-block) "Blocked by filter"))))))))

(df test-mutation-interceptor [] -> Bool
  :d "Verifies mutate middleware transforms the context payload."
  (let [(mw (on/make-middleware "mw-transform" "Transformer" (on/kind-mutate) 300 (list) (list)))
        (ctx (on/make-onion-context "c-3" "agent-1" "transform" "data-raw"))
        (dec (on/execute-middleware mw ctx))]
    (and (.-proceed dec)
         (= (.-payload (.-context dec)) "data-raw:mw-transform"))))

(df test-audit-interceptor [] -> Bool
  :d "Verifies audit middleware logs telemetry into the context audit log."
  (let [(mw (on/make-middleware "mw-telemetry" "Telemetry" (on/kind-audit) 500 (list) (list)))
        (ctx (on/make-onion-context "c-4" "agent-2" "tool-test" "payload"))
        (dec (on/execute-middleware mw ctx))]
    (and (.-proceed dec)
         (let [(log (.-audit-log (.-context dec)))]
           (not (list-empty? log))))))

(df test-full-onion-dispatch [] -> Bool
  :d "Verifies full end-to-end dispatch through composable onion pipeline."
  (let [(m-auth (on/make-middleware "mw-auth" "Auth" (on/kind-pre-call) 100 (list) (list)))
        (m-filter (on/make-middleware "mw-filter" "Filter" (on/kind-filter) 200 (list) (list)))
        (m-mutate (on/make-middleware "mw-mutate" "Mutate" (on/kind-mutate) 300 (list) (list)))
        (m-audit (on/make-middleware "mw-audit" "Audit" (on/kind-audit) 500 (list) (list)))
        (m-post (on/make-middleware "mw-post" "Post" (on/kind-post-call) 900 (list) (list)))
        (p0 (on/make-pipeline))
        (p1 (on/add-middleware p0 m-post))
        (p2 (on/add-middleware p1 m-audit))
        (p3 (on/add-middleware p2 m-mutate))
        (p4 (on/add-middleware p3 m-filter))
        (p5 (on/add-middleware p4 m-auth))
        (ctx (on/make-onion-context "c-5" "agent-root" "exec" "command-line"))]
    (let [(dec (on/dispatch-tool-call p5 ctx "execution-success-42"))]
      (and (.-proceed dec)
           (and (not (.-blocked dec))
                (and (= (.-payload (.-context dec)) "execution-success-42")
                     (let [(audit (.-audit-log (.-context dec)))]
                       (= (list-length audit) 6))))))))

(df test-core-agent [] -> Bool
  :d "Verifies core agent context, message framing, and tool registry."
  (let [(ctx0 (core/make-agent-context "agent-alpha" "sess-99" "You are a helpful agent."))
        (msg (core/make-message "user" "Hello AgentScript" "user-1"))
        (ctx1 (core/add-message ctx0 msg))
        (tool (core/make-tool-def "search" "Search engine" "(:q Str)"))
        (reg (core/register-tool (core/empty-registry "agent-alpha") tool))]
    (and (= (.-agent-id ctx1) "agent-alpha")
         (and (= (list-length (.-messages ctx1)) 1)
              (and (core/has-tool? reg "search")
                   (not (core/has-tool? reg "non-existent")))))))

(df run-tests [] -> Bool
  :d "Runs all agent core and onion middleware unit tests."
  (fold (fn [(acc Bool) (p Bool)] -> Bool (and acc p))
        true
        (list (test-priority-sorting)
              (test-dependency-override)
              (test-after-dependency)
              (test-filter-interceptor)
              (test-mutation-interceptor)
              (test-audit-interceptor)
              (test-full-onion-dispatch)
              (test-core-agent))))
