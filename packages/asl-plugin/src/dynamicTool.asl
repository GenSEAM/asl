(module asl-plugin/dynamicTool
  :d "Pure AgentScript dynamic tool plane mounting engine and on-demand domain projector."
  :x [ToolParam ToolDef ToolDomain ToolPlane MountReceipt UnmountReceipt ActiveLandscape
      baseTools emptyPlane createParam createTool createDomain domainLoaded?
      hasTool? lookupTool toolCount activeDomains loadDomain unloadDomain
      resetTurn mountReceipt unmountReceipt formatGraph renderParam
      renderTool renderLandscape activeLandscape baseLandscape?
      renderDenseTool renderDenseLandscape lookupToolHelp countWords validDenseDoc?]
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

(df countWords [(s Str)] -> Int
  :d "Counts words in a whitespace-separated string."
  (let [(tokens (filter (fn [(w Str)] -> Bool (not (string-empty? (string-trim w))))
                        (string-split s " ")))]
    (list-length tokens)))

(df validDenseDoc? [(doc Str)] -> Bool
  :d "Verifies that docstring contains strictly between 2 and 5 words."
  (let [(cnt (countWords doc))]
    (and (>= cnt 2) (<= cnt 5))))

(df renderDenseTool [(name Str) (sig Str) (doc Str)] -> Str
  :d "Renders a single tool definition into a compact Dense Keyword Signature."
  (str "(:tool :name \"" name "\" :sig \"" sig "\" :d \"" doc "\")"))

(df renderDenseLandscape [(plane ToolPlane) (denseTools (List Str))] -> Str
  :d "Compiles the compact Turn 0 prompt block with base meta-tools and dense keyword signatures."
  (let [(baseItems (map (fn [(b Str)] -> Str (str "(:meta-tool :name \"" b "\")")) (.-baseMeta plane)))
        (allItems (list-append baseItems denseTools))]
    (if (list-empty? allItems)
        "(:tools [])"
        (str "(:tools [\n  " (string-join allItems "\n  ") "\n])"))))

(df lookupToolHelp [(toolName Str)] -> (Option Str)
  :d "Dynamic lazy loading lookup of tool help payload without full schema mounting."
  (cond
    ((or (= toolName "mem.query") (= toolName "query"))
     (some (str "(:help\n"
                "  :tool \"mem.query\"\n"
                "  :summary \"Vector semantic search across AST docstrings, decisions, and codebase\"\n"
                "  :signature \"asl mem query <query> [--scope decisions|tasks|code|all] [--limit <n>]\"\n"
                "  :params [\n"
                "    (:param :name \"query\" :type :string :required true :d \"Search phrase or symbol pattern; max 512 bytes\")\n"
                "    (:param :name \"--scope\" :type :enum :values [\"decisions\" \"tasks\" \"code\" \"all\"] :default \"all\" :d \"Memory partition filter\")\n"
                "    (:param :name \"--limit\" :type :integer :default 10 :d \"Maximum ranked results returned\")\n"
                "  ]\n"
                "  :examples [\n"
                "    \"asl mem query \\\"vector cosine similarity\\\"\"\n"
                "    \"asl mem query \\\"auth token\\\" --scope decisions --limit 5\"\n"
                "  ]\n"
                "  :behavior \"Performs sub-15ms BM25 and cosine ranking in RAM. Returns ranked list of matches with file, line, and snippet.\"\n"
                "  :status :help)")))
    ((or (or (= toolName "mem.edit") (= toolName "edit")) (= toolName "replace"))
     (some (str "(:help\n"
                "  :tool \"mem.edit\"\n"
                "  :summary \"Stage in-memory atomic string replacement in RAM virtual file buffer\"\n"
                "  :signature \"asl mem edit <file> <old> <new> | asl mem replace <file> <old> <new>\"\n"
                "  :alias [\"replace\"]\n"
                "  :params [\n"
                "    (:param :name \"file\" :type :filepath :required true :d \"Workspace-relative file path to edit\")\n"
                "    (:param :name \"old\" :type :string :required true :d \"Exact substring to find and replace\")\n"
                "    (:param :name \"new\" :type :string :required true :d \"Replacement substring\")\n"
                "  ]\n"
                "  :examples [\n"
                "    \"asl mem edit \\\"mem/vfs.asl\\\" \\\"oldFn\\\" \\\"newFn\\\"\"\n"
                "    \"asl mem edit \\\"engine/asl.c\\\" \\\"#define OLD 1\\\" \\\"#define OLD 2\\\"\"\n"
                "  ]\n"
                "  :lifecycle \"Staged in RAM. Run 'asl mem diff' to preview, 'asl mem flush' to commit to disk, or 'asl mem discard' to cancel.\"\n"
                "  :status :help)")))
    ((or (= toolName "mem.diff") (= toolName "diff"))
     (some (str "(:help\n"
                "  :tool \"mem.diff\"\n"
                "  :summary \"Inspect staged in-memory modifications and dirty buffers before disk write\"\n"
                "  :signature \"asl mem diff [--file <file>]\"\n"
                "  :params [\n"
                "    (:param :name \"--file\" :type :filepath :required false :d \"Optional file filter to inspect specific buffer\")\n"
                "  ]\n"
                "  :examples [\n"
                "    \"asl mem diff\"\n"
                "    \"asl mem diff --file \\\"mem/vfs.asl\\\"\"\n"
                "  ]\n"
                "  :behavior \"Displays file paths, modification flags, and replacement counts currently held in RAM virtual buffers.\"\n"
                "  :status :help)")))
    ((or (= toolName "mem.flush") (= toolName "flush"))
     (some (str "(:help\n"
                "  :tool \"mem.flush\"\n"
                "  :summary \"Atomically persist staged in-memory edits to the physical filesystem\"\n"
                "  :signature \"asl mem flush\"\n"
                "  :params []\n"
                "  :examples [\n"
                "    \"asl mem flush\"\n"
                "  ]\n"
                "  :behavior \"Writes all modified staged buffers to disk in a single atomic transaction and clears the RAM staging area.\"\n"
                "  :status :help)")))
    ((or (= toolName "mem.discard") (= toolName "discard"))
     (some (str "(:help\n"
                "  :tool \"mem.discard\"\n"
                "  :summary \"Clear staged RAM modifications without modifying physical disk files\"\n"
                "  :signature \"asl mem discard\"\n"
                "  :params []\n"
                "  :examples [\n"
                "    \"asl mem discard\"\n"
                "  ]\n"
                "  :safety \"Non-destructive on help: invoking 'asl mem discard --help' displays this message and NEVER clears buffers.\"\n"
                "  :behavior \"Clears all modified virtual file buffers in RAM and restores staging clean state.\"\n"
                "  :status :help)")))
    ((or (= toolName "mem.write") (= toolName "write"))
     (some (str "(:help\n"
                "  :tool \"mem.write\"\n"
                "  :summary \"Append structured memory record to canonical workspace ledgers\"\n"
                "  :signature \"asl mem write <kind> <payload>\"\n"
                "  :params [\n"
                "    (:param :name \"kind\" :type :enum :values [\"intent\" \"task\" \"note\" \"practice\"] :required true :d \"Target ledger category\")\n"
                "    (:param :name \"payload\" :type :string :required true :d \"Valid ASN formatted record content\")\n"
                "  ]\n"
                "  :examples [\n"
                "    \"asl mem write note \\\"(:note :topic api-design)\\\"\"\n"
                "    \"asl mem write practice \\\"(:practice :id p-help)\\\"\"\n"
                "  ]\n"
                "  :behavior \"Validates delimiter balance and appends record to .asl/mem/<kind>.asn.\"\n"
                "  :status :help)")))
    ((or (= toolName "mem.doc") (= toolName "doc"))
     (some (str "(:help\n"
                "  :tool \"mem.doc\"\n"
                "  :summary \"Extract and read targeted documentation section without whole-file dump\"\n"
                "  :signature \"asl mem doc <file> <section>\"\n"
                "  :params [\n"
                "    (:param :name \"file\" :type :filepath :required true :d \"Target markdown file path\")\n"
                "    (:param :name \"section\" :type :string :required true :d \"Exact heading title to extract\")\n"
                "  ]\n"
                "  :examples [\n"
                "    \"asl mem doc \\\"README.md\\\" \\\"Ultra-Compact Native Tool Cheat Sheet\\\"\"\n"
                "    \"asl mem doc \\\"AGENTS.md\\\" \\\"The 4 Teleological Mandates\\\"\"\n"
                "  ]\n"
                "  :behavior \"Parses markdown AST in RAM and returns only the requested section body, preventing prompt pollution.\"\n"
                "  :status :help)")))
    ((or (= toolName "mem.tree") (= toolName "tree"))
     (some (str "(:help\n"
                "  :tool \"mem.tree\"\n"
                "  :summary \"Render dense structural telemetry of multi-tier memory hierarchy across packages\"\n"
                "  :signature \"asl mem tree [path] [--format text|asn]\"\n"
                "  :params [\n"
                "    (:param :name \"path\" :type :filepath :default \".\" :d \"Root directory of memory tree to traverse\")\n"
                "    (:param :name \"--format\" :type :enum :values [\"text\" \"asn\"] :default \"text\" :d \"Output serialization format\")\n"
                "  ]\n"
                "  :examples [\n"
                "    \"asl mem tree\"\n"
                "    \"asl mem tree . --format asn\"\n"
                "  ]\n"
                "  :behavior \"Recursively scans packages, grammars, and memory ledgers in <80ms, emitting structural counts.\"\n"
                "  :status :help)")))
    ((= toolName "mem")
     (some (str "(:help\n"
                "  :domain \"mem\"\n"
                "  :summary \"High-performance vector memory store and tiered virtual RAM buffer\"\n"
                "  :tools [\n"
                "    (:tool :name \"mem.query\" :sig \"query [scope] [limit]\" :d \"vector semantic search AST\")\n"
                "    (:tool :name \"mem.edit\" :sig \"file old new\" :d \"stage atomic string replacement\")\n"
                "    (:tool :name \"mem.diff\" :sig \"[file]\" :d \"inspect staged RAM diffs\")\n"
                "    (:tool :name \"mem.flush\" :sig \"\" :d \"persist staged edits disk\")\n"
                "    (:tool :name \"mem.discard\" :sig \"\" :d \"clear staged RAM buffers\")\n"
                "    (:tool :name \"mem.write\" :sig \"kind payload\" :d \"append durable memory ledger\")\n"
                "    (:tool :name \"mem.doc\" :sig \"file section\" :d \"read section without disk\")\n"
                "    (:tool :name \"mem.tree\" :sig \"[path]\" :d \"render holistic hierarchy telemetry\")\n"
                "  ]\n"
                "  :status :help)")))
    ((= toolName "eval")
     (some (str "(:help\n"
                "  :tool \"eval\"\n"
                "  :summary \"Evaluate AgentScript S-expression directly in engine\"\n"
                "  :signature \"eval <expr>\"\n"
                "  :status :help)")))
    ((= toolName "batch")
     (some (str "(:help\n"
                "  :tool \"batch\"\n"
                "  :summary \"Execute list of commands atomically\"\n"
                "  :signature \"batch <commands>\"\n"
                "  :status :help)")))
    ((= toolName "tool-load")
     (some (str "(:help\n"
                "  :tool \"tool-load\"\n"
                "  :summary \"Mount dynamic domain tools into active tool plane\"\n"
                "  :signature \"tool-load <domain>\"\n"
                "  :status :help)")))
    ((= toolName "tool-unload")
     (some (str "(:help\n"
                "  :tool \"tool-unload\"\n"
                "  :summary \"Unmount dynamic domain tools from active tool plane\"\n"
                "  :signature \"tool-unload <domain>\"\n"
                "  :status :help)")))
    (:else (none))))
