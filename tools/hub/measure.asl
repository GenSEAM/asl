(module asl-tools/hub/measure
  :x [rowAt rowOutcome tally measureText fetchStatus! main]
  :i [])

; (:m :ref ORCH-NODE2-CUTOVER-PREP :do "reads the whole gateway call ledger (it rotates at 10 MiB; default HOME/.asl/run/usage/gatewayCalls.asn) for the last N minutes and prints one (:hubMeasure ...) form: callsPerMin, real429Share (outcome 429), ownThrottleShare (outcome throttled); the ledger rows carry no queue wait, so admitWait is absent; the lead compares a window before the hub cutover with a window after it")
fn numAfter text: String marker: String -> Int64
  (match (stringIndexOf text marker)
    ((none) -1)
    ((some at)
      (let [(rest (optionOr (stringSlice text (+ at (stringLength marker)) (stringLength text)) ""))]
        (optionOr (stringToInt64 (optionOr (listHead (stringSplit rest " ")) "")) -1))))

fn rowAt line: String -> Int64
  (if (stringStartsWith? line "(:call :at ") (numAfter line ":at ") -1)

fn rowOutcome line: String -> String
  (match (stringIndexOf line ":outcome \"")
    ((none) "")
    ((some at)
      (let [(rest (optionOr (stringSlice line (+ at 10) (stringLength line)) ""))]
        (optionOr (listHead (stringSplit rest "\"")) ""))))

(schema Tally
  (:f calls Int64)
  (:f ok Int64)
  (:f real429 Int64)
  (:f throttled Int64))

fn tally text: String fromMs: Int64 toMs: Int64 -> Tally
  (fold (fn [(t Tally) (line String)] -> Tally
          (let [(at (rowAt line))]
            (if (or (< at fromMs) (> at toMs)) t
              (let [(o (rowOutcome line))]
                (Tally :calls (+ t.calls 1) :ok (+ t.ok (if (= o "ok") 1 0))
                  :real429 (+ t.real429 (if (= o "429") 1 0)) :throttled (+ t.throttled (if (= o "throttled") 1 0)))))))
    (Tally :calls 0 :ok 0 :real429 0 :throttled 0) (stringSplit text "\n"))

fn share n: Int64 d: Int64 -> Float64
  (if (<= d 0) 0.0 (/ (int64ToFloat64 n) (int64ToFloat64 d)))

fn measureText text: String nowMs: Int64 windowMin: Int64 -> String
  (let [(t (tally text (- nowMs (* windowMin 60000)) nowMs))]
    (str "(:hubMeasure :windowMin " (stringFromInt64 windowMin) " :calls " (stringFromInt64 t.calls) " :ok " (stringFromInt64 t.ok)
         " :real429 " (stringFromInt64 t.real429) " :throttled " (stringFromInt64 t.throttled)
         " :callsPerMin " (stringFromFloat64 (share t.calls windowMin))
         " :real429Share " (stringFromFloat64 (share t.real429 t.calls))
         " :ownThrottleShare " (stringFromFloat64 (share t.throttled t.calls))
         " :admitWait absent)"))

fn flagAfter args: (List String) flag: String fallback: String -> String
  (match (listIndexOf args flag)
    ((none) fallback)
    ((some i) (optionOr (listGet args (+ i 1)) fallback)))

fn ! readAll! fd: Int64 acc: String -> String
  (match (fdRead fd 65536)
    ((err _) acc)
    ((ok chunk) (if (stringEmpty? chunk) acc (readAll! fd (str acc chunk)))))

; (:m :ref ORCH-HUB-STATUS :do "GET /hub/status over the hub's unix socket; the reply body is the (:hub ...) form, the HTTP head is dropped")
fn ! fetchStatus! sock: String -> (Result String String)
  (match (unixConnect sock)
    ((err e) (err e))
    ((ok fd)
      (match (fdWrite fd "GET /hub/status HTTP/1.1\r\nHost: hub\r\nConnection: close\r\n\r\n")
        ((err e) (do (fdClose fd) (err e)))
        ((ok _)
          (let [(raw (readAll! fd ""))
                (closed (fdClose fd))]
            (match (stringIndexOf raw "\r\n\r\n")
              ((none) (err "ERR_HUB_STATUS_NO_BODY"))
              ((some end) (ok (stringTrim (optionOr (stringSlice raw (+ end 4) (stringLength raw)) ""))))))))))

fn ! main args: (List String) -> (Result Int64 String)
  (let [(home (optionOr (envGet "HOME") ""))
        (path (flagAfter args "--ledger" (str home "/.asl/run/usage/gatewayCalls.asn")))
        (windowMin (optionOr (stringToInt64 (flagAfter args "--window-min" "120")) 120))
        (nowMs (optionOr (stringToInt64 (flagAfter args "--now" "")) (/ (nowNs) 1000000)))]
    (match (fileReadString path)
      ((err e) (err (str "ERR_HUB_MEASURE_LEDGER: " e)))
      ((ok text) (do (println (measureText text nowMs windowMin)) (ok 0)))))
