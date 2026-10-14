(module asl-runtime/tests/stringsTest
  :x [testPadLeft testPadRight testTrimLeft testTrimRight testTrim testReplaceAll testSplitLines testSliceSafe testStringPredicates testRepeatCharFast runTests]
  :i [(asl-runtime/strings :a str)])

fn testPadLeft -> Bool
  (let [(p1 (str/strPadLeft "42" 5 "0"))
        (p2 (str/strPadLeft "alreadyLong" 5 "0"))
        (p3 (str/strPadLeft "" 3 "x"))]
    (do
      (assert (= p1 "00042") "padded to 5 chars with 0")
      (refute (!= p1 "00042") "refute non-matching pad left")
      (assert (= p2 "alreadyLong") "string longer than target stays unchanged")
      (assert (= p3 "xxx") "empty string padded to 3 chars")
      true))

fn testPadRight -> Bool
  (let [(p1 (str/strPadRight "hi" 5 "!"))
        (p2 (str/strPadRight "longer" 4 "."))
        (p3 (str/strPadRight "" 2 "-"))]
    (do
      (assert (= p1 "hi!!!") "padded right with exclamation")
      (refute (!= p1 "hi!!!") "refute incorrect right pad")
      (assert (= p2 "longer") "longer string remains unchanged")
      (assert (= p3 "--") "empty string padded right")
      true))

fn testTrimLeft -> Bool
  (let [(t1 (str/strTrimLeft "   hello world"))
        (t2 (str/strTrimLeft "\t\n  item"))
        (t3 (str/strTrimLeft "clean"))]
    (do
      (assert (= t1 "hello world") "leading spaces removed")
      (assert (= t2 "item") "leading tabs and newlines removed")
      (assert (= t3 "clean") "no leading spaces untouched")
      (refute (stringStartsWith? t1 " ") "refute leading space remains")
      true))

fn testTrimRight -> Bool
  (let [(t1 (str/strTrimRight "hello world   "))
        (t2 (str/strTrimRight "item\r\n\t"))
        (t3 (str/strTrimRight "clean"))]
    (do
      (assert (= t1 "hello world") "trailing spaces removed")
      (assert (= t2 "item") "trailing tabs and newlines removed")
      (assert (= t3 "clean") "no trailing spaces untouched")
      (refute (stringEndsWith? t1 " ") "refute trailing space remains")
      true))

fn testTrim -> Bool
  (let [(t1 (str/strTrim "  \t centered \n "))
        (t2 (str/strTrim "clean"))]
    (do
      (assert (= t1 "centered") "surrounding whitespace removed")
      (assert (= t2 "clean") "clean string untouched")
      true))

fn testReplaceAll -> Bool
  (let [(r1 (str/strReplaceAll "apple-banana-apple" "apple" "orange"))
        (r2 (str/strReplaceAll "no-match" "xyz" "abc"))
        (r3 (str/strReplaceAll "hello" "" "world"))]
    (do
      (assert (= r1 "orange-banana-orange") "multiple occurrences replaced")
      (refute (stringContains? r1 "apple") "refute old string remains")
      (assert (= r2 "no-match") "no-op when substring not present")
      (assert (= r3 "hello") "no-op when oldSub is empty")
      true))

fn testSplitLines -> Bool
  (let [(s "line1\nline2\r\nline3\n")
        (lines (str/strSplitLines s))]
    (do
      (assert (>= (listLength lines) 3) "at least 3 lines split")
      (assert (= (optionOr (listHead lines) "") "line1") "first line matches")
      (assert (= (optionOr (listGet lines 1) "") "line2") "second line carriage return removed")
      (assert (= (optionOr (listGet lines 2) "") "line3") "third line matches")
      (refute (stringContains? (optionOr (listGet lines 1) "") "\r") "refute carriage return in second line")
      true))

fn testSliceSafe -> Bool
  (let [(s "AgentSlang")
        (sl1 (str/strSliceSafe s 0 5))
        (sl2 (str/strSliceSafe s -3 5))
        (sl3 (str/strSliceSafe s 5 20))
        (sl4 (str/strSliceSafe s 8 4))]
    (do
      (assert (= sl1 "Agent") "slice 0..5 is Agent")
      (assert (= sl2 "Agent") "negative start clamped to 0")
      (assert (= sl3 "Script") "end past length clamped to len")
      (assert (= sl4 "") "start >= end returns empty string")
      (refute (!= sl1 "Agent") "refute incorrect safe slice")
      true))

fn testStringPredicates -> Bool
  (let [(s "Hello, AgentSlang World!")]
    (do
      (assert (str/strContains? s "AgentSlang") "strContains finds substring")
      (refute (str/strContains? s "Python") "strContains refutes absent substring")
      (assert (str/strStartsWith? s "Hello") "strStartsWith matches prefix")
      (refute (str/strStartsWith? s "World") "strStartsWith refutes wrong prefix")
      (assert (str/strEndsWith? s "World!") "strEndsWith matches suffix")
      (refute (str/strEndsWith? s "Hello") "strEndsWith refutes wrong suffix")
      true))

fn testRepeatCharFast -> Bool
  (let [(r1 (str/repeatCharFast "x" 5))
        (r2 (str/repeatCharFast "ab" 3))
        (r0 (str/repeatCharFast "z" 0))]
    (do
      (assert (= r1 "xxxxx") "repeat 5 times is xxxxx")
      (assert (= r2 "ababab") "repeat 3 times is ababab")
      (assert (= r0 "") "repeat 0 times is empty")
      (refute (!= r1 "xxxxx") "refute incorrect repeat")
      true))

fn runTests -> Bool
  (do
    (assert (testPadLeft) "testPadLeft")
    (assert (testPadRight) "testPadRight")
    (assert (testTrimLeft) "testTrimLeft")
    (assert (testTrimRight) "testTrimRight")
    (assert (testTrim) "testTrim")
    (assert (testReplaceAll) "testReplaceAll")
    (assert (testSplitLines) "testSplitLines")
    (assert (testSliceSafe) "testSliceSafe")
    (assert (testStringPredicates) "testStringPredicates")
    (assert (testRepeatCharFast) "testRepeatCharFast")
    true)

