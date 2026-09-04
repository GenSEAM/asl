(module asl-harness/proxy
  :d "Epistemic proxy firewall and namespace-isolated prompt cache manager."
  :x [ProxyState ProxyDecision init-proxy register-source store-cache lookup-cache evaluate-action]
  :i [(core :a core) (grounding :a gr)])

(dfs ProxyState
  (:f sources (List core/SourceDocument) "Registered source documents for grounding")
  (:f cache (List core/CacheEntry) "Namespace-isolated prompt cache entries")
  (:f blocked-actions (List Str) "Log of blocked ungrounded actions"))

(dfs ProxyDecision
  (:f allow Bool "True if action is permitted")
  (:f action-name Str "Identifier of evaluated action")
  (:f response Str "Response text if action succeeds")
  (:f reason Str "Explanation if action was blocked"))

(df init-proxy [] -> ProxyState
  :d "Initializes an empty epistemic proxy state."
  (ProxyState
    :sources (list)
    :cache (list)
    :blocked-actions (list)))

(df register-source [(state ProxyState) (doc core/SourceDocument)] -> ProxyState
  :d "Registers a source document for grounding verification."
  (ProxyState
    :sources (list-cons doc (.-sources state))
    :cache (.-cache state)
    :blocked-actions (.-blocked-actions state)))

(df store-cache [(state ProxyState) (namespace Str) (key Str) (resp Str)] -> ProxyState
  :d "Stores response in namespace-isolated cache."
  (let [(entry (core/CacheEntry
                 :namespace namespace
                 :key key
                 :prompt-hash key
                 :response resp
                 :ttl-seconds 3600))]
    (ProxyState
      :sources (.-sources state)
      :cache (list-cons entry (.-cache state))
      :blocked-actions (.-blocked-actions state))))

(df lookup-cache [(state ProxyState) (namespace Str) (key Str)] -> (Option Str)
  :d "Queries response strictly within the given namespace."
  (let [(matches (filter (fn [(e core/CacheEntry)] -> Bool
                           (and (= (.-namespace e) namespace)
                                (= (.-key e) key)))
                         (.-cache state)))]
    (mt (list-head matches)
      ((none) (none))
      ((some entry) (some (.-response entry))))))

(df evaluate-action [(state ProxyState) (action-name Str) (citations (List core/ClaimCitation))] -> ProxyDecision
  :d "Evaluates an agent action against citation grounding firewall."
  (let [(results (gr/verify-claims (.-sources state) citations))
        (grounded (gr/all-claims-grounded? results))]
    (if grounded
        (ProxyDecision
          :allow true
          :action-name action-name
          :response (str "Action "" action-name "" approved: all claims verified against sources.")
          :reason "")
        (let [(failed (filter (fn [(r core/VerificationResult)] -> Bool (not (.-verified r))) results))]
          (mt (list-head failed)
            ((none)
             (ProxyDecision
               :allow false
               :action-name action-name
               :response ""
               :reason "Action blocked: unknown verification failure"))
            ((some f)
             (ProxyDecision
               :allow false
               :action-name action-name
               :response ""
               :reason (str "Action blocked: " (.-failure-reason f)))))))))
