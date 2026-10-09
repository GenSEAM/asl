(module aslMem/telemetry :x [TelemetryRecord formatTelemetryEntry parseTelemetryEntry streamStepTelemetry] :i [(checkpoint :a cp)])

(schema TelemetryRecord (:f timestampMs I64) (:f phaseId Str) (:f tokensConsumed I64) (:f durationMs I64) (:f rssMb I64) (:f dirtyBufferCount I64))

fn formatTelemetryEntry entry: TelemetryRecord -> Str
  (let [(ts (stringFromInt64 entry.timestampMs)) (ph entry.phaseId) (tok (stringFromInt64 entry.tokensConsumed)) (dur (stringFromInt64 entry.durationMs)) (rss (stringFromInt64 entry.rssMb)) (dirty (stringFromInt64 entry.dirtyBufferCount)) (p1 (str "(:telem :ts " ts " :phase \"" ph "\" :tokens " tok)) (p2 (str " :duration " dur " :rss " rss " :dirty " dirty ")"))] (str p1 p2))

fn parseTelemetryEntry line: Str -> (Option TelemetryRecord)
  (let [(trimmed (stringTrim line))] (if (and (stringStartsWith? trimmed "(:telem") (stringEndsWith? trimmed ")")) (let [(tsStr (cp/extractBetween trimmed ":ts " " ")) (phaseStr (cp/extractBetween trimmed ":phase \"" "\"")) (tokStr (cp/extractBetween trimmed ":tokens " " ")) (durStr (cp/extractBetween trimmed ":duration " " ")) (rssStr (cp/extractBetween trimmed ":rss " " ")) (dirtyStr (cp/extractBetween trimmed ":dirty " ")"))] (mt phaseStr ((none) (none)) ((some ph) (some (TelemetryRecord :timestampMs (optionOr (stringToInt64 (stringTrim (optionOr tsStr "0"))) 0) :phaseId ph :tokensConsumed (optionOr (stringToInt64 (stringTrim (optionOr tokStr "0"))) 0) :durationMs (optionOr (stringToInt64 (stringTrim (optionOr durStr "0"))) 0) :rssMb (optionOr (stringToInt64 (stringTrim (optionOr rssStr "0"))) 0) :dirtyBufferCount (optionOr (stringToInt64 (stringTrim (optionOr dirtyStr "0"))) 0)))))) (none)))

fn streamStepTelemetry entry: TelemetryRecord streamLog: Str -> Str
  (let [(formatted (formatTelemetryEntry entry))] (if (stringEmpty? (stringTrim streamLog)) formatted (str streamLog "\n" formatted)))
