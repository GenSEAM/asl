(module prelude/tests/stringSplitTest :x [runTests] :i [])

; (:m :ref TEXTPASS :do "stringSplit against a reference built from stringIndexOf and stringSlice: every string over {a,b} up to length 7 and the multi-byte alphabet, against separators that overlap themselves, equal the whole string, are longer than it, or sit at either end")
fn refSplit s: String sep: String -> (List String)
  (match (stringIndexOf s sep)
    ((none) (list s))
    ((some i) (cons (optionOr (stringSlice s 0 i) "")
                    (refSplit (optionOr (stringSlice s (+ i (stringLength sep)) (stringLength s)) "") sep))))

fn extend ws: (List String) alphabet: (List String) -> (List String)
  (fold (fn [(acc (List String)) (w String)] -> (List String) (listAppend acc (map (fn [(c String)] -> String (stringConcat w c)) alphabet))) (list) ws)

fn wordsUpTo alphabet: (List String) depth: Int64 level: (List String) acc: (List String) -> (List String)
  (if (= depth 0) acc
    (let [(next (extend level alphabet))]
      (wordsUpTo alphabet (- depth 1) next (listAppend acc next))))

fn seps -> (List String)
  (list "a" "b" "aa" "ab" "ba" "aba" "bab" "aab" "abab" "aaaa" "abababa" "aaaaaaaa")

fn runDepth alphabet: (List String) depth: Int64 -> Bool
  (let [(words (cons "" (wordsUpTo alphabet depth (list "") (list))))]
    (listAll? (fn [(w String)] -> Bool (listAll? (fn [(p String)] -> Bool (= (stringSplit w p) (refSplit w p))) (seps))) words))

fn runTests -> Bool
  (do
    (assert (= (stringSplit "a,b,,c," ",") (list "a" "b" "" "c" "")) "empty fields and a trailing separator are kept")
    (assert (= (stringSplit "" ",") (list "")) "the empty string splits into one empty field")
    (assert (= (stringSplit "aaaa" "aa") (list "" "" "")) "matches do not overlap")
    (assert (= (stringSplit "abc" "abcd") (list "abc")) "a separator longer than the text finds nothing")
    (assert (= (stringSplit "xé→y" "é→") (list "x" "y")) "multibyte separators match bytewise")
    (assert (= (stringSplit "ab" "b") (list "a" "")) "a match in the last byte is found")
    (assert (runDepth (list "a" "b") 7) "every a/b string up to length 7 splits like the reference")
    (assert (runDepth (list "a" "é") 5) "strings mixing ASCII and multibyte characters split like the reference")
    true)
