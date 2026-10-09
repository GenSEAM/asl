(module aslVoice/aloud :x [AloudConfig AloudSpeechResult makeAloudConfig stripVisualChrome expandSpokenDurations sanitizeChipForEar formatForEar] :i [(asl-text/string :a s)])

(schema AloudConfig (:f maxSeconds I64) (:f charsPerSecond I64) (:f maxChars I64))

(schema AloudSpeechResult (:f spokenText Str) (:f charCount I64) (:f estimatedDurationSeconds F64) (:f isTruncated Bool))

fn makeAloudConfig maxSec: I64 rateCps: I64 -> AloudConfig
  (AloudConfig :maxSeconds maxSec :charsPerSecond rateCps :maxChars (* maxSec rateCps))

fn stripVisualChrome text: Str -> Str
  (let [(c1 (stringReplace text "**" "")) (c2 (stringReplace c1 "*" "")) (c3 (stringReplace c2 "`" "")) (c4 (stringReplace c3 "#" "")) (c5 (stringReplace c4 "[" "")) (c6 (stringReplace c5 "]" "")) (c7 (stringReplace c6 "{" "")) (c8 (stringReplace c7 "}" "")) (c9 (stringReplace c8 " - " " -- ")) (c10 (stringReplace c9 "[OK]" "")) (c11 (stringReplace c10 ">" "")) (c12 (stringReplace c11 "<" ""))] (stringTrim c12))

fn expandSpokenDurations text: Str -> Str
  (let [(t1 (stringReplace text " 1m" " 1 minute")) (t2 (stringReplace t1 " 2m" " 2 minutes")) (t3 (stringReplace t2 " 3m" " 3 minutes")) (t4 (stringReplace t3 " 5m" " 5 minutes")) (t5 (stringReplace t4 " 10m" " 10 minutes")) (t6 (stringReplace t5 " 15m" " 15 minutes")) (t7 (stringReplace t6 " 30m" " 30 minutes")) (t8 (stringReplace t7 " 45m" " 45 minutes")) (t9 (stringReplace t8 " 1h" " 1 hour")) (t10 (stringReplace t9 " 2h" " 2 hours")) (t11 (stringReplace t10 " 1s" " 1 second")) (t12 (stringReplace t11 " 2s" " 2 seconds")) (t13 (stringReplace t12 " 5s" " 5 seconds")) (t14 (stringReplace t13 " 10s" " 10 seconds")) (t15 (stringReplace t14 " 30s" " 30 seconds"))] t15)

fn sanitizeChipForEar chip: Str -> Str
  (let [(c1 (stringReplace chip "." " ")) (c2 (stringReplace c1 "/" " ")) (c3 (stringReplace c2 "_" " ")) (c4 (stringReplace c3 "-" " "))] (stringTrim c4))

fn formatForEar rawResponse: Str cfg: AloudConfig -> AloudSpeechResult
  (let [(stripped (stripVisualChrome rawResponse)) (expanded (expandSpokenDurations stripped)) (budget cfg.maxChars) (len (stringLength expanded))] (if (<= len budget) (AloudSpeechResult :spokenText expanded :charCount len :estimatedDurationSeconds (/ (int64ToFloat64 len) (int64ToFloat64 cfg.charsPerSecond)) :isTruncated false) (let [(clipped (stringSlice expanded 0 (- budget 1))) (finalText (str clipped "...")) (finalLen (stringLength finalText))] (AloudSpeechResult :spokenText finalText :charCount finalLen :estimatedDurationSeconds (/ (int64ToFloat64 finalLen) (int64ToFloat64 cfg.charsPerSecond)) :isTruncated true))))
