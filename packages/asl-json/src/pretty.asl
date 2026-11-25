(module asl-json/pretty
  :x [jsonPretty jsonCanonical]
  :i [(asl-json/json :a j)])

fn indentStr n: Int64 level: Int64 -> String
  (if (<= level 0) "" (stringRepeat " " (* n level)))

fn emitVal v: j/Json indent: Int64 level: Int64 -> String
  (match v
    ((j/jobj kvs)
      (if (listEmpty? kvs) "{}"
        (let [(inner (+ level 1))
              (pad (indentStr indent inner))
              (closePad (indentStr indent level))
              (parts (map (fn [(p (Pair String j/Json))] -> String
                           (str pad (j/jsonEmit (j/jstr (pairFirst p))) ": " (emitVal (pairSecond p) indent inner))) kvs))]
          (str "{\n" (stringJoin parts ",\n") "\n" closePad "}"))))
    ((j/jarr xs)
      (if (listEmpty? xs) "[]"
        (let [(inner (+ level 1))
              (pad (indentStr indent inner))
              (closePad (indentStr indent level))
              (parts (map (fn [(x j/Json)] -> String (str pad (emitVal x indent inner))) xs))]
          (str "[\n" (stringJoin parts ",\n") "\n" closePad "]"))))
    (_ (j/jsonEmit v)))

fn jsonPretty v: j/Json indent: Int64 -> String
  (emitVal v indent 0)

fn sortPairs kvs: (List (Pair String j/Json)) -> (List (Pair String j/Json))
  (listSortBy (fn [(p (Pair String j/Json))] -> String (pairFirst p)) kvs)

fn canonicalVal v: j/Json -> String
  (match v
    ((j/jobj kvs)
      (let [(sorted (sortPairs kvs))
            (parts (map (fn [(p (Pair String j/Json))] -> String
                         (str (j/jsonEmit (j/jstr (pairFirst p))) ":" (canonicalVal (pairSecond p)))) sorted))]
        (str "{" (stringJoin parts ",") "}")))
    ((j/jarr xs)
      (str "[" (stringJoin (map canonicalVal xs) ",") "]"))
    (_ (j/jsonEmit v)))

fn jsonCanonical v: j/Json -> String
  (canonicalVal v)
