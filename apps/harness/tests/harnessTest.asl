(module aslHarness/test :x [testAdapterName testValidGrounding testHallucinatedQuote testMissingDoc testNamespaceCache testProxyFirewallAction runTests] :i [(core :a core) (grounding :a gr) (proxy :a px) (aslHarness/harness :a h)])

fn sampleDoc -> core/SourceDocument
  (core/makeSourceDocument "doc-core-spec" "https://example.com/spec" "AgentScript compiles to WebAssembly and executes sandboxed in 0.04ms with zero host leaks." 1725400000)

fn testAdapterName -> Bool
  (let [(ak (h/code)) (ah (h/AgentHarness :name "test" :adapter ak :timeoutMs 1000))] (assert (= (h/getAdapterName (h/code)) "Code Engine") "Code engine adapter name must match") (assert (= (h/getAdapterName (h/browser)) "Browser Agent") "Browser adapter name must match") (assert (= (h/getAdapterName (h/computerUse)) "Computer-Use Controller") "Computer use adapter name must match") (assert (= (h/getAdapterName (h/chat)) "Chat RAG Assistant") "Chat adapter name must match") (assert (= ah.name "test") "AgentHarness name matches") (refute (= ah.name "wrong") "Refute wrong harness name") true)

fn testValidGrounding -> Bool
  (let [(doc (sampleDoc)) (cit (core/ClaimCitation :claimText "AgentScript runs in 0.04ms" :docId "doc-core-spec" :exactQuote "executes sandboxed in 0.04ms" :confidence 0.95)) (res (gr/verifyCitation (list doc) cit))] (do (assert res.verified "Verbatim quote citation must be verified") (assert (stringEmpty? res.failureReason) "Failure reason must be empty on valid grounding") true))

fn testHallucinatedQuote -> Bool
  (let [(doc (sampleDoc)) (cit (core/ClaimCitation :claimText "AgentScript has Python dependencies" :docId "doc-core-spec" :exactQuote "requires python runtime on client" :confidence 0.90)) (res (gr/verifyCitation (list doc) cit))] (do (assert (not res.verified) "Fabricated quote must not be verified") (assert (stringContains? res.failureReason "Exact quote not found") "Failure reason must indicate quote not found") true))

fn testMissingDoc -> Bool
  (let [(doc (sampleDoc)) (cit (core/ClaimCitation :claimText "Some assertion" :docId "unknown-doc" :exactQuote "something" :confidence 0.90)) (res (gr/verifyCitation (list doc) cit))] (do (assert (not res.verified) "Missing document citation must not be verified") (assert (stringContains? res.failureReason "Source document not found") "Failure reason must indicate document not found") true))

fn testNamespaceCache -> Bool
  (let [(p0 (px/initProxy)) (p1 (px/storeCache p0 "agent-alpha" "prompt-1" "response-alpha")) (p2 (px/storeCache p1 "agent-beta" "prompt-1" "response-beta"))] (let [(valAlpha (px/lookupCache p2 "agent-alpha" "prompt-1")) (valBeta (px/lookupCache p2 "agent-beta" "prompt-1")) (valGamma (px/lookupCache p2 "agent-gamma" "prompt-1"))] (do (assert (mt valAlpha ((none) false) ((some v) (= v "response-alpha"))) "Alpha namespace cache hit") (assert (mt valBeta ((none) false) ((some v) (= v "response-beta"))) "Beta namespace cache hit") (assert (mt valGamma ((none) true) ((some _) false)) "Gamma namespace cache miss") true)))

fn testProxyFirewallAction -> Bool
  (let [(doc (sampleDoc)) (p (px/registerSource (px/initProxy) doc)) (citGood (core/ClaimCitation :claimText "Wasm execution" :docId "doc-core-spec" :exactQuote "compiles to WebAssembly" :confidence 0.98)) (citBad (core/ClaimCitation :claimText "Wasm execution" :docId "doc-core-spec" :exactQuote "compiles to Java bytecode" :confidence 0.98)) (ce (px/CacheEntry :docId "d" :content "c" :registeredAt 1)) (ps (px/ProxyState :allowedSources (list ce))) (pd (px/ProxyDecision :allow true :reason "r"))] (let [(decGood (px/evaluateAction p "deploy-wasm" (list citGood))) (dec-bad (px/evaluateAction p "deploy-java" (list citBad)))] (do (assert decGood.allow "Grounded action must be allowed") (assert (not dec-bad.allow) "Ungrounded action must be blocked") (assert (stringContains? dec-bad.reason "Exact quote not found") "Block reason must cite ungrounded quote") (assert (= pd.reason "r") "ProxyDecision explicit property matches") (assert (= (listLength ps.allowedSources) 1) "ProxyState sources match") (refute (= pd.reason "wrong") "Refute ProxyDecision reason") true)))

fn runTests -> Bool
  (do (assert (testAdapterName)) (assert (testValidGrounding)) (assert (testHallucinatedQuote)) (assert (testMissingDoc)) (assert (testNamespaceCache)) (assert (testProxyFirewallAction)) true)
