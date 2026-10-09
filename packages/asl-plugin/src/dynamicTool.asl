(module asl-plugin/dynamicTool :x [ToolParam ToolDef ToolDomain ToolPlane MountReceipt UnmountReceipt ActiveLandscape baseTools emptyPlane createParam createTool createDomain domainLoaded? hasTool? lookupTool toolCount activeDomains loadDomain unloadDomain resetTurn mountReceipt unmountReceipt formatGraph renderParam renderTool renderLandscape activeLandscape baseLandscape? renderDenseTool renderDenseLandscape lookupToolHelp countWords validDenseDoc?] :i [(asl-text/text :a txt)])

(schema ToolParam (:f name Str) (:f paramType Str) (:f optional Bool) (:f doc Str))

(schema ToolDef (:f name Str) (:f domain Str) (:f params (List ToolParam)) (:f returnsType Str) (:f doc Str) (:f formatSchema Str))

(schema ToolDomain (:f name Str) (:f doc Str) (:f tools (List ToolDef)) (:f graphSchema Str))

(schema ToolPlane (:f baseMeta (List Str)) (:f activeDomains (List Str)) (:f mountedTools (Map Str ToolDef)) (:f turnCounter Int))

(schema MountReceipt (:f domain Str) (:f mountedCount Int) (:f status Str) (:f toolNames (List Str)))

(schema UnmountReceipt (:f domain Str) (:f unmountedCount Int) (:f status Str))

(schema ActiveLandscape (:f domains (List Str)) (:f toolNames (List Str)) (:f totalCount Int) (:f baseOnly Bool) (:f tokenFootprint Int))

fn baseTools -> (List Str)
  (list "eval" "batch" "tool-load" "tool-unload")

fn emptyPlane -> ToolPlane
  (ToolPlane :baseMeta (baseTools) :activeDomains (list) :mountedTools (mapEmpty) :turnCounter 0)

fn createParam name: Str ptype: Str opt: Bool doc: Str -> ToolParam
  (ToolParam :name name :paramType ptype :optional opt :doc doc)

fn createTool name: Str domain: Str params: (List ToolParam) returnsType: Str doc: Str formatSchema: Str -> ToolDef
  (ToolDef :name name :domain domain :params params :returnsType returnsType :doc doc :formatSchema formatSchema)

fn createDomain name: Str doc: Str tools: (List ToolDef) graphSchema: Str -> ToolDomain
  (ToolDomain :name name :doc doc :tools tools :graphSchema graphSchema)

fn domainLoaded? plane: ToolPlane domainName: Str -> Bool
  (listContains? plane.activeDomains domainName)

fn hasTool? plane: ToolPlane toolName: Str -> Bool
  (or (listContains? plane.baseMeta toolName) (mapHas? plane.mountedTools toolName))

fn lookupTool plane: ToolPlane toolName: Str -> (Option ToolDef)
  (mapGet plane.mountedTools toolName)

fn toolCount plane: ToolPlane -> Int
  (+ (listLength plane.baseMeta) (mapSize plane.mountedTools))

fn activeDomains plane: ToolPlane -> (List Str)
  plane.activeDomains

fn loadDomain plane: ToolPlane domain: ToolDomain -> ToolPlane
  (let [(dName domain.name) (newDomains (if (domainLoaded? plane dName) plane.activeDomains (listAppend plane.activeDomains (list dName)))) (newTools (fold (fn [(acc (Map Str ToolDef)) (t ToolDef)] -> (Map Str ToolDef) (mapSet acc t.name t)) plane.mountedTools domain.tools))] (with plane :activeDomains newDomains :mountedTools newTools :turnCounter (+ plane.turnCounter 1)))

fn unloadDomain plane: ToolPlane domainName: Str -> ToolPlane
  (let [(newDomains (filter (fn [(d Str)] -> Bool (not (= d domainName))) plane.activeDomains)) (newTools (fold (fn [(acc (Map Str ToolDef)) (toolName Str)] -> (Map Str ToolDef) (let [(tOpt (mapGet plane.mountedTools toolName))] (mt tOpt ((none) acc) ((some t) (if (= t.domain domainName) (mapRemove acc toolName) acc))))) plane.mountedTools (mapKeys plane.mountedTools)))] (with plane :activeDomains newDomains :mountedTools newTools :turnCounter (+ plane.turnCounter 1)))

fn resetTurn plane: ToolPlane -> ToolPlane
  (with plane :activeDomains (list) :mountedTools (mapEmpty) :turnCounter (+ plane.turnCounter 1))

fn mountReceipt domain: ToolDomain -> MountReceipt
  (let [(names (map (fn [(t ToolDef)] -> Str t.name) domain.tools))] (MountReceipt :domain domain.name :mountedCount (listLength names) :status "ok" :toolNames names))

fn unmountReceipt domainName: Str count: Int -> UnmountReceipt
  (UnmountReceipt :domain domainName :unmountedCount count :status "ok")

fn formatGraph node: Str edges: (List Str) -> Str
  (if (listEmpty? edges) (str "(:graph (" node "))") (str "(:graph (" node " > " (stringJoin edges " ") "))"))

fn renderParam p: ToolParam -> Str
  (let [(optStr (if p.optional " :opt true" ""))] (str "(:param :name \"" p.name "\" :type " p.paramType optStr ")"))

fn renderTool t: ToolDef -> Str
  (let [(paramsRendered (map (fn [(p ToolParam)] -> Str (renderParam p)) t.params)) (paramsStr (stringJoin paramsRendered " ")) (schemaStr (if (stringEmpty? t.formatSchema) "" (str " :schema \"" t.formatSchema "\"")))] (str "(:tool :name \"" t.name "\" :domain :" t.domain " :params [" paramsStr "] :returns " t.returnsType schemaStr ")"))

fn renderLandscape plane: ToolPlane -> Str
  (let [(baseItems (map (fn [(b Str)] -> Str (str "(:meta-tool :name \"" b "\")")) plane.baseMeta)) (mountedItems (map (fn [(toolName Str)] -> Str (let [(tOpt (mapGet plane.mountedTools toolName))] (mt tOpt ((none) "") ((some t) (renderTool t))))) (mapKeys plane.mountedTools))) (allItems (listAppend baseItems mountedItems))] (str "(:tools [\n  " (stringJoin allItems "\n  ") "\n])"))

fn baseLandscape? plane: ToolPlane -> Bool
  (and (= (listLength plane.activeDomains) 0) (and (= (mapSize plane.mountedTools) 0) (= (listLength plane.baseMeta) 4)))

fn activeLandscape plane: ToolPlane -> ActiveLandscape
  (let [(mountedNames (mapKeys plane.mountedTools)) (allNames (listAppend plane.baseMeta mountedNames)) (totCount (listLength allNames)) (isBase (= (mapSize plane.mountedTools) 0)) (rendered (renderLandscape plane)) (toks (txt/estimateTokens rendered))] (ActiveLandscape :domains plane.activeDomains :toolNames allNames :totalCount totCount :baseOnly isBase :tokenFootprint toks))

fn countWords s: Str -> Int
  (let [(tokens (filter (fn [(w Str)] -> Bool (not (stringEmpty? (stringTrim w)))) (stringSplit s " ")))] (listLength tokens))

fn validDenseDoc? doc: Str -> Bool
  (let [(cnt (countWords doc))] (and (>= cnt 2) (<= cnt 5)))

fn renderDenseTool name: Str sig: Str doc: Str -> Str
  (str "(:tool :name \"" name "\" :sig \"" sig "\" :d \"" doc "\")")

fn renderDenseLandscape plane: ToolPlane denseTools: (List Str) -> Str
  (let [(baseItems (map (fn [(b Str)] -> Str (str "(:meta-tool :name \"" b "\")")) plane.baseMeta)) (allItems (listAppend baseItems denseTools))] (if (listEmpty? allItems) "(:tools [])" (str "(:tools [\n  " (stringJoin allItems "\n  ") "\n])")))

fn lookupToolHelp toolName: Str -> (Option Str)
  (cond ((or (= toolName "mem.query") (= toolName "query")) (some (str "(:help\n" "  :tool \"mem.query\"\n" "  :summary \"Vector semantic search across AST docstrings, decisions, and codebase\"\n" "  :signature \"asl mem query <query> [--scope decisions|tasks|code|all] [--limit <n>]\"\n" "  :params [\n" "    (:param :name \"query\" :type :string :required true :d \"Search phrase or symbol pattern, max 512 bytes\")\n" "    (:param :name \"--scope\" :type :enum :values [\"decisions\" \"tasks\" \"code\" \"all\"] :default \"all\" :d \"Memory partition filter\")\n" "    (:param :name \"--limit\" :type :integer :default 10 :d \"Maximum ranked results returned\")\n" "  ]\n" "  :examples [\n" "    \"asl mem query \\\"vector cosine similarity\\\"\"\n" "    \"asl mem query \\\"auth token\\\" --scope decisions --limit 5\"\n" "  ]\n" "  :behavior \"Performs sub-15ms BM25 and cosine ranking in RAM. Returns ranked list of matches with file, line, and snippet.\"\n" "  :status :help)"))) ((or (or (= toolName "mem.edit") (= toolName "edit")) (= toolName "replace")) (some (str "(:help\n" "  :tool \"mem.edit\"\n" "  :summary \"Stage in-memory atomic string replacement in RAM virtual file buffer\"\n" "  :signature \"asl mem edit <file> <old> <new> | asl mem replace <file> <old> <new>\"\n" "  :alias [\"replace\"]\n" "  :params [\n" "    (:param :name \"file\" :type :filepath :required true :d \"Workspace-relative file path to edit\")\n" "    (:param :name \"old\" :type :string :required true :d \"Exact substring to find and replace\")\n" "    (:param :name \"new\" :type :string :required true :d \"Replacement substring\")\n" "  ]\n" "  :examples [\n" "    \"asl mem edit \\\"mem/vfs.asl\\\" \\\"oldFn\\\" \\\"newFn\\\"\"\n" "    \"asl mem edit \\\"engine/asl.c\\\" \\\"#define OLD 1\\\" \\\"#define OLD 2\\\"\"\n" "  ]\n" "  :lifecycle \"Staged in RAM. Run 'asl mem diff' to preview, 'asl mem flush' to commit to disk, or 'asl mem discard' to cancel.\"\n" "  :status :help)"))) ((or (= toolName "mem.diff") (= toolName "diff")) (some (str "(:help\n" "  :tool \"mem.diff\"\n" "  :summary \"Inspect staged in-memory modifications and dirty buffers before disk write\"\n" "  :signature \"asl mem diff [--file <file>]\"\n" "  :params [\n" "    (:param :name \"--file\" :type :filepath :required false :d \"Optional file filter to inspect specific buffer\")\n" "  ]\n" "  :examples [\n" "    \"asl mem diff\"\n" "    \"asl mem diff --file \\\"mem/vfs.asl\\\"\"\n" "  ]\n" "  :behavior \"Displays file paths, modification flags, and replacement counts currently held in RAM virtual buffers.\"\n" "  :status :help)"))) ((or (= toolName "mem.flush") (= toolName "flush")) (some (str "(:help\n" "  :tool \"mem.flush\"\n" "  :summary \"Atomically persist staged in-memory edits to the physical filesystem\"\n" "  :signature \"asl mem flush\"\n" "  :params []\n" "  :examples [\n" "    \"asl mem flush\"\n" "  ]\n" "  :behavior \"Writes all modified staged buffers to disk in a single atomic transaction and clears the RAM staging area.\"\n" "  :status :help)"))) ((or (= toolName "mem.discard") (= toolName "discard")) (some (str "(:help\n" "  :tool \"mem.discard\"\n" "  :summary \"Clear staged RAM modifications without modifying physical disk files\"\n" "  :signature \"asl mem discard\"\n" "  :params []\n" "  :examples [\n" "    \"asl mem discard\"\n" "  ]\n" "  :safety \"Non-destructive on help: invoking 'asl mem discard --help' displays this message and NEVER clears buffers.\"\n" "  :behavior \"Clears all modified virtual file buffers in RAM and restores staging clean state.\"\n" "  :status :help)"))) ((or (= toolName "mem.write") (= toolName "write")) (some (str "(:help\n" "  :tool \"mem.write\"\n" "  :summary \"Append structured memory record to canonical workspace ledgers\"\n" "  :signature \"asl mem write <kind> <payload>\"\n" "  :params [\n" "    (:param :name \"kind\" :type :enum :values [\"intent\" \"task\" \"note\" \"practice\"] :required true :d \"Target ledger category\")\n" "    (:param :name \"payload\" :type :string :required true :d \"Valid ASN formatted record content\")\n" "  ]\n" "  :examples [\n" "    \"asl mem write note \\\"(:note :topic api-design)\\\"\"\n" "    \"asl mem write practice \\\"(:practice :id p-help)\\\"\"\n" "  ]\n" "  :behavior \"Validates delimiter balance and appends record to .asl/mem/<kind>.asn.\"\n" "  :status :help)"))) ((or (= toolName "mem.doc") (= toolName "doc")) (some (str "(:help\n" "  :tool \"mem.doc\"\n" "  :summary \"Extract and read targeted documentation section without whole-file dump\"\n" "  :signature \"asl mem doc <file> <section>\"\n" "  :params [\n" "    (:param :name \"file\" :type :filepath :required true :d \"Target markdown file path\")\n" "    (:param :name \"section\" :type :string :required true :d \"Exact heading title to extract\")\n" "  ]\n" "  :examples [\n" "    \"asl mem doc \\\"README.md\\\" \\\"Ultra-Compact Native Tool Cheat Sheet\\\"\"\n" "    \"asl mem doc \\\"AGENTS.md\\\" \\\"The 4 Teleological Mandates\\\"\"\n" "  ]\n" "  :behavior \"Parses markdown AST in RAM and returns only the requested section body, preventing prompt pollution.\"\n" "  :status :help)"))) ((or (= toolName "mem.tree") (= toolName "tree")) (some (str "(:help\n" "  :tool \"mem.tree\"\n" "  :summary \"Render dense structural telemetry of multi-tier memory hierarchy across packages\"\n" "  :signature \"asl mem tree [path] [--format text|asn]\"\n" "  :params [\n" "    (:param :name \"path\" :type :filepath :default \".\" :d \"Root directory of memory tree to traverse\")\n" "    (:param :name \"--format\" :type :enum :values [\"text\" \"asn\"] :default \"text\" :d \"Output serialization format\")\n" "  ]\n" "  :examples [\n" "    \"asl mem tree\"\n" "    \"asl mem tree . --format asn\"\n" "  ]\n" "  :behavior \"Recursively scans packages, grammars, and memory ledgers in <80ms, emitting structural counts.\"\n" "  :status :help)"))) ((= toolName "mem") (some (str "(:help\n" "  :domain \"mem\"\n" "  :summary \"High-performance vector memory store and tiered virtual RAM buffer\"\n" "  :tools [\n" "    (:tool :name \"mem.query\" :sig \"query [scope] [limit]\" :d \"vector semantic search AST\")\n" "    (:tool :name \"mem.edit\" :sig \"file old new\" :d \"stage atomic string replacement\")\n" "    (:tool :name \"mem.diff\" :sig \"[file]\" :d \"inspect staged RAM diffs\")\n" "    (:tool :name \"mem.flush\" :sig \"\" :d \"persist staged edits disk\")\n" "    (:tool :name \"mem.discard\" :sig \"\" :d \"clear staged RAM buffers\")\n" "    (:tool :name \"mem.write\" :sig \"kind payload\" :d \"append durable memory ledger\")\n" "    (:tool :name \"mem.doc\" :sig \"file section\" :d \"read section without disk\")\n" "    (:tool :name \"mem.tree\" :sig \"[path]\" :d \"render holistic hierarchy telemetry\")\n" "  ]\n" "  :status :help)"))) ((= toolName "eval") (some (str "(:help\n" "  :tool \"eval\"\n" "  :summary \"Evaluate AgentScript S-expression directly in engine\"\n" "  :signature \"eval <expr>\"\n" "  :status :help)"))) ((= toolName "batch") (some (str "(:help\n" "  :tool \"batch\"\n" "  :summary \"Execute list of commands atomically\"\n" "  :signature \"batch <commands>\"\n" "  :status :help)"))) ((= toolName "tool-load") (some (str "(:help\n" "  :tool \"tool-load\"\n" "  :summary \"Mount dynamic domain tools into active tool plane\"\n" "  :signature \"tool-load <domain>\"\n" "  :status :help)"))) ((= toolName "tool-unload") (some (str "(:help\n" "  :tool \"tool-unload\"\n" "  :summary \"Unmount dynamic domain tools from active tool plane\"\n" "  :signature \"tool-unload <domain>\"\n" "  :status :help)"))) (else (none)))
