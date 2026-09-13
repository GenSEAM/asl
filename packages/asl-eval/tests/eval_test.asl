(module asl-eval/evalTest
  :d "Unit test suite for the pure ASL AST evaluator."
  :x [runTests
      testEvalLiterals
      testEvalUnknownSymbol
      testClosureInvocation
      testModuleLoader]
  :i [(eval :a ev)])

(df testEvalLiterals [] -> Bool
  :d "Verifies evaluation of primitive literals."
  (let [(env (ev/makeEvalEnv))
        (rTrue (ev/evalNode env "true"))
        (rFalse (ev/evalNode env "false"))
        (rNum (ev/evalNode env "42"))]
    (assert (.-ok rTrue) "eval true succeeds")
    (assert (= (.-value rTrue) "true") "eval true returns true")
    (assert (.-ok rFalse) "eval false succeeds")
    (assert (= (.-value rFalse) "false") "eval false returns false")
    (assert (.-ok rNum) "eval number succeeds")
    (assert (= (.-value rNum) "42") "eval number returns 42")
    true))

(df testEvalUnknownSymbol [] -> Bool
  :d "Verifies that unknown symbol returns ERR_UNBOUND_SYMBOL."
  (let [(env (ev/makeEvalEnv))
        (r (ev/evalNode env "undefined-identifier"))]
    (assert (not (.-ok r)) "unknown symbol fails evaluation")
    (assert (= (.-errCode r) "ERR_UNBOUND_SYMBOL") "unknown symbol produces ERR_UNBOUND_SYMBOL")
    true))

(df testClosureInvocation [] -> Bool
  :d "Verifies closure creation and invocation."
  (let [(env (ev/makeEvalEnv))
        (c (ev/Closure :params ["x"] :body "x" :env env))
        (r (ev/invokeClosure c ["arg1"]))]
    (assert (.-ok r) "closure invocation succeeds")
    (assert (= (.-value r) "x") "closure body returned")
    true))

(df testModuleLoader [] -> Bool
  :d "Verifies module loading and resolution error handling."
  (let [(rMissing (ev/loadModule "non-existent" "non/existent/path.asl"))
        (rReal (ev/loadModule "asl-eval" "asl/packages/asl-eval/src/eval.asl"))]
    (assert (not (.-ok rMissing)) "missing module load fails")
    (assert (= (.-errCode rMissing) "ERR_UNRESOLVED_IMPORT") "missing module produces ERR_UNRESOLVED_IMPORT")
    (assert (.-ok rReal) "existing module load succeeds")
    (assert (= (.-value rReal) "asl-eval") "existing module returns module name")
    true))

(df runTests [] -> Bool
  :d "Executes all unit tests for asl-eval."
  (do
    (assert (testEvalLiterals) "test-eval-literals must pass")
    (assert (testEvalUnknownSymbol) "test-eval-unknown-symbol must pass")
    (assert (testClosureInvocation) "test-closure-invocation must pass")
    (assert (testModuleLoader) "test-module-loader must pass")
    true))
