(module aslGateway/media
  :x (MediaGenRequest MediaGenReceipt MediaQuotaLedger validateMediaKind validateAspectRatio calculateMediaDimensions formatMediaRequest formatMediaReceipt createMediaReceipt isMediaTerminal? checkQuotaAvailability)
  :i ())

(schema MediaGenRequest
  (:f requestId Str)
  (:f mediaKind Str)
  (:f prompt Str)
  (:f negativePrompt Str)
  (:f aspectRatio Str)
  (:f durationSec I64)
  (:f provider Str))

(schema MediaGenReceipt
  (:f requestId Str)
  (:f status Str)
  (:f remoteUrl Str)
  (:f localPath Str)
  (:f sha256 Str)
  (:f width I64)
  (:f height I64)
  (:f tokensUsed I64))

(schema MediaQuotaLedger
  (:f provider Str)
  (:f dailyLimit I64)
  (:f usedCount I64)
  (:f remainingCount I64))

fn validateMediaKind kind: Str -> Bool
  (or (= kind "image")
    (or (= kind "video")
      (or (= kind "audio")
        (or (= kind "depthMap")
          (= kind "normalMap")))))

fn validateAspectRatio ratio: Str -> Bool
  (or (= ratio "9:16")
    (or (= ratio "16:9")
      (or (= ratio "1:1")
        (or (= ratio "4:5")
          (= ratio "21:9")))))

fn calculateMediaDimensions ratio: Str -> (Pair I64 I64)
  (if (= ratio "9:16")
    (pair 1080 1920)
    (if (= ratio "16:9")
      (pair 1920 1080)
      (if (= ratio "1:1")
        (pair 1024 1024)
        (if (= ratio "4:5")
          (pair 1080 1350)
          (if (= ratio "21:9")
            (pair 2560 1080)
            (pair 1080 1920))))))

fn formatMediaRequest req: MediaGenRequest -> Str
  (str "(:mediaRequest :id \"" req.requestId "\" :kind \"" req.mediaKind "\" :ratio \"" req.aspectRatio "\" :dur " req.durationSec " :provider \"" req.provider "\" :prompt \"" req.prompt "\")")

fn formatMediaReceipt rec: MediaGenReceipt -> Str
  (str "(:mediaReceipt :id \"" rec.requestId "\" :status :" rec.status " :url \"" rec.remoteUrl "\" :path \"" rec.localPath "\" :sha256 \"" rec.sha256 "\" :w " rec.width " :h " rec.height " :tokens " rec.tokensUsed ")")

fn createMediaReceipt reqId: Str status: Str url: Str local: Str hash: Str w: I64 h: I64 tokens: I64 -> MediaGenReceipt
  (MediaGenReceipt
    :requestId reqId
    :status status
    :remoteUrl url
    :localPath local
    :sha256 hash
    :width w
    :height h
    :tokensUsed tokens)

fn isMediaTerminal? rec: MediaGenReceipt -> Bool
  (or (= rec.status "ok")
    (or (= rec.status "rejected")
      (or (= rec.status "quota_exceeded")
        (= rec.status "error"))))

fn checkQuotaAvailability ledger: MediaQuotaLedger -> (Pair Bool I64)
  (let [(rem ledger.remainingCount)]
    (if (> rem 0)
      (pair true rem)
      (pair false 0)))
