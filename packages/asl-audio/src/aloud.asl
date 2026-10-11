(module asl-audio/aloud :x [formatAloudDigest formatAuditDigestAloud formatAttentionDigestAloud isWithinEarBudget?] :i [])

fn findLastSpaceLoop s: String idx: Int64 -> Int64
  (if (<= idx 0)
    -1
    (let [(ch (stringSlice s idx (+ idx 1)))]
      (if (= (optionOr ch "") " ")
        idx
        (findLastSpaceLoop s (- idx 1)))))

fn formatAloudDigest text: String maxChars: Int64 -> String
  (let [(limit (if (<= maxChars 0) 112 maxChars))
        (len (stringLength text))]
    (if (<= len limit)
      text
      (let [(targetLen (- limit 3))
            (prefix (optionOr (stringSlice text 0 targetLen) text))
            (lastSpace (findLastSpaceLoop prefix (- targetLen 1)))]
        (let [(cutIdx (if (> lastSpace (/ targetLen 2)) lastSpace targetLen))]
          (let [(cleanPrefix (optionOr (stringSlice prefix 0 cutIdx) prefix))]
            (str cleanPrefix "..."))))))

fn formatAuditDigestAloud passed: Int64 failed: Int64 mutantsKilled: Int64 -> String
  (let [(pStr (stringFromInt64 passed))
        (fStr (stringFromInt64 failed))
        (mStr (stringFromInt64 mutantsKilled))]
    (let [(raw (if (= failed 0)
                 (str "Аудит пройден: " pStr " гейтов зеленые, " mStr " мутантов убито.")
                 (str "Аудит провален: " fStr " гейтов красные, " pStr " зеленые.")))]
      (formatAloudDigest raw 112)))

fn formatAttentionDigestAloud actionName: String targetSymbol: String -> String
  (let [(raw (str "Применить " actionName " для " targetSymbol "?"))]
    (formatAloudDigest raw 48))

fn isWithinEarBudget? text: String maxChars: Int64 -> Bool
  (let [(limit (if (<= maxChars 0) 112 maxChars))
        (len (stringLength text))]
    (<= len limit))
