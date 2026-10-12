(module aslBrowserPlugin/tests/browserAgentTest
  :x [testBrowserPluginSourceIntegrity! testBrowserPluginGrammarRegistration! testActionClassificationLogic testMessageRoutingContracts! testInPageAgentBridgeWithSafetyGate! RunTests! runTests]
  :i [(aslBrowserPlugin/safetyGate :a sg)])

fn testBrowserPluginSourceIntegrity! -> Bool
  (let [(bgRes (fileRead "asl/packages/asl-browser-plugin/src/background.asl"))
        (cntRes (fileRead "asl/packages/asl-browser-plugin/src/content.asl"))
        (sgRes (fileRead "asl/packages/asl-browser-plugin/src/safetyGate.asl"))
        (rtRes (fileRead "asl/packages/asl-browser-plugin/src/runtime.asl"))]
    (mt bgRes
      ((err e1) (assert false (str "Failed to read background.asl: " e1)))
      ((ok bgSrc)
        (do
          (assert (stringContains? bgSrc "fn initServiceWorker") "background defines initServiceWorker")
          (assert (stringContains? bgSrc "fn handleMessage") "background defines handleMessage")
          (refute (stringContains? bgSrc "Mach-O") "Zero Mach-O in background")
          (refute (stringContains? bgSrc "ELF64") "Zero ELF64 in background"))))
    (mt cntRes
      ((err e2) (assert false (str "Failed to read content.asl: " e2)))
      ((ok cntSrc)
        (do
          (assert (stringContains? cntSrc "fn extractPageContext") "content defines extractPageContext")
          (assert (stringContains? cntSrc "fn dispatchAction") "content defines dispatchAction")
          (refute (= cntSrc "") "content source refutes empty"))))
    (mt sgRes
      ((err e3) (assert false (str "Failed to read safetyGate.asl: " e3)))
      ((ok sgSrc)
        (do
          (assert (stringContains? sgSrc "fn isActionPermitted?") "safetyGate defines isActionPermitted?")
          (assert (stringContains? sgSrc "fn validateBrowserAction") "safetyGate defines validateBrowserAction")
          (refute (= sgSrc "") "safetyGate source refutes empty"))))
    (mt rtRes
      ((err e4) (assert false (str "Failed to read runtime.asl: " e4)))
      ((ok rtSrc)
        (do
          (assert (or (stringContains? rtSrc "schema BrowserTab") (stringContains? rtSrc "dfs BrowserTab")) "runtime defines BrowserTab")
          (assert (or (stringContains? rtSrc "schema TabQuery") (stringContains? rtSrc "dfs TabQuery")) "runtime defines TabQuery")
          (assert (stringContains? rtSrc "fn listActiveTabs") "runtime defines listActiveTabs")
          (refute (= rtSrc "") "runtime source refutes empty"))))
    true)

fn testBrowserPluginGrammarRegistration! -> Bool
  (let [(gRes (fileRead "asl/packages/asl-browser-plugin/manifest.asn"))]
    (mt gRes
      ((err e) (assert false (str "Failed to read asl/packages/asl-browser-plugin/manifest.asn: " e)))
      ((ok gSrc)
        (do
          (assert (stringContains? gSrc ":package aslBrowserPlugin") "manifest registers aslBrowserPlugin")
          (assert (stringContains? gSrc "\"aslBrowserPlugin/runtime\"") "manifest registers runtime")
          (assert (stringContains? gSrc "\"aslBrowserPlugin/content\"") "manifest registers content")
          (assert (stringContains? gSrc "\"aslBrowserPlugin/background\"") "manifest registers background")
          (assert (stringContains? gSrc "\"aslBrowserPlugin/localSlm\"") "manifest registers local-slm")
          (assert (stringContains? gSrc "\"aslAgentBus\"") "manifest registers aslAgentBus dependency")
          (refute (stringContains? gSrc ";;") "browser plugin manifest refutes legacy line comments"))))
    true)

fn testActionClassificationLogic -> Bool
  (let [(safeAct (sg/makeBrowserAction "list-tabs" "t1" "" false))
        (guardedAct (sg/makeBrowserAction "open-tab" "t1" "" false))
        (dangerousAct (sg/makeBrowserAction "eval-js" "t1" "" false))
        (confirmedAct (sg/makeBrowserAction "eval-js" "t1" "" true))
        (allowed (list "example.org"))]
    (assert (sg/isActionPermitted? safeAct (list) "other.org") "safe action is permitted on any domain")
    (refute (sg/isActionPermitted? guardedAct allowed "other.org") "guarded action refutes an unlisted domain")
    (assert (sg/isActionPermitted? guardedAct allowed "example.org") "guarded action is permitted on a listed domain")
    (assert (sg/isActionPermitted? confirmedAct allowed "example.org") "confirmed dangerous action is permitted on a listed domain")
    (refute (sg/isActionPermitted? dangerousAct allowed "example.org") "unconfirmed dangerous action refutes permission")
    true)

fn testMessageRoutingContracts! -> Bool
  (mt (fileRead "asl/packages/asl-browser-plugin/src/background.asl")
    ((err e) (do (assert false (str "Failed to read background.asl: " e)) false))
    ((ok src)
     (do
       (assert (stringContains? src "((or (= clean \"(:ping)\") (= clean \"ping\")) \"(:pong)\")") "handleMessage answers a ping wire frame with pong")
       (refute (stringContains? src "(= clean \"(:pong)\")") "handleMessage refutes answering a pong")
       (assert (stringContains? src "(= clean \"(:get-version)\")") "handleMessage routes the get-version frame")
       (refute (stringContains? src "\"(:version \\\"2.0.0\\\")\"") "version response refutes 2.0.0")
       (assert (stringContains? src "\"(:version \\\"1.0.0\\\")\"") "version response names 1.0.0")
       (refute (stringContains? src "(= clean \"pong\")") "handleMessage refutes routing a bare pong")
       true)))

fn testInPageAgentBridgeWithSafetyGate! -> Bool
  (let [(cntRes (fileRead "asl/packages/asl-browser-plugin/src/content.asl"))
        (bgRes (fileRead "asl/packages/asl-browser-plugin/src/background.asl"))]
    (mt cntRes
      ((err e) (assert false (str "Failed to read content.asl: " e)))
      ((ok cntSrc)
        (do
          (assert (stringContains? cntSrc "extractMedia") "content recognizes extractMedia action")
          (assert (stringContains? cntSrc "execInPageAgent") "content recognizes execInPageAgent action")
          (assert (stringContains? cntSrc "window.__aslAgent") "content hooks into window.__aslAgent"))))
    (mt bgRes
      ((err e2) (assert false (str "Failed to read background.asl: " e2)))
      ((ok bgSrc)
        (do
          (assert (stringContains? bgSrc "sg/isActionPermitted?") "background enforces safety gate check")
          (assert (stringContains? bgSrc "execInPageAgent") "background routes execInPageAgent"))))
    true)

fn RunTests! -> Bool
  (and (testBrowserPluginSourceIntegrity!)
       (testBrowserPluginGrammarRegistration!)
       (testActionClassificationLogic)
       (testMessageRoutingContracts!)
       (testInPageAgentBridgeWithSafetyGate!))

fn ! runTests -> Bool
  (RunTests!)
