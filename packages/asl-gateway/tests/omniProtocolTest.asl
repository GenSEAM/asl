(module asl/packages/asl-gateway/tests/omniProtocolTest
  :x [runTests]
  :i [(aslGateway/sync :a sync)
      (aslGateway/browser :a browser)
      (aslGateway/media :a media)
      (aslGateway/server :a server)])

fn testSyncOmniProtocol -> Bool
  (let [(proj (sync/ProjectSync
                :id "proj-589-test"
                :name "Omni Gateway Pipeline"
                :intentions "Universal cognitive nexus"
                :stage "building"
                :projectType "protocol"
                :generationConfig "(:cfg :mode :omni)"))
        (chan (sync/ChannelSync
                :id "chan-omni"
                :name "Omni Channel"
                :platform "youtube"
                :styleGuide "(:palette :dark)"))
        (formattedProj (sync/formatProjectSync proj))
        (formattedChan (sync/formatChannelSync chan))
        (hash1 (sync/computeContentHash "canonical test content"))
        (hash2 (sync/computeContentHash "canonical test content"))
        (hash3 (sync/computeContentHash "divergent content"))
        (reconcileSame (sync/reconcileSync hash1 hash2))
        (reconcileDiff (sync/reconcileSync hash1 hash3))]
    (do
      (assert (= proj.id "proj-589-test") "Project ID must match")
      (assert (stringContains? formattedProj ":projectSync") "Must format project S-expr")
      (assert (= chan.platform "youtube") "Channel platform must be youtube")
      (assert (stringContains? formattedChan ":channelSync") "Must format channel S-expr")
      (assert (= hash1 hash2) "Deterministic hash must match for identical content")
      (refute (= hash1 hash3) "Distinct content must produce distinct hash")
      (assert (pairFirst reconcileSame) "Same hashes must reconcile as true")
      (assert (not (pairFirst reconcileDiff)) "Diff hashes must reconcile as false")
      true))

fn testBrowserOmniProtocol -> Bool
  (let [(act (browser/BrowserActionFrame
               :actionId "act-01"
               :op "navigate"
               :selector "body"
               :payload "https://gemini.google.com"
               :timeoutMs 5000
               :requireAuth true))
        (rec (browser/createSuccessReceipt "act-01" 50 "https://gemini.google.com" "art.png" "Loaded"))
        (formattedAct (browser/formatBrowserAction act))
        (formattedRec (browser/formatBrowserReceipt rec))
        (seqRes (browser/validateActionSequence (list act)))]
    (do
      (assert (browser/validateActionOp "navigate") "navigate op must be valid")
      (assert (browser/validateActionOp "click") "click op must be valid")
      (refute (browser/validateActionOp "invalid_op") "invalid op must be refuted")
      (assert (stringContains? formattedAct ":browserAction") "Must format as browserAction")
      (assert (stringContains? formattedRec ":browserActionReceipt") "Must format as browserActionReceipt")
      (assert (pairFirst seqRes) "Valid sequence must pass validation")
      true))

fn testMediaOmniProtocol -> Bool
  (let [(req (media/MediaGenRequest
               :requestId "req-01"
               :mediaKind "image"
               :prompt "Futuristic landscape"
               :negativePrompt "grain"
               :aspectRatio "9:16"
               :durationSec 0
               :provider "imagen"))
        (rec (media/createMediaReceipt "req-01" "ok" "uri://asset" "/tmp/asset" "sha256-hash" 1080 1920 10))
        (dim (media/calculateMediaDimensions "9:16"))
        (formattedReq (media/formatMediaRequest req))
        (formattedRec (media/formatMediaReceipt rec))]
    (do
      (assert (media/validateMediaKind "image") "image kind must be valid")
      (assert (media/validateMediaKind "video") "video kind must be valid")
      (refute (media/validateMediaKind "unsupported") "unsupported media must be refuted")
      (assert (= (pairFirst dim) 1080) "9:16 width must be 1080")
      (assert (= (pairSecond dim) 1920) "9:16 height must be 1920")
      (assert (stringContains? formattedReq ":mediaRequest") "Must format as mediaRequest")
      (assert (stringContains? formattedRec ":mediaReceipt") "Must format as mediaReceipt")
      (assert (media/isMediaTerminal? rec) "ok receipt must be terminal")
      true))

fn testServerOmniDispatch -> Bool
  (let [(syncRes (server/handleSyncIngest "(:projectSync :id \"test\")"))
        (frame (browser/BrowserActionFrame :actionId "act-99" :op "click" :selector "#btn" :payload "" :timeoutMs 1000 :requireAuth false))
        (browserRec (server/handleBrowserDispatch frame))
        (mediaReq (media/MediaGenRequest :requestId "m-99" :mediaKind "video" :prompt "A video" :negativePrompt "" :aspectRatio "16:9" :durationSec 5 :provider "veo"))
        (mediaRec (server/handleMediaDispatch mediaReq))
        (cleanTurn (server/inspectCompletionTurn "Here is the result." true))
        (isEsh (server/detectEshViolation "The refactor is done and all tests pass cleanly."))]
    (do
      (assert (= (pairFirst syncRes) "ok") "Sync ingest must return ok")
      (assert (= browserRec.status "ok") "Browser dispatch must return ok")
      (assert (= mediaRec.status "ok") "Media dispatch must return ok")
      (assert (= mediaRec.width 1920) "16:9 width must be 1920")
      (assert cleanTurn.allowed "Clean conversational turn must be allowed")
      (assert isEsh "Unverified test passage claim must be detected as ESH")
      (refute (not isEsh) "ESH violation must be refuted when negated")
      true))

fn runTests -> Bool
  (and (testSyncOmniProtocol)
    (and (testBrowserOmniProtocol)
      (and (testMediaOmniProtocol)
        (testServerOmniDispatch))))
