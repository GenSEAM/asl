(module aslAgentBus/browserBridge :x [BridgeTab BridgeCommand BrowserBridgeState BrowserBridgeTraceFrame bridgeInit bridgeRegisterTab bridgeEnqueueCommand bridgePollCommands bridgeCompleteCommand formatCorsHttpResponse isBridgeOpfsPathSafe? emitBrowserTraceFrame queryBrowserBridgeCapability makeBrowserBridgeTraceFrame convertBrowserFrameToMesh] :i [(asl-text/string :a s) (mesh :a mesh)])

(schema BridgeTab (:f tabId Str) (:f url Str) (:f title Str) (:f connectedAt I64))

(schema BridgeCommand (:f id Str) (:f tabId Str) (:f action Str) (:f payload Str) (:f status Str) (:f result Str))

(schema BrowserBridgeState (:f port I64) (:f tabs (List BridgeTab)) (:f commands (List BridgeCommand)))

fn bridgeInit port: I64 -> BrowserBridgeState
  (BrowserBridgeState :port port :tabs (list) :commands (list))

fn bridgeRegisterTab state: BrowserBridgeState tab: BridgeTab -> BrowserBridgeState
  (let [(existing (filter (fn [(t BridgeTab)] -> Bool (!= t.tabId tab.tabId)) state.tabs)) (updatedTabs (listAppend existing (list tab)))] (with state :tabs updatedTabs))

fn bridgeEnqueueCommand state: BrowserBridgeState cmd: BridgeCommand -> BrowserBridgeState
  (with state :commands (listAppend state.commands (list cmd)))

fn bridgePollCommands state: BrowserBridgeState tabId: Str -> (Pair BrowserBridgeState (List BridgeCommand))
  (let [(pendingCmds (filter (fn [(c BridgeCommand)] -> Bool (and (== c.tabId tabId) (== c.status "pending"))) state.commands)) (updatedCommands (map (fn [(c BridgeCommand)] -> BridgeCommand (if (and (== c.tabId tabId) (== c.status "pending")) (BridgeCommand :id c.id :tabId c.tabId :action c.action :payload c.payload :status "dispatched" :result c.result) c)) state.commands))] (pair (with state :commands updatedCommands) pendingCmds))

fn bridgeCompleteCommand state: BrowserBridgeState cmdId: Str status: Str result: Str -> BrowserBridgeState
  (let [(updatedCommands (map (fn [(c BridgeCommand)] -> BridgeCommand (if (== c.id cmdId) (BridgeCommand :id c.id :tabId c.tabId :action c.action :payload c.payload :status status :result result) c)) state.commands))] (with state :commands updatedCommands))

fn formatCorsHttpResponse statusCode: I64 contentType: Str body: Str -> Str
  (let [(corsHeaders "Access-Control-Allow-Origin: http://localhost\r\nAccess-Control-Allow-Methods: GET, POST, OPTIONS, PUT, DELETE\r\nAccess-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With")] (if (= statusCode 204) (str "HTTP/1.1 204 No Content\r\n" corsHeaders "\r\nContent-Length: 0\r\n\r\n") (let [(statusLine (cond ((= statusCode 200) "HTTP/1.1 200 OK") ((= statusCode 400) "HTTP/1.1 400 Bad Request") ((= statusCode 404) "HTTP/1.1 404 Not Found") (else "HTTP/1.1 500 Internal Server Error"))) (bodyLen (stringLength body))] (str statusLine "\r\n" corsHeaders "\r\nContent-Type: " contentType "\r\nContent-Length: " bodyLen "\r\n\r\n" body))))

fn checkBridgeSegments segs: (List Str) depth: I64 -> Bool
  (if (listEmpty? segs) true (let [(h (optionOr (listHead segs) "")) (t (optionOr (listTail segs) (list)))] (cond ((or (stringEmpty? h) (= h ".")) (checkBridgeSegments t depth)) ((= h "..") (if (<= depth 0) false (checkBridgeSegments t (- depth 1)))) (else (checkBridgeSegments t (+ depth 1))))))

fn isBridgeOpfsPathSafe? wsRoot: Str targetPath: Str -> Bool
  (if (stringStartsWith? targetPath "/") false (let [(subpath (if (stringStartsWith? targetPath "opfs://") (if (stringStartsWith? targetPath wsRoot) (let [(wslen (stringLength wsRoot)) (tlen (stringLength targetPath))] (if (= wslen tlen) "" (let [(rest (optionOr (stringSlice targetPath wslen tlen) ""))] (if (stringStartsWith? rest "/") (optionOr (stringSlice rest 1 (stringLength rest)) "") rest)))) "INVALID_OPFS_ROOT") targetPath))] (if (= subpath "INVALID_OPFS_ROOT") false (checkBridgeSegments (stringSplit subpath "/") 0))))

fn emitBrowserTraceFrame frameId: Str sessionId: Str senderId: Str parentDigest: Str seq: I64 clock: I64 nowMs: I64 op: Str target: Str status: Str digest: Str -> mesh/CausalTraceFrame
  (mesh/makeCausalTraceFrame frameId sessionId "browser" senderId parentDigest seq clock nowMs op target status digest)

fn queryBrowserBridgeCapability capId: Str -> (Option Str)
  (cond ((= capId "pathBoundary") (some "works")) ((= capId "wasmBatchRpc") (some "works")) ((= capId "runCommand") (some "delegate to local or relay runtime via agent-bus")) ((= capId "procSpawn") (some "delegate to local or relay runtime via agent-bus")) ((= capId "netSocket") (some "use fetch or WebSockets via browser-bridge")) ((= capId "nativeFs") (some "use OPFS workspace")) (else none))
