(module asl-parser/tests/asnValueTest
  :x [runTests]
  :i [(asl-parser/asnValue :a av)])

fn configText -> String
  "(config :name \"vt bot\" :count -3 :ratio 1.5 :path \"a\\\\b\\\"c\" :tags (\"x\" \"y\") (:m note \"kept\"))"

fn getOr row: av/AsnValue key: String -> av/AsnValue
  (optionOr (av/asnGet row key) (av/asnSym ""))

fn checkConfig -> Bool
  (match (av/asnParse (configText))
    ((ok forms)
     (let [(n (assert (= (listLength forms) 1) "one top-level form"))
           (row (optionOr (listHead forms) (av/asnSym "")))
           (a (assert (= (optionOr (av/asnText (getOr row ":name")) "") "vt bot") "string value"))
           (b (assert (= (optionOr (av/asnInt (getOr row ":count")) 0) (- 0 3)) "negative int"))
           (c (assert (= (optionOr (av/asnFloat (getOr row ":ratio")) 0.0) 1.5) "float value"))
           (d (assert (= (optionOr (av/asnText (getOr row ":path")) "") "a\\b\"c") "string escapes"))
           (e (assert (= (listLength (av/asnItems (getOr row ":tags"))) 2) "nested list"))
           (f (assert (= (optionOr (av/asnText (optionOr (listHead (av/asnItems (getOr row ":tags"))) (av/asnSym ""))) "") "x") "first tag"))
           (g (assert (= (listLength (av/asnItems (optionOr (listLast (av/asnItems row)) (av/asnSym "")))) 3) "comment form kept as list"))]
       true))
    ((err _) (let [(x (assert false "config should parse"))] true)))

fn checkMulti -> Bool
  (match (av/asnParse "(a 1) (b 2)")
    ((ok forms) (let [(x (assert (= (listLength forms) 2) "two top-level forms"))] true))
    ((err _) (let [(x (assert false "multi should parse"))] true)))

fn checkUnbalanced -> Bool
  (match (av/asnParse "(config :a 1")
    ((ok _) (let [(x (assert false "unbalanced input should fail"))] true))
    ((err e) (let [(x (assert (stringContains? e "position") "error names a position"))] true)))

fn checkStray -> Bool
  (match (av/asnParse ")")
    ((ok _) (let [(x (assert false "stray closer should fail"))] true))
    ((err e) (let [(x (assert (stringContains? e "position") "stray closer names a position"))] true)))

fn checkUnterminated -> Bool
  (match (av/asnParse "(a \"x)")
    ((ok _) (let [(x (assert false "unterminated string should fail"))] true))
    ((err e) (let [(x (assert (stringContains? e "position") "unterminated string names a position"))] true)))

fn checkGetSkipsValue -> Bool
  (match (av/asnParse "(:mode :fast :level 3)")
    ((ok forms)
     (let [(row (optionOr (listHead forms) (av/asnSym "")))
           (a (assert (none? (av/asnGet row ":fast")) "keyword value is not a key"))
           (b (assert (= (optionOr (av/asnInt (optionOr (av/asnGet row ":level") (av/asnSym ""))) 0) 3) "level found after skipping value"))]
       true))
    ((err _) (let [(x (assert false "row should parse"))] true)))

fn checkMismatch -> Bool
  (match (av/asnParse "([)]")
    ((ok _) (let [(x (assert false "mismatched closer should fail"))] true))
    ((err e) (let [(x (assert (stringContains? e "position") "mismatched closer names a position"))] true)))

fn checkGetMissingValue -> Bool
  (match (av/asnParse "(:a)")
    ((ok forms)
     (let [(row (optionOr (listHead forms) (av/asnSym "")))
           (x (assert (none? (av/asnGet row ":a")) "key with no value yields none"))]
       true))
    ((err _) (let [(x (assert false "row should parse"))] true)))

fn checkGetNonList -> Bool
  (let [(x (assert (none? (av/asnGet (av/asnSym "x") ":a")) "non-list row yields none"))]
    true)

fn runTests -> Bool
  (let [(a (checkConfig))
        (b (checkMulti))
        (c (checkUnbalanced))
        (d (checkStray))
        (e (checkUnterminated))
        (f (checkGetSkipsValue))
        (g (checkMismatch))
        (h (checkGetMissingValue))
        (i (checkGetNonList))]
    (and a (and b (and c (and d (and e (and f (and g (and h i)))))))))
