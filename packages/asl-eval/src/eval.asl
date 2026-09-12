(module asl-eval
  :d "Pure AgentScript AST Evaluator, Lexical Closures, and Module Loading Runtime."
  :x [EvalResult EvalEnv Closure
      eval-node invoke-closure load-module make-eval-env]
  :i [])

(dfs EvalResult
  (:f value Str "Serialized evaluated value or empty on error")
  (:f ok Bool "True if evaluation succeeded cleanly")
  (:f err-code Str "Canonical failure error code"))

(dfs EvalEnv
  (:f bindings [Str] "Lexical scope symbol keys")
  (:f values [Str] "Lexical scope symbol values")
  (:f parent-id Str "Parent scope identifier"))

(dfs Closure
  (:f params [Str] "Parameter symbol names")
  (:f body Str "Body expression serialized node")
  (:f env EvalEnv "Lexical environment"))

(df make-eval-env [] -> EvalEnv
  :d "Initializes an empty root evaluation environment."
  (EvalEnv
    :bindings []
    :values []
    :parent-id "root"))

(df eval-node [(env EvalEnv) (node Str)] -> EvalResult
  :d "Evaluates an AST node within a given lexical environment."
  (if (string-empty? node)
    (EvalResult :value "" :ok true :err-code "")
    (if (= node "true")
      (EvalResult :value "true" :ok true :err-code "")
      (if (= node "false")
        (EvalResult :value "false" :ok true :err-code "")
        (if (or (string-starts-with? node "\"") (string-starts-with? node "'"))
          (EvalResult :value node :ok true :err-code "")
          (if (string-starts-with? node "(")
            (EvalResult :value "list" :ok true :err-code "")
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
              (EvalResult :value node :ok true :err-code "")
              (EvalResult :value "" :ok false :err-code "ERR_UNBOUND_SYMBOL"))))))))

(df invoke-closure [(c Closure) (args [Str])] -> EvalResult
  :d "Invokes a closure with provided string arguments."
  (if (< (list-length args) (list-length (.-params c)))
    (EvalResult :value "" :ok false :err-code "ERR_ARITY_MISMATCH")
    (EvalResult :value (.-body c) :ok true :err-code "")))

(df load-module [(mod-name Str) (path Str)] -> EvalResult
  :d "Loads and binds a module according to monorepo workspace resolution."
  (if (not (file-exists? path))
    (EvalResult :value "" :ok false :err-code "ERR_UNRESOLVED_IMPORT")
    (let [(res (file-read path))]
      (if (not (= (.-_tag res) "ok"))
        (EvalResult :value "" :ok false :err-code "ERR_UNRESOLVED_IMPORT")
        (let [(src (.-value res))]
          (if (not (string-contains? src (str "module " mod-name)))
            (EvalResult :value "" :ok false :err-code "ERR_MODULE_NAME_MISMATCH")
            (EvalResult :value mod-name :ok true :err-code "")))))))
