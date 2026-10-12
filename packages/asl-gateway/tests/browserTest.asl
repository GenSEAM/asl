(module aslGateway/tests/browserTest
  :x [testActionOps testBrowserActionFormatting testBrowserReceiptFormatting testSuccessAndErrorReceipts testSequenceValidation runTests]
  :i [(browser :a b)])

fn testActionOps -> Bool
  (do
    (assert (b/validateActionOp "navigate") "navigate op must be valid")
    (assert (b/validateActionOp "click") "click op must be valid")
    (assert (b/validateActionOp "fill") "fill op must be valid")
    (assert (b/validateActionOp "wait") "wait op must be valid")
    (assert (b/validateActionOp "screenshot") "screenshot op must be valid")
    (assert (b/validateActionOp "download") "download op must be valid")
    (assert (b/validateActionOp "eval") "eval op must be valid")
    (assert (not (b/validateActionOp "arbitrary_command")) "arbitrary command must be invalid")
    true)

fn testBrowserActionFormatting -> Bool
  (let [(frame (b/BrowserActionFrame
                 :actionId "act-001"
                 :op "navigate"
                 :selector "none"
                 :payload "https://gemini.google.com"
                 :timeoutMs 5000
                 :requireAuth true))
        (formatted (b/formatBrowserAction frame))]
    (do
      (assert (= frame.actionId "act-001") "Action ID must match")
      (assert (= frame.op "navigate") "Op must be navigate")
      (assert frame.requireAuth "Require auth must be true")
      (assert (stringContains? formatted ":browserAction") "Must format as :browserAction")
      (assert (stringContains? formatted "https://gemini.google.com") "Formatted text must contain URL")
      true))

fn testBrowserReceiptFormatting -> Bool
  (let [(rec (b/BrowserActionReceipt
               :actionId "act-002"
               :status "ok"
               :durationMs 240
               :pageUrl "https://gemini.google.com/app"
               :artifactPath "artifacts/screen.png"
               :capturedText "Hello World"))
        (formatted (b/formatBrowserReceipt rec))]
    (do
      (assert (= rec.status "ok") "Status must be ok")
      (assert (= rec.durationMs 240) "Duration must match")
      (assert (b/isActionTerminal? rec) "ok status must be terminal")
      (assert (stringContains? formatted ":browserActionReceipt") "Must format as :browserActionReceipt")
      (assert (stringContains? formatted "artifacts/screen.png") "Must contain artifact path")
      true))

fn testSuccessAndErrorReceipts -> Bool
  (let [(sRec (b/createSuccessReceipt "act-10" 120 "https://target.url" "shot.png" "DOM Title"))
        (eRec (b/createErrorReceipt "act-11" 5000 "timeout" "Page navigation timed out"))]
    (do
      (assert (= sRec.status "ok") "Success receipt status must be ok")
      (assert (= sRec.artifactPath "shot.png") "Artifact path must match")
      (assert (= eRec.status "timeout") "Error receipt status must be timeout")
      (assert (b/isActionTerminal? eRec) "Timeout status must be terminal")
      (assert (= eRec.pageUrl "") "Error pageUrl must be empty")
      true))

fn testSequenceValidation -> Bool
  (let [(f1 (b/BrowserActionFrame :actionId "1" :op "navigate" :selector "" :payload "https://test.com" :timeoutMs 3000 :requireAuth false))
        (f2 (b/BrowserActionFrame :actionId "2" :op "click" :selector "#login-btn" :payload "" :timeoutMs 2000 :requireAuth true))
        (fBad (b/BrowserActionFrame :actionId "3" :op "invalid_cmd" :selector "" :payload "" :timeoutMs 1000 :requireAuth false))
        (validSeq (list f1 f2))
        (invalidSeq (list f1 fBad))
        (resValid (b/validateActionSequence validSeq))
        (resInvalid (b/validateActionSequence invalidSeq))
        (resEmpty (b/validateActionSequence (list)))]
    (do
      (assert (pairFirst resValid) "Valid sequence must validate to true")
      (assert (= (pairSecond resValid) "all_valid") "Reason must be all_valid")
      (assert (not (pairFirst resInvalid)) "Invalid sequence must validate to false")
      (assert (stringContains? (pairSecond resInvalid) "invalid_op") "Reason must identify invalid op")
      (assert (not (pairFirst resEmpty)) "Empty sequence must validate to false")
      true))

fn runTests -> Bool
  (and (testActionOps)
    (and (testBrowserActionFormatting)
      (and (testBrowserReceiptFormatting)
        (and (testSuccessAndErrorReceipts)
          (testSequenceValidation)))))
