(module asl-text/emoji-guard
  :d "Pure AgentScript Unicode Emoji Invariant Guard and Zero-Emoji Auditor per C2."
  :x [EmojiViolation
      EmojiScanResult
      has-raw-emoji?
      scan-line-emoji
      scan-file-emoji
      audit-asn-emojis]
  :i [(string :a s)])

(dfs EmojiViolation
  (:f file Str "Target path containing emoji violation")
  (:f line-num I64 "1-indexed line number of violation")
  (:f text Str "Offending line content slice"))

(dfs EmojiScanResult
  (:f clean Bool "True if zero emojis detected")
  (:f violations (List EmojiViolation) "List of detected violations"))

(df has-raw-emoji? [(line Str)] -> Bool
  :d "Determines whether a line contains raw Unicode emoji bytes."
  (or (s/has? line "\xf0\x9f")
      (or (s/has? line "\xf0\x9e")
          (or (s/has? line "\xe2\x9c")
              (s/has? line "\xe2\x98")))))

(df scan-line-emoji [(file Str) (line-num I64) (content Str)] -> (Option EmojiViolation)
  :d "Scans an individual line for raw emoji characters."
  (if (has-raw-emoji? content)
    (some (EmojiViolation :file file :line-num line-num :text (string-trim content)))
    (none)))

(df scan-file-emoji [(file Str) (lines (List Str))] -> EmojiScanResult
  :d "Scans a list of lines from a file and accumulates violations."
  (let [(v-list (fold (fn [(acc (List EmojiViolation)) (item Str)] -> (List EmojiViolation)
                        (let [(idx (+ (list-length acc) 1))]
                          (if (has-raw-emoji? item)
                            (list-append acc (list (EmojiViolation :file file :line-num idx :text (string-trim item))))
                            acc)))
                      (list)
                      lines))]
    (EmojiScanResult
      :clean (list-empty? v-list)
      :violations v-list)))

(df audit-asn-emojis [(entries (List Str))] -> Bool
  :d "Verifies zero emoji violations across a list of file contents."
  (all (fn [(content Str)] -> Bool
         (not (has-raw-emoji? content)))
       entries))
