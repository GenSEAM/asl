(module asl-pcp/test
  :d "Comprehensive unit tests for the native ASL PCP constitutional engine."
  :x [run-tests
      is-none-sc?
      is-none-rule?
      sample-valid-codes
      sample-test-ledger
      test-types-and-shortcodes
      test-scanner-extracts-pcp-references
      test-scanner-parses-shortcodes
      test-ledger-asn-roundtrip
      test-verification-valid-module
      test-verification-missing-rules
      test-check-invariants-detects-violations
      test-query-rule]
  :i [(types :a t) (scanner :a sc) (ledger :a lg) (verify :a v)])

"run: (run-tests)"

(df is-none-sc? [(opt (Option t/Shortcode))] -> Bool
  :d "Checks if optional Shortcode is none."
  (if (mt opt ((some _) true) ((none) false))
    false
    true))

(df is-none-rule? [(opt (Option t/PcpRule))] -> Bool
  :d "Checks if optional PcpRule is none."
  (mt opt
    ((none) true)
    ((some _) false)))

(df sample-valid-codes [] -> (List Str)
  :d "List of standard test shortcodes."
  (cons "d-1eed" (cons "c-099a" (cons "l-a250" (list)))))

(df sample-test-ledger [] -> t/Ledger
  :d "Constructs a sample Ledger for testing."
  (let [(r1 (t/make-rule "d-1eed" "Self-hosting typechecker" "Soundness without runtime" "active"))
        (r2 (t/make-rule "c-099a" "Semantic fixture assertion" "Prevents silent masking" "active"))
        (r3 (t/make-rule "l-a250" "Retired comment syntax" "Enforces canonical forms" "active"))]
    (t/make-ledger (cons r1 (cons r2 (cons r3 (list)))) (sample-valid-codes))))

(df test-types-and-shortcodes [] -> Bool
  :d "Verifies ShortcodeType enum variants and Shortcode record construction."
  (let [(d-val (t/p-dec))
        (c-val (t/p-crit))
        (l-val (t/p-law))
        (r-val (t/p-req))
        (sc-dec (t/make-shortcode d-val "d-1eed"))
        (sc-crit (t/make-shortcode c-val "c-099a"))
        (sc-law (t/make-shortcode l-val "l-a250"))
        (sc-req (t/make-shortcode r-val "r-8d8e"))]
    (and (= (t/shortcode-type-to-string d-val) "d")
         (and (= (t/shortcode-type-to-string c-val) "c")
              (and (= (t/shortcode-type-to-string l-val) "l")
                   (and (= (t/shortcode-type-to-string r-val) "r")
                        (and (= (.-code sc-dec) "d-1eed")
                             (and (= (.-code sc-crit) "c-099a")
                                  (and (= (.-code sc-law) "l-a250")
                                       (= (.-code sc-req) "r-8d8e"))))))))))

(df test-scanner-extracts-pcp-references [] -> Bool
  :d "Verifies scanner correctly extracts and normalizes all PCP shortcode references."
  (let [(sample-txt "fn @pcp:d-8d4c for typechecker, adheres to c-099a and @pcp:l-a250 and r-8d8e again @pcp:d-8d4c")
        (refs (sc/scan-pcp-references sample-txt))]
    (and (= (list-length refs) 4)
         (and (list-contains? refs "d-8d4c")
              (and (list-contains? refs "c-099a")
                   (and (list-contains? refs "l-a250")
                        (list-contains? refs "r-8d8e")))))))

(df test-scanner-parses-shortcodes [] -> Bool
  :d "Verifies parsing of individual shortcodes into structured records."
  (let [(p-opt (sc/parse-shortcode "@pcp:d-1eed"))
        (bad-opt (sc/parse-shortcode "not-a-shortcode"))]
    (and (mt p-opt
           ((some sc) (and (= (.-code sc) "d-1eed")
                           (= (t/shortcode-type-to-string (.-kind sc)) "d")))
           ((none) false))
         (is-none-sc? bad-opt))))

(df test-ledger-asn-roundtrip [] -> Bool
  :d "Verifies ASN tabular constitution encoding and parsing round-trip."
  (let [(orig-ledger (sample-test-ledger))
        (doc (lg/encode-ledger-asn orig-ledger))
        (parsed-opt (lg/parse-ledger-asn doc))]
    (mt parsed-opt
      ((none) false)
      ((some parsed-ledger)
       (let [(parsed-rules (.-rules parsed-ledger))
             (parsed-codes (.-shortcodes parsed-ledger))]
         (and (= (list-length parsed-rules) 3)
              (and (= (list-length parsed-codes) 3)
                   (and (list-contains? parsed-codes "d-1eed")
                        (and (list-contains? parsed-codes "c-099a")
                             (list-contains? parsed-codes "l-a250"))))))))))

(df test-verification-valid-module [] -> Bool
  :d "Verifies a compliant module produces zero missing rules."
  (let [(ledger (sample-test-ledger))
        (result (v/verify-module ledger "mod-valid" (sample-valid-codes)))]
    (and (= (.-module result) "mod-valid")
         (and (= (list-length (.-referenced result)) 3)
              (list-empty? (.-missing result))))))

(df test-verification-missing-rules [] -> Bool
  :d "Verifies unregistered references and missing invariant laws are detected."
  (let [(ledger (sample-test-ledger))
        (missing-refs (cons "d-1eed" (cons "d-9999" (list))))
        (result (v/verify-module ledger "mod-incomplete" missing-refs))
        (missing (.-missing result))]
    (and (= (.-module result) "mod-incomplete")
         (and (list-contains? missing "unregistered:d-9999")
              (list-contains? missing "missing-invariant:l-a250")))))

(df test-check-invariants-detects-violations [] -> Bool
  :d "Verifies invariant checker detects retired rules and missing laws."
  (let [(r-active (t/make-rule "d-1eed" "Decision" "Why" "active"))
        (r-ret (t/make-rule "d-old1" "Old Decision" "Why" "retired"))
        (r-law (t/make-rule "l-a250" "Mandatory Law" "Why" "active"))
        (mixed-rules (cons r-active (cons r-ret (cons r-law (list)))))
        (mixed-codes (cons "d-1eed" (cons "d-old1" (cons "l-a250" (list)))))
        (ledger (t/make-ledger mixed-rules mixed-codes))
        (active-set (cons "d-1eed" (cons "d-old1" (list))))
        (violations (v/check-invariants ledger active-set))]
    (and (list-contains? violations "retired:d-old1")
         (list-contains? violations "missing-invariant:l-a250"))))

(df test-query-rule [] -> Bool
  :d "Verifies querying existing and non-existing rules in a ledger."
  (let [(ledger (sample-test-ledger))
        (q1 (v/query-rule ledger "d-1eed"))
        (q2 (v/query-rule ledger "@pcp:c-099a"))
        (q3 (v/query-rule ledger "d-nonexistent"))]
    (and (mt q1
           ((some r) (= (.-title r) "Self-hosting typechecker"))
           ((none) false))
         (and (mt q2
                ((some r) (= (.-title r) "Semantic fixture assertion"))
                ((none) false))
              (is-none-rule? q3)))))

(df run-tests [] -> Bool
  :d "Runs all ASL PCP unit tests and verifies they pass."
  (let [(t-res (list (test-types-and-shortcodes)
                     (test-scanner-extracts-pcp-references)
                     (test-scanner-parses-shortcodes)
                     (test-ledger-asn-roundtrip)
                     (test-verification-valid-module)
                     (test-verification-missing-rules)
                     (test-check-invariants-detects-violations)
                     (test-query-rule)))]
    (not (list-contains? t-res false))))
