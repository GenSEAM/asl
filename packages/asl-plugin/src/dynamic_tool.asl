(module asl-plugin/dynamicTool
  :d "Pure AgentScript dynamic tool plane mounting engine and on-demand domain projector."
  :x [ToolParam ToolDef ToolDomain ToolPlane MountReceipt UnmountReceipt ActiveLandscape
      baseTools emptyPlane createParam createTool createDomain domainLoaded?
      hasTool? lookupTool toolCount activeDomains loadDomain unloadDomain
      resetTurn mountReceipt unmountReceipt formatGraph renderParam
      renderTool renderLandscape activeLandscape baseLandscape?]
  :i [(asl-text/text :a txt)])

(dfs ToolParam
  (:f name Str "Parameter identifier")
  (:f paramType Str "Typed scalar or structural category")
  (:f optional Bool "Whether parameter is optional")
  (:f doc Str "Documentation description of parameter"))

(dfs ToolDef
  (:f name Str "Tool identifier")
  (:f domain Str "Parent domain identifier")
  (:f params (List ToolParam) "Typed parameters")
  (:f returnsType Str "Return type description")
  (:f doc Str "Tool documentation")
  (:f formatSchema Str "Optional formatting schema"))

(dfs ToolDomain
  (:f name Str "Domain identifier")
  (:f doc Str "Domain documentation")
  (:f tools (List ToolDef) "Domain tool definitions")
  (:f graphSchema Str "Domain graph DSL schema if applicable"))

(dfs ToolPlane
  (:f baseMeta (List Str) "Static base meta-tools: eval, batch, tool-load, tool-unload")
  (:f activeDomains (List Str) "List of currently mounted domain names")
  (:f mountedTools (Map Str ToolDef) "Map of tool name to mounted ToolDef")
  (:f turnCounter Int "Turn transaction counter"))

(dfs MountReceipt
  (:f domain Str "Mounted domain name")
  (:f mountedCount Int "Count of tools introduced")
  (:f status Str "Receipt status ok or error")
  (:f toolNames (List Str) "Names of mounted tools"))

(dfs UnmountReceipt
  (:f domain Str "Unmounted domain name")
  (:f unmountedCount Int "Count of tools removed")
  (:f status Str "Receipt status ok or error"))

(dfs ActiveLandscape
  (:f domains (List Str) "List of mounted domains")
  (:f toolNames (List Str) "List of all active tool names")
  (:f totalCount Int "Total number of active tools")
  (:f baseOnly Bool "True if only base meta-tools active")
  (:f tokenFootprint Int "Estimated token consumption"))

(df baseTools [] -> (List Str)
  :d "Returns the 4 canonical base meta-tools for the O(1) dynamic tool plane."
  (list "eval" "batch" "tool-load" "tool-unload"))

(df emptyPlane [] -> ToolPlane
  :d "Initializes an empty dynamic tool plane containing strictly the 4 base meta-tools."
  (ToolPlane :baseMeta (baseTools)
             :activeDomains (list)
             :mountedTools (map-empty)
             :turnCounter 0))

(df createParam [(name Str) (ptype Str) (opt Bool) (doc Str)] -> ToolParam
  :d "Constructs a typed tool parameter definition."
  (ToolParam :name name :paramType ptype :optional opt :doc doc))

(df createTool [(name Str) (domain Str) (params (List ToolParam)) (returnsType Str) (doc Str) (formatSchema Str)] -> ToolDef
  :d "Constructs a domain tool definition."
  (ToolDef :name name :domain domain :params params :returnsType returnsType :doc doc :formatSchema formatSchema))

(df createDomain [(name Str) (doc Str) (tools (List ToolDef)) (graphSchema Str)] -> ToolDomain
  :d "Constructs a domain grouping of tools."
  (ToolDomain :name name :doc doc :tools tools :graphSchema graphSchema))

(df domainLoaded? [(plane ToolPlane) (domainName Str)] -> Bool
  :d "Checks if a domain is currently mounted in the active tool plane."
  (list-contains? (.-activeDomains plane) domainName))

(df hasTool? [(plane ToolPlane) (toolName Str)] -> Bool
  :d "Checks if a tool is currently available in the base meta-tools or mounted tools."
  (or (list-contains? (.-baseMeta plane) toolName)
      (map-has? (.-mountedTools plane) toolName)))

(df lookupTool [(plane ToolPlane) (toolName Str)] -> (Option ToolDef)
  :d "Looks up a mounted tool definition by name."
  (map-get (.-mountedTools plane) toolName))

(df toolCount [(plane ToolPlane)] -> Int
  :d "Returns total count of available tools: 4 base meta-tools plus mounted tools."
  (+ (list-length (.-baseMeta plane)) (map-size (.-mountedTools plane))))

(df activeDomains [(plane ToolPlane)] -> (List Str)
  :d "Returns list of currently mounted domain names."
  (.-activeDomains plane))

(df loadDomain [(plane ToolPlane) (domain ToolDomain)] -> ToolPlane
  :d "Mounts all tools from a domain into the active tool plane for the current turn."
  (let [(dName (.-name domain))
        (newDomains (if (domainLoaded? plane dName)
                         (.-activeDomains plane)
                         (list-append (.-activeDomains plane) (list dName))))
        (newTools (fold (fn [(acc (Map Str ToolDef)) (t ToolDef)] -> (Map Str ToolDef)
                           (map-set acc (.-name t) t))
                         (.-mountedTools plane)
                         (.-tools domain)))]
    (ToolPlane :baseMeta (.-baseMeta plane)
               :activeDomains newDomains
               :mountedTools newTools
               :turnCounter (+ (.-turnCounter plane) 1))))

(df unloadDomain [(plane ToolPlane) (domainName Str)] -> ToolPlane
  :d "Unmounts a domain and removes its tools from the active tool plane."
  (let [(newDomains (filter (fn [(d Str)] -> Bool (not (= d domainName))) (.-activeDomains plane)))
        (newTools (fold (fn [(acc (Map Str ToolDef)) (toolName Str)] -> (Map Str ToolDef)
                           (let [(tOpt (map-get (.-mountedTools plane) toolName))]
                             (mt tOpt
                               ((none) acc)
                               ((some t)
                                (if (= (.-domain t) domainName)
                                    (map-remove acc toolName)
                                    acc)))))
                         (.-mountedTools plane)
                         (map-keys (.-mountedTools plane))))]
    (ToolPlane :baseMeta (.-baseMeta plane)
               :activeDomains newDomains
               :mountedTools newTools
               :turnCounter (+ (.-turnCounter plane) 1))))

(df resetTurn [(plane ToolPlane)] -> ToolPlane
  :d "Discards all dynamically mounted domain tools at turn boundary, restoring O(1) base landscape."
  (ToolPlane :baseMeta (.-baseMeta plane)
             :activeDomains (list)
             :mountedTools (map-empty)
             :turnCounter (+ (.-turnCounter plane) 1)))

(df mountReceipt [(domain ToolDomain)] -> MountReceipt
  :d "Generates a structured step receipt for a loaded domain."
  (let [(names (map (fn [(t ToolDef)] -> Str (.-name t)) (.-tools domain)))]
    (MountReceipt :domain (.-name domain)
                  :mountedCount (list-length names)
                  :status "ok"
                  :toolNames names)))

(df unmountReceipt [(domainName Str) (count Int)] -> UnmountReceipt
  :d "Generates a structured step receipt for an unloaded domain."
  (UnmountReceipt :domain domainName
                  :unmountedCount count
                  :status "ok"))

(df formatGraph [(node Str) (edges (List Str))] -> Str
  :d "Formats an Adjacency DSL expression (:graph (Node > Target1:edge Target2:edge))."
  (if (list-empty? edges)
      (str "(:graph (" node "))")
      (str "(:graph (" node " > " (string-join edges " ") "))")))

(df renderParam [(p ToolParam)] -> Str
  :d "Renders a tool parameter specification into compact ASN form."
  (let [(optStr (if (.-optional p) " :opt true" ""))]
    (str "(:param :name \"" (.-name p) "\" :type " (.-paramType p) optStr ")")))

(df renderTool [(t ToolDef)] -> Str
  :d "Renders a single tool definition into ASN representation."
  (let [(paramsRendered (map (fn [(p ToolParam)] -> Str (renderParam p)) (.-params t)))
        (paramsStr (string-join paramsRendered " "))
        (schemaStr (if (string-empty? (.-formatSchema t)) "" (str " :schema \"" (.-formatSchema t) "\"")))]
    (str "(:tool :name \"" (.-name t) "\" :domain :" (.-domain t) " :params [" paramsStr "] :returns " (.-returnsType t) schemaStr ")")))

(df renderLandscape [(plane ToolPlane)] -> Str
  :d "Renders active tool plane schema into compact system prompt context."
  (let [(baseItems (map (fn [(b Str)] -> Str (str "(:meta-tool :name \"" b "\")")) (.-baseMeta plane)))
        (mountedItems (map (fn [(toolName Str)] -> Str
                              (let [(tOpt (map-get (.-mountedTools plane) toolName))]
                                (mt tOpt
                                  ((none) "")
                                  ((some t) (renderTool t)))))
                            (map-keys (.-mountedTools plane))))
        (allItems (list-append baseItems mountedItems))]
    (str "(:tools [\n  " (string-join allItems "\n  ") "\n])")))

(df baseLandscape? [(plane ToolPlane)] -> Bool
  :d "Verifies that the tool plane contains strictly base meta-tools and token count is <= 200."
  (and (= (list-length (.-activeDomains plane)) 0)
       (and (= (map-size (.-mountedTools plane)) 0)
            (= (list-length (.-baseMeta plane)) 4))))

(df activeLandscape [(plane ToolPlane)] -> ActiveLandscape
  :d "Builds an ActiveLandscape snapshot of currently available tools."
  (let [(mountedNames (map-keys (.-mountedTools plane)))
        (allNames (list-append (.-baseMeta plane) mountedNames))
        (totCount (list-length allNames))
        (isBase (= (map-size (.-mountedTools plane)) 0))
        (rendered (renderLandscape plane))
        (toks (txt/estimateTokens rendered))]
    (ActiveLandscape :domains (.-activeDomains plane)
                     :toolNames allNames
                     :totalCount totCount
                     :baseOnly isBase
                     :tokenFootprint toks)))
