(module aslAgent/computerUse :x [TargetSubstrate ComputerActionKind SpatialBoundingBox ComputerActionRequest ComputerActionReceipt substrateBrowser substrateDesktop substrateTerminal actionNavigate actionClick actionType actionInspect actionScreenshot makeSpatialBox makeComputerAction confirmComputerAction isActionPermitted? formatCdpPayload formatAccessibilityPayload executeComputerAction formatComputerReceiptAsn routeComputerAction resolveSubstrateByIntent] :i [(asl-text/string :a s)])

(enum TargetSubstrate (:c substrateBrowser [] "Browser substrate via Chrome DevTools Protocol or WebExtension") (:c substrateDesktop [] "Desktop substrate via macOS Accessibility API") (:c substrateTerminal [] "Terminal CLI execution via PTY"))

(enum ComputerActionKind (:c actionNavigate [] "Navigate to URL or open application") (:c actionClick [] "Mouse click or element tap") (:c actionType [] "Keyboard typing or key combination") (:c actionInspect [] "Query accessibility tree or element hierarchy") (:c actionScreenshot [] "Capture active window or spatial box"))

(schema SpatialBoundingBox (:f x I64) (:f y I64) (:f width I64) (:f height I64))

(schema ComputerActionRequest (:f actionId Str) (:f substrate TargetSubstrate) (:f kind ComputerActionKind) (:f targetSelector Str) (:f payload Str) (:f box SpatialBoundingBox) (:f isDestructive Bool) (:f confirmedByUser Bool))

(schema ComputerActionReceipt (:f actionId Str) (:f exitCode I64) (:f status Str) (:f observation Str) (:f durationMs I64))

fn makeSpatialBox x: I64 y: I64 w: I64 h: I64 -> SpatialBoundingBox
  (SpatialBoundingBox :x x :y y :width w :height h)

fn makeComputerAction id: Str sub: TargetSubstrate kind: ComputerActionKind selector: Str payload: Str box: SpatialBoundingBox destructive: Bool -> ComputerActionRequest
  (ComputerActionRequest :actionId id :substrate sub :kind kind :targetSelector selector :payload payload :box box :isDestructive destructive :confirmedByUser false)

fn confirmComputerAction action: ComputerActionRequest -> ComputerActionRequest
  (with action :confirmedByUser true)

fn isActionPermitted? action: ComputerActionRequest -> Bool
  (if action.isDestructive action.confirmedByUser true)

fn formatCdpPayload action: ComputerActionRequest -> Str
  (mt action.kind ((actionNavigate) (str "{\"id\":1,\"method\":\"Page.navigate\",\"params\":{\"url\":\"" action.payload "\"}}")) ((actionClick) (str "{\"id\":2,\"method\":\"Input.dispatchMouseEvent\",\"params\":{\"type\":\"mousePressed\",\"x\":" (stringFromInt64 action.box.x) ",\"y\":" (stringFromInt64 action.box.y) ",\"button\":\"left\",\"clickCount\":1}}")) ((actionType) (str "{\"id\":3,\"method\":\"Input.insertText\",\"params\":{\"text\":\"" action.payload "\"}}")) ((actionInspect) "{\"id\":4,\"method\":\"Accessibility.getFullAXTree\",\"params\":{}}") ((actionScreenshot) "{\"id\":5,\"method\":\"Page.captureScreenshot\",\"params\":{}}"))

fn formatAccessibilityPayload action: ComputerActionRequest -> Str
  (str "(:ax-call :target \"" action.targetSelector "\" :action \"" action.payload "\" :box (:x " (stringFromInt64 action.box.x) " :y " (stringFromInt64 action.box.y) "))")

fn resolveSubstrateByIntent intent: Str -> TargetSubstrate
  (cond ((or (stringContains? intent "terminal") (or (stringContains? intent "shell") (stringContains? intent "cli"))) (substrateTerminal)) ((or (stringContains? intent "browser") (or (stringContains? intent "url") (or (stringContains? intent "http") (stringContains? intent "web")))) (substrateBrowser)) (else (substrateDesktop)))

fn routeComputerAction id: Str intent: Str kind: ComputerActionKind selector: Str payload: Str box: SpatialBoundingBox isDestructive: Bool -> ComputerActionRequest
  (let [(sub (resolveSubstrateByIntent intent))] (ComputerActionRequest :actionId id :substrate sub :kind kind :targetSelector selector :payload payload :box box :isDestructive isDestructive :confirmedByUser false))

fn executeComputerAction action: ComputerActionRequest -> ComputerActionReceipt
  (if (not (isActionPermitted? action)) (ComputerActionReceipt :actionId action.actionId :exitCode 1 :status "blocked-by-safety" :observation "Destructive operation blocked pending operator confirmation" :durationMs 0) (let [(execRes (mt action.substrate ((substrateBrowser) (formatCdpPayload action)) ((substrateDesktop) (formatAccessibilityPayload action)) ((substrateTerminal) "pty-not-supported")))] (ComputerActionReceipt :actionId action.actionId :exitCode 0 :status "success" :observation (str "Executed action on " action.targetSelector " with res: " execRes) :durationMs 18)))

fn formatComputerReceiptAsn r: ComputerActionReceipt -> Str
  (str "(:action-receipt :id \"" r.actionId "\" :status \"" r.status "\" :exit " (stringFromInt64 r.exitCode) " :latency-ms " (stringFromInt64 r.durationMs) ")")
