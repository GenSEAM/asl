(module asl-eval :x [EvalResult EvalEnv Closure evalNode invokeClosure loadModule! makeEvalEnv evalArithmetic clamp] :i [])

(schema EvalResult (:f value Str) (:f ok Bool) (:f errCode Str))

(schema EvalEnv (:f bindings [Str]) (:f values [Str]) (:f parentId Str))

(schema Closure (:f params [Str]) (:f body Str) (:f env EvalEnv))

fn makeEvalEnv -> EvalEnv
  (EvalEnv :bindings [] :values [] :parentId "root")

(schema SplitScanState
  (:f acc (List Str))
  (:f cur Str)
  (:f depth Int64))

fn splitSExprTokens text: Str -> (List Str)
  (let [(chars (stringChars text))
        (init (SplitScanState :acc (list) :cur "" :depth 0))
        (finalSt (fold (fn [(st SplitScanState) (ch Str)]
                         (if (= ch "(")
                           (SplitScanState
                             :acc st.acc
                             :cur (str st.cur ch)
                             :depth (+ st.depth 1))
                           (if (= ch ")")
                             (SplitScanState
                               :acc st.acc
                               :cur (str st.cur ch)
                               :depth (- st.depth 1))
                             (if (and (= st.depth 0) (or (= ch " ") (or (= ch "\t") (= ch "\n"))))
                               (if (stringEmpty? st.cur)
                                 st
                                 (SplitScanState
                                   :acc (listAppend st.acc (list st.cur))
                                   :cur ""
                                   :depth 0))
                               (SplitScanState
                                 :acc st.acc
                                 :cur (str st.cur ch)
                                 :depth st.depth)))))
                       init
                       chars))]
    (if (stringEmpty? finalSt.cur)
      finalSt.acc
      (listAppend finalSt.acc (list finalSt.cur))))

fn evalSExpr env: EvalEnv node: Str -> EvalResult
  (let [(slen (stringLength node))]
    (if (or (< slen 2) (not (stringEndsWith? node ")")))
      (EvalResult :value "list" :ok true :errCode "")
      (let [(inner (stringTrim (optionOr (stringSlice node 1 (- slen 1)) "")))
            (parts (splitSExprTokens inner))]
        (if (< (listLength parts) 3)
          (EvalResult :value "list" :ok true :errCode "")
          (let [(op (optionOr (listGet parts 0) ""))
                (arg1Res (evalNode env (optionOr (listGet parts 1) "")))
                (arg2Res (evalNode env (optionOr (listGet parts 2) "")))]
            (if (or (not arg1Res.ok) (not arg2Res.ok))
              (EvalResult :value "" :ok false :errCode (if (not arg1Res.ok) arg1Res.errCode arg2Res.errCode))
              (let [(optN1 (stringToInt64 arg1Res.value))
                    (optN2 (stringToInt64 arg2Res.value))]
                (if (or (none? optN1) (none? optN2))
                  (EvalResult :value "list" :ok true :errCode "")
                  (let [(n1 (optionOr optN1 0))
                        (n2 (optionOr optN2 0))]
                    (cond
                      ((= op "+") (EvalResult :value (stringFromInt64 (+ n1 n2)) :ok true :errCode ""))
                      ((= op "-") (EvalResult :value (stringFromInt64 (- n1 n2)) :ok true :errCode ""))
                      ((= op "*") (EvalResult :value (stringFromInt64 (* n1 n2)) :ok true :errCode ""))
                      ((= op "/") (if (= n2 0) (EvalResult :value "" :ok false :errCode "ERR_DIV_BY_ZERO") (EvalResult :value (stringFromInt64 (/ n1 n2)) :ok true :errCode "")))
                      ((= op "mod") (if (= n2 0) (EvalResult :value "" :ok false :errCode "ERR_DIV_BY_ZERO") (EvalResult :value (stringFromInt64 (mod n1 n2)) :ok true :errCode "")))
                      (else (EvalResult :value "list" :ok true :errCode ""))))))))))))

fn evalNode env: EvalEnv node: Str -> EvalResult
  (if (stringEmpty? node) (EvalResult :value "" :ok true :errCode "") (if (= node "true") (EvalResult :value "true" :ok true :errCode "") (if (= node "false") (EvalResult :value "false" :ok true :errCode "") (if (or (stringStartsWith? node "\"") (stringStartsWith? node "'")) (EvalResult :value node :ok true :errCode "") (if (stringStartsWith? node "(") (evalSExpr env node) (if (or (stringStartsWith? node "0") (or (stringStartsWith? node "1") (or (stringStartsWith? node "2") (or (stringStartsWith? node "3") (or (stringStartsWith? node "4") (or (stringStartsWith? node "5") (or (stringStartsWith? node "6") (or (stringStartsWith? node "7") (or (stringStartsWith? node "8") (stringStartsWith? node "9")))))))))) (EvalResult :value node :ok true :errCode "") (mt (listIndexOf env.bindings node) ((some idx) (EvalResult :value (optionOr (listGet env.values idx) "") :ok true :errCode "")) ((none) (EvalResult :value "" :ok false :errCode "ERR_UNBOUND_SYMBOL")))))))))

fn invokeClosure c: Closure args: [Str] -> EvalResult
  (if (< (listLength args) (listLength c.params))
    (EvalResult :value "" :ok false :errCode "ERR_ARITY_MISMATCH")
    (let [(parentEnv c.env)
          (childEnv (EvalEnv
                      :bindings (listAppend parentEnv.bindings c.params)
                      :values (listAppend parentEnv.values args)
                      :parentId "closure"))]
      (evalNode childEnv c.body)))

fn loadModule! modName: Str path: Str -> EvalResult
  (if (not (fileExists? path)) (EvalResult :value "" :ok false :errCode "ERR_UNRESOLVED_IMPORT") (mt (fileRead path) ((err _) (EvalResult :value "" :ok false :errCode "ERR_UNRESOLVED_IMPORT")) ((ok src) (if (not (stringContains? src (str "module " modName))) (EvalResult :value "" :ok false :errCode "ERR_MODULE_NAME_MISMATCH") (EvalResult :value modName :ok true :errCode "")))))

fn evalArithmetic op: I64 a: I64 b: I64 -> I64
  (if (= op 1) (+ a b) (if (= op 2) (- a b) (if (= op 3) (* a b) (if (= op 4) (/ a b) (if (= op 5) (mod a b) 0)))))

fn clamp v: I64 low: I64 high: I64 -> I64
  (if (< v low) low (if (> v high) high v))
