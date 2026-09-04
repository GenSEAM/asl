(module asl-agent-core/onion
  :d "Composable Onion Middleware Pipeline and Topological DAG Dispatcher."
  :x [MiddlewareKind Middleware OnionContext OnionDecision OnionPipeline TopoState
      make-middleware make-onion-context make-pipeline add-middleware sort-pipeline
      has-dep-edge? has-prerequisite? sort-middlewares
      execute-middleware dispatch-tool-call]
  :i [(core :a core)])

(dfe MiddlewareKind
  (:c kind-pre-call [] "Pre-call hook interceptor")
  (:c kind-post-call [] "Post-call hook interceptor")
  (:c kind-filter [] "Filter hook verifying permission or boundary")
  (:c kind-mutate [] "Mutation hook transforming payload")
  (:c kind-audit [] "Audit telemetry hook"))

(dfs Middleware
  (:f id Str "Unique middleware identifier e.g. mw-auth, mw-logger")
  (:f name Str "Human-readable middleware name")
  (:f kind MiddlewareKind "Phase and category of middleware")
  (:f priority I64 "Numeric priority where lower numbers execute in outer layers")
  (:f before (List Str) "List of middleware IDs that must execute after this")
  (:f after (List Str) "List of middleware IDs that must execute before this")
  (:f config (Map Str Str) "Arbitrary string configuration key-values"))

(dfs OnionContext
  (:f call-id Str "Unique invocation trace ID")
  (:f caller-id Str "Agent or principal ID initiating invocation")
  (:f tool-name Str "Target tool or method name")
  (:f payload Str "Serialized arguments or message payload")
  (:f status Str "Current status: ok, blocked, error")
  (:f audit-log (List Str) "Ordered audit log entries recorded by pipeline"))

(dfs OnionDecision
  (:f proceed Bool "True if invocation is allowed to continue")
  (:f blocked Bool "True if blocked by filter")
  (:f reason Str "Diagnostic reason if blocked or errored")
  (:f context OnionContext "Updated onion context carrying payload and audit trail"))

(dfs OnionPipeline
  (:f middlewares (List Middleware) "Registered middleware collection")
  (:f sorted (List Middleware) "Topologically sorted execution order"))

(dfs TopoState
  (:f remaining (List Middleware) "Unscheduled middlewares")
  (:f acc (List Middleware) "Ordered middlewares scheduled so far"))

(df make-middleware [(id Str) (name Str) (kind MiddlewareKind) (priority I64) (before (List Str)) (after (List Str))] -> Middleware
  :d "Constructs a Middleware definition record."
  (Middleware
    :id id
    :name name
    :kind kind
    :priority priority
    :before before
    :after after
    :config (map-empty)))

(df make-onion-context [(call-id Str) (caller-id Str) (tool-name Str) (payload Str)] -> OnionContext
  :d "Constructs an initial OnionContext."
  (OnionContext
    :call-id call-id
    :caller-id caller-id
    :tool-name tool-name
    :payload payload
    :status "ok"
    :audit-log (list)))

(df contains-id [(ids (List Str)) (target Str)] -> Bool
  :d "Checks if a string list contains the target ID."
  (let [(matches (filter (fn [(x Str)] -> Bool (= x target)) ids))]
    (not (list-empty? matches))))

(df has-dep-edge? [(a Middleware) (b Middleware)] -> Bool
  :d "Checks whether middleware a must precede b by explicit dependency."
  (or (contains-id (.-before a) (.-id b))
      (contains-id (.-after b) (.-id a))))

(df has-prerequisite? [(target Middleware) (remaining (List Middleware))] -> Bool
  :d "Checks if target has any unmet prerequisite in remaining list."
  (let [(prereqs (filter (fn [(other Middleware)] -> Bool
                           (if (= (.-id other) (.-id target))
                               false
                               (has-dep-edge? other target)))
                         remaining))]
    (not (list-empty? prereqs))))

(df topo-step [(state TopoState) (step I64)] -> TopoState
  :d "Performs one step of topological sort by selecting highest-precedence ready middleware."
  (if (list-empty? (.-remaining state))
      state
      (let [(ready (filter (fn [(m Middleware)] -> Bool
                             (not (has-prerequisite? m (.-remaining state))))
                           (.-remaining state)))]
        (let [(candidates (if (list-empty? ready)
                              (.-remaining state)
                              ready))]
          (let [(sorted-cands (list-sort-by (fn [(m Middleware)] -> I64 (.-priority m)) candidates))]
            (mt (list-head sorted-cands)
              ((none) state)
              ((some chosen)
               (let [(next-rem (filter (fn [(m Middleware)] -> Bool
                                         (!= (.-id m) (.-id chosen)))
                                       (.-remaining state)))
                     (next-acc (list-append (.-acc state) (list chosen)))]
                 (TopoState :remaining next-rem :acc next-acc)))))))))

(df sort-middlewares [(mws (List Middleware))] -> (List Middleware)
  :d "Topologically sorts middleware list by explicit dependencies with numeric priority resolution."
  (let [(n (list-length mws))
        (init-state (TopoState :remaining mws :acc (list)))
        (final-state (fold topo-step init-state (range 0 n)))]
    (.-acc final-state)))

(df make-pipeline [] -> OnionPipeline
  :d "Initializes an empty OnionPipeline."
  (OnionPipeline
    :middlewares (list)
    :sorted (list)))

(df add-middleware [(pipe OnionPipeline) (mw Middleware)] -> OnionPipeline
  :d "Registers a middleware into the pipeline and re-sorts execution order."
  (let [(updated-mws (list-cons mw (.-middlewares pipe)))
        (sorted-mws (sort-middlewares updated-mws))]
    (OnionPipeline
      :middlewares updated-mws
      :sorted sorted-mws)))

(df sort-pipeline [(pipe OnionPipeline)] -> OnionPipeline
  :d "Re-computes topological sort over registered middlewares."
  (OnionPipeline
    :middlewares (.-middlewares pipe)
    :sorted (sort-middlewares (.-middlewares pipe))))

(df execute-middleware [(mw Middleware) (ctx OnionContext)] -> OnionDecision
  :d "Executes a single middleware against the onion context."
  (mt (.-kind mw)
    ((kind-filter)
     (if (string-contains? (.-payload ctx) "blocked")
         (let [(audit-entry (str "filter:blocked:" (.-id mw)))
               (next-ctx (OnionContext
                           :call-id (.-call-id ctx)
                           :caller-id (.-caller-id ctx)
                           :tool-name (.-tool-name ctx)
                           :payload (.-payload ctx)
                           :status "blocked"
                           :audit-log (list-cons audit-entry (.-audit-log ctx))))]
           (OnionDecision :proceed false :blocked true :reason (str "Blocked by filter: " (.-id mw)) :context next-ctx))
         (let [(audit-entry (str "filter:pass:" (.-id mw)))
               (next-ctx (OnionContext
                           :call-id (.-call-id ctx)
                           :caller-id (.-caller-id ctx)
                           :tool-name (.-tool-name ctx)
                           :payload (.-payload ctx)
                           :status (.-status ctx)
                           :audit-log (list-cons audit-entry (.-audit-log ctx))))]
           (OnionDecision :proceed true :blocked false :reason "" :context next-ctx))))
    ((kind-mutate)
     (let [(mutated-payload (str (.-payload ctx) ":" (.-id mw)))
           (audit-entry (str "mutate:" (.-id mw)))
           (next-ctx (OnionContext
                       :call-id (.-call-id ctx)
                       :caller-id (.-caller-id ctx)
                       :tool-name (.-tool-name ctx)
                       :payload mutated-payload
                       :status (.-status ctx)
                       :audit-log (list-cons audit-entry (.-audit-log ctx))))]
       (OnionDecision :proceed true :blocked false :reason "" :context next-ctx)))
    ((kind-audit)
     (let [(audit-entry (str "audit:" (.-id mw) ":" (.-tool-name ctx)))
           (next-ctx (OnionContext
                       :call-id (.-call-id ctx)
                       :caller-id (.-caller-id ctx)
                       :tool-name (.-tool-name ctx)
                       :payload (.-payload ctx)
                       :status (.-status ctx)
                       :audit-log (list-cons audit-entry (.-audit-log ctx))))]
       (OnionDecision :proceed true :blocked false :reason "" :context next-ctx)))
    ((kind-pre-call)
     (let [(audit-entry (str "pre-call:" (.-id mw)))
           (next-ctx (OnionContext
                       :call-id (.-call-id ctx)
                       :caller-id (.-caller-id ctx)
                       :tool-name (.-tool-name ctx)
                       :payload (.-payload ctx)
                       :status (.-status ctx)
                       :audit-log (list-cons audit-entry (.-audit-log ctx))))]
       (OnionDecision :proceed true :blocked false :reason "" :context next-ctx)))
    ((kind-post-call)
     (let [(audit-entry (str "post-call:" (.-id mw)))
           (next-ctx (OnionContext
                       :call-id (.-call-id ctx)
                       :caller-id (.-caller-id ctx)
                       :tool-name (.-tool-name ctx)
                       :payload (.-payload ctx)
                       :status (.-status ctx)
                       :audit-log (list-cons audit-entry (.-audit-log ctx))))]
       (OnionDecision :proceed true :blocked false :reason "" :context next-ctx)))))

(df dispatch-tool-call [(pipe OnionPipeline) (ctx OnionContext) (executor-result Str)] -> OnionDecision
  :d "Dispatches a tool call through the full composable onion pipeline."
  (let [(sorted-mws (.-sorted pipe))
        (init-dec (OnionDecision :proceed true :blocked false :reason "" :context ctx))]
    (let [(pre-dec (fold (fn [(dec OnionDecision) (mw Middleware)] -> OnionDecision
                           (if (not (.-proceed dec))
                               dec
                               (execute-middleware mw (.-context dec))))
                         init-dec
                         sorted-mws))]
      (if (not (.-proceed pre-dec))
          pre-dec
          (let [(exec-ctx (OnionContext
                            :call-id (.-call-id (.-context pre-dec))
                            :caller-id (.-caller-id (.-context pre-dec))
                            :tool-name (.-tool-name (.-context pre-dec))
                            :payload executor-result
                            :status "ok"
                            :audit-log (list-cons (str "exec:" executor-result) (.-audit-log (.-context pre-dec)))))]
            (OnionDecision :proceed true :blocked false :reason "" :context exec-ctx))))))
