(module aslGateway/browserGateway :x [BrowserInferenceTarget BrowserTurnVerdict BrowserTargetKind BrowserTabSummary BrowserTargetDescriptor targetToString inspectBrowserTurn convertJsonToAsnToolcall formatBrowserWirePayload targetStealthSteel targetExtensionChrome targetExtensionSafari targetCdpDirect makeBrowserTabSummary makeBrowserTargetDescriptor browserTargetKindToString parseBrowserTargetKind formatBrowserTargetAsn resolvePreferredTarget] :i [(wire :a wire) (server :a server) (asl-text/string :a s)])

(enum BrowserInferenceTarget (:c targetWebgpu [] "In-browser WebGPU execution (e.g. WebLLM, Transformers.js)") (:c targetWasm [] "In-browser WebAssembly CPU execution (e.g. ONNX Runtime Web)") (:c targetLocalOllama [] "Local machine Ollama HTTP endpoint") (:c targetLocalVllm [] "Local machine vLLM or llama.cpp endpoint"))

(enum BrowserTargetKind (:c targetStealthSteel [] "Isolated headless stealth session for unauthenticated crawling/scraping") (:c targetExtensionChrome [] "User daily Chrome browser with ASL WebExtension") (:c targetExtensionSafari [] "User daily Safari browser with ASL WebExtension") (:c targetCdpDirect [] "Direct Chrome DevTools Protocol port connection"))

(schema BrowserTabSummary (:f tabId Str) (:f title Str) (:f url Str) (:f isActive Bool))

(schema BrowserTargetDescriptor (:f targetId Str) (:f kind BrowserTargetKind) (:f browserFamily Str) (:f isAuthenticatedContext Bool) (:f capabilities (List Str)) (:f activeTabs (List BrowserTabSummary)) (:f lastHeartbeatSec I64))

(schema BrowserTurnVerdict (:f allowed Bool) (:f quarantinedThink Str) (:f cleanOutput Str) (:f toolCalls (List Str)) (:f rejectionReason Str))

fn convertJsonToAsnToolcall toolName: Str jsonArgsStr: Str -> Str
  (str "(:call :tool \"" toolName "\" :args " jsonArgsStr ")")

fn targetToString target: BrowserInferenceTarget -> Str
  (mt target ((targetWebgpu) "target-webgpu") ((targetWasm) "target-wasm") ((targetLocalOllama) "target-local-ollama") ((targetLocalVllm) "target-local-vllm"))

fn browserTargetKindToString kind: BrowserTargetKind -> Str
  (mt kind ((targetStealthSteel) "stealthSteel") ((targetExtensionChrome) "extensionChrome") ((targetExtensionSafari) "extensionSafari") ((targetCdpDirect) "cdpDirect"))

fn parseBrowserTargetKind s: Str -> BrowserTargetKind
  (cond ((or (= s "stealthSteel") (= s "steel")) (targetStealthSteel)) ((or (= s "extensionChrome") (= s "chrome")) (targetExtensionChrome)) ((or (= s "extensionSafari") (= s "safari")) (targetExtensionSafari)) (else (targetCdpDirect)))

fn makeBrowserTabSummary id: Str title: Str url: Str active: Bool -> BrowserTabSummary
  (BrowserTabSummary :tabId id :title title :url url :isActive active)

fn makeBrowserTargetDescriptor id: Str kind: BrowserTargetKind family: Str auth: Bool caps: (List Str) tabs: (List BrowserTabSummary) heartbeat: I64 -> BrowserTargetDescriptor
  (BrowserTargetDescriptor :targetId id :kind kind :browserFamily family :isAuthenticatedContext auth :capabilities caps :activeTabs tabs :lastHeartbeatSec heartbeat)

fn escapeAsnString strVal: Str -> Str
  (let [(chars (stringChars strVal))] (fold (fn [(acc Str) (c Str)] -> Str (if (= c "\\") (str acc "\\\\") (if (= c "\"") (str acc "\\\"") (if (= c "\n") (str acc "\\n") (if (= c "\t") (str acc "\\t") (if (= c "\r") (str acc "\\r") (str acc c))))))) "" chars))

fn formatBrowserWirePayload prompt: Str target: BrowserInferenceTarget -> Str
  (str "(:inference-request :target \"" (targetToString target) "\" :prompt \"" (escapeAsnString prompt) "\")")

fn formatBrowserTargetAsn desc: BrowserTargetDescriptor -> Str
  (let [(kindStr (browserTargetKindToString desc.kind)) (authStr (if desc.isAuthenticatedContext "true" "false")) (tabCount (listLength desc.activeTabs))] (str "(:browserTarget :id \"" desc.targetId "\" :kind :" kindStr " :family \"" desc.browserFamily "\" :authenticated " authStr " :tabsCount " (stringFromInt64 tabCount) " :lastHeartbeat " (stringFromInt64 desc.lastHeartbeatSec) ")"))

fn resolvePreferredTarget intent: Str hasActiveUserSession: Bool -> BrowserTargetKind
  (cond ((or (stringContains? intent "scrape") (or (stringContains? intent "crawl") (stringContains? intent "research"))) (targetStealthSteel)) ((and hasActiveUserSession (stringContains? intent "safari")) (targetExtensionSafari)) (hasActiveUserSession (targetExtensionChrome)) (else (targetStealthSteel)))

fn inspectBrowserTurn rawText: Str hasVerifiedExec: Bool -> BrowserTurnVerdict
  (let [(demuxThink (server/extractThinkBlocks rawText)) (thinkPart (pairFirst demuxThink)) (remaining (pairSecond demuxThink)) (demuxAsn (wire/demuxRawAsnTurn remaining)) (uiPart (pairFirst demuxAsn)) (toolPart (pairSecond demuxAsn)) (isEsh (and (server/detectEshViolation uiPart) (not hasVerifiedExec)))] (if isEsh (BrowserTurnVerdict :allowed false :quarantinedThink thinkPart :cleanOutput "Action blocked by L7 Cognitive Gateway: verbal claim of test passage without verified execution receipt (ESH violation)." :toolCalls (list) :rejectionReason "Verbal self-declared execution without verified runtime proof (ESH violation)") (BrowserTurnVerdict :allowed true :quarantinedThink thinkPart :cleanOutput uiPart :toolCalls toolPart :rejectionReason "")))
