(module asl-text/tests/emoji-guard-test
  :d "Comprehensive falsifiable test suite for pure AgentScript emoji guard per C2."
  :x [run-tests
      test-clean-line-passes
      test-emoji-detection-fails
      test-scan-file-accumulation
      test-audit-asn-emojis]
  :i [(emoji-guard :a eg)])

(df test-clean-line-passes [] -> Bool
  :d "Verifies that clean text lines without emojis pass inspection."
  (let [(line1 "(:task :id \"Task43201\" :status :done)")
        (line2 "This is a clean ASCII string.")
        (line3 "Русский текст без эмодзи.")]
    (assert (not (eg/has-raw-emoji? line1)) "Clean ASN task line must not trigger emoji guard")
    (assert (not (eg/has-raw-emoji? line2)) "Clean ASCII text must not trigger emoji guard")
    (assert (not (eg/has-raw-emoji? line3)) "Clean Cyrillic text must not trigger emoji guard")
    (assert (option-none? (eg/scan-line-emoji "test.asn" 1 line1)) "Clean line scan must return none")
    true))

(df test-emoji-detection-fails [] -> Bool
  :d "Verifies that lines containing raw emoji bytes are detected."
  (let [(bad-line "(:task :title \"Bad \xf0\x9f\x9a\x80 Task\")")
        (viol (eg/scan-line-emoji "test.asn" 5 bad-line))]
    (assert (eg/has-raw-emoji? bad-line) "Line with rocket emoji byte must be flagged")
    (assert (not (option-none? viol)) "Violation record must be present")
    (assert (option-some? viol) "Option must be some for flagged line")
    true))

(df test-scan-file-accumulation [] -> Bool
  :d "Verifies file-level line accumulation and clean report generation."
  (let [(clean-lines (list "line 1" "line 2" "line 3"))
        (res-clean (eg/scan-file-emoji "clean.asn" clean-lines))
        (dirty-lines (list "line 1" "bad \xf0\x9f\x98\x80 line" "line 3"))
        (res-dirty (eg/scan-file-emoji "dirty.asn" dirty-lines))]
    (assert (.-clean res-clean) "Clean file scan must report clean true")
    (assert (= (list-length (.-violations res-clean)) 0) "Clean file must have zero violations")
    (assert (not (.-clean res-dirty)) "Dirty file scan must report clean false")
    (assert (not (= (list-length (.-violations res-dirty)) 0)) "Dirty file must have non-zero violations")
    true))

(df test-audit-asn-emojis [] -> Bool
  :d "Verifies multi-file bulk audit logic with both positive and negative cases."
  (let [(good-entries (list "entry 1" "entry 2" "entry 3"))
        (bad-entries (list "entry 1" "violating \xf0\x9f\x92\xa1" "entry 3"))]
    (assert (eg/audit-asn-emojis good-entries) "Clean entries list must pass audit")
    (assert (not (eg/audit-asn-emojis bad-entries)) "Dirty entries list must fail audit")
    true))

(df run-tests [] -> Bool
  :d "Runs all test cases in the emoji guard test suite."
  (do
    (test-clean-line-passes)
    (test-emoji-detection-fails)
    (test-scan-file-accumulation)
    (test-audit-asn-emojis)
    true))
