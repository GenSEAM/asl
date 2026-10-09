(module aslGateway/tests/mediaTest
  :x (testMediaKindValidation testAspectRatioAndDimensions testMediaRequestFormatting testMediaReceiptFormatting testQuotaLedger runTests)
  :i ((media :a m)))

fn testMediaKindValidation -> Bool
  (do
    (assert (m/validateMediaKind "image") "image kind must be valid")
    (assert (m/validateMediaKind "video") "video kind must be valid")
    (assert (m/validateMediaKind "audio") "audio kind must be valid")
    (assert (m/validateMediaKind "depthMap") "depthMap kind must be valid")
    (assert (m/validateMediaKind "normalMap") "normalMap kind must be valid")
    (assert (not (m/validateMediaKind "executable")) "executable kind must be invalid")
    true)

fn testAspectRatioAndDimensions -> Bool
  (let ((dim916 (m/calculateMediaDimensions "9:16"))
        (dim169 (m/calculateMediaDimensions "16:9"))
        (dim11 (m/calculateMediaDimensions "1:1")))
    (do
      (assert (m/validateAspectRatio "9:16") "9:16 ratio must be valid")
      (assert (m/validateAspectRatio "16:9") "16:9 ratio must be valid")
      (assert (not (m/validateAspectRatio "invalid_ratio")) "invalid ratio must be false")
      (assert (= (pairFirst dim916) 1080) "9:16 width must be 1080")
      (assert (= (pairSecond dim916) 1920) "9:16 height must be 1920")
      (assert (= (pairFirst dim169) 1920) "16:9 width must be 1920")
      (assert (= (pairSecond dim169) 1080) "16:9 height must be 1080")
      (assert (= (pairFirst dim11) 1024) "1:1 width must be 1024")
      true))

fn testMediaRequestFormatting -> Bool
  (let ((req (m/MediaGenRequest
               :requestId "req-img-001"
               :mediaKind "image"
               :prompt "Cinematic hyper-realistic portrait in volumetric lighting"
               :negativePrompt "grain, blur, text, watermark"
               :aspectRatio "9:16"
               :durationSec 0
               :provider "imagen"))
        (formatted (m/formatMediaRequest req)))
    (do
      (assert (= req.requestId "req-img-001") "Request ID must match")
      (assert (= req.mediaKind "image") "Media kind must be image")
      (assert (= req.provider "imagen") "Provider must be imagen")
      (assert (stringContains? formatted ":mediaRequest") "Must format as :mediaRequest")
      (assert (stringContains? formatted "Cinematic") "Prompt must be present in formatted string")
      true))

fn testMediaReceiptFormatting -> Bool
  (let ((rec (m/createMediaReceipt
               "req-vid-002"
               "ok"
               "https://storage.provider.com/gen/video.mp4"
               "/tmp/cache/video.mp4"
               "a591a6d40bf420404a011733cfb7b190d62c65bf0bcda32b57b277d9ad9f146e"
               1080
               1920
               120))
        (formatted (m/formatMediaReceipt rec)))
    (do
      (assert (= rec.status "ok") "Receipt status must be ok")
      (assert (m/isMediaTerminal? rec) "ok status must be terminal")
      (assert (= rec.width 1080) "Width must be 1080")
      (assert (= rec.height 1920) "Height must be 1920")
      (assert (= rec.tokensUsed 120) "Tokens used must be 120")
      (assert (stringContains? formatted ":mediaReceipt") "Must format as :mediaReceipt")
      (assert (stringContains? formatted "/tmp/cache/video.mp4") "Must contain local path")
      true))

fn testQuotaLedger -> Bool
  (let ((availableLedger (m/MediaQuotaLedger :provider "veo" :dailyLimit 100 :usedCount 25 :remainingCount 75))
        (exhaustedLedger (m/MediaQuotaLedger :provider "veo" :dailyLimit 100 :usedCount 100 :remainingCount 0))
        (availCheck (m/checkQuotaAvailability availableLedger))
        (exhaustCheck (m/checkQuotaAvailability exhaustedLedger)))
    (do
      (assert (pairFirst availCheck) "Available ledger must check true")
      (assert (= (pairSecond availCheck) 75) "Remaining count must be 75")
      (assert (not (pairFirst exhaustCheck)) "Exhausted ledger must check false")
      (assert (= (pairSecond exhaustCheck) 0) "Exhausted remaining count must be 0")
      true))

fn runTests -> Bool
  (and (testMediaKindValidation)
    (and (testAspectRatioAndDimensions)
      (and (testMediaRequestFormatting)
        (and (testMediaReceiptFormatting)
          (testQuotaLedger)))))
