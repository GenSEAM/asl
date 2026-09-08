(module asl-compiler/evaluator-test
  :d "Unit tests for 100% pure AgentScript evaluator engine."
  :x [test-eval-literals
      test-eval-arithmetic
      test-eval-comparison
      test-eval-logic
      test-eval-strings
      test-eval-env-binding
      test-eval-assert
      test-eval-if-branch
      run-tests]
  :i [(evaluator :a ev) (reader :a rd)])

(df test-eval-literals [] -> Bool
  :d "Verifies evaluation of integer, boolean, string, and null literals."
  (let [(env (ev/make-root-env))
        (v-int (ev/eval-sexpr (rd/make-atom "42") env))
        (v-true (ev/eval-sexpr (rd/make-atom "true") env))
        (v-false (ev/eval-sexpr (rd/make-atom "false") env))
        (v-null (ev/eval-sexpr (rd/make-atom "null") env))]
    (assert (mt v-int ((ev/val-int n) (= n 42)) (_ false)) "int literal")
    (assert (mt v-true ((ev/val-bool b) b) (_ false)) "true literal")
    (assert (mt v-false ((ev/val-bool b) (not b)) (_ false)) "false literal")
    (assert (mt v-null ((ev/val-null) true) (_ false)) "null literal")
    true))

(df test-eval-arithmetic [] -> Bool
  :d "Verifies evaluation of arithmetic builtins (+, -, *, /, mod)."
  (let [(env (ev/make-root-env))
        (add-expr (rd/make-list (list (rd/make-atom "+") (rd/make-atom "10") (rd/make-atom "20"))))
        (sub-expr (rd/make-list (list (rd/make-atom "-") (rd/make-atom "50") (rd/make-atom "15"))))
        (mul-expr (rd/make-list (list (rd/make-atom "*") (rd/make-atom "6") (rd/make-atom "7"))))
        (div-expr (rd/make-list (list (rd/make-atom "/") (rd/make-atom "100") (rd/make-atom "4"))))
        (mod-expr (rd/make-list (list (rd/make-atom "mod") (rd/make-atom "17") (rd/make-atom "5"))))
        (r-add (ev/eval-sexpr add-expr env))
        (r-sub (ev/eval-sexpr sub-expr env))
        (r-mul (ev/eval-sexpr mul-expr env))
        (r-div (ev/eval-sexpr div-expr env))
        (r-mod (ev/eval-sexpr mod-expr env))]
    (assert (mt r-add ((ev/val-int n) (= n 30)) (_ false)) "add")
    (assert (mt r-sub ((ev/val-int n) (= n 35)) (_ false)) "sub")
    (assert (mt r-mul ((ev/val-int n) (= n 42)) (_ false)) "mul")
    (assert (mt r-div ((ev/val-int n) (= n 25)) (_ false)) "div")
    (assert (mt r-mod ((ev/val-int n) (= n 2)) (_ false)) "mod")
    true))

(df test-eval-comparison [] -> Bool
  :d "Verifies evaluation of comparison operators (=, !=, <, >=)."
  (let [(env (ev/make-root-env))
        (eq-expr (rd/make-list (list (rd/make-atom "=") (rd/make-atom "5") (rd/make-atom "5"))))
        (neq-expr (rd/make-list (list (rd/make-atom "!=") (rd/make-atom "5") (rd/make-atom "6"))))
        (lt-expr (rd/make-list (list (rd/make-atom "<") (rd/make-atom "3") (rd/make-atom "8"))))
        (gte-expr (rd/make-list (list (rd/make-atom ">=") (rd/make-atom "10") (rd/make-atom "10"))))
        (r-eq (ev/eval-sexpr eq-expr env))
        (r-neq (ev/eval-sexpr neq-expr env))
        (r-lt (ev/eval-sexpr lt-expr env))
        (r-gte (ev/eval-sexpr gte-expr env))]
    (assert (mt r-eq ((ev/val-bool b) b) (_ false)) "eq")
    (assert (mt r-neq ((ev/val-bool b) b) (_ false)) "neq")
    (assert (mt r-lt ((ev/val-bool b) b) (_ false)) "lt")
    (assert (mt r-gte ((ev/val-bool b) b) (_ false)) "gte")
    true))

(df test-eval-logic [] -> Bool
  :d "Verifies evaluation of boolean logic builtins (and, or)."
  (let [(env (ev/make-root-env))
        (and-expr (rd/make-list (list (rd/make-atom "and") (rd/make-atom "true") (rd/make-atom "false"))))
        (or-expr (rd/make-list (list (rd/make-atom "or") (rd/make-atom "false") (rd/make-atom "true"))))
        (r-and (ev/eval-sexpr and-expr env))
        (r-or (ev/eval-sexpr or-expr env))]
    (assert (mt r-and ((ev/val-bool b) (not b)) (_ false)) "and")
    (assert (mt r-or ((ev/val-bool b) b) (_ false)) "or")
    true))

(df test-eval-strings [] -> Bool
  :d "Verifies evaluation of string operations (str-concat, str-len, str-contains?)."
  (let [(env (ev/make-root-env))
        (cat-expr (rd/make-list (list (rd/make-atom "str-concat") (rd/make-atom "\"hello \"") (rd/make-atom "\"world\""))))
        (len-expr (rd/make-list (list (rd/make-atom "str-len") (rd/make-atom "\"pipeline\""))))
        (cont-expr (rd/make-list (list (rd/make-atom "str-contains?") (rd/make-atom "\"runtime engine\"") (rd/make-atom "\"engine\""))))
        (r-cat (ev/eval-sexpr cat-expr env))
        (r-len (ev/eval-sexpr len-expr env))
        (r-cont (ev/eval-sexpr cont-expr env))]
    (assert (mt r-cat ((ev/val-str s) (= s "hello world")) (_ false)) "cat")
    (assert (mt r-len ((ev/val-int n) (= n 8)) (_ false)) "len")
    (assert (mt r-cont ((ev/val-bool b) b) (_ false)) "cont")
    true))

(df test-eval-env-binding [] -> Bool
  :d "Verifies environment binding creation and lexical lookup."
  (let [(root (ev/make-root-env))
        (b1 (ev/env-bind root "x" (ev/val-int 100)))
        (child (ev/make-child-env b1))
        (b2 (ev/env-bind child "y" (ev/val-int 200)))
        (look-x (ev/env-lookup b2 "x"))
        (look-y (ev/env-lookup b2 "y"))
        (look-z (ev/env-lookup b2 "z"))]
    (assert (mt look-x ((some (ev/val-int v)) (= v 100)) (_ false)) "lookup x")
    (assert (mt look-y ((some (ev/val-int v)) (= v 200)) (_ false)) "lookup y")
    (assert (mt look-z ((none) true) (_ false)) "lookup z none")
    true))

(df test-eval-assert [] -> Bool
  :d "Verifies falsifiable assertion semantics: truthy returns ok, falsy returns val-error."
  (let [(env (ev/make-root-env))
        (pass-expr (rd/make-list (list (rd/make-atom "assert") (rd/make-atom "true") (rd/make-atom "\"should pass\""))))
        (fail-expr (rd/make-list (list (rd/make-atom "assert") (rd/make-atom "false") (rd/make-atom "\"expected failure\""))))
        (r-pass (ev/eval-sexpr pass-expr env))
        (r-fail (ev/eval-sexpr fail-expr env))]
    (assert (ev/eval-result-is-ok? r-pass) "r-pass ok")
    (assert (not (ev/eval-result-is-ok? r-fail)) "r-fail not ok")
    (assert (mt r-fail ((ev/val-error msg) (= msg "expected failure")) (_ false)) "r-fail msg")
    true))

(df test-eval-if-branch [] -> Bool
  :d "Verifies branch selection in conditional if forms."
  (let [(env (ev/make-root-env))
        (then-expr (rd/make-list (list (rd/make-atom "if") (rd/make-atom "true") (rd/make-atom "1") (rd/make-atom "2"))))
        (else-expr (rd/make-list (list (rd/make-atom "if") (rd/make-atom "false") (rd/make-atom "1") (rd/make-atom "2"))))
        (r-then (ev/eval-sexpr then-expr env))
        (r-else (ev/eval-sexpr else-expr env))]
    (assert (mt r-then ((ev/val-int n) (= n 1)) (_ false)) "then branch")
    (assert (mt r-else ((ev/val-int n) (= n 2)) (_ false)) "else branch")
    true))

(df run-tests [] -> Bool
  :d "Runs all pure AgentScript evaluator engine test suites."
  (do
    (assert (test-eval-literals) "test-eval-literals must pass")
    (assert (test-eval-arithmetic) "test-eval-arithmetic must pass")
    (assert (test-eval-comparison) "test-eval-comparison must pass")
    (assert (test-eval-logic) "test-eval-logic must pass")
    (assert (test-eval-strings) "test-eval-strings must pass")
    (assert (test-eval-env-binding) "test-eval-env-binding must pass")
    (assert (test-eval-assert) "test-eval-assert must pass")
    (assert (test-eval-if-branch) "test-eval-if-branch must pass")
    true))
