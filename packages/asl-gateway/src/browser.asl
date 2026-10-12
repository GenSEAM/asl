(module aslGateway/browser
  :x (BrowserActionFrame BrowserActionReceipt BrowserSessionConfig validateActionOp formatBrowserAction formatBrowserReceipt createSuccessReceipt createErrorReceipt isActionTerminal? validateActionSequence)
  :i ())

(schema BrowserActionFrame
  (:f actionId Str)
  (:f op Str)
  (:f selector Str)
  (:f payload Str)
  (:f timeoutMs I64)
  (:f requireAuth Bool))

(schema BrowserActionReceipt
  (:f actionId Str)
  (:f status Str)
  (:f durationMs I64)
  (:f pageUrl Str)
  (:f artifactPath Str)
  (:f capturedText Str))

(schema BrowserSessionConfig
  (:f sessionId Str)
  (:f headless Bool)
  (:f viewportWidth I64)
  (:f viewportHeight I64)
  (:f userAgent Str))

fn validateActionOp op: Str -> Bool
  (or (= op "navigate")
    (or (= op "click")
      (or (= op "fill")
        (or (= op "wait")
          (or (= op "screenshot")
            (or (= op "download")
              (= op "eval")))))))

fn formatBrowserAction frame: BrowserActionFrame -> Str
  (str "(:browserAction :id \"" frame.actionId "\" :op \"" frame.op "\" :selector \"" frame.selector "\" :payload \"" frame.payload "\" :timeout " frame.timeoutMs " :requireAuth " (if frame.requireAuth "true" "false") ")")

fn formatBrowserReceipt receipt: BrowserActionReceipt -> Str
  (str "(:browserActionReceipt :id \"" receipt.actionId "\" :status :" receipt.status " :duration " receipt.durationMs " :url \"" receipt.pageUrl "\" :artifact \"" receipt.artifactPath "\" :text \"" receipt.capturedText "\")")

fn createSuccessReceipt actionId: Str durationMs: I64 pageUrl: Str artifactPath: Str capturedText: Str -> BrowserActionReceipt
  (BrowserActionReceipt
    :actionId actionId
    :status "ok"
    :durationMs durationMs
    :pageUrl pageUrl
    :artifactPath artifactPath
    :capturedText capturedText)

fn createErrorReceipt actionId: Str durationMs: I64 errStatus: Str capturedText: Str -> BrowserActionReceipt
  (BrowserActionReceipt
    :actionId actionId
    :status errStatus
    :durationMs durationMs
    :pageUrl ""
    :artifactPath ""
    :capturedText capturedText)

fn isActionTerminal? receipt: BrowserActionReceipt -> Bool
  (or (= receipt.status "ok")
    (or (= receipt.status "timeout")
      (or (= receipt.status "auth_expired")
        (= receipt.status "error"))))

fn validateLoop frames: (List BrowserActionFrame) idx: I64 -> (Pair Bool Str)
  (if (>= idx (listLength frames))
    (pair true "all_valid")
    (let [(frame (optionOr (listGet frames idx) (BrowserActionFrame :actionId "" :op "" :selector "" :payload "" :timeoutMs 0 :requireAuth false)))]
      (if (not (validateActionOp frame.op))
        (pair false (str "invalid_op: " frame.op))
        (validateLoop frames (+ idx 1)))))

fn validateActionSequence frames: (List BrowserActionFrame) -> (Pair Bool Str)
  (if (= (listLength frames) 0)
    (pair false "empty_sequence")
    (validateLoop frames 0))
