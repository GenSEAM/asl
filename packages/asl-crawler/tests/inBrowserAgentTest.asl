(module aslCrawlerTests/inBrowserAgentTest
  :x [testConfig testStealthScript testDistillerScript testKineticsScript testBootstrapScript testBootstrapEscaping testStatusAsn runTests]
  :i [(aslCrawler/inBrowserAgent :a iba)])

fn testConfig -> Bool
  (let [(cfg (iba/makeDefaultAgentConfig))]
    (assert (= cfg.agentId "asl-in-page-agent") "agentId default")
    (assert (= cfg.version "1.0.0") "version default")
    (assert cfg.stealthEvasions "stealth default true")
    (assert cfg.kineticsEnabled "kinetics default true")
    (assert (= cfg.maxSnapshotNodes 100) "max nodes 100")
    (refute (= cfg.agentId "unknown-agent") "refute unknown agent")
    (refute (<= cfg.maxSnapshotNodes 0) "refute non-positive nodes")
    true)

fn testStealthScript -> Bool
  (let [(s (iba/generateStealthEvasionScript))]
    (assert (stringContains? s "navigator, 'webdriver'") "contains webdriver evasion")
    (assert (stringContains? s "navigator, 'languages'") "contains languages evasion")
    (assert (stringContains? s "navigator, 'plugins'") "contains plugins evasion")
    (assert (stringContains? s "window.chrome = window.chrome") "contains chrome runtime mock")
    (assert (stringContains? s "WebGLRenderingContext.prototype.getParameter") "contains webgl evasion")
    (assert (stringContains? s "cdc_adoQpoasnfa76pfcZLmcfl_Array") "contains cdc array deletion")
    (refute (stringContains? s "alert('hacked')") "refute malicious code")
    true)

fn testDistillerScript -> Bool
  (let [(d (iba/generateDomDistillerScript 75))]
    (assert (stringContains? d "function distillDomToAsn()") "contains distiller function")
    (assert (stringContains? d "document.querySelectorAll") "contains query selector")
    (assert (stringContains? d "(:pageSnapshot") "contains pageSnapshot ASN")
    (assert (stringContains? d "(:node :tag") "contains node ASN")
    (assert (stringContains? d "75") "contains limit parameter")
    (assert (stringContains? d "sel += '.' + el.className.trim().split(/\\s+/)[0];") "class selector splits on JS whitespace regex")
    (refute (stringContains? d "split(/\\\\s+/)") "refute doubled backslash in split regex")
    (assert (stringContains? d "return '(:pageSnapshot\\n  :url \"' + url + '\"\\n  :title \"' + title + '\"\\n  :nodesCount ' + nodes.length + '\\n  :nodes [' + nodes.join(' ') + ']\\n  :status :ok)';") "snapshot fields separated by JS newline escapes")
    (refute (stringContains? d "(:pageSnapshot\\\\n") "refute literal backslash-n in snapshot")
    (refute (stringContains? d "JSON.stringify(document)") "refute naive json stringify")
    true)

fn testKineticsScript -> Bool
  (let [(k (iba/generateKineticExecutorScript))]
    (assert (stringContains? k "function executeKineticClick") "contains kinetic click")
    (assert (stringContains? k "function executeKineticType") "contains kinetic type")
    (assert (stringContains? k "function executeKineticScroll") "contains kinetic scroll")
    (assert (stringContains? k "MouseEvent('click'") "dispatches mouse click")
    (assert (stringContains? k "Event('input'") "dispatches input event")
    (refute (stringContains? k "document.write") "refute document.write")
    true)

fn testBootstrapScript -> Bool
  (let [(cfg (iba/makeDefaultAgentConfig))
        (b (iba/generateInBrowserAgentBootstrap cfg))]
    (assert (stringContains? b "window.__aslAgentActive") "contains active guard")
    (assert (stringContains? b "window.__aslAgent =") "exports global agent bridge")
    (assert (stringContains? b "distillDomToAsn") "integrates distiller")
    (assert (stringContains? b "executeKineticClick") "integrates kinetics")
    (assert (stringContains? b "navigator, 'webdriver'") "integrates stealth")
    (refute (stringContains? b "eval(") "refute unescaped eval")
    true)

fn testBootstrapEscaping -> Bool
  (let [(cfg (iba/InBrowserAgentConfig
               :agentId "a'b\\c"
               :version "v'1"
               :gatewayUrl "http://127.0.0.1:8765"
               :stealthEvasions false
               :kineticsEnabled false
               :behavioralNoise false
               :maxSnapshotNodes 5))
        (b (iba/generateInBrowserAgentBootstrap cfg))]
    (assert (stringContains? b "window.__aslAgentVersion = 'v\\'1';") "bootstrap escapes version global")
    (assert (stringContains? b "window.__aslAgentId = 'a\\'b\\\\c';") "bootstrap escapes agentId global")
    (assert (stringContains? b "    id: 'a\\'b\\\\c',") "bridge escapes agentId")
    (assert (stringContains? b "    version: 'v\\'1',") "bridge escapes version")
    (refute (stringContains? b "'a'b") "refute raw apostrophe in agentId")
    true)

fn testStatusAsn -> Bool
  (let [(cfg (iba/makeDefaultAgentConfig))
        (asn (iba/formatAgentStatusAsn cfg))]
    (assert (stringContains? asn "(:inBrowserAgent") "contains root header")
    (assert (stringContains? asn ":agentId \"asl-in-page-agent\"") "contains agentId")
    (assert (stringContains? asn ":stealthEvasions true") "contains stealth")
    (assert (stringContains? asn ":status :ready") "contains ready status")
    (refute (stringContains? asn ":status :failed") "refute failed status")
    true)

fn runTests -> Bool
  (do
    (assert (testConfig) "testConfig must pass")
    (assert (testStealthScript) "testStealthScript must pass")
    (assert (testDistillerScript) "testDistillerScript must pass")
    (assert (testKineticsScript) "testKineticsScript must pass")
    (assert (testBootstrapScript) "testBootstrapScript must pass")
    (assert (testBootstrapEscaping) "testBootstrapEscaping must pass")
    (assert (testStatusAsn) "testStatusAsn must pass")
    true)
