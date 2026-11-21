(module asl-text/tests/dotenvTest :x [runTests] :i [(asl-text/dotenv :a d)])

fn row0 rows: (List (Pair String String)) -> (Pair String String)
  (optionOr (listHead rows) (pair "" ""))

fn row1 rows: (List (Pair String String)) -> (Pair String String)
  (row0 (optionOr (listTail rows) (list)))

fn row2 rows: (List (Pair String String)) -> (Pair String String)
  (row1 (optionOr (listTail rows) (list)))

fn testParseSimple -> Bool
  (let [(r (d/parseDotenv "FOO=bar\nBAZ=qux\n"))]
    (do (assert (= (listLength r) 2) "two rows")
        (assert (= (row0 r) (pair "FOO" "bar")) "first row FOO=bar")
        (assert (= (row1 r) (pair "BAZ" "qux")) "second row BAZ=qux")
        true))

fn testQuotes -> Bool
  (let [(r (d/parseDotenv "A=\"John Doe\"\nB='single quoted'\nC=\"\"\n"))]
    (do (assert (= (pairSecond (row0 r)) "John Doe") "double quotes stripped")
        (assert (= (pairSecond (row1 r)) "single quoted") "single quotes stripped")
        (assert (= (pairSecond (row2 r)) "") "empty quoted value")
        true))

fn testExportComments -> Bool
  (let [(r (d/parseDotenv "# comment\n\n  export FOO=bar  \n\t# another\n"))]
    (do (assert (= (listLength r) 1) "comments and blanks skipped")
        (assert (= (row0 r) (pair "FOO" "bar")) "export prefix stripped and line trimmed")
        true))

fn testNoExpansion -> Bool
  (let [(r (d/parseDotenv "PATH=$HOME/bin\nQ=\"${FOO}\"\n"))]
    (do (assert (= (pairSecond (row0 r)) "$HOME/bin") "no expansion unquoted")
        (assert (= (pairSecond (row1 r)) "${FOO}") "no expansion quoted")
        true))

fn testSpacesHash -> Bool
  (let [(r (d/parseDotenv "A=\" pad \"\nB=\"a#b\"\n"))]
    (do (assert (= (pairSecond (row0 r)) " pad ") "quoted edge spaces kept")
        (assert (= (pairSecond (row1 r)) "a#b") "hash inside quotes kept")
        true))

fn testEscapes -> Bool
  (let [(r (d/parseDotenv "A=\"line\\nbreak\"\nB=\"say \\\"hi\\\"\"\nC=\"back\\\\slash\"\n"))]
    (do (assert (= (pairSecond (row0 r)) "line\nbreak") "newline escape decoded")
        (assert (= (pairSecond (row1 r)) "say \"hi\"") "quote escape decoded")
        (assert (= (pairSecond (row2 r)) "back\\slash") "backslash escape decoded")
        true))

fn testRenderRoundTrip -> Bool
  (let [(rows (list (pair "FOO" "bar") (pair "PAD" " x ") (pair "Q" "a\"b") (pair "S" "it's") (pair "N" "a\nb") (pair "H" "#tag") (pair "E" "") (pair "B" "a\\b")))
        (out (d/renderDotenv rows))]
    (do (assert (= (d/renderDotenv (list (pair "FOO" "bar"))) "FOO=bar\n") "simple render is raw")
        (assert (= (d/parseDotenv out) rows) "render then parse round-trips")
        true))

fn testEmptyInvalid -> Bool
  (do (assert (= (listLength (d/parseDotenv "")) 0) "empty text has no rows")
      (assert (= (listLength (d/parseDotenv "noequals\n=orphan\n")) 0) "lines without a key are skipped")
      true)

fn runTests -> Bool
  (and (testParseSimple) (and (testQuotes) (and (testExportComments) (and (testNoExpansion) (and (testSpacesHash) (and (testEscapes) (and (testRenderRoundTrip) (testEmptyInvalid))))))))
