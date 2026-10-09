(module aslHarness/proxy :x [CacheEntry ProxyState ProxyDecision initProxy registerSource storeCache lookupCache evaluateAction] :i [(core :a core) (grounding :a gr)])

(schema CacheEntry (:f docId Str) (:f content Str) (:f registeredAt I64))

(schema ProxyState (:f sources (List core/SourceDocument)) (:f cache (List core/CacheEntry)) (:f blockedActions (List Str)) (:f allowedSources (List CacheEntry)))

(schema ProxyDecision (:f allow Bool) (:f actionName Str) (:f response Str) (:f reason Str))

fn initProxy -> ProxyState
  (ProxyState :sources (list) :cache (list) :blockedActions (list) :allowedSources (list))

fn registerSource state: ProxyState doc: core/SourceDocument -> ProxyState
  (with state :sources (cons doc state.sources))

fn storeCache state: ProxyState namespace: Str key: Str resp: Str -> ProxyState
  (let [(entry (core/CacheEntry :namespace namespace :key key :promptHash key :response resp :ttlSeconds 3600))] (with state :cache (cons entry state.cache)))

fn lookupCache state: ProxyState namespace: Str key: Str -> (Option Str)
  (let [(matches (filter (fn [(e core/CacheEntry)] -> Bool (and (= e.namespace namespace) (= e.key key))) state.cache))] (mt (listHead matches) ((none) (none)) ((some entry) (some entry.response))))

fn evaluateAction state: ProxyState actionName: Str citations: (List core/ClaimCitation) -> ProxyDecision
  (let [(results (gr/verifyClaims state.sources citations)) (grounded (gr/allClaimsGrounded? results))] (if grounded (ProxyDecision :allow true :actionName actionName :response (str "Action " " action-name " " approved: all claims verified against sources.") :reason "") (let [(failed (filter (fn [(r core/VerificationResult)] -> Bool (not r.verified)) results))] (mt (listHead failed) ((none) (ProxyDecision :allow false :actionName actionName :response "" :reason "Action blocked: unknown verification failure")) ((some f) (ProxyDecision :allow false :actionName actionName :response "" :reason (str "Action blocked: " f.failureReason)))))))
