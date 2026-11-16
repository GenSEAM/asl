(module asl-runtime/tests/stringsCoverTest
  :x [testRepeatChar testIsWhitespaceChar runTests]
  :i [(asl-runtime/strings :a str)])

fn testRepeatChar -> Bool
  (do
    (let [(r1 (str/repeatChar "x" 5 ""))]
      (assert (= r1 "xxxxx") "repeatChar 5 times normal"))
    (let [(r0 (str/repeatChar "y" 0 ""))]
      (assert (= r0 "") "repeatChar zero count returns empty"))
    (let [(rn (str/repeatChar "z" -3 ""))]
      (assert (= rn "") "repeatChar negative count returns empty"))
    (let [(rmax (str/repeatChar "a" 1000 ""))]
      (assert (= (stringLength rmax) 1000) "repeatChar large count length"))
    (let [(rempty (str/repeatChar "" 3 ""))]
      (assert (= rempty "") "repeatChar empty char returns empty"))
    (let [(racc (str/repeatChar "x" 3 "ab"))]
      (assert (= racc "abxxx") "repeatChar accumulates onto non-empty acc"))
    true)

fn testIsWhitespaceChar -> Bool
  (do
    (assert (str/isWhitespaceChar " ") "space is whitespace")
    (assert (str/isWhitespaceChar "\t") "tab is whitespace")
    (assert (str/isWhitespaceChar "\n") "newline is whitespace")
    (assert (str/isWhitespaceChar "\r") "carriage return is whitespace")
    (refute (str/isWhitespaceChar "") "empty string is not whitespace")
    (refute (str/isWhitespaceChar "a") "letter a is not whitespace")
    (refute (str/isWhitespaceChar "0") "digit 0 is not whitespace")
    (refute (str/isWhitespaceChar "!") "exclamation is not whitespace")
    (refute (str/isWhitespaceChar "  ") "multi-char string is not whitespace")
    true)

fn runTests -> Bool
  (do
    (assert (testRepeatChar) "testRepeatChar")
    (assert (testIsWhitespaceChar) "testIsWhitespaceChar")
    true)
