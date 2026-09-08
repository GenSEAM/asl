(module asl-plugin/dynamic-tool-test
  :d "Strict falsifiable test suite for dynamic tool plane on demand."
  :x [run-tests]
  :i [(dynamic_tool :a dt)])

(df test-empty-plane-and-base-tools [] -> Bool
  :d "Verifies initial empty plane contains strictly 4 base meta-tools and satisfies base landscape."
  (let [(plane (dt/empty-plane))
        (tools (dt/base-tools))]
    (assert (= (list-length tools) 4) "Base tools must contain exactly 4 meta-tools")
    (assert (list-contains? tools "eval") "Base tools must contain eval")
    (assert (list-contains? tools "batch") "Base tools must contain batch")
    (assert (list-contains? tools "tool-load") "Base tools must contain tool-load")
    (assert (list-contains? tools "tool-unload") "Base tools must contain tool-unload")
    (assert (dt/base-landscape? plane) "Empty plane must satisfy base-landscape predicate")
    (assert (= (dt/tool-count plane) 4) "Initial tool count must be exactly 4")
    true))

(df test-domain-loading-and-lookup [] -> Bool
  :d "Verifies dynamic loading of domain tool definitions and in-plane lookups."
  (let [(p1 (dt/create-param "sym" ":str" false "Target symbol name"))
        (p2 (dt/create-param "format" ":str" true "Output format option"))
        (t1 (dt/create-tool "callers" "intel" (list p1 p2) "(:graph :callers)" "Find callers" "(:graph (Caller > Target:call Line:int))"))
        (d-intel (dt/create-domain "intel" "Code intelligence" (list t1) "(:graph (Node > Target:edge))"))
        (plane (dt/empty-plane))
        (p-mounted (dt/load-domain plane d-intel))]
    (assert (= (.-name p1) "sym") "Param name must match")
    (assert (= (.-param-type p1) ":str") "Param type must match")
    (assert (= (.-name t1) "callers") "Tool name must match")
    (assert (= (.-domain t1) "intel") "Tool domain must match")
    (assert (= (.-name d-intel) "intel") "Domain name must match")
    (assert (= (list-length (.-tools d-intel)) 1) "Domain must contain 1 tool")
    (assert (dt/domain-loaded? p-mounted "intel") "Intel domain must be marked loaded")
    (assert (not (dt/base-landscape? p-mounted)) "Mounted plane must not be base landscape")
    (assert (= (dt/tool-count p-mounted) 5) "Tool count must increase to 5")
    (assert (dt/has-tool? p-mounted "callers") "Mounted tool callers must be accessible")
    (assert (dt/has-tool? p-mounted "eval") "Base meta-tool eval must remain accessible")
    (assert (is-some? (dt/lookup-tool p-mounted "callers")) "Lookup for callers must return some")
    (assert (is-none? (dt/lookup-tool p-mounted "nonexistent")) "Lookup for unknown tool must return none")
    true))

(df test-domain-unloading-and-receipts [] -> Bool
  :d "Verifies unloading mounted domains and generation of structured step receipts."
  (let [(p1 (dt/create-param "sym" ":str" false "Target symbol"))
        (t1 (dt/create-tool "callers" "intel" (list p1) ":graph" "Find callers" ""))
        (d-intel (dt/create-domain "intel" "Code intelligence" (list t1) ""))
        (plane (dt/empty-plane))
        (p-mounted (dt/load-domain plane d-intel))
        (rcpt (dt/mount-receipt d-intel))
        (p-unmounted (dt/unload-domain p-mounted "intel"))
        (u-rcpt (dt/unmount-receipt "intel" 1))]
    (assert (= (.-status rcpt) "ok") "Mount receipt status must be ok")
    (assert (= (.-mounted-count rcpt) 1) "Mount receipt count must be 1")
    (assert (= (.-domain rcpt) "intel") "Mount receipt domain must be intel")
    (assert (not (dt/domain-loaded? p-unmounted "intel")) "Intel domain must not be loaded after unload")
    (assert (not (dt/has-tool? p-unmounted "callers")) "Callers tool must not be present after unload")
    (assert (dt/base-landscape? p-unmounted) "Tool plane must revert to base landscape after unload")
    (assert (= (dt/tool-count p-unmounted) 4) "Tool count must revert to 4")
    (assert (= (.-status u-rcpt) "ok") "Unmount receipt status must be ok")
    (assert (= (.-unmounted-count u-rcpt) 1) "Unmount receipt count must be 1")
    true))

(df test-turn-reset-and-token-landscape [] -> Bool
  :d "Verifies turn boundary reset discarding mounts and token footprint <= 200."
  (let [(p1 (dt/create-param "path" ":str" false "File path"))
        (t1 (dt/create-tool "read" "fs" (list p1) ":str" "Read file" ""))
        (d-fs (dt/create-domain "fs" "Filesystem operations" (list t1) ""))
        (plane (dt/empty-plane))
        (p-mounted (dt/load-domain plane d-fs))
        (p-reset (dt/reset-turn p-mounted))
        (ls-empty (dt/active-landscape (dt/empty-plane)))
        (ls-mounted (dt/active-landscape p-mounted))]
    (assert (dt/base-landscape? p-reset) "Plane after turn reset must be base landscape")
    (assert (= (dt/tool-count p-reset) 4) "Reset plane must have exactly 4 tools")
    (assert (.-base-only ls-empty) "Empty landscape base-only flag must be true")
    (assert (= (.-total-count ls-empty) 4) "Empty landscape tool count must be 4")
    (assert (< (.-token-footprint ls-empty) 200) "Base landscape token footprint must be <= 200")
    (assert (not (.-base-only ls-mounted)) "Mounted landscape base-only flag must be false")
    (assert (= (.-total-count ls-mounted) 5) "Mounted landscape tool count must be 5")
    true))

(df test-adjacency-graph-dsl [] -> Bool
  :d "Verifies Adjacency DSL formatting schema (:graph (Node > Target1:edge Target2:edge))."
  (let [(g1 (dt/format-graph "CallerA" (list "TargetB:call" "TargetC:call")))
        (g2 (dt/format-graph "Leaf" (list)))]
    (assert (= g1 "(:graph (CallerA > TargetB:call TargetC:call))") "Adjacency DSL must match expected format")
    (assert (string-contains? g1 ">") "Adjacency DSL must contain transition symbol >")
    (assert (string-contains? g1 "CallerA") "Adjacency DSL must contain source node")
    (assert (= g2 "(:graph (Leaf))") "Empty edge graph must format without transition symbol")
    true))

(df run-tests [] -> Bool
  :d "Runs all dynamic tool plane test suites."
  (and (test-empty-plane-and-base-tools)
       (and (test-domain-loading-and-lookup)
            (and (test-domain-unloading-and-receipts)
                 (and (test-turn-reset-and-token-landscape)
                      (test-adjacency-graph-dsl))))))
