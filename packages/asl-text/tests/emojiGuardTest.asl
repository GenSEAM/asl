(module asl-text/tests/emojiGuardTest :x [runTests testCleanLinePasses testEmojiDetectionFails testScanFileAccumulation testAuditAsnEmojis] :i [(emojiGuard :a eg)])

fn testCleanLinePasses -> Bool
  (let [(line1 "(:task :id \"Task43201\" :status :done)") (line2 "This is a clean ASCII string.") (line3 "Русский текст без эмодзи.")] (refute (eg/hasRawEmoji? line1) "Clean ASN task line must not trigger emoji guard") (refute (eg/hasRawEmoji? line2) "Clean ASCII text must not trigger emoji guard") (refute (eg/hasRawEmoji? line3) "Clean Cyrillic text must not trigger emoji guard") (assert (none? (eg/scanLineEmoji "test.asn" 1 line1)) "Clean line scan must return none") true)

fn testEmojiDetectionFails -> Bool
  (let [(badLine "(:task :title \"Bad \xf0\x9f\x9a\x80 Task\")") (viol (eg/scanLineEmoji "test.asn" 5 badLine))] (assert (eg/hasRawEmoji? badLine) "Line with rocket emoji byte must be flagged") (refute (none? viol) "Violation record must be present") (assert (some? viol) "Option must be some for flagged line") true)

fn testScanFileAccumulation -> Bool
  (let [(cleanLines (list "line 1" "line 2" "line 3")) (resClean (eg/scanFileEmoji "clean.asn" cleanLines)) (dirtyLines (list "clean line 1" "line 2 bad \xf0\x9f\x98\x80 smile" "clean line 3" "line 4 bad \xf0\x9f\x9a\x80 rocket" "clean line 5")) (resDirty (eg/scanFileEmoji "dirty.asn" dirtyLines))] (assert resClean.clean "Clean file scan must report clean true") (assert (= (listLength resClean.violations) 0) "Clean file must have zero violations") (refute resDirty.clean "Dirty file scan must report clean false") (assert (= (listLength resDirty.violations) 2) "Dirty file must have two violations") (let [(v1 (optionOr (listHead resDirty.violations) (eg/EmojiViolation :file "" :lineNum 0 :text ""))) (tail1 (optionOr (listTail resDirty.violations) (list))) (v2 (optionOr (listHead tail1) (eg/EmojiViolation :file "" :lineNum 0 :text "")))] (assert (= v1.lineNum 2) "Violation line number must be 2") (refute (= v1.lineNum 1) "Violation line number must not be 1") (assert (= v2.lineNum 4) "Second violation line number must be 4") (refute (= v2.lineNum 2) "Second violation line number must not be 2")) true)

fn testAuditAsnEmojis -> Bool
  (let [(goodEntries (list "entry 1" "entry 2" "entry 3")) (badEntries (list "entry 1" "violating \xf0\x9f\x92\xa1" "entry 3"))] (assert (eg/auditAsnEmojis goodEntries) "Clean entries list must pass audit") (refute (eg/auditAsnEmojis badEntries) "Dirty entries list must fail audit") true)

fn runTests -> Bool
  (do (testCleanLinePasses) (testEmojiDetectionFails) (testScanFileAccumulation) (testAuditAsnEmojis) true)
