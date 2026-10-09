(module asl-transpile/scalarTest :x [testParseBooleans testParseNulls testParseNumbers testParseStrings testIsScalarLiteral testNegativeCases runTests] :i [(asl-transpile/scalar :a sc) (asl-parser/reader :a rd)])

fn testParseBooleans -> Bool
  (let [(t1 (rd/sexprHead (sc/parseCommonScalar "true")))
        (t2 (rd/sexprHead (sc/parseCommonScalar "yes")))
        (f1 (rd/sexprHead (sc/parseCommonScalar "false")))
        (f2 (rd/sexprHead (sc/parseCommonScalar "no")))]
    (assert (= t1 "true") "true parses to true")
    (assert (= t2 "true") "yes parses to true")
    (assert (= f1 "false") "false parses to false")
    (assert (= f2 "false") "no parses to false")
    (refute (= t1 "false") "true is not false")
    (refute (= f1 "true") "false is not true")
    true)

fn testParseNulls -> Bool
  (let [(n1 (rd/sexprHead (sc/parseCommonScalar "null")))
        (n2 (rd/sexprHead (sc/parseCommonScalar "~")))
        (n3 (rd/sexprHead (sc/parseCommonScalar "_")))
        (n4 (rd/sexprHead (sc/parseCommonScalar "nil")))
        (n5 (rd/sexprHead (sc/parseCommonScalar "")))]
    (assert (= n1 "_") "null parses to _")
    (assert (= n2 "_") "~ parses to _")
    (assert (= n3 "_") "_ parses to _")
    (assert (= n4 "_") "nil parses to _")
    (assert (= n5 "_") "empty string parses to _")
    (refute (= n1 "null") "null atom is normalized to _")
    true)

fn testParseNumbers -> Bool
  (let [(num1 (rd/sexprHead (sc/parseCommonScalar "42")))
        (num2 (rd/sexprHead (sc/parseCommonScalar "-17")))
        (num3 (rd/sexprHead (sc/parseCommonScalar "3.14")))]
    (assert (= num1 "42") "positive int parses correctly")
    (assert (= num2 "-17") "negative int parses correctly")
    (assert (= num3 "3.14") "float parses correctly")
    (refute (= num1 "43") "numeric precision preserved")
    true)

fn testParseStrings -> Bool
  (let [(s1 (rd/sexprHead (sc/parseCommonScalar "\"hello\"")))
        (s2 (rd/sexprHead (sc/parseCommonScalar "'world'")))
        (s3 (rd/sexprHead (sc/parseCommonScalar "hello world")))
        (s4 (rd/sexprHead (sc/parseCommonScalar "foo")))]
    (assert (= s1 "\"hello\"") "double quotes normalized")
    (assert (= s2 "\"world\"") "single quotes normalized to double")
    (assert (= s3 "\"hello world\"") "spaced string wrapped in quotes")
    (assert (= s4 "foo") "bare identifier kept as bare atom")
    (refute (= s1 "'hello'") "single quotes replaced")
    true)

fn testIsScalarLiteral -> Bool
  (do
    (assert (sc/isScalarLiteral? "true") "true is scalar literal")
    (assert (sc/isScalarLiteral? "false") "false is scalar literal")
    (assert (sc/isScalarLiteral? "yes") "yes is scalar literal")
    (assert (sc/isScalarLiteral? "no") "no is scalar literal")
    (assert (sc/isScalarLiteral? "null") "null is scalar literal")
    (assert (sc/isScalarLiteral? "~") "~ is scalar literal")
    (assert (sc/isScalarLiteral? "_") "_ is scalar literal")
    (assert (sc/isScalarLiteral? "nil") "nil is scalar literal")
    (assert (sc/isScalarLiteral? "42") "42 is scalar literal")
    (assert (sc/isScalarLiteral? "-100") "-100 is scalar literal")
    (assert (sc/isScalarLiteral? "3.1415") "3.1415 is scalar literal")
    (assert (sc/isScalarLiteral? "\"quoted string\"") "double quoted is scalar literal")
    (assert (sc/isScalarLiteral? "'single quoted'") "single quoted is scalar literal")
    (refute (sc/isScalarLiteral? "myIdentifier") "identifier is not scalar literal")
    (refute (sc/isScalarLiteral? "package-name") "kebab-case is not scalar literal")
    (refute (sc/isScalarLiteral? "hello world") "unquoted multiword is not scalar literal")
    true)

fn testNegativeCases -> Bool
  (let [(res (rd/sexprHead (sc/parseCommonScalar "   ")))]
    (assert (= res "_") "whitespace only parses to _")
    (refute (sc/isScalarLiteral? "") "empty string is not literal")
    true)

fn runTests -> Bool
  (do
    (assert (testParseBooleans) "booleans suite")
    (assert (testParseNulls) "nulls suite")
    (assert (testParseNumbers) "numbers suite")
    (assert (testParseStrings) "strings suite")
    (assert (testIsScalarLiteral) "classifier suite")
    (assert (testNegativeCases) "negative suite")
    true)
