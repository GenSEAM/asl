(module asl-ir/tests/genericDispatchParityTest
  :x [runTests]
  :i [(asl-ir/lower :a low) (asl-checker/types :a cty)])

; (:m :ref NAMES-FIX :do "asl-ir/src/lower.asl used to carry its own hand-written copy (genericStar/genericKinded) of asl-checker/src/types.asl's genericRows/genericAlias dispatch table and could silently drift from it; lower.asl now delegates genericConcrete/genericAlias/genericMulti? to the checker's functions, so this suite pins every row through asl-ir/lower's exported surface and goes red if either package's table changes")

(schema KindRow (:f op String) (:f kind String) (:f concrete String))

fn kindRows -> (List KindRow)
  (list
    (KindRow :op "length" :kind "String" :concrete "stringLength") (KindRow :op "length" :kind "List" :concrete "listLength")
    (KindRow :op "length" :kind "Bytes" :concrete "bytesLength") (KindRow :op "length" :kind "Map" :concrete "mapSize")
    (KindRow :op "length" :kind "I64Array" :concrete "i64ArrayLen") (KindRow :op "length" :kind "I8Array" :concrete "i8ArrayLen")
    (KindRow :op "length" :kind "F64Array" :concrete "f64ArrayLen")
    (KindRow :op "empty?" :kind "String" :concrete "stringEmpty?") (KindRow :op "empty?" :kind "List" :concrete "listEmpty?")
    (KindRow :op "get" :kind "List" :concrete "listGet") (KindRow :op "get" :kind "Bytes" :concrete "bytesGet")
    (KindRow :op "get" :kind "Map" :concrete "mapGet") (KindRow :op "get" :kind "I64Array" :concrete "i64ArrayGet")
    (KindRow :op "get" :kind "I8Array" :concrete "i8ArrayGet") (KindRow :op "get" :kind "F64Array" :concrete "f64ArrayGet")
    (KindRow :op "set" :kind "Bytes" :concrete "bytesSet") (KindRow :op "set" :kind "Map" :concrete "mapSet")
    (KindRow :op "slice" :kind "String" :concrete "stringSlice") (KindRow :op "slice" :kind "List" :concrete "listSlice")
    (KindRow :op "slice" :kind "I64Array" :concrete "i64ArraySlice") (KindRow :op "slice" :kind "I8Array" :concrete "i8ArraySlice")
    (KindRow :op "slice" :kind "F64Array" :concrete "f64ArraySlice")
    (KindRow :op "contains?" :kind "String" :concrete "stringContains?") (KindRow :op "contains?" :kind "List" :concrete "listContains?")
    (KindRow :op "contains?" :kind "Map" :concrete "mapHas?")
    (KindRow :op "indexOf" :kind "String" :concrete "stringIndexOf") (KindRow :op "indexOf" :kind "List" :concrete "listIndexOf")
    (KindRow :op "reverse" :kind "String" :concrete "stringReverse") (KindRow :op "reverse" :kind "List" :concrete "listReverse")
    (KindRow :op "append" :kind "String" :concrete "stringConcat") (KindRow :op "append" :kind "List" :concrete "listAppend")
    (KindRow :op "sum" :kind "List" :concrete "listSum") (KindRow :op "sum" :kind "I64Array" :concrete "i64ArraySum")
    (KindRow :op "sum" :kind "I8Array" :concrete "i8ArraySum") (KindRow :op "sum" :kind "F64Array" :concrete "f64ArraySum")
    (KindRow :op "countEq" :kind "I64Array" :concrete "i64ArrayCountEq") (KindRow :op "countEq" :kind "I8Array" :concrete "i8ArrayCountEq")
    (KindRow :op "countEq" :kind "F64Array" :concrete "f64ArrayCountEq"))

fn aliasRows -> (List (Pair String String))
  (list
    (pair "head" "listHead") (pair "tail" "listTail") (pair "last" "listLast") (pair "take" "listTake") (pair "drop" "listDrop")
    (pair "all?" "listAll?") (pair "any?" "listAny?") (pair "sort" "listSort") (pair "sortBy" "listSortBy")
    (pair "startsWith?" "stringStartsWith?") (pair "endsWith?" "stringEndsWith?") (pair "split" "stringSplit") (pair "join" "stringJoin")
    (pair "replace" "stringReplace") (pair "trim" "stringTrim") (pair "chars" "stringChars") (pair "lines" "stringLines")
    (pair "upper" "stringUpper") (pair "lower" "stringLower") (pair "repeat" "stringRepeat") (pair "countChar" "stringCountChar")
    (pair "keys" "mapKeys") (pair "values" "mapValues") (pair "pairs" "mapPairs") (pair "remove" "mapRemove")
    (pair "getFloat64" "bytesGetFloat64") (pair "setFloat64" "bytesSetFloat64") (pair "sha256" "bytesSha256"))

fn multiOps -> (List String)
  (list "length" "empty?" "get" "set" "slice" "contains?" "indexOf" "reverse" "append" "sum" "countEq")

fn checkKindRow! r: KindRow -> Bool
  (do
    (assert (= (low/genericConcrete r.op r.kind) r.concrete) (str "low/genericConcrete " r.op " " r.kind " -> " r.concrete))
    (assert (= (cty/genericConcrete r.op r.kind) r.concrete) (str "cty/genericConcrete " r.op " " r.kind " -> " r.concrete))
    true)

fn checkAliasRow! r: (Pair String String) -> Bool
  (let [(name (pairFirst r)) (concrete (pairSecond r))]
    (do
      (assert (= (low/genericAlias name) concrete) (str "low/genericAlias " name " -> " concrete))
      (assert (= (cty/genericAlias name) concrete) (str "cty/genericAlias " name " -> " concrete))
      (assert (= (low/genericConcrete name "*") concrete) (str "low/genericConcrete " name " \"*\" -> " concrete))
      true))

fn checkMultiOp! name: String -> Bool
  (do
    (assert (low/genericMulti? name) (str name " is a multi-receiver generic op in asl-ir"))
    (assert (cty/genericMulti? name) (str name " is a multi-receiver generic op in asl-checker"))
    true)

fn ! runTests -> Bool
  (do
    (assert (listAll? checkKindRow! (kindRows)) "every multi-receiver row agrees between asl-ir/lower and asl-checker/types")
    (assert (listAll? checkAliasRow! (aliasRows)) "every single-receiver alias agrees between asl-ir/lower and asl-checker/types")
    (assert (listAll? checkMultiOp! (multiOps)) "every multi-receiver op name is recognized by both packages")
    (assert (not (low/genericMulti? "head")) "an alias name is not a multi-receiver op")
    (assert (not (cty/genericMulti? "head")) "an alias name is not a multi-receiver op (checker side)")
    (assert (= (low/genericConcrete "length" "Keyword") "") "an out-of-set receiver kind has no concrete name")
    (assert (= (low/genericAlias "totallyNotAGenericName") "") "an unrelated name is not an alias")
    true)
