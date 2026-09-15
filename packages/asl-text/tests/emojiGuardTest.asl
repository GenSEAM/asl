(module asl-text/tests/emojiGuardTest
  :d "Comprehensive falsifiable test suite for pure AgentScript emoji guard per C2."
  :x [runTests
      testCleanLinePasses
      testEmojiDetectionFails
      testScanFileAccumulation
      testAuditAsnEmojis]
  :i [(emojiGuard :a eg)])

(df testCleanLinePasses [] -> Bool
  :d "Verifies that clean text lines without emojis pass inspection."
  (let [(line1 "(:task :id \"Task43201\" :status :done)")
        (line2 "This is a clean ASCII string.")
        (line3 "Русский текст без эмодзи.")]
    (refute (eg/hasRawEmoji? line1) "Clean ASN task line must not trigger emoji guard")
    (refute (eg/hasRawEmoji? line2) "Clean ASCII text must not trigger emoji guard")
    (refute (eg/hasRawEmoji? line3) "Clean Cyrillic text must not trigger emoji guard")
    (assert (option-none? (eg/scanLineEmoji "test.asn" 1 line1)) "Clean line scan must return none")
    true))

(df testEmojiDetectionFails [] -> Bool
  :d "Verifies that lines containing raw emoji bytes are detected."
  (let [(badLine "(:task :title \"Bad \xf0\x9f\x9a\x80 Task\")")
        (viol (eg/scanLineEmoji "test.asn" 5 badLine))]
    (assert (eg/hasRawEmoji? badLine) "Line with rocket emoji byte must be flagged")
    (refute (option-none? viol) "Violation record must be present")
    (assert (optionSome? viol) "Option must be some for flagged line")
    true))

(df testScanFileAccumulation [] -> Bool
  :d "Verifies file-level line accumulation and clean report generation."
  (let [(cleanLines (list "line 1" "line 2" "line 3"))
        (resClean (eg/scanFileEmoji "clean.asn" cleanLines))
        (dirtyLines (list "clean line 1"
                          "line 2 bad \xf0\x9f\x98\x80 smile"
                          "clean line 3"
                          "line 4 bad \xf0\x9f\x9a\x80 rocket"
                          "clean line 5"))
        (resDirty (eg/scanFileEmoji "dirty.asn" dirtyLines))]
    (assert (.-clean resClean) "Clean file scan must report clean true")
    (assert (= (list-length (.-violations resClean)) 0) "Clean file must have zero violations")
    (refute (.-clean resDirty) "Dirty file scan must report clean false")
    (assert (= (list-length (.-violations resDirty)) 2) "Dirty file must have two violations")
    (let [(v1 (option-or (list-head (.-violations resDirty)) (eg/EmojiViolation :file "" :lineNum 0 :text "")))
          (tail1 (option-or (list-tail (.-violations resDirty)) (list)))
          (v2 (option-or (list-head tail1) (eg/EmojiViolation :file "" :lineNum 0 :text "")))]
      (assert (= (.-lineNum v1) 2) "Violation line number must be 2")
      (refute (= (.-lineNum v1) 1) "Violation line number must not be 1")
      (assert (= (.-lineNum v2) 4) "Second violation line number must be 4")
      (refute (= (.-lineNum v2) 2) "Second violation line number must not be 2"))
    true))

(df testAuditAsnEmojis [] -> Bool
  :d "Verifies multi-file bulk audit logic with both positive and negative cases."
  (let [(goodEntries (list "entry 1" "entry 2" "entry 3"))
        (badEntries (list "entry 1" "violating \xf0\x9f\x92\xa1" "entry 3"))]
    (assert (eg/auditAsnEmojis goodEntries) "Clean entries list must pass audit")
    (refute (eg/auditAsnEmojis badEntries) "Dirty entries list must fail audit")
    true))

(df runTests [] -> Bool
  :d "Runs all test cases in the emoji guard test suite."
  (do
    (testCleanLinePasses)
    (testEmojiDetectionFails)
    (testScanFileAccumulation)
    (testAuditAsnEmojis)
    true))
