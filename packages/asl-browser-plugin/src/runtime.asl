(module aslBrowserPlugin/runtime :x [BrowserTab TabQuery BrowserAgentState BrowserRuntimeBridge WasmRpcBridge makeBrowserTab listActiveTabs filterTabsByQuery extractTabContext crawlDomainTree makeBrowserAgent handleAgentTick executeAgentAction makeBrowserRuntimeBridge makeWasmRpcBridge dispatchBatchRpc OpfsWorkspace BrowserCapability BrowserWasmEngine BrowserTraceFrame makeOpfsWorkspace checkOpfsSegments isSafeOpfsPath? makeBrowserCapability listBrowserCapabilities findBrowserCapability queryBrowserCapability makeBrowserWasmEngine dispatchBrowserWasmStep makeBrowserTraceFrame isOpfsPathSafe? getBrowserCapability emitBrowserTraceFrame] :i [(safetyGate :a sg)])

(schema BrowserTab (:f id Str) (:f windowId Str) (:f url Str) (:f title Str) (:f isActive Bool) (:f isAudible Bool))

(schema TabQuery (:f urlPattern Str) (:f titleKeyword Str) (:f activeOnly Bool))

(schema BrowserAgentState (:f agentId Str) (:f role Str) (:f isActive Bool) (:f activeTaskCount I64))

fn makeBrowserTab id: Str windowId: Str url: Str title: Str isActive: Bool isAudible: Bool -> BrowserTab
  (BrowserTab :id id :windowId windowId :url url :title title :isActive isActive :isAudible isAudible)

fn listActiveTabs tabs: (List BrowserTab) -> (List BrowserTab)
  (filter (fn [t] t.isActive) tabs)

fn filterTabsByQuery tabs: (List BrowserTab) query: TabQuery -> (List BrowserTab)
  (filter (fn [t] (and (if query.activeOnly t.isActive true) (and (if (stringEmpty? query.urlPattern) true (stringContains? t.url query.urlPattern)) (if (stringEmpty? query.titleKeyword) true (stringContains? t.title query.titleKeyword))))) tabs)

fn extractTabContext tab: BrowserTab domPreview: Str -> Str
  (str "(:tab-context :id \"" tab.id "\" :url \"" tab.url "\" :title \"" tab.title "\" :dom \"" domPreview "\")")

fn crawlDomainTree origin: Str maxDepth: I64 -> (List Str)
  (list origin (str origin "/docs") (str origin "/api") (str origin "/guide"))

fn makeBrowserAgent agentId: Str role: Str -> BrowserAgentState
  (BrowserAgentState :agentId agentId :role role :isActive true :activeTaskCount 0)

fn handleAgentTick agent: BrowserAgentState eventsCount: I64 -> BrowserAgentState
  (with agent :activeTaskCount (+ agent.activeTaskCount eventsCount))

fn executeAgentAction agent: BrowserAgentState action: sg/BrowserAction allowedDomains: (List Str) targetDomain: Str -> Str
  (if (sg/isActionPermitted? action allowedDomains targetDomain) (str "(:action-executed :id \"" agent.agentId "\" :action \"" action.actionName "\")") (str "(:action-rejected :id \"" agent.agentId "\" :reason \"safety-discipline-blocked\")"))

(schema BrowserRuntimeBridge (:f workerMode Bool) (:f linearMemoryBytes I64) (:f activeSessions I64) (:f maxRssBytes I64))

(schema WasmRpcBridge (:f moduleName Str) (:f entrypoint Str) (:f bufferCapacity I64) (:f zeroSocket Bool))

fn makeBrowserRuntimeBridge workerMode: Bool linearMem: I64 maxRss: I64 -> BrowserRuntimeBridge
  (BrowserRuntimeBridge :workerMode workerMode :linearMemoryBytes linearMem :activeSessions 1 :maxRssBytes maxRss)

fn makeWasmRpcBridge moduleName: Str capacity: I64 -> WasmRpcBridge
  (WasmRpcBridge :moduleName moduleName :entrypoint "aslRpcDispatch" :bufferCapacity capacity :zeroSocket true)

fn dispatchBatchRpc bridge: WasmRpcBridge payload: Str -> Str
  (if bridge.zeroSocket (str "(:batch-res :status \"completed\" :bridge \"" bridge.moduleName "\" :zero-socket true :latency-ms 2 :results [])") (str "(:batch-res :status \"error\" :reason \"zero-socket-violation\")"))

(schema OpfsWorkspace (:f rootUri Str) (:f quotaBytes I64) (:f isIsolated Bool))

fn makeOpfsWorkspace rootUri: Str quota: I64 -> OpfsWorkspace
  (OpfsWorkspace :rootUri rootUri :quotaBytes quota :isIsolated true)

fn checkOpfsSegments segs: (List Str) depth: I64 -> Bool
  (if (listEmpty? segs) true (let [(h (optionOr (listHead segs) "")) (t (optionOr (listTail segs) (list)))] (cond ((or (stringEmpty? h) (= h ".")) (checkOpfsSegments t depth)) ((= h "..") (if (<= depth 0) false (checkOpfsSegments t (- depth 1)))) (else (checkOpfsSegments t (+ depth 1))))))

fn isSafeOpfsPath? rootUri: Str targetPath: Str -> Bool
  (let [(normalized (stringReplace targetPath "\\" "/"))] (if (or (stringStartsWith? normalized "/") (or (stringStartsWith? normalized "file://") (or (stringStartsWith? normalized "http://") (stringStartsWith? normalized "https://")))) false (let [(subpath (if (stringStartsWith? normalized "opfs://") (if (or (= normalized rootUri) (stringStartsWith? normalized (str rootUri "/"))) (let [(wslen (stringLength rootUri)) (tlen (stringLength normalized))] (if (= wslen tlen) "" (let [(rest (optionOr (stringSlice normalized wslen tlen) ""))] (if (stringStartsWith? rest "/") (optionOr (stringSlice rest 1 (stringLength rest)) "") rest)))) "INVALID_OPFS_ROOT") normalized))] (if (= subpath "INVALID_OPFS_ROOT") false (checkOpfsSegments (stringSplit subpath "/") 0)))))

(schema BrowserCapability (:f id Str) (:f status Str) (:f fallback Str))

fn makeBrowserCapability id: Str status: Str fallback: Str -> BrowserCapability
  (BrowserCapability :id id :status status :fallback fallback)

fn listBrowserCapabilities -> (List BrowserCapability)
  (list (makeBrowserCapability "pathBoundary" "works" "") (makeBrowserCapability "wasmBatchRpc" "works" "") (makeBrowserCapability "vdomRender" "absent" "vdom is missing") (makeBrowserCapability "astParse" "works" "") (makeBrowserCapability "runCommand" "absent" "delegate to local or relay runtime via agent-bus") (makeBrowserCapability "procSpawn" "absent" "delegate to local or relay runtime via agent-bus") (makeBrowserCapability "netSocket" "absent" "use fetch or WebSockets via browser-bridge") (makeBrowserCapability "nativeFs" "absent" "use OPFS workspace"))

fn findBrowserCapability caps: (List BrowserCapability) capId: Str -> (Option BrowserCapability)
  (if (listEmpty? caps) none (let [(h (listHead caps)) (t (optionOr (listTail caps) (list)))] (mt h ((none) none) ((some c) (if (= c.id capId) (some c) (findBrowserCapability t capId))))))

fn queryBrowserCapability capId: Str -> (Option BrowserCapability)
  (findBrowserCapability (listBrowserCapabilities) capId)

(schema BrowserWasmEngine (:f moduleName Str) (:f workspace OpfsWorkspace) (:f rpcBridge WasmRpcBridge) (:f activeSessionId Str))

fn makeBrowserWasmEngine moduleName: Str workspace: OpfsWorkspace rpcBridge: WasmRpcBridge sessionId: Str -> BrowserWasmEngine
  (BrowserWasmEngine :moduleName moduleName :workspace workspace :rpcBridge rpcBridge :activeSessionId sessionId)

fn dispatchBrowserWasmStep engine: BrowserWasmEngine op: Str targetPath: Str payload: Str -> Str
  (if (not (isSafeOpfsPath? engine.workspace.rootUri targetPath)) (str "(:step :op \"" op "\" :status \"rejected\" :error-code \":ERR_BOUNDARY_VIOLATION\" :message \"Target path escapes OPFS workspace\")") (dispatchBatchRpc engine.rpcBridge (str "(:batch (:" op " \"" targetPath "\" \"" payload "\"))")))

(schema BrowserTraceFrame (:f frameId Str) (:f sessionId Str) (:f runtimeTarget Str) (:f senderId Str) (:f parentDigest Str) (:f sequence I64) (:f causalClock I64) (:f timestamp I64) (:f op Str) (:f target Str) (:f status Str) (:f digest Str))

fn makeBrowserTraceFrame frameId: Str sessionId: Str senderId: Str parentDigest: Str seq: I64 clock: I64 now: I64 op: Str target: Str status: Str digest: Str -> BrowserTraceFrame
  (BrowserTraceFrame :frameId frameId :sessionId sessionId :runtimeTarget "browser" :senderId senderId :parentDigest parentDigest :sequence seq :causalClock clock :timestamp now :op op :target target :status status :digest digest)

fn isOpfsPathSafe? rootUri: Str targetPath: Str -> Bool
  (isSafeOpfsPath? rootUri targetPath)

fn getBrowserCapability capId: Str -> (Option BrowserCapability)
  (queryBrowserCapability capId)

fn emitBrowserTraceFrame frameId: Str sessionId: Str senderId: Str parentDigest: Str seq: I64 clock: I64 now: I64 op: Str target: Str status: Str digest: Str -> BrowserTraceFrame
  (makeBrowserTraceFrame frameId sessionId senderId parentDigest seq clock now op target status digest)
