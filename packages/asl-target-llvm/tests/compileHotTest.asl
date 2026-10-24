(module asl-target-llvm/tests/compileHotTest
  :x [runTests]
  :i [(asl-target-llvm/rtError :a rterr)
      (asl-target-llvm/rtValue :a valrt)])

fn hasKey keys: (Map String Bool) k: String -> Bool
  (mapHas? keys k)

; (:m :ref COMPILEHOT :do "refKeys over text with @ at the start, the middle, after a non-stop byte, and last without a delimiter")
fn testRefKeys -> Bool
  (let [(keys (rterr/refKeys "@a(x) call @b, q@c(z) tail@d"))]
    (do
      (assert (hasKey keys "@a(") "@ at index 0 is found")
      (assert (hasKey keys "@b,") "key ends at its delimiter, delimiter included")
      (assert (hasKey keys "@c(") "@ glued to a preceding word is found")
      (refute (hasKey keys "@d") "a key with no delimiter at the end of text is dropped")
      (refute (hasKey keys "@x") "bytes after the delimiter are not a key")
      (assert (= (mapSize (rterr/refKeys "no at sign at all")) 0) "text without @ has no keys")
      (assert (= (mapSize (rterr/refKeys "")) 0) "empty text has no keys")
      true))

; (:m :ref COMPILEHOT :do "a shim header defined only after thousands of other lines and after a mere call of another shim is still found; a name only called, never defined, is not defined")
fn testDefinedNames -> Bool
  (let [(filler (stringJoin (map (fn [(i Int64)] -> String (str "  %v" i " = call i32 @other" i "(ptr %p)")) (range 0 2000)) "\n"))
        (hdr "define internal ptr @symName(i32 %id) {")
        (text (str "  %x = call i32 @intern(ptr %t, i64 1)\n" filler "\n" hdr "\n  ret ptr null\n}\n"))
        (keys (rterr/refKeys text))
        (defined (valrt/rtValueDefinedNames text keys))]
    (do
      (assert (listContains? defined "symName") "a header defined late in the text is found")
      (refute (listContains? defined "intern") "a name that is only called is not defined")
      (refute (listContains? defined "mkStr") "a name that is absent is not defined")
      (assert (= (listLength defined) 1) "exactly the one defined shim")
      (assert (valrt/rtValueDefines? text "symName") "rtValueDefines? still agrees on the defined name")
      (refute (valrt/rtValueDefines? text "intern") "rtValueDefines? still agrees on the called-only name")
      (assert (= (listLength (valrt/rtValueDefinedNames "" (mapEmpty))) 0) "empty text defines none")
      true))

; (:m :ref COMPILEHOT :do "splitting where the separator shares its first byte with data: overlaps, partial matches, adjacent and edge separators")
fn testSplitFirstByte -> Bool
  (do
    (assert (= (stringSplit "aab" "ab") (list "a" "")) "partial match then real match")
    (assert (= (stringSplit "a,,b" ",") (list "a" "" "b")) "adjacent single-byte separators")
    (assert (= (stringSplit "xaaby" "aab") (list "x" "y")) "separator after a first-byte prefix")
    (assert (= (stringSplit "aaa" "aa") (list "" "a")) "overlapping separator consumes left to right")
    (assert (= (stringSplit "ab" "ab") (list "" "")) "text equal to separator")
    (assert (= (stringSplit "a" "ab") (list "a")) "separator longer than text")
    (assert (= (stringSplit "xa" "ab") (list "xa")) "first byte at the very end without the rest")
    (assert (= (stringSplit "" ",") (list "")) "empty text")
    (assert (= (stringSplit "a\nb\n" "\n") (list "a" "b" "")) "trailing separator")
    true)

fn ! runTests -> Bool
  (do (assert (testRefKeys) "refKeys") (assert (testDefinedNames) "defined names") (assert (testSplitFirstByte) "split first byte") true)
