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
  (:c val-error [(msg String)] "Error value"))

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
    ((val-vect items) (not (list-empty? items)))))

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
    ((val-vect _) true)))

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
       ((val-error _) false)))
    ((val-float af)
     (mt b
       ((val-float bf) (= af bf))
       ((val-int _) false)
       ((val-str _) false)
       ((val-bool _) false)
       ((val-null) false)
       ((val-list _) false)
       ((val-vect _) false)
       ((val-error _) false)))
    ((val-str as)
     (mt b
       ((val-str bs) (= as bs))
       ((val-int _) false)
       ((val-float _) false)
       ((val-bool _) false)
       ((val-null) false)
       ((val-list _) false)
       ((val-vect _) false)
       ((val-error _) false)))
    ((val-bool ab)
     (mt b
       ((val-bool bb) (= ab bb))
       ((val-int _) false)
       ((val-float _) false)
       ((val-str _) false)
       ((val-null) false)
       ((val-list _) false)
       ((val-vect _) false)
       ((val-error _) false)))
    ((val-null)
     (mt b
       ((val-null) true)
       ((val-int _) false)
       ((val-float _) false)
       ((val-str _) false)
       ((val-bool _) false)
       ((val-list _) false)
       ((val-vect _) false)
       ((val-error _) false)))
    ((val-list _) false)
    ((val-vect _) false)
    ((val-error _) false)))

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
          ((val-error _) (val-error "ERR_TYPE_MISMATCH_COMPARISON"))))
       ((val-float _) (val-error "ERR_TYPE_MISMATCH_COMPARISON"))
       ((val-str _) (val-error "ERR_TYPE_MISMATCH_COMPARISON"))
       ((val-bool _) (val-error "ERR_TYPE_MISMATCH_COMPARISON"))
       ((val-null) (val-error "ERR_TYPE_MISMATCH_COMPARISON"))
       ((val-list _) (val-error "ERR_TYPE_MISMATCH_COMPARISON"))
       ((val-vect _) (val-error "ERR_TYPE_MISMATCH_COMPARISON"))
       ((val-error _) (val-error "ERR_TYPE_MISMATCH_COMPARISON"))))
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
          ((val-error _) (val-error "ERR_TYPE_MISMATCH_COMPARISON"))))
       ((val-float _) (val-error "ERR_TYPE_MISMATCH_COMPARISON"))
       ((val-str _) (val-error "ERR_TYPE_MISMATCH_COMPARISON"))
       ((val-bool _) (val-error "ERR_TYPE_MISMATCH_COMPARISON"))
       ((val-null) (val-error "ERR_TYPE_MISMATCH_COMPARISON"))
       ((val-list _) (val-error "ERR_TYPE_MISMATCH_COMPARISON"))
       ((val-vect _) (val-error "ERR_TYPE_MISMATCH_COMPARISON"))
       ((val-error _) (val-error "ERR_TYPE_MISMATCH_COMPARISON"))))
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
          ((val-error _) (val-error "ERR_TYPE_MISMATCH_COMPARISON"))))
       ((val-float _) (val-error "ERR_TYPE_MISMATCH_COMPARISON"))
       ((val-str _) (val-error "ERR_TYPE_MISMATCH_COMPARISON"))
       ((val-bool _) (val-error "ERR_TYPE_MISMATCH_COMPARISON"))
       ((val-null) (val-error "ERR_TYPE_MISMATCH_COMPARISON"))
       ((val-list _) (val-error "ERR_TYPE_MISMATCH_COMPARISON"))
       ((val-vect _) (val-error "ERR_TYPE_MISMATCH_COMPARISON"))
       ((val-error _) (val-error "ERR_TYPE_MISMATCH_COMPARISON"))))
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
          ((val-error _) (val-error "ERR_TYPE_MISMATCH_COMPARISON"))))
       ((val-float _) (val-error "ERR_TYPE_MISMATCH_COMPARISON"))
       ((val-str _) (val-error "ERR_TYPE_MISMATCH_COMPARISON"))
       ((val-bool _) (val-error "ERR_TYPE_MISMATCH_COMPARISON"))
       ((val-null) (val-error "ERR_TYPE_MISMATCH_COMPARISON"))
       ((val-list _) (val-error "ERR_TYPE_MISMATCH_COMPARISON"))
       ((val-vect _) (val-error "ERR_TYPE_MISMATCH_COMPARISON"))
       ((val-error _) (val-error "ERR_TYPE_MISMATCH_COMPARISON"))))
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

(df eval-special-form [(op String) (args (List rd/SExpr)) (env EvalEnv)] -> EvalValue
  :d "Evaluates special forms including if, assert, let, and do."
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
                             ((val-error _) "Assertion failed")))
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
                 (eval-special-form "do" rest env)))
            ((none) first-res))))
       ((none) (val-null))))
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
             ((or (= op "if") (or (= op "assert") (= op "do")))
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
             (:else (val-error (str "ERR_UNKNOWN_PROCEDURE: " op)))))
          ((rd/sexpr-list _) (val-error "ERR_UNSUPPORTED_APPLICATION_HEAD"))
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
    ((val-vect items) (str "[" (string-join (map (fn [(it EvalValue)] -> String (format-val it)) items) " ") "]"))))
