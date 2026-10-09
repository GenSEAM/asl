(module asl-checker/dialectTest :x [runTests] :i [(types :a ty) (ast :a a) (resolve :a r) (check :a c)])

fn libSrc -> Str
  "(module p/lib :x [R mkR] :i [])\n\n(schema R (:f x Int64 \"x\") (:f y Str \"y\"))\n\nfn mkR n: Int64 -> R\n  (R :x n :y \"lib\")\n"

fn libDeps -> (Map Str r/ModuleSummary)
  (mt (a/parse (libSrc)) ((ok forms) (mapSet (mapEmpty) "p/lib" (r/collectSummary forms "p/lib.asl"))) ((err _) (mapEmpty)))

fn modSrc body: Str -> Str
  (str "(module m :x [] :i [(p/lib :a l)])\n\n(schema Loc (:f n Int64 \"n\") (:f s Str \"s\"))\n\n" body)

fn diagsOf body: Str -> (List ty/Diagnostic)
  (c/checkSource (modSrc body) (libDeps) "m.asl")

fn showDiags ds: (List ty/Diagnostic) -> Str
  (stringJoin (map (fn [(d ty/Diagnostic)] -> Str (str (stringFromInt64 d.line) ":" (stringFromInt64 d.col) " [" d.code "] " d.message)) ds) "; ")

fn found ds: (List ty/Diagnostic) code: Str needle: Str -> (Option ty/Diagnostic)
  (listHead (filter (fn [(d ty/Diagnostic)] -> Bool (and (= d.code code) (stringContains? d.message needle))) ds))

fn cascade? ds: (List ty/Diagnostic) -> Bool
  (listAny? (fn [(d ty/Diagnostic)] -> Bool (or (stringContains? d.message "unbound symbol: :") (or (= d.message "unbound symbol: ") (or (= d.message "do is not defined") (= d.message "else is not defined"))))) ds)

fn clean? body: Str label: Str -> Bool
  (let [(ds (diagsOf body))] (do (assert (listEmpty? ds) (str label " is accepted; got " (showDiags ds))) true))

fn rejectedAt? body: Str code: Str needle: Str line: Int64 label: Str -> Bool
  (let [(ds (diagsOf body))]
    (mt (found ds code needle)
      ((none) (do (assert false (str label ": no [" code "] " needle "; got " (showDiags ds))) false))
      ((some d) (do (assert (= d.line line) (str label ": diagnostic at the body form's line " (stringFromInt64 line) "; got " (showDiags ds))) (refute (cascade? ds) (str label ": no cascade from dialect forms; got " (showDiags ds))) true))))

fn ! runTests -> Bool
  (do
    (clean? "fn f -> Loc\n  (Loc :n 1 :s \"a\")\n" "local record constructor")
    (rejectedAt? "fn f -> Loc\n  (Loc :n 1 :z \"a\")\n" "ctor" "Loc has no field z" 6 "wrong field name in a local record constructor")
    (rejectedAt? "fn f -> Loc\n  (Loc :n \"one\" :s \"a\")\n" "type" "field n of Loc" 6 "wrong field type in a local record constructor")
    (clean? "fn f -> l/R\n  (l/R :x 1 :y \"b\")\n" "record constructor through an import alias")
    (rejectedAt? "fn f -> l/R\n  (l/R :x \"one\" :y \"b\")\n" "type" "field x of R" 6 "wrong field type through an import alias")
    (clean? "fn f r: l/R -> Int64\n  (+ r.x (l/mkR 2).x)\n" "field of an imported record type")
    (rejectedAt? "fn f r: l/R -> Int64\n  r.z\n" "type" "has no field z" 6 "unknown field of an imported record type")
    (rejectedAt? "fn f r: l/Nope -> Int64\n  1\n" "rule-9" "Nope is not an exported type of p/lib" 6 "unknown qualified type")
    (clean? "fn ! f -> Unit\n  (do (println \"a\") ())\n" "Unit return with do")
    (rejectedAt? "fn f u: Unit -> Int64\n  u.n\n" "type" "Unit is not a record, so it has no field n" 6 "field of Unit")
    (clean? "fn f -> Int64\n  (do)\n  (do 1 2)\n  3\n" "do of any arity")
    (rejectedAt? "fn f -> Int64\n  1\n  (do (undefinedProbe 1) 2)\n" "rule-2" "undefinedProbe is not defined" 7 "undefined call inside do, second body form")
    (clean? "fn f x: Int64 -> Str\n  (cond ((= x 1) \"one\") (else \"other\"))\n" "else in cond")
    (rejectedAt? "fn f x: Int64 -> Str\n  (cond ((= x 1) \"one\") (else 2))\n" "type" "cond else clause" 6 "else clause of the wrong type")
    (clean? "fn f xs: (List Int64) -> (List Int64)\n  (let [(k 1) (g (fn [y] y))] (map (fn [(x Int64)] -> Int64 (+ x k)) xs))\n" "let bindings, annotated and bare lambdas")
    (rejectedAt? "fn f xs: (List Int64) -> (List Str)\n  (let [(k \"s\")] (map (fn [(x Str)] -> Str (str x k)) xs))\n" "type" "argument to map" 6 "lambda of the wrong parameter type")
    (clean? "fn f p: (Pair Int64 Str) -> Str\n  (str (stringFromInt64 (pairFirst p)) (pairSecond p))\n" "pairFirst and pairSecond")
    (rejectedAt? "fn f p: (Pair Int64 Str) -> Int64\n  (pairSecond p)\n" "type" "return of f" 6 "pairSecond of the wrong type")
    true)
