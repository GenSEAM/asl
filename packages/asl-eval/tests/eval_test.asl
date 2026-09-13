(module asl-eval/eval-test
  :d "Unit test suite for the pure ASL AST evaluator."
  :x [run-tests
      test-eval-literals
      test-eval-unknown-symbol
      test-closure-invocation
      test-module-loader]
  :i [(eval :a ev)])

(df test-eval-literals [] -> Bool
  :d "Verifies evaluation of primitive literals."
  (let [(env (ev/make-eval-env))
        (r-true (ev/eval-node env "true"))
        (r-false (ev/eval-node env "false"))
        (r-num (ev/eval-node env "42"))]
    (assert (.-ok r-true) "eval true succeeds")
    (assert (= (.-value r-true) "true") "eval true returns true")
    (assert (.-ok r-false) "eval false succeeds")
    (assert (= (.-value r-false) "false") "eval false returns false")
    (assert (.-ok r-num) "eval number succeeds")
    (assert (= (.-value r-num) "42") "eval number returns 42")
    true))

(df test-eval-unknown-symbol [] -> Bool
  :d "Verifies that unknown symbol returns ERR_UNBOUND_SYMBOL."
  (let [(env (ev/make-eval-env))
        (r (ev/eval-node env "undefined-identifier"))]
    (assert (not (.-ok r)) "unknown symbol fails evaluation")
    (assert (= (.-err-code r) "ERR_UNBOUND_SYMBOL") "unknown symbol produces ERR_UNBOUND_SYMBOL")
    true))

(df test-closure-invocation [] -> Bool
  :d "Verifies closure creation and invocation."
  (let [(env (ev/make-eval-env))
        (c (ev/Closure :params ["x"] :body "x" :env env))
        (r (ev/invoke-closure c ["arg1"]))]
    (assert (.-ok r) "closure invocation succeeds")
    (assert (= (.-value r) "x") "closure body returned")
    true))

(df test-module-loader [] -> Bool
  :d "Verifies module loading and resolution error handling."
  (let [(r-missing (ev/load-module "non-existent" "non/existent/path.asl"))
        (r-real (ev/load-module "asl-eval" "asl/packages/asl-eval/src/eval.asl"))]
    (assert (not (.-ok r-missing)) "missing module load fails")
    (assert (= (.-err-code r-missing) "ERR_UNRESOLVED_IMPORT") "missing module produces ERR_UNRESOLVED_IMPORT")
    (assert (.-ok r-real) "existing module load succeeds")
    (assert (= (.-value r-real) "asl-eval") "existing module returns module name")
    true))

(df run-tests [] -> Bool
  :d "Executes all unit tests for asl-eval."
  (do
    (assert (test-eval-literals) "test-eval-literals must pass")
    (assert (test-eval-unknown-symbol) "test-eval-unknown-symbol must pass")
    (assert (test-closure-invocation) "test-closure-invocation must pass")
    (assert (test-module-loader) "test-module-loader must pass")
    true))
