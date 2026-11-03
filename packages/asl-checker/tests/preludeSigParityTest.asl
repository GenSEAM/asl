(module asl-checker/tests/preludeSigParityTest
  :x [runTests]
  :i [(asl-parser/ast :a a) (asl-checker/types :a ty)])

; (:m :ref SCRIPT-ENTRY :do "the checker types prelude calls from its own table (types.asl) while prelude.asl declares them again; every prelude fn the table knows must carry the same parameter and return types in both, and the documented argInt/argStr rows in prelude.asn must match their declarations, so the copies cannot drift")
fn paramTypes d: a/DefunNode -> (List String)
  (map (fn [(p a/Param)] -> String p.type) d.params)

; (:m :ref LL-SIZED-CHECK :do "the bit operators are typed over any integral type in types.asl (I and J are integer-kind variables) while prelude.asl declares them over Int64; the two agree when every integer-kind variable is read as Int64")
fn asInt64 t: String -> String
  (if (or (= t "I") (= t "J")) "Int64" (if (= t "(Option I)") "(Option Int64)" t))

fn mismatch d: a/DefunNode -> String
  (match (ty/builtinSig d.name)
    ((none) "")
    ((some sg) (if (and (= (paramTypes d) (map asInt64 (pairFirst sg))) (= d.retType (asInt64 (pairSecond (pairSecond sg)))))
                 ""
                 (str d.name ": prelude.asl " (stringJoin (paramTypes d) " ") " -> " d.retType ", types.asl " (stringJoin (pairFirst sg) " ") " -> " (pairSecond (pairSecond sg))))))

fn defuns forms: (List a/TopForm) -> (List a/DefunNode)
  (listFlatMap (fn [(t a/TopForm)] -> (List a/DefunNode) (match t ((a/topDefun d) (list d)) (_ (list)))) forms)

fn typed? d: a/DefunNode -> Bool
  (some? (ty/builtinSig d.name))

fn docType d: a/DefunNode -> String
  (str (stringJoin (paramTypes d) " ") " -> " d.retType)

fn docRow? doc: String d: a/DefunNode -> Bool
  (stringContains? doc (str "(:name \"" d.name "\" :sec \"String\" :type \"" (docType d) "\" :src \"asl/prelude/prelude.asl\""))

fn named ds: (List a/DefunNode) name: String -> (List a/DefunNode)
  (filter (fn [(d a/DefunNode)] -> Bool (= d.name name)) ds)

fn ! runTests -> Bool
  (match (fileReadString "asl/prelude/prelude.asl")
    ((err e) (do (assert false (str "prelude.asl is readable: " e)) false))
    ((ok src) (match (a/parse src)
                ((err e) (do (assert false (str "prelude.asl parses: " e.msg)) false))
                ((ok forms) (let [(ds (defuns forms))
                                  (known (filter typed? ds))
                                  (bad (filter (fn [(m String)] -> Bool (not (stringEmpty? m))) (map mismatch known)))
                                  (doc (resultOr (fileReadString "asl/prelude/prelude.asn") ""))]
                              (do (assert (> (listLength known) 100) (str "the checker table types most prelude fns: " (listLength known)))
                                  (assert (listEmpty? bad) (str "prelude.asl and types.asl agree on every shared signature: " (stringJoin bad "; ")))
                                  (assert (listAll? (fn [(n String)] -> Bool (= (listLength (filter typed? (named ds n))) 1)) (list "argInt" "argStr" "preludeMainDone" "preludeScriptFail")) "argInt, argStr and the main hooks are each declared once and typed by the table")
                                  (assert (listAll? (fn [(d a/DefunNode)] -> Bool (docRow? doc d)) (listFlatMap (fn [(n String)] -> (List a/DefunNode) (named ds n)) (list "argInt" "argStr"))) "the prelude.asn rows of argInt and argStr carry their declared types")
                                  true))))))
