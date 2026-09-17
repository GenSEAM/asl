(module asl-text/emojiGuard :doc "Pure AgentScript Unicode Emoji Invariant Guard and Zero-Emoji Auditor per C2." :export [EmojiViolation EmojiScanResult hasRawEmoji? scanLineEmoji scanFileEmoji auditAsnEmojis] :i [(string :a s)])

schema EmojiViolation { file: Str "Target path containing emoji violation" lineNum: I64 "1-indexed line number of violation" text: Str "Offending line content slice" }

schema EmojiScanResult { clean: Bool "True if zero emojis detected" violations: (List EmojiViolation) "List of detected violations" }

fn hasRawEmoji? line: Str -> Bool
  or (s/has? line "\xf0\x9f") (or (s/has? line "\xf0\x9e") (or (s/has? line "\xe2\x9c") (s/has? line "\xe2\x98")))

fn scanLineEmoji file: Str lineNum: I64 content: Str -> (Option EmojiViolation)
  if (hasRawEmoji? content) (some (EmojiViolation :file file :lineNum lineNum :text (string-trim content))) (none)

fn scanFileLinesRec file: Str lines: (List Str) idx: I64 acc: (List EmojiViolation) -> (List EmojiViolation)
  if (list-empty? lines) acc (let head = (option-or (list-head lines) "") in (let tail = (option-or (list-tail lines) (list)) in (let nextAcc = (if (hasRawEmoji? head) (list-append acc (list (EmojiViolation :file file :lineNum idx :text (string-trim head)))) acc) in (scanFileLinesRec file tail (+ idx 1) nextAcc))))

fn scanFileEmoji file: Str lines: (List Str) -> EmojiScanResult
  let vList = (scanFileLinesRec file lines 1 (list))
  EmojiScanResult :clean (list-empty? vList) :violations vList

fn auditAsnEmojis entries: (List Str) -> Bool
  all (fn [(content Str)] -> Bool (not (hasRawEmoji? content))) entries
