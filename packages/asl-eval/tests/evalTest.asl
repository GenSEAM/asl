(module asl-eval/evalTest :x [runTests testEvalLiterals testEvalUnknownSymbol testClosureInvocation testModuleLoader!] :i [(eval :a ev)])

fn testEvalLiterals -> Bool
  (let [(env (ev/makeEvalEnv)) (rTrue (ev/evalNode env "true")) (rFalse (ev/evalNode env "false")) (rNum (ev/evalNode env "42"))] (assert rTrue.ok "eval true succeeds") (assert (= rTrue.value "true") "eval true returns true") (assert rFalse.ok "eval false succeeds") (assert (= rFalse.value "false") "eval false returns false") (assert rNum.ok "eval number succeeds") (assert (= rNum.value "42") "eval number returns 42") true)

fn testEvalUnknownSymbol -> Bool
  (let [(env (ev/makeEvalEnv)) (r (ev/evalNode env "undefined-identifier"))] (assert (not r.ok) "unknown symbol fails evaluation") (assert (= r.errCode "ERR_UNBOUND_SYMBOL") "unknown symbol produces ERR_UNBOUND_SYMBOL") true)

fn testClosureInvocation -> Bool
  (let [(env (ev/makeEvalEnv))
        (c (ev/Closure :params ["x"] :body "x" :env env))
        (r (ev/invokeClosure c ["arg1"]))
        (cArith (ev/Closure :params ["x"] :body "(+ x 5)" :env env))
        (rArith (ev/invokeClosure cArith ["10"]))
        (rArity (ev/invokeClosure c (list)))]
    (assert r.ok "closure invocation succeeds")
    (assert (= r.value "arg1") "closure argument binds to x and returns evaluated arg1")
    (refute (= r.value "x") "refutation: closure must evaluate bound parameter, not return symbol name x")
    (assert rArith.ok "closure with arithmetic body succeeds")
    (assert (= rArith.value "15") "closure evaluates (+ x 5) with x=10 to 15")
    (assert (not rArity.ok) "closure with insufficient arguments fails")
    (assert (= rArity.errCode "ERR_ARITY_MISMATCH") "arity mismatch produces ERR_ARITY_MISMATCH")
    true)

fn testModuleLoader! -> Bool
  (let [(rMissing (ev/loadModule! "non-existent" "non/existent/path.asl")) (rReal (ev/loadModule! "asl-eval" "asl/packages/asl-eval/src/eval.asl"))] (assert (not rMissing.ok) "missing module load fails") (assert (= rMissing.errCode "ERR_UNRESOLVED_IMPORT") "missing module produces ERR_UNRESOLVED_IMPORT") (assert rReal.ok "existing module load succeeds") (assert (= rReal.value "asl-eval") "existing module returns module name") true)

fn testEvalSExprArithmetic -> Bool
  (let [(env (ev/makeEvalEnv))
        (r (ev/evalNode env "(+ 10 20)"))
        (rNested (ev/evalNode env "(+ 10 (+ 20 30))"))]
    (assert r.ok "eval arithmetic s-expression succeeds")
    (assert (= r.value "30") "eval (+ 10 20) evaluates to 30")
    (assert rNested.ok "nested s-expression evaluation succeeds")
    (assert (= rNested.value "60") "eval (+ 10 (+ 20 30)) evaluates to 60")
    (refute (!= rNested.value "60") "nested s-expression refutes non-60")
    true)

fn ! runTests -> Bool
  (do (assert (testEvalLiterals) "test-eval-literals must pass") (assert (testEvalUnknownSymbol) "test-eval-unknown-symbol must pass") (assert (testClosureInvocation) "test-closure-invocation must pass") (assert (testModuleLoader!) "test-module-loader must pass") (assert (testEvalSExprArithmetic) "test-eval-sexpr-arithmetic must pass") true)
