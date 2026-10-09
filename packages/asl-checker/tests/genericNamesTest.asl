(module asl-checker/genericNamesTest :x [runTests] :i [(check :a c) (types :a ty)])

fn probe body: String sig: String -> (List ty/Diagnostic)
  (c/checkSource (str "(module probe :x [f]) (fn f " sig " " body ")") (mapEmpty) "genericNamesProbe.asl")

fn codes ds: (List ty/Diagnostic) -> (List String)
  (map (fn [(d ty/Diagnostic)] -> String d.code) ds)

fn text ds: (List ty/Diagnostic) -> String
  (stringJoin (map (fn [(d ty/Diagnostic)] -> String (str d.code " " d.message)) ds) "; ")

fn ! runTests -> Bool
  (let [(onString (probe "(length s)" "[(s String)] -> Int64"))
        (onList (probe "(length xs)" "[(xs (List Int64))] -> Int64"))
        (onBytes (probe "(get b 0)" "[(b Bytes)] -> Int64"))
        (listGet (probe "(get xs 0)" "[(xs (List String))] -> (Option String)"))
        (wrongResult (probe "(get xs 0)" "[(xs (List String))] -> Int64"))
        (late (probe "(let [ys (list)] (do (length ys) (append ys (list \"a\"))))" "[] -> (List String)"))
        (ambiguous (probe "(let [f (fn [x] (length x))] 0)" "[] -> Int64"))
        (appliedLater (probe "((fn [x] (length x)) \"abc\")" "[] -> Int64"))
        (outside (probe "(length n)" "[(n Int64)] -> Int64"))
        (single (probe "(head xs)" "[(xs (List Int64))] -> (Option Int64)"))]
    (do
      (assert (listEmpty? onString) (str "length over a String resolves to stringLength: " (text onString)))
      (assert (listEmpty? onList) (str "length over a List resolves to listLength: " (text onList)))
      (assert (listEmpty? onBytes) (str "get over Bytes resolves to bytesGet returning Int64: " (text onBytes)))
      (assert (listEmpty? listGet) (str "get over a List returns the element Option: " (text listGet)))
      (assert (stringContains? (text wrongResult) "Option") (str "the resolved overload's result type is checked: " (text wrongResult)))
      (assert (listEmpty? late) (str "a receiver resolved later in the function is checked at its end: " (text late)))
      (assert (listContains? (codes ambiguous) "ERR_AMBIGUOUS_OVERLOAD") (str "a receiver still a type variable is ambiguous: " (text ambiguous)))
      (assert (stringContains? (text ambiguous) "candidates String, List, Bytes, Map, I64Array, I8Array, F64Array; annotate the receiver") (str "the ambiguity names the candidates: " (text ambiguous)))
      (assert (listEmpty? appliedLater) (str "a lambda parameter typed by its later application resolves: " (text appliedLater)))
      (assert (stringContains? (text outside) "argument 1 of length: expected one of String, List") (str "a known receiver outside the rows names the candidates: " (text outside)))
      (assert (listEmpty? single) (str "a one-type name resolves without a receiver check: " (text single)))
      (assert (= (ty/renamedHint "stringLength") "; renamed to length (D159)") "a retired multi-type name hints its generic name")
      (assert (= (ty/renamedHint "listHead") "; renamed to head (D159)") "a retired one-type name hints its generic name")
      (assert (= (ty/renamedHint "stringFromInt64") "") "a conversion keeps its name and has no hint")
      true))
