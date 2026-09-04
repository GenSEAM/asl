(module asl-codegen/expr-test
  :d "Unit tests for asl-codegen/expr"
  :x [test-expr]
  :i [(expr :a ex) (reader :a rd)])

(df test-expr [] -> String
  :d "Verifies expression and special forms emission."
  (let [(aliases (map-empty))
        (e1 (ex/emit-expr (rd/sexpr-atom "123") aliases))
        (e2 (ex/emit-expr (rd/sexpr-atom "\"hello\"") aliases))
        (e3 (ex/emit-expr (rd/sexpr-list (list (rd/sexpr-atom "+") (rd/sexpr-atom "1") (rd/sexpr-atom "2"))) aliases))
        (e4 (ex/emit-expr (rd/sexpr-list (list (rd/sexpr-atom "if") (rd/sexpr-atom "true") (rd/sexpr-atom "1") (rd/sexpr-atom "0"))) aliases))
        (b-pair (rd/sexpr-vect (list (rd/sexpr-atom "x") (rd/sexpr-atom "10"))))
        (bindings (rd/sexpr-vect (list b-pair)))
        (e5 (ex/emit-expr (rd/sexpr-list (list (rd/sexpr-atom "let") bindings (rd/sexpr-atom "x"))) aliases))
        (e6 (ex/emit-expr (rd/sexpr-list (list (rd/sexpr-atom "try") (rd/sexpr-atom "res"))) aliases))
        (e7 (ex/emit-expr (rd/sexpr-list (list (rd/sexpr-atom ".-first") (rd/sexpr-atom "p"))) aliases))]
    (cond
      ((not (= e1 "123")) "fail e1")
      ((not (= e2 "\"hello\".to_string()")) "fail e2")
      ((not (= e3 "rt::add(1, 2)")) "fail e3")
      ((not (= e4 "if true { 1 } else { 0 }")) "fail e4")
      ((not (= e5 "{ let x = 10; x }")) "fail e5")
      ((not (= e6 "(res.clone())?")) "fail e6")
      ((not (= e7 "p.clone().0.clone()")) "fail e7")
      (:else "ok"))))
