(module asl-gates/tests/dyckTest :x [testBalanced testUnbalanced testByteOffsets testEsc testDirectoryRejected! runTests] :i [(asl-gates/dyck :a dyck)])

fn testBalanced -> Bool
  (let [(b1 (stringToBytes ""))
        (r1 (dyck/check b1 true))
        (b2 (stringToBytes "(hello [world {foo}])"))
        (r2 (dyck/check b2 true))
        (b3 (stringToBytes "(\"string with ( parens ) and [ brackets ]\")"))
        (r3 (dyck/check b3 true))
        (b4 (stringToBytes "(\"escaped \\\" quote ( inside string\")"))
        (r4 (dyck/check b4 true))
        (b5 (stringToBytes "; comment with ( unclosed\n(balanced)"))
        (r5 (dyck/check b5 true))
        (b6 (stringToBytes "(in asl ; is not comment)"))
        (r6 (dyck/check b6 false))]
    (do
      (assert (none? r1) "empty bytes balanced")
      (assert (none? r2) "nested balanced")
      (assert (none? r3) "parens in string balanced")
      (assert (none? r4) "escaped quote in string balanced")
      (assert (none? r5) "paren in comment balanced")
      (assert (none? r6) "semicolon in asl balanced")
      true))

fn testUnbalanced -> Bool
  (let [(b1 (stringToBytes "("))
        (r1 (dyck/check b1 true))
        (b2 (stringToBytes ")"))
        (r2 (dyck/check b2 true))
        (b3 (stringToBytes "(]"))
        (r3 (dyck/check b3 true))
        (b4 (stringToBytes "\"unterminated"))
        (r4 (dyck/check b4 true))]
    (do
      (assert (some? r1) "extra open detected")
      (mt r1
        ((some p)
          (do
            (assert (= (pairFirst p) 0) "extra open byte")
            (assert (= (pairSecond p) "unclosed (") "extra open message")))
        ((none) (assert false "expected extra open")))
      (assert (some? r2) "extra close detected")
      (mt r2
        ((some p)
          (do
            (assert (= (pairFirst p) 0) "extra close byte")
            (assert (= (pairSecond p) "unexpected )") "extra close message")))
        ((none) (assert false "expected extra close")))
      (assert (some? r3) "mismatched close detected")
      (mt r3
        ((some p)
          (do
            (assert (= (pairFirst p) 1) "mismatched close byte")
            (assert (= (pairSecond p) "] closes ( opened at byte 0") "mismatched message")))
        ((none) (assert false "expected mismatched close")))
      (assert (some? r4) "unterminated string detected")
      (mt r4
        ((some p)
          (do
            (assert (= (pairFirst p) 0) "unterminated string byte")
            (assert (= (pairSecond p) "unterminated string") "unterminated message")))
        ((none) (assert false "expected unterminated string")))
      true))

fn testByteOffsets -> Bool
  (let [(b (stringToBytes "abc { def [ ghi ( jkl ) ] } )"))
        (r (dyck/check b true))]
    (do
      (assert (some? r) "stray close detected")
      (mt r
        ((some p)
          (do
            (assert (= (pairFirst p) 28) "stray close at byte 28")
            (assert (= (pairSecond p) "unexpected )") "stray close message")))
        ((none) (assert false "expected stray close")))
      true))

fn testEsc -> Bool
  (do
    (assert (= (dyck/esc "hello") "hello") "esc plain")
    (assert (= (dyck/esc "foo\\bar") "foo\\\\bar") "esc backslash")
    (assert (= (dyck/esc "foo\"bar") "foo\\\"bar") "esc double quote")
    true)

fn testDirectoryRejected! -> Bool
  (let [(r (dyck/checkFile! "asl/packages/asl-gates/src"))]
    (mt r
      ((err ev) (do (assert (= ev "Is a directory") "directory returns Is a directory error") true))
      ((ok _) (assert false "expected directory to return err"))))

fn ! runTests -> Bool
  (do
    (assert (testBalanced) "testBalanced")
    (assert (testUnbalanced) "testUnbalanced")
    (assert (testByteOffsets) "testByteOffsets")
    (assert (testEsc) "testEsc")
    (assert (testDirectoryRejected!) "testDirectoryRejected")
    true)
