(module asl-compiler/evaluator
  :d "Unified 100% self-hosted pure AgentScript evaluator engine."
  :x [EvalValue EvalEnv make-root-env make-child-env env-lookup env-bind
           eval-atom eval-builtin-arithmetic eval-builtin-comparison eval-builtin-logic
           eval-builtin-string eval-builtin-list eval-special-form eval-sexpr
           eval-assert is-truthy? eval-result-is-ok? format-val]
  :i [(reader :a rd)])

(dfe EvalValue
  (:c val-int [(v Int64)] "64-bit signed integer value")
  (:c val-float [(v Float64)] "64-bit floating point value")
  (:c val-str [(v String)] "String value")
  (:c val-bool [(v Bool)] "Boolean truth value")
  (:c val-null [] "Unit / Null value")
  (:c val-list [(items (List EvalValue))] "List of values")
  (:c val-vect [(items (List EvalValue))] "Vector of values")
  (:c val-error [(msg String)] "Error value")
  (:c val-closure [(name String) (params (List String)) (body rd/SExpr) (env EvalEnv)] "Lexical closure function value"))

(dfs EvalEnv
  (:f bindings (Map String EvalValue) "Current scope frame bindings")
  (:f parent-frames (List (Map String EvalValue)) "Enclosing scope frames from inner to outer"))

(df make-root-env [] -> EvalEnv
  :d "Creates a root evaluation environment with empty bindings."
  (EvalEnv :bindings (map-empty) :parent-frames (list)))

(df make-child-env [(parent EvalEnv)] -> EvalEnv
  :d "Creates a child evaluation environment nested inside parent."
  (EvalEnv :bindings (map-empty)
           :parent-frames (list-cons (.-bindings parent) (.-parent-frames parent))))

(df frames-lookup [(frames (List (Map String EvalValue))) (name String)] -> (Option EvalValue)
  :d "Recursively looks up a symbol across enclosing scope frames."
  (mt (list-head frames)
    ((some frame)
     (mt (map-get frame name)
       ((some v) (some v))
       ((none)
        (mt (list-tail frames)
          ((some rest-frames) (frames-lookup rest-frames name))
          ((none) (none))))))
    ((none) (none))))

(df env-lookup [(env EvalEnv) (name String)] -> (Option EvalValue)
  :d "Looks up a variable binding in current environment or parent frames."
  (mt (map-get (.-bindings env) name)
    ((some v) (some v))
    ((none) (frames-lookup (.-parent-frames env) name))))

(df env-bind [(env EvalEnv) (name String) (val EvalValue)] -> EvalEnv
  :d "Binds a variable to a value in the current environment scope."
  (EvalEnv :bindings (map-set (.-bindings env) name val)
           :parent-frames (.-parent-frames env)))

(df is-truthy? [(v EvalValue)] -> Bool
  :d "Evaluates whether an EvalValue is truthy in logical contexts."
  (mt v
    ((val-bool b) b)
    ((val-null) false)
    ((val-error _) false)
    ((val-int n) (!= n 0))
    ((val-float f) (!= f 0.0))
    ((val-str s) (not (string-empty? s)))
    ((val-list items) (not (list-empty? items)))
    ((val-vect items) (not (list-empty? items)))
    ((val-closure _ _ _ _) true)))

(df eval-result-is-ok? [(v EvalValue)] -> Bool
  :d "Returns true if the evaluation produced a valid non-error result."
  (mt v
    ((val-error _) false)
    ((val-int _) true)
    ((val-float _) true)
    ((val-str _) true)
    ((val-bool _) true)
    ((val-null) true)
    ((val-list _) true)
    ((val-vect _) true)
    ((val-closure _ _ _ _) true)))

(df eval-assert [(cond-val EvalValue) (msg-str String)] -> EvalValue
  :d "Falsifiable assertion returning val-bool true on success or val-error on failure."
  (if (is-truthy? cond-val)
      (val-bool true)
      (val-error msg-str)))

(df eval-atom [(atom-str String) (env EvalEnv)] -> EvalValue
  :d "Evaluates an atomic token literal or resolves an identifier from environment."
  (cond
    ((= atom-str "true") (val-bool true))
    ((= atom-str "false") (val-bool false))
    ((or (= atom-str "null") (= atom-str "nil")) (val-null))
    ((and (string-starts-with? atom-str "\"") (string-ends-with? atom-str "\""))
     (let [(len (string-length atom-str))]
       (if (>= len 2)
           (mt (string-slice atom-str 1 (- len 1))
             ((some unquoted) (val-str unquoted))
             ((none) (val-str "")))
           (val-str ""))))
    (:else
     (mt (string-to-int64 atom-str)
       ((some i) (val-int i))
       ((none)
        (mt (string-to-float64 atom-str)
          ((some f) (val-float f))
          ((none)
           (mt (env-lookup env atom-str)
             ((some v) v)
             ((none) (val-error (str "ERR_UNBOUND_SYMBOL: " atom-str)))))))))))

(df eval-builtin-arithmetic [(op String) (a Int64) (b Int64)] -> EvalValue
  :d "Evaluates binary arithmetic operations over 64-bit integers."
  (cond
    ((= op "+") (val-int (+ a b)))
    ((= op "-") (val-int (- a b)))
    ((= op "*") (val-int (* a b)))
    ((= op "/")
     (if (= b 0)
         (val-error "ERR_DIVISION_BY_ZERO")
         (val-int (/ a b))))
    ((= op "mod")
     (if (= b 0)
         (val-error "ERR_MODULO_BY_ZERO")
         (val-int (mod a b))))
    (:else (val-error (str "ERR_UNKNOWN_ARITHMETIC_OP: " op)))))

(df eval-values-equal? [(a EvalValue) (b EvalValue)] -> Bool
  :d "Determines structural equality between two EvalValues."
  (mt a
    ((val-int ai)
     (mt b
       ((val-int bi) (= ai bi))
       ((val-float _) false)
       ((val-str _) false)
       ((val-bool _) false)
       ((val-null) false)
       ((val-list _) false)
       ((val-vect _) false)
       ((val-error _) false)
       ((val-closure _ _ _ _) false)))
    ((val-float af)
     (mt b
       ((val-float bf) (= af bf))
       ((val-int _) false)
       ((val-str _) false)
       ((val-bool _) false)
       ((val-null) false)
       ((val-list _) false)
       ((val-vect _) false)
       ((val-error _) false)
       ((val-closure _ _ _ _) false)))
    ((val-str as)
     (mt b
       ((val-str bs) (= as bs))
       ((val-int _) false)
       ((val-float _) false)
       ((val-bool _) false)
       ((val-null) false)
       ((val-list _) false)
       ((val-vect _) false)
       ((val-error _) false)
       ((val-closure _ _ _ _) false)))
    ((val-bool ab)
     (mt b
       ((val-bool bb) (= ab bb))
       ((val-int _) false)
       ((val-float _) false)
       ((val-str _) false)
       ((val-null) false)
       ((val-list _) false)
       ((val-vect _) false)
       ((val-error _) false)
       ((val-closure _ _ _ _) false)))
    ((val-null)
     (mt b
       ((val-null) true)
       ((val-int _) false)
       ((val-float _) false)
       ((val-str _) false)
       ((val-bool _) false)
       ((val-list _) false)
       ((val-vect _) false)
       ((val-error _) false)
       ((val-closure _ _ _ _) false)))
    ((val-list _) false)
    ((val-vect _) false)
    ((val-error _) false)
    ((val-closure _ _ _ _) false)))

(df eval-builtin-comparison [(op String) (a EvalValue) (b EvalValue)] -> EvalValue
  :d "Evaluates binary comparison operations between EvalValues."
  (cond
    ((= op "=") (val-bool (eval-values-equal? a b)))
    ((= op "!=") (val-bool (not (eval-values-equal? a b))))
    ((= op "<")
     (mt a
       ((val-int ai)
        (mt b
          ((val-int bi) (val-bool (< ai bi)))
          ((val-float _) (val-error "ERR_TYPE_MISMATCH_COMPARISON"))
          ((val-str _) (val-error "ERR_TYPE_MISMATCH_COMPARISON"))
          ((val-bool _) (val-error "ERR_TYPE_MISMATCH_COMPARISON"))
          ((val-null) (val-error "ERR_TYPE_MISMATCH_COMPARISON"))
          ((val-list _) (val-error "ERR_TYPE_MISMATCH_COMPARISON"))
          ((val-vect _) (val-error "ERR_TYPE_MISMATCH_COMPARISON"))
          ((val-error _) (val-error "ERR_TYPE_MISMATCH_COMPARISON"))
          ((val-closure _ _ _ _) (val-error "ERR_TYPE_MISMATCH_COMPARISON"))))
       ((val-float _) (val-error "ERR_TYPE_MISMATCH_COMPARISON"))
       ((val-str _) (val-error "ERR_TYPE_MISMATCH_COMPARISON"))
       ((val-bool _) (val-error "ERR_TYPE_MISMATCH_COMPARISON"))
       ((val-null) (val-error "ERR_TYPE_MISMATCH_COMPARISON"))
       ((val-list _) (val-error "ERR_TYPE_MISMATCH_COMPARISON"))
       ((val-vect _) (val-error "ERR_TYPE_MISMATCH_COMPARISON"))
       ((val-error _) (val-error "ERR_TYPE_MISMATCH_COMPARISON"))
       ((val-closure _ _ _ _) (val-error "ERR_TYPE_MISMATCH_COMPARISON"))))
    ((= op "<=")
     (mt a
       ((val-int ai)
        (mt b
          ((val-int bi) (val-bool (<= ai bi)))
          ((val-float _) (val-error "ERR_TYPE_MISMATCH_COMPARISON"))
          ((val-str _) (val-error "ERR_TYPE_MISMATCH_COMPARISON"))
          ((val-bool _) (val-error "ERR_TYPE_MISMATCH_COMPARISON"))
          ((val-null) (val-error "ERR_TYPE_MISMATCH_COMPARISON"))
          ((val-list _) (val-error "ERR_TYPE_MISMATCH_COMPARISON"))
          ((val-vect _) (val-error "ERR_TYPE_MISMATCH_COMPARISON"))
          ((val-error _) (val-error "ERR_TYPE_MISMATCH_COMPARISON"))
          ((val-closure _ _ _ _) (val-error "ERR_TYPE_MISMATCH_COMPARISON"))))
       ((val-float _) (val-error "ERR_TYPE_MISMATCH_COMPARISON"))
       ((val-str _) (val-error "ERR_TYPE_MISMATCH_COMPARISON"))
       ((val-bool _) (val-error "ERR_TYPE_MISMATCH_COMPARISON"))
       ((val-null) (val-error "ERR_TYPE_MISMATCH_COMPARISON"))
       ((val-list _) (val-error "ERR_TYPE_MISMATCH_COMPARISON"))
       ((val-vect _) (val-error "ERR_TYPE_MISMATCH_COMPARISON"))
       ((val-error _) (val-error "ERR_TYPE_MISMATCH_COMPARISON"))
       ((val-closure _ _ _ _) (val-error "ERR_TYPE_MISMATCH_COMPARISON"))))
    ((= op ">")
     (mt a
       ((val-int ai)
        (mt b
          ((val-int bi) (val-bool (> ai bi)))
          ((val-float _) (val-error "ERR_TYPE_MISMATCH_COMPARISON"))
          ((val-str _) (val-error "ERR_TYPE_MISMATCH_COMPARISON"))
          ((val-bool _) (val-error "ERR_TYPE_MISMATCH_COMPARISON"))
          ((val-null) (val-error "ERR_TYPE_MISMATCH_COMPARISON"))
          ((val-list _) (val-error "ERR_TYPE_MISMATCH_COMPARISON"))
          ((val-vect _) (val-error "ERR_TYPE_MISMATCH_COMPARISON"))
          ((val-error _) (val-error "ERR_TYPE_MISMATCH_COMPARISON"))
          ((val-closure _ _ _ _) (val-error "ERR_TYPE_MISMATCH_COMPARISON"))))
       ((val-float _) (val-error "ERR_TYPE_MISMATCH_COMPARISON"))
       ((val-str _) (val-error "ERR_TYPE_MISMATCH_COMPARISON"))
       ((val-bool _) (val-error "ERR_TYPE_MISMATCH_COMPARISON"))
       ((val-null) (val-error "ERR_TYPE_MISMATCH_COMPARISON"))
       ((val-list _) (val-error "ERR_TYPE_MISMATCH_COMPARISON"))
       ((val-vect _) (val-error "ERR_TYPE_MISMATCH_COMPARISON"))
       ((val-error _) (val-error "ERR_TYPE_MISMATCH_COMPARISON"))
       ((val-closure _ _ _ _) (val-error "ERR_TYPE_MISMATCH_COMPARISON"))))
    ((= op ">=")
     (mt a
       ((val-int ai)
        (mt b
          ((val-int bi) (val-bool (>= ai bi)))
          ((val-float _) (val-error "ERR_TYPE_MISMATCH_COMPARISON"))
          ((val-str _) (val-error "ERR_TYPE_MISMATCH_COMPARISON"))
          ((val-bool _) (val-error "ERR_TYPE_MISMATCH_COMPARISON"))
          ((val-null) (val-error "ERR_TYPE_MISMATCH_COMPARISON"))
          ((val-list _) (val-error "ERR_TYPE_MISMATCH_COMPARISON"))
          ((val-vect _) (val-error "ERR_TYPE_MISMATCH_COMPARISON"))
          ((val-error _) (val-error "ERR_TYPE_MISMATCH_COMPARISON"))
          ((val-closure _ _ _ _) (val-error "ERR_TYPE_MISMATCH_COMPARISON"))))
       ((val-float _) (val-error "ERR_TYPE_MISMATCH_COMPARISON"))
       ((val-str _) (val-error "ERR_TYPE_MISMATCH_COMPARISON"))
       ((val-bool _) (val-error "ERR_TYPE_MISMATCH_COMPARISON"))
       ((val-null) (val-error "ERR_TYPE_MISMATCH_COMPARISON"))
       ((val-list _) (val-error "ERR_TYPE_MISMATCH_COMPARISON"))
       ((val-vect _) (val-error "ERR_TYPE_MISMATCH_COMPARISON"))
       ((val-error _) (val-error "ERR_TYPE_MISMATCH_COMPARISON"))
       ((val-closure _ _ _ _) (val-error "ERR_TYPE_MISMATCH_COMPARISON"))))
    (:else (val-error (str "ERR_UNKNOWN_COMPARISON_OP: " op)))))

(df eval-builtin-logic [(op String) (a Bool) (b Bool)] -> EvalValue
  :d "Evaluates binary boolean logic operations."
  (cond
    ((= op "and") (val-bool (and a b)))
    ((= op "or") (val-bool (or a b)))
    (:else (val-error (str "ERR_UNKNOWN_LOGIC_OP: " op)))))

(df eval-builtin-string [(op String) (args (List EvalValue))] -> EvalValue
  :d "Evaluates string operations (str-concat, str-len, str-contains?)."
  (cond
    ((= op "str-concat")
     (mt (list-head args)
       ((some (val-str s1))
        (mt (list-tail args)
          ((some rest)
           (mt (list-head rest)
             ((some (val-str s2)) (val-str (str s1 s2)))
             ((some _) (val-error "ERR_TYPE_EXPECTED_STRING"))
             ((none) (val-str s1))))
          ((none) (val-str s1))))
       ((some _) (val-error "ERR_TYPE_EXPECTED_STRING"))
       ((none) (val-str ""))))
    ((= op "str-len")
     (mt (list-head args)
       ((some (val-str s)) (val-int (string-length s)))
       ((some _) (val-error "ERR_TYPE_EXPECTED_STRING"))
       ((none) (val-error "ERR_MISSING_ARGUMENT"))))
    ((= op "str-contains?")
     (mt (list-head args)
       ((some (val-str s1))
        (mt (list-tail args)
          ((some rest)
           (mt (list-head rest)
             ((some (val-str s2)) (val-bool (string-contains? s1 s2)))
             ((some _) (val-error "ERR_TYPE_EXPECTED_STRING"))
             ((none) (val-error "ERR_MISSING_ARGUMENT"))))
          ((none) (val-error "ERR_MISSING_ARGUMENT"))))
       ((some _) (val-error "ERR_TYPE_EXPECTED_STRING"))
       ((none) (val-error "ERR_MISSING_ARGUMENT"))))
    (:else (val-error (str "ERR_UNKNOWN_STRING_OP: " op)))))

(df eval-builtin-list [(op String) (args (List EvalValue))] -> EvalValue
  :d "Evaluates list operations (cons, first, rest, list-empty?)."
  (cond
    ((= op "cons")
     (mt (list-head args)
       ((some item)
        (mt (list-tail args)
          ((some rest)
           (mt (list-head rest)
             ((some (val-list items)) (val-list (list-cons item items)))
             ((some _) (val-error "ERR_TYPE_EXPECTED_LIST"))
             ((none) (val-error "ERR_MISSING_ARGUMENT"))))
          ((none) (val-error "ERR_MISSING_ARGUMENT"))))
       ((none) (val-error "ERR_MISSING_ARGUMENT"))))
    ((= op "first")
     (mt (list-head args)
       ((some (val-list items))
        (mt (list-head items)
          ((some h) h)
          ((none) (val-null))))
       ((some _) (val-error "ERR_TYPE_EXPECTED_LIST"))
       ((none) (val-error "ERR_MISSING_ARGUMENT"))))
    ((= op "rest")
     (mt (list-head args)
       ((some (val-list items))
        (mt (list-tail items)
          ((some t) (val-list t))
          ((none) (val-list (list)))))
       ((some _) (val-error "ERR_TYPE_EXPECTED_LIST"))
       ((none) (val-error "ERR_MISSING_ARGUMENT"))))
    ((= op "list-empty?")
     (mt (list-head args)
       ((some (val-list items)) (val-bool (list-empty? items)))
       ((some _) (val-error "ERR_TYPE_EXPECTED_LIST"))
       ((none) (val-error "ERR_MISSING_ARGUMENT"))))
    (:else (val-error (str "ERR_UNKNOWN_LIST_OP: " op)))))

(df extract-param-name [(p rd/SExpr)] -> String
  :d "Extracts parameter identifier string from symbol atom or typed pair."
  (mt p
    ((rd/sexpr-atom name) name)
    ((rd/sexpr-list items)
     (mt (list-head items)
       ((some (rd/sexpr-atom name)) name)
       ((some _) "")
       ((none) "")))
    ((rd/sexpr-vect items)
     (mt (list-head items)
       ((some (rd/sexpr-atom name)) name)
       ((some _) "")
       ((none) "")))))

(df extract-param-names-list [(items (List rd/SExpr))] -> (List String)
  :d "Extracts list of parameter names from a list of SExpr parameters."
  (mt (list-head items)
    ((some h)
     (list-cons (extract-param-name h)
                (mt (list-tail items)
                  ((some rest) (extract-param-names-list rest))
                  ((none) (list)))))
    ((none) (list))))

(df skip-type-and-doc [(items (List rd/SExpr))] -> (List rd/SExpr)
  :d "Skips optional return type and docstring annotations in function declarations."
  (mt (list-head items)
    ((some (rd/sexpr-atom a))
     (if (= a "->")
         (mt (list-tail items)
           ((some rest1)
            (mt (list-tail rest1)
              ((some rest2) (skip-type-and-doc rest2))
              ((none) (list))))
           ((none) (list)))
         (if (or (= a ":d") (= a "d"))
             (mt (list-tail items)
               ((some rest1)
                (mt (list-tail rest1)
                  ((some rest2) (skip-type-and-doc rest2))
                  ((none) (list))))
               ((none) (list)))
             items)))
    ((some _) items)
    ((none) (list))))

(df extract-fn-body [(rest (List rd/SExpr))] -> rd/SExpr
  :d "Extracts and wraps function body SExpr from declaration tail."
  (let [(body-items (skip-type-and-doc rest))]
    (mt (list-head body-items)
      ((some first-expr)
       (mt (list-tail body-items)
         ((some tail-exprs)
          (if (list-empty? tail-exprs)
              first-expr
              (rd/make-list (list-cons (rd/make-atom "do") body-items))))
         ((none) first-expr)))
      ((none) (rd/make-atom "null")))))

(df bind-params [(env EvalEnv) (params (List String)) (args (List EvalValue))] -> EvalEnv
  :d "Binds formal parameters to evaluated arguments in environment."
  (mt (list-head params)
    ((some p)
     (mt (list-head args)
       ((some a)
        (let [(next-env (env-bind env p a))]
          (mt (list-tail params)
            ((some p-rest)
             (mt (list-tail args)
               ((some a-rest) (bind-params next-env p-rest a-rest))
               ((none) next-env)))
            ((none) next-env))))
       ((none) env)))
    ((none) env)))

(df apply-closure [(closure EvalValue) (arg-vals (List EvalValue))] -> EvalValue
  :d "Invokes a closure with evaluated arguments in its captured lexical environment."
  (mt closure
    ((val-closure name params body captured-env)
     (let [(base-env (make-child-env captured-env))]
       (let [(env-with-self (if (= name "")
                               base-env
                               (env-bind base-env name closure)))]
         (let [(call-env (bind-params env-with-self params arg-vals))]
           (eval-sexpr body call-env)))))
    ((val-error msg) (val-error msg))
    ((val-int _) (val-error "ERR_NOT_A_FUNCTION"))
    ((val-float _) (val-error "ERR_NOT_A_FUNCTION"))
    ((val-str _) (val-error "ERR_NOT_A_FUNCTION"))
    ((val-bool _) (val-error "ERR_NOT_A_FUNCTION"))
    ((val-null) (val-error "ERR_NOT_A_FUNCTION"))
    ((val-list _) (val-error "ERR_NOT_A_FUNCTION"))
    ((val-vect _) (val-error "ERR_NOT_A_FUNCTION"))))

(df bind-let-flat [(items (List rd/SExpr)) (env EvalEnv)] -> EvalEnv
  :d "Sequentially evaluates and binds flat let binding pairs."
  (mt (list-head items)
    ((some name-expr)
     (let [(var-name (extract-param-name name-expr))]
       (mt (list-tail items)
         ((some rest1)
          (mt (list-head rest1)
            ((some val-expr)
             (let [(val (eval-sexpr val-expr env))]
               (let [(next-env (env-bind env var-name val))]
                 (mt (list-tail rest1)
                   ((some rest2) (bind-let-flat rest2 next-env))
                   ((none) next-env)))))
            ((none) env)))
         ((none) env))))
    ((none) env)))

(df bind-let-nested [(items (List rd/SExpr)) (env EvalEnv)] -> EvalEnv
  :d "Sequentially evaluates and binds nested let binding pairs."
  (mt (list-head items)
    ((some pair-expr)
     (let [(pair-items (mt pair-expr
                         ((rd/sexpr-list pi) pi)
                         ((rd/sexpr-vect pi) pi)
                         ((rd/sexpr-atom _) (list))))]
       (mt (list-head pair-items)
         ((some name-expr)
          (let [(var-name (extract-param-name name-expr))]
            (mt (list-tail pair-items)
              ((some val-rest)
               (mt (list-head val-rest)
                 ((some val-expr)
                  (let [(val (eval-sexpr val-expr env))]
                    (let [(next-env (env-bind env var-name val))]
                      (mt (list-tail items)
                        ((some rest) (bind-let-nested rest next-env))
                        ((none) next-env)))))
                 ((none) env)))
              ((none) env))))
         ((none) env))))
    ((none) env)))

(df bind-let-bindings [(bindings-expr rd/SExpr) (env EvalEnv)] -> EvalEnv
  :d "Dispatches flat vs nested let binding vectors."
  (let [(items (mt bindings-expr
                 ((rd/sexpr-vect it) it)
                 ((rd/sexpr-list it) it)
                 ((rd/sexpr-atom _) (list))))]
    (mt (list-head items)
      ((some first-item)
       (mt first-item
         ((rd/sexpr-atom _) (bind-let-flat items env))
         ((rd/sexpr-list _) (bind-let-nested items env))
         ((rd/sexpr-vect _) (bind-let-nested items env))))
      ((none) env))))

(df eval-special-form [(op String) (args (List rd/SExpr)) (env EvalEnv)] -> EvalValue
  :d "Evaluates special forms including if, assert, let, do, df, fn, and module."
  (cond
    ((= op "if")
     (mt (list-head args)
       ((some cond-expr)
        (let [(c-val (eval-sexpr cond-expr env))]
          (mt (list-tail args)
            ((some then-rest)
             (mt (list-head then-rest)
               ((some then-expr)
                (if (is-truthy? c-val)
                    (eval-sexpr then-expr env)
                    (mt (list-tail then-rest)
                      ((some else-rest)
                       (mt (list-head else-rest)
                         ((some else-expr) (eval-sexpr else-expr env))
                         ((none) (val-null))))
                      ((none) (val-null)))))
               ((none) (val-null))))
            ((none) (val-null)))))
       ((none) (val-error "ERR_MALFORMED_IF"))))
    ((= op "assert")
     (mt (list-head args)
       ((some cond-expr)
        (let [(c-val (eval-sexpr cond-expr env))]
          (let [(msg (mt (list-tail args)
                       ((some rest)
                        (mt (list-head rest)
                          ((some msg-expr)
                           (mt (eval-sexpr msg-expr env)
                             ((val-str ms) ms)
                             ((val-int _) "Assertion failed")
                             ((val-float _) "Assertion failed")
                             ((val-bool _) "Assertion failed")
                             ((val-null) "Assertion failed")
                             ((val-list _) "Assertion failed")
                             ((val-vect _) "Assertion failed")
                             ((val-error _) "Assertion failed")
                             ((val-closure _ _ _ _) "Assertion failed")))
                          ((none) "Assertion failed")))
                       ((none) "Assertion failed")))]
            (eval-assert c-val msg))))
       ((none) (val-error "ERR_MALFORMED_ASSERT"))))
    ((= op "do")
     (mt (list-head args)
       ((some first-expr)
        (let [(first-res (eval-sexpr first-expr env))]
          (mt (list-tail args)
            ((some rest)
             (if (list-empty? rest)
                 first-res
                 (let [(next-env (mt first-res
                                   ((val-closure name _ _ _)
                                    (if (= name "") env (env-bind env name first-res)))
                                   ((val-int _) env)
                                   ((val-float _) env)
                                   ((val-str _) env)
                                   ((val-bool _) env)
                                   ((val-null) env)
                                   ((val-list _) env)
                                   ((val-vect _) env)
                                   ((val-error _) env)))]
                   (eval-special-form "do" rest next-env))))
            ((none) first-res))))
       ((none) (val-null))))
    ((= op "let")
     (mt (list-head args)
       ((some bindings-expr)
        (let [(child-env (make-child-env env))]
          (let [(bound-env (bind-let-bindings bindings-expr child-env))]
            (mt (list-tail args)
              ((some body-exprs)
               (eval-special-form "do" body-exprs bound-env))
              ((none) (val-null))))))
       ((none) (val-error "ERR_MALFORMED_LET"))))
    ((= op "module") (val-null))
    ((= op "df")
     (mt (list-head args)
       ((some name-expr)
        (let [(name (extract-param-name name-expr))]
          (mt (list-tail args)
            ((some after-name)
             (mt (list-head after-name)
               ((some params-expr)
                (let [(params (extract-param-names-list
                               (mt params-expr
                                 ((rd/sexpr-vect pi) pi)
                                 ((rd/sexpr-list pi) pi)
                                 ((rd/sexpr-atom _) (list)))))]
                  (mt (list-tail after-name)
                    ((some body-rest)
                     (let [(body (extract-fn-body body-rest))]
                       (val-closure name params body env)))
                    ((none) (val-closure name params (rd/make-atom "null") env)))))
               ((none) (val-error "ERR_MALFORMED_DF"))))
            ((none) (val-error "ERR_MALFORMED_DF")))))
       ((none) (val-error "ERR_MALFORMED_DF"))))
    ((= op "fn")
     (mt (list-head args)
       ((some params-expr)
        (let [(params (extract-param-names-list
                       (mt params-expr
                         ((rd/sexpr-vect pi) pi)
                         ((rd/sexpr-list pi) pi)
                         ((rd/sexpr-atom _) (list)))))]
          (mt (list-tail args)
            ((some body-rest)
             (let [(body (extract-fn-body body-rest))]
               (val-closure "" params body env)))
            ((none) (val-closure "" params (rd/make-atom "null") env)))))
       ((none) (val-error "ERR_MALFORMED_FN"))))
    (:else (val-error (str "ERR_UNKNOWN_SPECIAL_FORM: " op)))))

(df eval-sexpr-list [(items (List rd/SExpr)) (env EvalEnv)] -> (List EvalValue)
  :d "Evaluates a list of SExprs within an environment."
  (mt (list-head items)
    ((some h)
     (let [(hv (eval-sexpr h env))]
       (mt (list-tail items)
         ((some t) (list-cons hv (eval-sexpr-list t env)))
         ((none) (list hv)))))
    ((none) (list))))

(df eval-sexpr [(expr rd/SExpr) (env EvalEnv)] -> EvalValue
  :d "Evaluates an S-Expression within an environment."
  (mt expr
    ((rd/sexpr-atom a) (eval-atom a env))
    ((rd/sexpr-vect items) (val-vect (eval-sexpr-list items env)))
    ((rd/sexpr-list items)
     (mt (list-head items)
       ((some h)
        (mt h
          ((rd/sexpr-atom op)
           (cond
             ((or (= op "if") (or (= op "assert") (or (= op "do") (or (= op "let") (or (= op "df") (or (= op "fn") (= op "module")))))))
              (mt (list-tail items)
                ((some args) (eval-special-form op args env))
                ((none) (eval-special-form op (list) env))))
             ((or (= op "+") (or (= op "-") (or (= op "*") (or (= op "/") (= op "mod")))))
              (mt (list-tail items)
                ((some args)
                 (let [(eval-args (eval-sexpr-list args env))]
                   (mt (list-head eval-args)
                     ((some (val-int a1))
                      (mt (list-tail eval-args)
                        ((some rest)
                         (mt (list-head rest)
                           ((some (val-int a2)) (eval-builtin-arithmetic op a1 a2))
                           ((some _) (val-error "ERR_ARITHMETIC_OPERAND_NOT_INT"))
                           ((none) (val-error "ERR_MISSING_ARITHMETIC_OPERAND"))))
                        ((none) (val-error "ERR_MISSING_ARITHMETIC_OPERAND"))))
                     ((some _) (val-error "ERR_ARITHMETIC_OPERAND_NOT_INT"))
                     ((none) (val-error "ERR_MISSING_ARITHMETIC_OPERAND")))))
                ((none) (val-error "ERR_MISSING_ARITHMETIC_OPERAND"))))
             ((or (= op "=") (or (= op "!=") (or (= op "<") (or (= op "<=") (or (= op ">") (= op ">="))))))
              (mt (list-tail items)
                ((some args)
                 (let [(eval-args (eval-sexpr-list args env))]
                   (mt (list-head eval-args)
                     ((some a1)
                      (mt (list-tail eval-args)
                        ((some rest)
                         (mt (list-head rest)
                           ((some a2) (eval-builtin-comparison op a1 a2))
                           ((none) (val-error "ERR_MISSING_COMPARISON_OPERAND"))))
                        ((none) (val-error "ERR_MISSING_COMPARISON_OPERAND"))))
                     ((none) (val-error "ERR_MISSING_COMPARISON_OPERAND")))))
                ((none) (val-error "ERR_MISSING_COMPARISON_OPERAND"))))
             ((or (= op "and") (= op "or"))
              (mt (list-tail items)
                ((some args)
                 (let [(eval-args (eval-sexpr-list args env))]
                   (mt (list-head eval-args)
                     ((some (val-bool b1))
                      (mt (list-tail eval-args)
                        ((some rest)
                         (mt (list-head rest)
                           ((some (val-bool b2)) (eval-builtin-logic op b1 b2))
                           ((some _) (val-error "ERR_LOGIC_OPERAND_NOT_BOOL"))
                           ((none) (val-error "ERR_MISSING_LOGIC_OPERAND"))))
                        ((none) (val-error "ERR_MISSING_LOGIC_OPERAND"))))
                     ((some _) (val-error "ERR_LOGIC_OPERAND_NOT_BOOL"))
                     ((none) (val-error "ERR_MISSING_LOGIC_OPERAND")))))
                ((none) (val-error "ERR_MISSING_LOGIC_OPERAND"))))
             ((or (= op "str-concat") (or (= op "str-len") (= op "str-contains?")))
              (mt (list-tail items)
                ((some args) (eval-builtin-string op (eval-sexpr-list args env)))
                ((none) (eval-builtin-string op (list)))))
             ((or (= op "cons") (or (= op "first") (or (= op "rest") (= op "list-empty?"))))
              (mt (list-tail items)
                ((some args) (eval-builtin-list op (eval-sexpr-list args env)))
                ((none) (eval-builtin-list op (list)))))
             (:else
              (mt (env-lookup env op)
                ((some func-val)
                 (mt (list-tail items)
                   ((some arg-exprs)
                    (let [(arg-vals (eval-sexpr-list arg-exprs env))]
                      (apply-closure func-val arg-vals)))
                   ((none) (apply-closure func-val (list)))))
                ((none) (val-error (str "ERR_UNKNOWN_PROCEDURE: " op)))))))
          ((rd/sexpr-list _)
           (let [(callee (eval-sexpr h env))]
             (mt (list-tail items)
               ((some arg-exprs)
                (let [(arg-vals (eval-sexpr-list arg-exprs env))]
                  (apply-closure callee arg-vals)))
               ((none) (apply-closure callee (list))))))
          ((rd/sexpr-vect _) (val-error "ERR_UNSUPPORTED_APPLICATION_HEAD"))))
       ((none) (val-null))))))

(df format-val [(v EvalValue)] -> String
  :d "Formats an EvalValue into readable S-expression literal representation."
  (mt v
    ((val-int i) (string-from-int64 i))
    ((val-float f) (string-from-float64 f))
    ((val-str s) (str "\"" s "\""))
    ((val-bool b) (if b "true" "false"))
    ((val-null) "null")
    ((val-error msg) (str "(error \"" msg "\")"))
    ((val-list items) (str "(" (string-join (map (fn [(it EvalValue)] -> String (format-val it)) items) " ") ")"))
    ((val-vect items) (str "[" (string-join (map (fn [(it EvalValue)] -> String (format-val it)) items) " ") "]"))
    ((val-closure name _ _ _) (if (= name "") "(closure)" (str "(closure " name ")")))))
