(module asl-text/tests/wrapTest
  :x [runTests]
  :i [(asl-text/wrap :a w)])

fn runTests -> Bool
  (do
    (assert (= (w/wordWrap "the quick brown fox jumps over the lazy dog" 20) (list "the quick brown fox" "jumps over the lazy" "dog")) "paragraph width 20")
    (assert (= (w/wordWrap "https://example.com/very/long/path" 10) (list "https://ex" "ample.com/" "very/long/" "path")) "long url width 10")
    (assert (= (listGet (w/wordWrap "https://example.com/very/long/path" 10) 3) (some "path")) "long url fourth line")
    (assert (= (w/wordWrap "one two\n\nthree four" 20) (list "one two" "" "three four")) "two paragraphs blank line")
    (assert (= (w/wordWrap "a\n \nb" 20) (list "a" "" "b")) "whitespace-only line kept as blank")
    (assert (= (w/wordWrap "привет мир как дела сегодня" 20) (list "привет мир как дела" "сегодня")) "cyrillic code points not bytes")
    (assert (= (w/wordWrap "a b\nc" 0) (list "a b\nc")) "width 0 returns input as one line")
    (assert (= (w/wordWrap "ab abcdefghijklmnop qr" 10) (list "ab" "abcdefghij" "klmnop qr")) "long word among words")
    (assert (= (w/wrapIndent "one two\n\nthree" 20 "> ") (list "> one two" "> " "> three")) "wrapIndent prefix")
    true)
