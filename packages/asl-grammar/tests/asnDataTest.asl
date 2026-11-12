(module asl/packages/asl-grammar/tests/asnDataTest
  :x [runTests]
  :i [(asl-grammar/asnData :a ad)])

; (:m :ref DS-ASNREADER :do "ASN data reader on literal texts: the row case (:a 1 :b \"x\" :c (1 2)) as typed values, the inbox repro where a string with a paren and a comment must not leak :active true, booleans and floats, escapes, a keyword used as a value, labelled errs for unbalanced, empty and trailing input, and a render round trip")

fn errOf r: (Result ad/AsnValue String) -> String
  (match r ((ok _) "") ((err e) e))

fn valueOf r: (Result ad/AsnValue String) -> ad/AsnValue
  (match r ((ok v) v) ((err e) (ad/asnStr (str "<err " e ">"))))

fn fieldOf r: (Result ad/AsnValue String) key: String -> ad/AsnValue
  (optionOr (ad/asnField (valueOf r) key) (ad/asnSym "<none>"))

fn intOf v: ad/AsnValue -> Int64
  (optionOr (ad/asnInt v) -999)

fn textOf v: ad/AsnValue -> String
  (optionOr (ad/asnString v) "<not text>")

fn boolText v: ad/AsnValue -> String
  (match (ad/asnBool v) ((some b) (if b "true" "false")) ((none) "<not bool>"))

fn labelled? e: String label: String -> Bool
  (stringStartsWith? e (str label ":"))

fn rowText -> String
  "(:a 1 :b \"x\" :c (1 2))"

fn reproText -> String
  "(:cfg :active false :name \"a (b\" ; c :active true\n)"

fn ! runTests -> Bool
  (let [(row (ad/asnParse (rowText)))
        (rowC (fieldOf row "c"))
        (rowCInts (map intOf (ad/asnItems rowC)))
        (repro (ad/asnParse (reproText)))
        (reproActive (boolText (fieldOf repro "active")))
        (reproName (textOf (fieldOf repro "name")))
        (reproKeys (listCount (fn [(x ad/AsnValue)] -> Bool (some? (ad/asnKeyword x))) (ad/asnItems (valueOf repro))))
        (typedText (ad/asnParse "(:on true :off false :ratio 1.5 :exp 2e3 :neg -7 :sym node2 :v [1 \"two\" :three])"))
        (ratio (optionOr (ad/asnFloat (fieldOf typedText "ratio")) -1.0))
        (expo (optionOr (ad/asnFloat (fieldOf typedText "exp")) -1.0))
        (vec (ad/asnItems (fieldOf typedText "v")))
        (escaped (ad/asnParse "(:s \"q\\\"uote\\\\ :k (x\\n\" :after 1)"))
        (kwValue (ad/asnParse "(:mode :fast :fast 9)"))
        (unbalanced (errOf (ad/asnParse "(:a 1 :b (2 3)")))
        (closer (errOf (ad/asnParse "(:a 1))")))
        (openString (errOf (ad/asnParse "(:a \"x)")))
        (empty (errOf (ad/asnParse "  ; only a comment\n")))
        (trailing (errOf (ad/asnParse "(:a 1) (:b 2)")))
        (all (ad/asnParseAll "(:a 1) (:b 2) ; tail\n"))
        (allCount (match all ((ok xs) (listLength xs)) ((err _) -1)))
        (tree (valueOf (ad/asnParse "(:cfg :name \"a \\\"b\\\"\\n\" :on true :r 0.25 :xs [1 -2 (:k sym)])")))
        (printed (ad/asnRender tree))
        (again (ad/asnParse printed))
        (printedAgain (ad/asnRender (valueOf again)))]
    (do
      (assert (= (errOf row) "") (str "the row case parses: " (errOf row)))
      (assert (and (= (intOf (fieldOf row "a")) 1) (= (textOf (fieldOf row "b")) "x")) (str "row :a is the Int 1 and :b the String x: " (ad/asnRender (valueOf row))))
      (assert (= rowCInts (list 1 2)) (str "row :c is a list of the Ints 1 2: " (ad/asnRender rowC)))
      (assert (= (ad/asnInt (fieldOf row "b")) (none)) "a String is not an Int")
      (assert (= (ad/asnField (valueOf row) "missing") (none)) "an absent key is none")
      (assert (= reproActive "false") (str "the repro's top-level :active is false: " reproActive " in " (ad/asnRender (valueOf repro))))
      (assert (= reproName "a (b") (str "a paren inside a string stays in the string: " reproName))
      (assert (= reproKeys 3) (str "the commented :active true does not leak a key, the keywords are :cfg :active :name: " (stringFromInt64 reproKeys) " keywords"))
      (assert (and (= (boolText (fieldOf typedText "on")) "true") (= (boolText (fieldOf typedText "off")) "false")) (str "true and false read as Bool: " (errOf typedText)))
      (assert (and (= ratio 1.5) (= expo 2000.0)) (str "decimals with a point or exponent read as Float64: " (stringFromFloat64 ratio) " " (stringFromFloat64 expo)))
      (assert (and (= (intOf (fieldOf typedText "neg")) -7) (= (ad/asnBool (fieldOf typedText "neg")) (none))) "-7 is an Int, not a Bool")
      (assert (= (textOf (fieldOf typedText "sym")) "node2") "a symbol reads as its text")
      (assert (and (= (listLength vec) 3) (= (textOf (optionOr (listGet vec 1) (ad/asnSym ""))) "two") (= (ad/asnKeyword (optionOr (listGet vec 2) (ad/asnSym ""))) (some "three"))) (str "a vector keeps its typed items: " (ad/asnRender (fieldOf typedText "v"))))
      (assert (= (textOf (fieldOf escaped "s")) "q\"uote\\ :k (x\n") (str "escapes resolve and a key or paren in a string stays text: " (textOf (fieldOf escaped "s"))))
      (assert (and (= (intOf (fieldOf escaped "after")) 1) (= (ad/asnField (valueOf escaped) "k") (none))) "the key after an escaped string is read and the one inside it is not")
      (assert (and (= (ad/asnKeyword (fieldOf kwValue "mode")) (some "fast")) (= (intOf (fieldOf kwValue "fast")) 9)) (str "a keyword used as a value is not read as a key: " (ad/asnRender (valueOf kwValue))))
      (assert (and (labelled? unbalanced "ERR_ASN_READ") (stringContains? unbalanced "unclosed")) (str "an unclosed form is a labelled err: " unbalanced))
      (assert (and (labelled? closer "ERR_ASN_READ") (stringContains? closer "byte 6")) (str "an extra closer is a labelled err with its byte: " closer))
      (assert (labelled? openString "ERR_ASN_READ") (str "an unterminated string is a labelled err: " openString))
      (assert (labelled? empty "ERR_ASN_EMPTY") (str "text with no value is a labelled err: " empty))
      (assert (labelled? trailing "ERR_ASN_TRAILING") (str "two top-level values to asnParse is a labelled err: " trailing))
      (assert (= allCount 2) (str "asnParseAll returns every top-level value: " (stringFromInt64 allCount)))
      (assert (= printed "(:cfg :name \"a \\\"b\\\"\\n\" :on true :r 0.25 :xs [1 -2 (:k sym)])") (str "asnRender prints canonical text: " printed))
      (assert (and (= (errOf again) "") (= printedAgain printed)) (str "the printed text parses back to the same value: " (errOf again) " " printedAgain))
      true))
