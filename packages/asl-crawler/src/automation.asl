(module aslCrawler/automation
  :x [AutomationAction AutomationReceipt MediaMetadataReceipt makeClickAction makeTypeAction makeScrollAction makeNavigateAction makeWatchMediaAction makeTikTokExtractAction formatActionAsn makeAutomationReceipt makeFailedReceipt makeMediaMetadataReceipt formatReceiptAsn formatMediaMetadataAsn simulateActionExecution isValidActionOp?]
  :i [(asl-text/escape :a esc)])

(schema AutomationAction
  (:f op Str)
  (:f target Str)
  (:f value Str)
  (:f kinetic Bool)
  (:f direction Str)
  (:f pixels I64)
  (:f durationSec I64)
  (:f extractMetadata Bool)
  (:f timeoutMs I64))

(schema AutomationReceipt
  (:f actionId Str)
  (:f status Str)
  (:f durationMs I64)
  (:f currentUrl Str)
  (:f snapshot Str)
  (:f errorReason Str))

(schema MediaMetadataReceipt
  (:f receiptId Str)
  (:f platform Str)
  (:f videoId Str)
  (:f author Str)
  (:f caption Str)
  (:f likesCount I64)
  (:f commentsCount I64)
  (:f soundTitle Str))

fn makeClickAction target: Str kinetic: Bool -> AutomationAction
  (AutomationAction
    :op "click"
    :target target
    :value ""
    :kinetic kinetic
    :direction ""
    :pixels 0
    :durationSec 0
    :extractMetadata false
    :timeoutMs 3500)

fn makeTypeAction target: Str text: Str minDelayMs: I64 maxDelayMs: I64 -> AutomationAction
  (AutomationAction
    :op "type"
    :target target
    :value text
    :kinetic true
    :direction ""
    :pixels 0
    :durationSec 0
    :extractMetadata false
    :timeoutMs 5000)

fn makeScrollAction direction: Str pixels: I64 inertia: Bool -> AutomationAction
  (AutomationAction
    :op "scroll"
    :target "window"
    :value ""
    :kinetic inertia
    :direction direction
    :pixels pixels
    :durationSec 0
    :extractMetadata false
    :timeoutMs 3000)

fn makeNavigateAction url: Str -> AutomationAction
  (AutomationAction
    :op "navigate"
    :target url
    :value ""
    :kinetic false
    :direction ""
    :pixels 0
    :durationSec 0
    :extractMetadata false
    :timeoutMs 10000)

fn makeWatchMediaAction target: Str durationSec: I64 extractMeta: Bool -> AutomationAction
  (AutomationAction
    :op "watchMedia"
    :target target
    :value ""
    :kinetic false
    :direction ""
    :pixels 0
    :durationSec durationSec
    :extractMetadata extractMeta
    :timeoutMs (+ (* durationSec 1000) 5000))

fn makeTikTokExtractAction url: Str -> AutomationAction
  (AutomationAction
    :op "extractMedia"
    :target url
    :value ""
    :kinetic false
    :direction ""
    :pixels 0
    :durationSec 0
    :extractMetadata true
    :timeoutMs 10000)

fn formatActionAsn action: AutomationAction -> Str
  (str "(:action"
       " :op :" action.op
       " :target \"" (esc/escapeAsnStr action.target) "\""
       (if (> (stringLength action.value) 0) (str " :value \"" (esc/escapeAsnStr action.value) "\"") "")
       (if action.kinetic " :kinetic true" "")
       (if (> (stringLength action.direction) 0) (str " :direction :" action.direction) "")
       (if (> action.pixels 0) (str " :pixels " (stringFromInt64 action.pixels)) "")
       (if (> action.durationSec 0) (str " :duration " (stringFromInt64 action.durationSec)) "")
       (if action.extractMetadata " :extractMetadata true" "")
       " :timeoutMs " (stringFromInt64 action.timeoutMs)
       ")")

fn makeAutomationReceipt id: Str status: Str durationMs: I64 currentUrl: Str snapshot: Str err: Str -> AutomationReceipt
  (AutomationReceipt
    :actionId id
    :status status
    :durationMs durationMs
    :currentUrl currentUrl
    :snapshot snapshot
    :errorReason err)

fn makeFailedReceipt id: Str status: Str err: Str -> AutomationReceipt
  (AutomationReceipt
    :actionId id
    :status "failed"
    :durationMs 0
    :currentUrl ""
    :snapshot ""
    :errorReason err)

fn formatReceiptAsn receipt: AutomationReceipt -> Str
  (str "(:automationReceipt"
       " :id \"" (esc/escapeAsnStr receipt.actionId) "\""
       " :status :" receipt.status
       " :duration " (stringFromInt64 receipt.durationMs)
       (if (> (stringLength receipt.currentUrl) 0) (str " :url \"" (esc/escapeAsnStr receipt.currentUrl) "\"") "")
       (if (> (stringLength receipt.snapshot) 0) (str " :snapshot " receipt.snapshot) "")
       (if (> (stringLength receipt.errorReason) 0) (str " :error \"" (esc/escapeAsnStr receipt.errorReason) "\"") "")
       ")")

fn makeMediaMetadataReceipt id: Str platform: Str videoId: Str author: Str caption: Str likesCount: I64 commentsCount: I64 soundTitle: Str -> MediaMetadataReceipt
  (MediaMetadataReceipt
    :receiptId id
    :platform platform
    :videoId videoId
    :author author
    :caption caption
    :likesCount likesCount
    :commentsCount commentsCount
    :soundTitle soundTitle)

fn formatMediaMetadataAsn receipt: MediaMetadataReceipt -> Str
  (str "(:mediaMetadataReceipt"
       " :id \"" (esc/escapeAsnStr receipt.receiptId) "\""
       " :platform :" receipt.platform
       " :videoId \"" (esc/escapeAsnStr receipt.videoId) "\""
       " :author \"" (esc/escapeAsnStr receipt.author) "\""
       (if (> (stringLength receipt.caption) 0) (str " :caption \"" (esc/escapeAsnStr receipt.caption) "\"") "")
       " :likesCount " (stringFromInt64 receipt.likesCount)
       " :commentsCount " (stringFromInt64 receipt.commentsCount)
       (if (> (stringLength receipt.soundTitle) 0) (str " :soundTitle \"" (esc/escapeAsnStr receipt.soundTitle) "\"") "")
       ")")

fn isValidActionOp? op: Str -> Bool
  (let [(clean (stringLower (stringTrim op)))]
    (or (== clean "navigate")
      (or (== clean "click")
        (or (== clean "type")
          (or (== clean "scroll")
            (or (== clean "watchmedia")
              (or (== clean "extractmedia")
                (or (== clean "wait")
                  (or (== clean "snapshot")
                    (== clean "execasl"))))))))))

fn simulateActionExecution action: AutomationAction -> AutomationReceipt
  (let [(op action.op)]
    (cond
      ((== op "navigate")
        (makeAutomationReceipt
          "act-sim-001"
          "ok"
          65
          action.target
          (str "(:pageSnapshot :url \"" (esc/escapeAsnStr action.target) "\" :title \"Simulated Page\" :status :ok)")
          ""))
      ((== op "watchMedia")
        (makeAutomationReceipt
          "act-sim-002"
          "ok"
          (* action.durationSec 1000)
          "https://www.tiktok.com/@creator"
          "(:mediaSnapshot :mediaType :video :observedSeconds 15 :status :completed)"
          ""))
      (else
        (makeAutomationReceipt
          "act-sim-003"
          "ok"
          35
          "https://example.com"
          "(:pageSnapshot :status :ok)"
          ""))))
