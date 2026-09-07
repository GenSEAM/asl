(module asl-codec/asnl-test
  :d "Unit verification test suite for ASNL Streaming Protocol"
  :x [test-balanced-forms
      test-escaping-and-quotes
      test-corrupt-lines
      test-line-encoding
      test-line-decoding
      test-stream-parsing
      test-transpilation
      run-tests]
  :i [(asnl :a asnl)])

(df test-balanced-forms [] -> Bool
  :d "Verifies validation of diverse balanced ASNL records and vectors."
  (and (asnl/asnl-validate-line "(:event :type \"tick\" :ts 100)")
       (and (asnl/asnl-validate-line "[:a :b :c]")
            (and (asnl/asnl-validate-line "(:user :name \"alice\" :active true :count 42)")
                 (asnl/asnl-validate-line "(:nested (:inner [1 2 3]))")))))

(df test-escaping-and-quotes [] -> Bool
  :d "Verifies quote escaping and delimiter isolation inside string literals."
  (and (asnl/asnl-validate-line "(:msg \"hello \\\"world\\\"\")")
       (and (asnl/asnl-validate-line "(:code \"(balanced (inside) string)\")")
            (asnl/asnl-validate-line "(:brackets \"[inside] [string]\")"))))

(df test-corrupt-lines [] -> Bool
  :d "Verifies strict rejection of malformed or corrupt ASNL lines."
  (and (not (asnl/asnl-validate-line "(:unclosed (paren"))
       (and (not (asnl/asnl-validate-line "(:unclosed \"string)"))
            (and (not (asnl/asnl-validate-line "(:extra))"))
                 (and (not (asnl/asnl-validate-line "[:unclosed vector"))
                      (and (not (asnl/asnl-validate-line ""))
                           (not (asnl/asnl-validate-line "   "))))))))

(df test-line-encoding [] -> Bool
  :d "Verifies serialization and compaction of multi-line forms into single-line ASNL."
  (and (= (asnl/asnl-encode-line "(:a 1)") "(:a 1)")
       (and (= (asnl/asnl-encode-line "(:event\n  :type \"tick\"\n  :ts 100)") "(:event :type \"tick\" :ts 100)")
            (asnl/asnl-validate-line (asnl/asnl-encode-line "(:multi\n  :line\n  [1 2 3])")))))

(df test-line-decoding [] -> Bool
  :d "Verifies line decoding behavior on valid and corrupt inputs."
  (and (= (asnl/asnl-decode-line "  (:event :type \"tick\")  ") "(:event :type \"tick\")")
       (= (asnl/asnl-decode-line "(:corrupt (unclosed") "")))

(df test-stream-parsing [] -> Bool
  :d "Verifies incremental streaming parser skips empty and corrupt lines."
  (and (= (list-length (asnl/asnl-decode-stream "(:e1 1)\n(:e2 2)\n(:e3 3)")) 3)
       (and (= (list-length (asnl/asnl-decode-stream "(:e1 1)\n\n  \n(:e2 2)\n")) 2)
            (= (list-length (asnl/asnl-decode-stream "(:e1 1)\n(:corrupt (unclosed\n(:e2 2)")) 2))))

(df test-transpilation [] -> Bool
  :d "Verifies bidirectional JSONL <-> ASNL streaming transpilation."
  (let [(r1 (asnl/jsonl-to-asnl "{\"type\": \"tick\", \"ts\": 100}\n{\"type\": \"tock\", \"ts\": 101}"))
        (r2 (asnl/asnl-to-jsonl "(:type \"tick\" :ts 100)\n(:type \"tock\" :ts 101)"))]
    (and (.-success r1)
         (and (string-contains? (.-output r1) ":type \"tick\"")
              (and (>= (.-savings-percent r1) 40.0)
                   (and (.-success r2)
                        (string-contains? (.-output r2) "\"type\": \"tick\"")))))))

(df run-tests [] -> Bool
  :d "Executes all 26 ASNL verification assertions."
  (do
    (assert (asnl/asnl-validate-line "(:event :type \"tick\" :ts 100)"))
    (assert (asnl/asnl-validate-line "[:a :b :c]"))
    (assert (asnl/asnl-validate-line "(:user :name \"alice\" :active true :count 42)"))
    (assert (asnl/asnl-validate-line "(:nested (:inner [1 2 3]))"))
    (assert (asnl/asnl-validate-line "(:msg \"hello \\\"world\\\"\")"))
    (assert (asnl/asnl-validate-line "(:code \"(balanced (inside) string)\")"))
    (assert (asnl/asnl-validate-line "(:brackets \"[inside] [string]\")"))
    (assert (not (asnl/asnl-validate-line "(:unclosed (paren")))
    (assert (not (asnl/asnl-validate-line "(:unclosed \"string)")))
    (assert (not (asnl/asnl-validate-line "(:extra))")))
    (assert (not (asnl/asnl-validate-line "[:unclosed vector")))
    (assert (not (asnl/asnl-validate-line "")))
    (assert (not (asnl/asnl-validate-line "   ")))
    (assert (= (asnl/asnl-encode-line "(:a 1)") "(:a 1)"))
    (assert (= (asnl/asnl-encode-line "(:event\n  :type \"tick\"\n  :ts 100)") "(:event :type \"tick\" :ts 100)"))
    (assert (asnl/asnl-validate-line (asnl/asnl-encode-line "(:multi\n  :line\n  [1 2 3])")))
    (assert (= (asnl/asnl-decode-line "  (:event :type \"tick\")  ") "(:event :type \"tick\")"))
    (assert (= (asnl/asnl-decode-line "(:corrupt (unclosed") ""))
    (assert (= (list-length (asnl/asnl-decode-stream "(:e1 1)\n(:e2 2)\n(:e3 3)")) 3))
    (assert (= (list-length (asnl/asnl-decode-stream "(:e1 1)\n\n  \n(:e2 2)\n")) 2))
    (assert (= (list-length (asnl/asnl-decode-stream "(:e1 1)\n(:corrupt (unclosed\n(:e2 2)")) 2))
    (assert (.-success (asnl/jsonl-to-asnl "{\"type\": \"tick\", \"ts\": 100}\n{\"type\": \"tock\", \"ts\": 101}")))
    (assert (string-contains? (.-output (asnl/jsonl-to-asnl "{\"type\": \"tick\", \"ts\": 100}")) ":type \"tick\""))
    (assert (>= (.-savings-percent (asnl/jsonl-to-asnl "{\"type\": \"tick\", \"ts\": 100}")) 40.0))
    (assert (.-success (asnl/asnl-to-jsonl "(:type \"tick\" :ts 100)\n(:type \"tock\" :ts 101)")))
    (assert (string-contains? (.-output (asnl/asnl-to-jsonl "(:type \"tick\" :ts 100)")) "\"type\": \"tick\""))
    (assert (test-balanced-forms))
    (assert (test-escaping-and-quotes))
    (assert (test-corrupt-lines))
    (assert (test-line-encoding))
    (assert (test-line-decoding))
    (assert (test-stream-parsing))
    (assert (test-transpilation))))
