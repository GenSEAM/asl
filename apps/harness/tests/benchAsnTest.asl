(module aslHarness/benchAsnTest
  :x [runTests]
  :i [(aslHarness/benchAsn :a asn)])

fn ! runTests -> Bool
  (let [(expected (asn/asnList (list
                       (asn/asnAtom ":root")
                       (asn/asnAtom ":id")
                       (asn/asnString "x")
                       (asn/asnAtom ":items")
                       (asn/asnList (list (asn/asnAtom "one") (asn/asnString "two"))))))
        (parsed (asn/parse "(:root :id \"x\" :items (one \"two\"))"))
        (unicode (asn/parse "(:label \"café\")"))
        (expectedUnicode (ok (asn/asnList (list (asn/asnAtom ":label") (asn/asnString "café")))))
        (crComment (asn/parse ";comment\r(:x)"))
        (expectedCrComment (ok (asn/asnList (list (asn/asnAtom ":x")))))
        (escaped (asn/parse "; heading\n(:x \"a\\\"b\\\\c\\n\") ; tail"))
        (expectedEscaped (ok (asn/asnList (list (asn/asnAtom ":x") (asn/asnString (str "a\"b\\c\n"))))))]
    (assert (= parsed (ok expected)) "parses nested atoms, strings, and lists structurally")
    (assert (= unicode expectedUnicode) "preserves multibyte UTF-8 text")
    (assert (= crComment expectedCrComment) "ends comments on carriage-return lines")
    (assert (= escaped expectedEscaped) "parses comments and escaped quote, backslash, and newline")
    (assert (err? (asn/parse "(x")) "rejects unterminated list")
    (assert (err? (asn/parse "x y")) "rejects trailing second form")
    (assert (err? (asn/parse "\"\\q\"")) "rejects unsupported escape")
    (assert (ok? (asn/parseFile! "harness/skills.asn")) "reads and parses a real ASN file")
    true)
