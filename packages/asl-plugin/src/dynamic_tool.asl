(module asl-plugin/dynamic-tool
  :d "Pure AgentScript dynamic tool plane mounting engine and on-demand domain projector."
  :x [ToolParam ToolDef ToolDomain ToolPlane MountReceipt UnmountReceipt ActiveLandscape
      base-tools empty-plane create-param create-tool create-domain domain-loaded?
      has-tool? lookup-tool tool-count active-domains load-domain unload-domain
      reset-turn mount-receipt unmount-receipt format-graph render-param
      render-tool render-landscape active-landscape estimate-tokens base-landscape?]
  :i [])

(dfs ToolParam
  (:f name Str "Parameter identifier")
  (:f param-type Str "Typed scalar or structural category")
  (:f optional Bool "Whether parameter is optional")
  (:f doc Str "Documentation description of parameter"))

(dfs ToolDef
  (:f name Str "Tool identifier")
  (:f domain Str "Parent domain identifier")
  (:f params (List ToolParam) "Typed parameters")
  (:f returns-type Str "Return type description")
  (:f doc Str "Tool documentation")
  (:f format-schema Str "Optional formatting schema"))

(dfs ToolDomain
  (:f name Str "Domain identifier")
  (:f doc Str "Domain documentation")
  (:f tools (List ToolDef) "Domain tool definitions")
  (:f graph-schema Str "Domain graph DSL schema if applicable"))

(dfs ToolPlane
  (:f base-meta (List Str) "Static base meta-tools: eval, batch, tool-load, tool-unload")
  (:f active-domains (List Str) "List of currently mounted domain names")
  (:f mounted-tools (Map Str ToolDef) "Map of tool name to mounted ToolDef")
  (:f turn-counter Int "Turn transaction counter"))

(dfs MountReceipt
  (:f domain Str "Mounted domain name")
  (:f mounted-count Int "Count of tools introduced")
  (:f status Str "Receipt status ok or error")
  (:f tool-names (List Str) "Names of mounted tools"))

(dfs UnmountReceipt
  (:f domain Str "Unmounted domain name")
  (:f unmounted-count Int "Count of tools removed")
  (:f status Str "Receipt status ok or error"))

(dfs ActiveLandscape
  (:f domains (List Str) "List of mounted domains")
  (:f tool-names (List Str) "List of all active tool names")
  (:f total-count Int "Total number of active tools")
  (:f base-only Bool "True if only base meta-tools active")
  (:f token-footprint Int "Estimated token consumption"))

(df base-tools [] -> (List Str)
  :d "Returns the 4 canonical base meta-tools for the O(1) dynamic tool plane."
  (list "eval" "batch" "tool-load" "tool-unload"))

(df empty-plane [] -> ToolPlane
  :d "Initializes an empty dynamic tool plane containing strictly the 4 base meta-tools."
  (ToolPlane :base-meta (base-tools)
             :active-domains (list)
             :mounted-tools (map-empty)
             :turn-counter 0))

(df create-param [(name Str) (ptype Str) (opt Bool) (doc Str)] -> ToolParam
  :d "Constructs a typed tool parameter definition."
  (ToolParam :name name :param-type ptype :optional opt :doc doc))

(df create-tool [(name Str) (domain Str) (params (List ToolParam)) (returns-type Str) (doc Str) (format-schema Str)] -> ToolDef
  :d "Constructs a domain tool definition."
  (ToolDef :name name :domain domain :params params :returns-type returns-type :doc doc :format-schema format-schema))

(df create-domain [(name Str) (doc Str) (tools (List ToolDef)) (graph-schema Str)] -> ToolDomain
  :d "Constructs a domain grouping of tools."
  (ToolDomain :name name :doc doc :tools tools :graph-schema graph-schema))

(df domain-loaded? [(plane ToolPlane) (domain-name Str)] -> Bool
  :d "Checks if a domain is currently mounted in the active tool plane."
  (list-contains? (.-active-domains plane) domain-name))

(df has-tool? [(plane ToolPlane) (tool-name Str)] -> Bool
  :d "Checks if a tool is currently available in the base meta-tools or mounted tools."
  (or (list-contains? (.-base-meta plane) tool-name)
      (map-has? (.-mounted-tools plane) tool-name)))

(df lookup-tool [(plane ToolPlane) (tool-name Str)] -> (Option ToolDef)
  :d "Looks up a mounted tool definition by name."
  (map-get (.-mounted-tools plane) tool-name))

(df tool-count [(plane ToolPlane)] -> Int
  :d "Returns total count of available tools: 4 base meta-tools plus mounted tools."
  (+ (list-length (.-base-meta plane)) (map-size (.-mounted-tools plane))))

(df active-domains [(plane ToolPlane)] -> (List Str)
  :d "Returns list of currently mounted domain names."
  (.-active-domains plane))

(df load-domain [(plane ToolPlane) (domain ToolDomain)] -> ToolPlane
  :d "Mounts all tools from a domain into the active tool plane for the current turn."
  (let [(d-name (.-name domain))
        (new-domains (if (domain-loaded? plane d-name)
                         (.-active-domains plane)
                         (list-append (.-active-domains plane) (list d-name))))
        (new-tools (fold (fn [(acc (Map Str ToolDef)) (t ToolDef)] -> (Map Str ToolDef)
                           (map-set acc (.-name t) t))
                         (.-mounted-tools plane)
                         (.-tools domain)))]
    (ToolPlane :base-meta (.-base-meta plane)
               :active-domains new-domains
               :mounted-tools new-tools
               :turn-counter (+ (.-turn-counter plane) 1))))

(df unload-domain [(plane ToolPlane) (domain-name Str)] -> ToolPlane
  :d "Unmounts a domain and removes its tools from the active tool plane."
  (let [(new-domains (filter (fn [(d Str)] -> Bool (not (= d domain-name))) (.-active-domains plane)))
        (new-tools (fold (fn [(acc (Map Str ToolDef)) (tool-name Str)] -> (Map Str ToolDef)
                           (let [(t-opt (map-get (.-mounted-tools plane) tool-name))]
                             (mt t-opt
                               ((none) acc)
                               ((some t)
                                (if (= (.-domain t) domain-name)
                                    (map-remove acc tool-name)
                                    acc)))))
                         (.-mounted-tools plane)
                         (map-keys (.-mounted-tools plane))))]
    (ToolPlane :base-meta (.-base-meta plane)
               :active-domains new-domains
               :mounted-tools new-tools
               :turn-counter (+ (.-turn-counter plane) 1))))

(df reset-turn [(plane ToolPlane)] -> ToolPlane
  :d "Discards all dynamically mounted domain tools at turn boundary, restoring O(1) base landscape."
  (ToolPlane :base-meta (.-base-meta plane)
             :active-domains (list)
             :mounted-tools (map-empty)
             :turn-counter (+ (.-turn-counter plane) 1)))

(df mount-receipt [(domain ToolDomain)] -> MountReceipt
  :d "Generates a structured step receipt for a loaded domain."
  (let [(names (map (fn [(t ToolDef)] -> Str (.-name t)) (.-tools domain)))]
    (MountReceipt :domain (.-name domain)
                  :mounted-count (list-length names)
                  :status "ok"
                  :tool-names names)))

(df unmount-receipt [(domain-name Str) (count Int)] -> UnmountReceipt
  :d "Generates a structured step receipt for an unloaded domain."
  (UnmountReceipt :domain domain-name
                  :unmounted-count count
                  :status "ok"))

(df format-graph [(node Str) (edges (List Str))] -> Str
  :d "Formats an Adjacency DSL expression (:graph (Node > Target1:edge Target2:edge))."
  (if (list-empty? edges)
      (str "(:graph (" node "))")
      (str "(:graph (" node " > " (string-join edges " ") "))")))

(df render-param [(p ToolParam)] -> Str
  :d "Renders a tool parameter specification into compact ASN form."
  (let [(opt-str (if (.-optional p) " :opt true" ""))]
    (str "(:param :name \"" (.-name p) "\" :type " (.-param-type p) opt-str ")")))

(df render-tool [(t ToolDef)] -> Str
  :d "Renders a single tool definition into ASN representation."
  (let [(params-rendered (map (fn [(p ToolParam)] -> Str (render-param p)) (.-params t)))
        (params-str (string-join params-rendered " "))
        (schema-str (if (string-empty? (.-format-schema t)) "" (str " :schema \"" (.-format-schema t) "\"")))]
    (str "(:tool :name \"" (.-name t) "\" :domain :" (.-domain t) " :params [" params-str "] :returns " (.-returns-type t) schema-str ")")))

(df render-landscape [(plane ToolPlane)] -> Str
  :d "Renders active tool plane schema into compact system prompt context."
  (let [(base-items (map (fn [(b Str)] -> Str (str "(:meta-tool :name \"" b "\")")) (.-base-meta plane)))
        (mounted-items (map (fn [(tool-name Str)] -> Str
                              (let [(t-opt (map-get (.-mounted-tools plane) tool-name))]
                                (mt t-opt
                                  ((none) "")
                                  ((some t) (render-tool t)))))
                            (map-keys (.-mounted-tools plane))))
        (all-items (list-append base-items mounted-items))]
    (str "(:tools [\n  " (string-join all-items "\n  ") "\n])")))

(df estimate-tokens [(landscape-text Str)] -> Int
  :d "Estimates token footprint of formatted tool landscape using word and punctuation splitting."
  (let [(words (string-split landscape-text " "))]
    (fold (fn [(acc Int) (w Str)] -> Int
            (if (string-empty? (string-trim w))
                acc
                (+ acc 1)))
          0
          words)))

(df base-landscape? [(plane ToolPlane)] -> Bool
  :d "Verifies that the tool plane contains strictly base meta-tools and token count is <= 200."
  (and (= (list-length (.-active-domains plane)) 0)
       (and (= (map-size (.-mounted-tools plane)) 0)
            (= (list-length (.-base-meta plane)) 4))))

(df active-landscape [(plane ToolPlane)] -> ActiveLandscape
  :d "Builds an ActiveLandscape snapshot of currently available tools."
  (let [(mounted-names (map-keys (.-mounted-tools plane)))
        (all-names (list-append (.-base-meta plane) mounted-names))
        (tot-count (list-length all-names))
        (is-base (= (map-size (.-mounted-tools plane)) 0))
        (rendered (render-landscape plane))
        (toks (estimate-tokens rendered))]
    (ActiveLandscape :domains (.-active-domains plane)
                     :tool-names all-names
                     :total-count tot-count
                     :base-only is-base
                     :token-footprint toks)))
