(module asl/packages/asl-gateway/tests/omniDispatchNotSupportedTest
  :x [runTests]
  :i [(aslGateway/browser :a browser)
      (aslGateway/media :a media)
      (aslGateway/server :a server)])

fn testBrowserDispatchNotSupported -> Bool
  (let [(frame (browser/BrowserActionFrame :actionId "act-ns" :op "navigate" :selector "body" :payload "https://example.com" :timeoutMs 5000 :requireAuth false))
        (rec (server/handleBrowserDispatch frame))
        (formatted (browser/formatBrowserReceipt rec))]
    (do
      (assert (= rec.status "not_supported") "Browser dispatch status must be not_supported")
      (assert (= rec.capturedText "Browser dispatch not supported") "Browser dispatch must have explicit text")
      (assert (= rec.durationMs 0) "Browser dispatch duration must be 0")
      (assert (= rec.pageUrl "") "Browser dispatch pageUrl must be empty")
      (refute (stringContains? formatted "gateway.local") "No canned gateway.local in browser receipt")
      (refute (stringContains? formatted "45") "No canned 45 in browser receipt")
      true))

fn testMediaDispatchNotSupported -> Bool
  (let [(req (media/MediaGenRequest :requestId "m-ns" :mediaKind "image" :prompt "test" :negativePrompt "" :aspectRatio "1:1" :durationSec 0 :provider "test"))
        (rec (server/handleMediaDispatch req))
        (formatted (media/formatMediaReceipt rec))]
    (do
      (assert (= rec.status "not_supported") "Media dispatch status must be not_supported")
      (assert (= rec.remoteUrl "") "Media dispatch remoteUrl must be empty")
      (assert (= rec.localPath "") "Media dispatch localPath must be empty")
      (assert (= rec.sha256 "") "Media dispatch sha256 must be empty")
      (assert (= rec.width 0) "Media dispatch width must be 0")
      (assert (= rec.height 0) "Media dispatch height must be 0")
      (assert (= rec.tokensUsed 0) "Media dispatch tokensUsed must be 0")
      (refute (stringContains? formatted "storage://generated/asset") "No canned storage URL in media receipt")
      (refute (stringContains? formatted "/tmp/asset") "No canned /tmp/asset in media receipt")
      (refute (stringContains? formatted "hash123") "No canned hash123 in media receipt")
      true))

fn runTests -> Bool
  (and (testBrowserDispatchNotSupported)
    (testMediaDispatchNotSupported))
