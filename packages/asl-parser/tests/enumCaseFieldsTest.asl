(module asl-parser/enumCaseFieldsTest :x [runTests] :i [(asl-parser/ast :a ast)])

fn enumSrc -> Str
  "(module m :x [E] :i [])\n\n(enum E (:c one [(node Int64)] \"one field\") (:c two [(a Int64) (b Str)] \"two fields\") (:c none [] \"no fields\"))\n"

fn caseFieldNames forms: (List ast/TopForm) -> (List Str)
  (fold (fn [(acc (List Str)) (f ast/TopForm)] -> (List Str) (mt f ((ast/topEnum e) (listAppend acc (map (fn [(c ast/EnumCase)] -> Str (str c.name "(" (stringJoin (map (fn [(p ast/Param)] -> Str (str p.name ":" p.type)) c.fields) " ") ")")) e.cases))) (_ acc))) (list) forms)

fn fieldsOf src: Str -> (List Str)
  (mt (ast/parse src) ((ok forms) (caseFieldNames forms)) ((err pe) (list (str "parse error: " pe.msg))))

fn ! runTests -> Bool
  (let [(want (list "one(node:Int64)" "two(a:Int64 b:String)" "none()"))
        (sexprDialect (fieldsOf (enumSrc)))
        (fnDialect (fieldsOf (str (enumSrc) "\nfn f -> Int64\n  1\n")))]
    (do
      (assert (= sexprDialect want) (str "s-expression source: " (str sexprDialect)))
      (assert (= fnDialect want) (str "fn-dialect source: " (str fnDialect)))
      true))
