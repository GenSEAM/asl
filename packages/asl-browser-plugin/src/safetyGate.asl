(module aslBrowserPlugin/safetyGate :x [BrowserAction classifyActionTier validateBrowserAction isActionPermitted? makeBrowserAction] :i [(aslContracts/toolPlane :a tp)])

(schema BrowserAction (:f actionName Str) (:f tier ToolSafety) (:f targetTab Str) (:f payload Str) (:f isConfirmed Bool))

fn classifyActionTier actionName: Str -> ToolSafety
  (let [(act (stringLower actionName))] (cond ((or (= act "list-tabs") (or (= act "get-dom") (or (= act "search") (or (= act "extract-text") (= act "get-tab-info"))))) (tp/safetySafe)) ((or (= act "open-tab") (or (= act "scroll") (or (= act "switch-tab") (= act "click-link")))) (tp/safetyGuarded)) (else (tp/safetyDangerous))))

fn makeBrowserAction actionName: Str targetTab: Str payload: Str isConfirmed: Bool -> BrowserAction
  (BrowserAction :actionName actionName :tier (classifyActionTier actionName) :targetTab targetTab :payload payload :isConfirmed isConfirmed)

fn isActionPermitted? action: BrowserAction allowedDomains: (List Str) targetDomain: Str -> Bool
  (mt action.tier ((safetySafe) true) ((safetyGuarded) (listContains? allowedDomains targetDomain)) ((safetyDangerous) (and action.isConfirmed (listContains? allowedDomains targetDomain))))

fn validateBrowserAction actionName: Str isConfirmed: Bool allowedDomains: (List Str) targetDomain: Str -> Bool
  (let [(act (makeBrowserAction actionName "tab-1" "" isConfirmed))] (isActionPermitted? act allowedDomains targetDomain))
