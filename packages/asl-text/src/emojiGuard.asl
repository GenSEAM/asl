(module asl-text/emojiGuard
  :x [EmojiViolation EmojiScanResult hasRawEmoji? scanLineEmoji scanFileEmoji auditAsnEmojis]
  :i [(string :a s)])

(schema EmojiViolation
  (:f file Str)
  (:f lineNum Int64)
  (:f text Str))

(schema EmojiScanResult
  (:f clean Bool)
  (:f violations (List EmojiViolation)))

fn hasRawEmoji? line: Str -> Bool
  (or (stringContains? line "\xf0\x9f")
      (or (stringContains? line "\xf0\x9e")
          (or (stringContains? line "\xe2\x9c")
              (stringContains? line "\xe2\x98"))))

fn scanLineEmoji file: Str lineNum: Int64 content: Str -> (Option EmojiViolation)
  (if (hasRawEmoji? content)
    (some (EmojiViolation :file file :lineNum lineNum :text (stringTrim content)))
    (none))

fn scanFileLinesRec file: Str lines: (List Str) idx: Int64 acc: (List EmojiViolation) -> (List EmojiViolation)
  (if (listEmpty? lines)
    acc
    (let [(head (optionOr (listHead lines) ""))
          (tail (optionOr (listTail lines) (list)))
          (nextAcc (if (hasRawEmoji? head)
                     (listAppend acc (list (EmojiViolation :file file :lineNum idx :text (stringTrim head))))
                     acc))]
      (scanFileLinesRec file tail (+ idx 1) nextAcc)))

fn scanFileEmoji file: Str lines: (List Str) -> EmojiScanResult
  (let [(vList (scanFileLinesRec file lines 1 (list)))]
    (EmojiScanResult :clean (listEmpty? vList) :violations vList))

fn auditAsnEmojis entries: (List Str) -> Bool
  (listAll? (fn [(content Str)] -> Bool (not (hasRawEmoji? content))) entries)
