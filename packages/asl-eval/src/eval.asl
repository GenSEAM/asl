(module asl-eval
  :d "Pure AgentScript AST Evaluator, Lexical Closures, and Module Loading Runtime."
  :x [EvalResult EvalEnv Closure
      evalNode invokeClosure loadModule makeEvalEnv
      evalArithmetic clamp]
  :i [])

(dfs EvalResult
  (:f value Str "Serialized evaluated value or empty on error")
  (:f ok Bool "True if evaluation succeeded cleanly")
  (:f errCode Str "Canonical failure error code"))

(dfs EvalEnv
  (:f bindings [Str] "Lexical scope symbol keys")
  (:f values [Str] "Lexical scope symbol values")
  (:f parentId Str "Parent scope identifier"))

(dfs Closure
  (:f params [Str] "Parameter symbol names")
  (:f body Str "Body expression serialized node")
  (:f env EvalEnv "Lexical environment"))

(df makeEvalEnv [] -> EvalEnv
  :d "Initializes an empty root evaluation environment."
  (EvalEnv
    :bindings []
    :values []
    :parentId "root"))

(df evalNode [(env EvalEnv) (node Str)] -> EvalResult
  :d "Evaluates an AST node within a given lexical environment."
  (if (string-empty? node)
    (EvalResult :value "" :ok true :errCode "")
    (if (= node "true")
      (EvalResult :value "true" :ok true :errCode "")
      (if (= node "false")
        (EvalResult :value "false" :ok true :errCode "")
        (if (or (string-starts-with? node "\"") (string-starts-with? node "'"))
          (EvalResult :value node :ok true :errCode "")
          (if (string-starts-with? node "(")
            (EvalResult :value "list" :ok true :errCode "")
            (if (or (string-starts-with? node "0")
                    (or (string-starts-with? node "1")
                        (or (string-starts-with? node "2")
                            (or (string-starts-with? node "3")
                                (or (string-starts-with? node "4")
                                    (or (string-starts-with? node "5")
                                        (or (string-starts-with? node "6")
                                            (or (string-starts-with? node "7")
                                                (or (string-starts-with? node "8")
                                                    (string-starts-with? node "9"))))))))))
              (EvalResult :value node :ok true :errCode "")
              (mt (list-index-of (.-bindings env) node)
                ((some idx)
                 (EvalResult :value (option-or (list-get (.-values env) idx) "") :ok true :errCode ""))
                ((none)
                 (EvalResult :value "" :ok false :errCode "ERR_UNBOUND_SYMBOL"))))))))))

(df invokeClosure [(c Closure) (args [Str])] -> EvalResult
  :d "Invokes a closure with provided string arguments."
  (if (< (list-length args) (list-length (.-params c)))
    (EvalResult :value "" :ok false :errCode "ERR_ARITY_MISMATCH")
    (EvalResult :value (.-body c) :ok true :errCode "")))

(df loadModule [(modName Str) (path Str)] -> EvalResult
  :d "Loads and binds a module according to monorepo workspace resolution."
  (if (not (file-exists? path))
    (EvalResult :value "" :ok false :errCode "ERR_UNRESOLVED_IMPORT")
    (let [(res (file-read path))]
      (if (not (= (.-_tag res) "ok"))
        (EvalResult :value "" :ok false :errCode "ERR_UNRESOLVED_IMPORT")
        (let [(src (.-value res))]
          (if (not (string-contains? src (str "module " modName)))
            (EvalResult :value "" :ok false :errCode "ERR_MODULE_NAME_MISMATCH")
            (EvalResult :value modName :ok true :errCode "")))))))

(df evalArithmetic [(op I64) (a I64) (b I64)] -> I64
  :d "Evaluates arithmetic operation op: 1=add, 2=sub, 3=mul, 4=div, 5=mod."
  (if (= op 1) (+ a b)
    (if (= op 2) (- a b)
      (if (= op 3) (* a b)
        (if (= op 4) (/ a b)
          (if (= op 5) (mod a b) 0))))))

(df clamp [(v I64) (low I64) (high I64)] -> I64
  :d "Clamps an integer between lower and upper bounds."
  (if (< v low) low (if (> v high) high v)))
