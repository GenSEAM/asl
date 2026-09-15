(module asl-text/emojiGuard
  :d "Pure AgentScript Unicode Emoji Invariant Guard and Zero-Emoji Auditor per C2."
  :x [EmojiViolation
      EmojiScanResult
      hasRawEmoji?
      scanLineEmoji
      scanFileEmoji
      auditAsnEmojis]
  :i [(string :a s)])

(dfs EmojiViolation
  (:f file Str "Target path containing emoji violation")
  (:f lineNum I64 "1-indexed line number of violation")
  (:f text Str "Offending line content slice"))

(dfs EmojiScanResult
  (:f clean Bool "True if zero emojis detected")
  (:f violations (List EmojiViolation) "List of detected violations"))

(df hasRawEmoji? [(line Str)] -> Bool
  :d "Determines whether a line contains raw Unicode emoji bytes."
  (or (s/has? line "\xf0\x9f")
      (or (s/has? line "\xf0\x9e")
          (or (s/has? line "\xe2\x9c")
              (s/has? line "\xe2\x98")))))

(df scanLineEmoji [(file Str) (lineNum I64) (content Str)] -> (Option EmojiViolation)
  :d "Scans an individual line for raw emoji characters."
  (if (hasRawEmoji? content)
    (some (EmojiViolation :file file :lineNum lineNum :text (string-trim content)))
    (none)))

(df scanFileLinesRec [(file Str) (lines (List Str)) (idx I64) (acc (List EmojiViolation))] -> (List EmojiViolation)
  :d "Recursively scans lines maintaining 1-based source line index."
  (if (list-empty? lines)
    acc
    (let [(head (option-or (list-head lines) ""))
          (tail (option-or (list-tail lines) (list)))
          (nextAcc (if (hasRawEmoji? head)
                     (list-append acc (list (EmojiViolation :file file :lineNum idx :text (string-trim head))))
                     acc))]
      (scanFileLinesRec file tail (+ idx 1) nextAcc))))

(df scanFileEmoji [(file Str) (lines (List Str))] -> EmojiScanResult
  :d "Scans a list of lines from a file and accumulates violations."
  (let [(vList (scanFileLinesRec file lines 1 (list)))]
    (EmojiScanResult
      :clean (list-empty? vList)
      :violations vList)))

(df auditAsnEmojis [(entries (List Str))] -> Bool
  :d "Verifies zero emoji violations across a list of file contents."
  (all (fn [(content Str)] -> Bool
         (not (hasRawEmoji? content)))
       entries))
