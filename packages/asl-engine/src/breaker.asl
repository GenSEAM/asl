(module asl-engine/breaker
  :x [BreakerVerdict parseTimestamps formatTimestamps filterRecent
      formatBreakerTrippedMessage evaluateBreaker checkBreakerFile!]
  :i [])

(schema BreakerVerdict
  (:f tripped Bool)
  (:f count Int64)
  (:f message String)
  (:f markerContent String))

fn parseTimestamps text: String -> (List Int64)
  (let [(lines (stringSplit text "\n"))]
    (fold (fn [(acc (List Int64)) (line String)] -> (List Int64)
            (let [(trimmed (stringTrim line))]
              (if (stringEmpty? trimmed)
                acc
                (mt (stringToInt64 trimmed)
                  ((some ts) (cons ts acc))
                  ((none) acc)))))
          (list)
          lines))

fn formatTimestamps timestamps: (List Int64) -> String
  (let [(strs (map (fn [(ts Int64)] -> String (stringFromInt64 ts)) timestamps))]
    (stringJoin strs "\n"))

fn filterRecent timestamps: (List Int64) nowSec: Int64 -> (List Int64)
  (filter (fn [(ts Int64)] -> Bool
            (and (> ts 0) (<= (- nowSec ts) 30)))
          timestamps)

fn formatBreakerTrippedMessage count: Int64 logPath: String -> String
  (str "=== [ASL ENGINE CIRCUIT BREAKER TRIPPED] ===\n"
       "Engine has restarted " (stringFromInt64 count) " times within the last 30 seconds.\n"
       "Halting automatic restart loop to prevent flapping / restart storm.\n"
       "Use 'asl engine restart --force' to override or inspect logs at " logPath ".")

fn evaluateBreaker markerText: String nowSec: Int64 force: Bool logPath: String -> BreakerVerdict
  (if force
    (BreakerVerdict :tripped false :count 0 :message "" :markerContent "")
    (let [(tsList (parseTimestamps markerText))
          (recent (filterRecent tsList nowSec))
          (count (listLength recent))]
      (if (>= count 3)
        (BreakerVerdict :tripped true :count count :message (formatBreakerTrippedMessage count logPath) :markerContent markerText)
        (let [(updated (cons nowSec recent))
              (newText (formatTimestamps (listReverse updated)))]
          (BreakerVerdict :tripped false :count (+ count 1) :message "" :markerContent newText)))))

fn checkBreakerFile! socketPath: String force: Bool logPath: String -> (Result BreakerVerdict String)
  (let [(markerPath (str socketPath ".flapping"))]
    (if force
      (do
        (pathRemove markerPath)
        (ok (BreakerVerdict :tripped false :count 0 :message "" :markerContent "")))
      (let [(content (resultOr (fileReadString markerPath) ""))
            (nowSec (/ (nowNs) 1000000000))
            (verdict (evaluateBreaker content nowSec false logPath))]
        (if verdict.tripped
          (err verdict.message)
          (do
            (fileWrite markerPath verdict.markerContent)
            (ok verdict))))))
