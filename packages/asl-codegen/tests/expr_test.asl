(module asl-codegen/expr-test
  :d "Unit tests for asl-codegen/expr"
  :x [test-expr run-tests]
  :i [(expr :a ex) (reader :a rd)])

(df test-expr [] -> Bool
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
    (assert (= e1 "123") "e1 atom")
    (assert (= e2 "\"hello\".to_string()") "e2 string")
    (assert (= e3 "rt::add(1, 2)") "e3 add")
    (assert (= e4 "if true { 1 } else { 0 }") "e4 if")
    (assert (= e5 "{ let x = 10; x }") "e5 let")
    (assert (= e6 "(res)?") "e6 try")
    (assert (= e7 "p.clone().0.clone()") "e7 .-first")
    true))

(df run-tests [] -> Bool
  :d "Runs expr test suite"
  (do
    (assert (test-expr) "test-expr must pass")
    true))
