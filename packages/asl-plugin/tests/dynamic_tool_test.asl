(module asl-plugin/dynamicToolTest
  :d "Strict falsifiable test suite for dynamic tool plane on demand."
  :x [runTests]
  :i [(dynamic_tool :a dt)])

(df testEmptyPlaneAndBaseTools [] -> Bool
  :d "Verifies initial empty plane contains strictly 4 base meta-tools and satisfies base landscape."
  (let [(plane (dt/emptyPlane))
        (tools (dt/baseTools))]
    (assert (= (list-length tools) 4) "Base tools must contain exactly 4 meta-tools")
    (assert (list-contains? tools "eval") "Base tools must contain eval")
    (assert (list-contains? tools "batch") "Base tools must contain batch")
    (assert (list-contains? tools "tool-load") "Base tools must contain tool-load")
    (assert (list-contains? tools "tool-unload") "Base tools must contain tool-unload")
    (assert (dt/baseLandscape? plane) "Empty plane must satisfy base-landscape predicate")
    (assert (= (dt/toolCount plane) 4) "Initial tool count must be exactly 4")
    true))

(df testDomainLoadingAndLookup [] -> Bool
  :d "Verifies dynamic loading of domain tool definitions and in-plane lookups."
  (let [(p1 (dt/createParam "sym" ":str" false "Target symbol name"))
        (p2 (dt/createParam "format" ":str" true "Output format option"))
        (t1 (dt/createTool "callers" "intel" (list p1 p2) "(:graph :callers)" "Find callers" "(:graph (Caller > Target:call Line:int))"))
        (dIntel (dt/createDomain "intel" "Code intelligence" (list t1) "(:graph (Node > Target:edge))"))
        (plane (dt/emptyPlane))
        (pMounted (dt/loadDomain plane dIntel))]
    (assert (= (.-name p1) "sym") "Param name must match")
    (assert (= (.-paramType p1) ":str") "Param type must match")
    (assert (= (.-name t1) "callers") "Tool name must match")
    (assert (= (.-domain t1) "intel") "Tool domain must match")
    (assert (= (.-name dIntel) "intel") "Domain name must match")
    (assert (= (list-length (.-tools dIntel)) 1) "Domain must contain 1 tool")
    (assert (dt/domainLoaded? pMounted "intel") "Intel domain must be marked loaded")
    (refute (dt/baseLandscape? pMounted) "Mounted plane must not be base landscape")
    (assert (= (dt/toolCount pMounted) 5) "Tool count must increase to 5")
    (assert (dt/hasTool? pMounted "callers") "Mounted tool callers must be accessible")
    (assert (dt/hasTool? pMounted "eval") "Base meta-tool eval must remain accessible")
    (assert (is-some? (dt/lookupTool pMounted "callers")) "Lookup for callers must return some")
    (assert (is-none? (dt/lookupTool pMounted "nonexistent")) "Lookup for unknown tool must return none")
    true))

(df testDomainUnloadingAndReceipts [] -> Bool
  :d "Verifies unloading mounted domains and generation of structured step receipts."
  (let [(p1 (dt/createParam "sym" ":str" false "Target symbol"))
        (t1 (dt/createTool "callers" "intel" (list p1) ":graph" "Find callers" ""))
        (dIntel (dt/createDomain "intel" "Code intelligence" (list t1) ""))
        (plane (dt/emptyPlane))
        (pMounted (dt/loadDomain plane dIntel))
        (rcpt (dt/mountReceipt dIntel))
        (pUnmounted (dt/unloadDomain pMounted "intel"))
        (uRcpt (dt/unmountReceipt "intel" 1))]
    (assert (= (.-status rcpt) "ok") "Mount receipt status must be ok")
    (assert (= (.-mountedCount rcpt) 1) "Mount receipt count must be 1")
    (assert (= (.-domain rcpt) "intel") "Mount receipt domain must be intel")
    (refute (dt/domainLoaded? pUnmounted "intel") "Intel domain must not be loaded after unload")
    (refute (dt/hasTool? pUnmounted "callers") "Callers tool must not be present after unload")
    (assert (dt/baseLandscape? pUnmounted) "Tool plane must revert to base landscape after unload")
    (assert (= (dt/toolCount pUnmounted) 4) "Tool count must revert to 4")
    (assert (= (.-status uRcpt) "ok") "Unmount receipt status must be ok")
    (assert (= (.-unmountedCount uRcpt) 1) "Unmount receipt count must be 1")
    true))

(df testTurnResetAndTokenLandscape [] -> Bool
  :d "Verifies turn boundary reset discarding mounts and token footprint <= 200."
  (let [(p1 (dt/createParam "path" ":str" false "File path"))
        (t1 (dt/createTool "read" "fs" (list p1) ":str" "Read file" ""))
        (dFs (dt/createDomain "fs" "Filesystem operations" (list t1) ""))
        (plane (dt/emptyPlane))
        (pMounted (dt/loadDomain plane dFs))
        (pReset (dt/resetTurn pMounted))
        (lsEmpty (dt/activeLandscape (dt/emptyPlane)))
        (lsMounted (dt/activeLandscape pMounted))]
    (assert (dt/baseLandscape? pReset) "Plane after turn reset must be base landscape")
    (assert (= (dt/toolCount pReset) 4) "Reset plane must have exactly 4 tools")
    (assert (.-baseOnly lsEmpty) "Empty landscape base-only flag must be true")
    (assert (= (.-totalCount lsEmpty) 4) "Empty landscape tool count must be 4")
    (assert (< (.-tokenFootprint lsEmpty) 200) "Base landscape token footprint must be <= 200")
    (refute (.-baseOnly lsMounted) "Mounted landscape base-only flag must be false")
    (assert (= (.-totalCount lsMounted) 5) "Mounted landscape tool count must be 5")
    true))

(df testAdjacencyGraphDsl [] -> Bool
  :d "Verifies Adjacency DSL formatting schema (:graph (Node > Target1:edge Target2:edge))."
  (let [(g1 (dt/formatGraph "CallerA" (list "TargetB:call" "TargetC:call")))
        (g2 (dt/formatGraph "Leaf" (list)))]
    (assert (= g1 "(:graph (CallerA > TargetB:call TargetC:call))") "Adjacency DSL must match expected format")
    (assert (string-contains? g1 ">") "Adjacency DSL must contain transition symbol >")
    (assert (string-contains? g1 "CallerA") "Adjacency DSL must contain source node")
    (assert (= g2 "(:graph (Leaf))") "Empty edge graph must format without transition symbol")
    true))

(df runTests [] -> Bool
  :d "Runs all dynamic tool plane test suites."
  (and (testEmptyPlaneAndBaseTools)
       (and (testDomainLoadingAndLookup)
            (and (testDomainUnloadingAndReceipts)
                 (and (testTurnResetAndTokenLandscape)
                      (testAdjacencyGraphDsl))))))
