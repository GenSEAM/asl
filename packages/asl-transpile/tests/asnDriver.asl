(module asl-transpile/asnDriver :x [canon shape kinds verdict idem decodedField runTests] :i [(asn :a a) (asnCheck :a c)])

fn canon src: String -> String
  (mt (a/asnRead src) ((ok v) (a/asnWrite v)) ((err co) (str "!" co)))

fn idem src: String -> Bool
  (let [(once (canon src))] (= (canon once) once))

fn shapeOf v: a/AsnValue -> String
  (mt v ((a/asnNil) "nil") ((a/asnBool _) "bool") ((a/asnUnit) "unit") ((a/asnInt _) "int") ((a/asnFloat _) "float") ((a/asnStr _) "str") ((a/asnKw _) "kw") ((a/asnSym _) "sym") ((a/asnPair _ _) "pair") ((a/asnVec items) (str "vec/" (stringFromInt64 (listLength items)))) ((a/asnMap es) (str "map/" (stringFromInt64 (listLength es)))) ((a/asnRec fs) (str "rec/" (stringFromInt64 (listLength fs)))) ((a/asnCtor n fs) (str "ctor " n "/" (stringFromInt64 (listLength fs)))) ((a/asnRows n rows) (str "rows " n "/" (stringFromInt64 (listLength rows)))) ((a/asnCase n args) (str "case " n "/" (stringFromInt64 (listLength args)))) ((a/asnTable cs rs) (str "table/" (stringFromInt64 (listLength cs)) "x" (stringFromInt64 (listLength rs)))))

fn shape src: String -> String
  (mt (a/asnRead src) ((ok v) (shapeOf v)) ((err co) (str "!" co)))

fn kinds src: String -> String
  (mt (a/asnRead src) ((ok v) (stringJoin (map (fn [(x a/AsnValue)] -> String (shapeOf x)) (a/vecItems v)) "|")) ((err co) (str "!" co)))

fn verdict src: String -> String
  (mt (a/asnRead src) ((ok v) (c/diagCodes (c/asnCheck v))) ((err co) (str "!" co)))

fn decodedField src: String key: String -> String
  (mt (a/asnRead src) ((ok v) (fieldText v key)) ((err co) (str "!" co)))

fn fieldText v: a/AsnValue key: String -> String
  (mt v ((a/asnRec fs) (mt (listHead (filter (fn [(f a/AsnField)] -> Bool (= f.key key)) fs)) ((some f) (mt (a/asnStringValue f.val) ((some s) s) ((none) ""))) ((none) ""))) (_ ""))

fn runTests -> Bool
  (do
    (assert (idem "(:hello \"world\")") "canon should be idempotent")
    (assert (= (shape "(:a 1)") "rec/1") "shape should report rec/1")
    true)
