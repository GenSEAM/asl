(module aslCrawlerTests/automationTest
  :x [testActionCreationAndFormatting testMediaWatchingAction testSessionPresets testActionExecutionSimulation testAutomationReceiptSerialization testBrowserSessionHandleSerialization testTikTokMediaMetadataExtraction runTests]
  :i [(automation :a auto) (session :a sess)])

fn testActionCreationAndFormatting -> Bool
  (let [(clickAct (auto/makeClickAction "button#login" true))
        (typeAct (auto/makeTypeAction "input[name='q']" "AgentSlang" 80 160))
        (scrollAct (auto/makeScrollAction "down" 850 true))
        (navAct (auto/makeNavigateAction "https://www.tiktok.com/@creator"))]
    (do
      (assert (== clickAct.op "click") "click operation")
      (assert (== clickAct.target "button#login") "click target selector")
      (assert clickAct.kinetic "click has kinetic flag")
      (assert (== typeAct.op "type") "type operation")
      (assert (== typeAct.value "AgentSlang") "type value")
      (assert (== scrollAct.op "scroll") "scroll operation")
      (assert (== scrollAct.direction "down") "scroll direction")
      (assert (== scrollAct.pixels 850) "scroll pixels")
      (assert (== navAct.op "navigate") "nav operation")
      (refute (== navAct.op "click") "nav refutes click")
      true))

fn testMediaWatchingAction -> Bool
  (let [(watchAct (auto/makeWatchMediaAction "video.player" 15 true))
        (formatted (auto/formatActionAsn watchAct))]
    (do
      (assert (== watchAct.op "watchMedia") "watchMedia op")
      (assert (== watchAct.target "video.player") "watchMedia target selector")
      (assert (== watchAct.durationSec 15) "watchMedia duration")
      (assert watchAct.extractMetadata "watchMedia extract metadata flag")
      (assert (stringContains? formatted ":op :watchMedia") "ASN contains :op :watchMedia")
      (assert (stringContains? formatted ":duration 15") "ASN contains :duration 15")
      (refute (stringContains? formatted ":op :click") "ASN refutes :click")
      true))

fn testSessionPresets -> Bool
  (let [(ttPreset (sess/getServicePreset "tiktok"))
        (ghPreset (sess/getServicePreset "github"))
        (xPreset (sess/getServicePreset "x"))
        (unknownPreset (sess/getServicePreset "nonexistent"))]
    (do
      (assert (== ttPreset.serviceName "tiktok") "tiktok service name")
      (assert (stringContains? ttPreset.loginUrl "tiktok.com") "tiktok login URL")
      (assert (== ghPreset.serviceName "github") "github service name")
      (assert (stringContains? ghPreset.loginUrl "github.com") "github login URL")
      (assert (== xPreset.serviceName "x") "x service name")
      (assert (== unknownPreset.serviceName "generic") "unknown service falls back to generic")
      (refute (== ttPreset.serviceName "github") "tiktok refutes github")
      true))

fn testActionExecutionSimulation -> Bool
  (let [(navAct (auto/makeNavigateAction "https://example.com"))
        (receipt (auto/simulateActionExecution navAct))
        (failedReceipt (auto/makeFailedReceipt "act-999" "timeout" "Navigation timed out after 5000ms"))]
    (do
      (assert (== receipt.status "ok") "simulation returns ok status")
      (assert (> receipt.durationMs 0) "simulation duration positive")
      (assert (== receipt.currentUrl "https://example.com") "current URL matches")
      (assert (stringContains? receipt.snapshot ":pageSnapshot") "snapshot is valid Dyck-1 ASN")
      (assert (== failedReceipt.status "failed") "failed status matches")
      (assert (== failedReceipt.errorReason "Navigation timed out after 5000ms") "error reason matches")
      (refute (== failedReceipt.status "ok") "failed receipt refutes ok")
      true))

fn testAutomationReceiptSerialization -> Bool
  (let [(rcpt (auto/makeAutomationReceipt "act-101" "ok" 42 "https://agentslang.org" "(:pageSnapshot :title \"AgentSlang\")" ""))
        (asn (auto/formatReceiptAsn rcpt))]
    (do
      (assert (stringContains? asn ":automationReceipt") "contains receipt header")
      (assert (stringContains? asn ":id \"act-101\"") "contains action id")
      (assert (stringContains? asn ":status :ok") "contains status :ok")
      (assert (stringContains? asn ":duration 42") "contains duration")
      (refute (stringContains? asn ":status :failed") "refutes failed")
      true))

fn testBrowserSessionHandleSerialization -> Bool
  (let [(handle (sess/makeBrowserSessionHandle "sess-99" "tab-1" "patchright" "https://example.com/app"))
        (asn (sess/formatBrowserSessionHandleAsn handle))]
    (do
      (assert (== handle.sessionId "sess-99") "handle sessionId")
      (assert (== handle.tabId "tab-1") "handle tabId")
      (assert (== handle.mode "patchright") "handle mode")
      (assert (== handle.currentUrl "https://example.com/app") "handle url")
      (assert handle.isActive "handle is active")
      (assert (stringContains? asn ":browserSession") "contains :browserSession tag")
      (assert (stringContains? asn ":sessionId \"sess-99\"") "contains session id")
      (assert (stringContains? asn ":mode :patchright") "contains mode")
      (assert (stringContains? asn ":active true") "contains active true")
      (refute (stringContains? asn ":active false") "refutes active false")
      true))

fn testTikTokMediaMetadataExtraction -> Bool
  (let [(extractAct (auto/makeTikTokExtractAction "https://www.tiktok.com/@creator/video/12345"))
        (metaReceipt (auto/makeMediaMetadataReceipt "meta-001" "tiktok" "12345" "@creator" "Super cool video" 15420 890 "Original Sound"))
        (asn (auto/formatMediaMetadataAsn metaReceipt))]
    (do
      (assert (== extractAct.op "extractMedia") "extractMedia op")
      (assert (== metaReceipt.platform "tiktok") "platform tiktok")
      (assert (== metaReceipt.videoId "12345") "videoId 12345")
      (assert (== metaReceipt.author "@creator") "author @creator")
      (assert (= metaReceipt.likesCount 15420) "likes count 15420")
      (assert (stringContains? asn "(:mediaMetadataReceipt") "ASN format contains header")
      (refute (stringContains? asn ":platform \"youtube\"") "ASN refutes wrong platform")
      true))

fn runTests -> Bool
  (and (testActionCreationAndFormatting)
       (testMediaWatchingAction)
       (testSessionPresets)
       (testActionExecutionSimulation)
       (testAutomationReceiptSerialization)
       (testBrowserSessionHandleSerialization)
       (testTikTokMediaMetadataExtraction))
