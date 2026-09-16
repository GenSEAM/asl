(module asl-compiler/evaluator
  :d "Unified 100% self-hosted pure AgentScript evaluator engine."
  :x [EvalValue EvalEnv makeRootEnv makeChildEnv envLookup envBind
            evalAtom evalBuiltinArithmetic evalBuiltinComparison evalBuiltinLogic
            evalBuiltinString evalBuiltinList evalBuiltinIo evalBuiltinSys
            evalSpecialForm evalSexpr evalAssert truthy? evalResultIsOk? formatVal]
  :i [(reader :a rd) (wasi :a wasi)])

(dfe EvalValue
  (:c valInt [(v Int64)] "64-bit signed integer value")
  (:c valFloat [(v Float64)] "64-bit floating point value")
  (:c valStr [(v String)] "String value")
  (:c valBool [(v Bool)] "Boolean truth value")
  (:c valNull [] "Unit / Null value")
  (:c valList [(items (List EvalValue))] "List of values")
  (:c valVect [(items (List EvalValue))] "Vector of values")
  (:c valMap [(entries (Map String EvalValue))] "Key-value map table")
  (:c valError [(msg String)] "Error value")
  (:c valClosure [(name String) (params (List String)) (body rd/SExpr) (env EvalEnv)] "Lexical closure function value"))

(dfs EvalEnv
  (:f bindings (Map String EvalValue) "Current scope frame bindings")
  (:f parentFrames (List (Map String EvalValue)) "Enclosing scope frames from inner to outer"))

(df makeRootEnv [] -> EvalEnv
  :d "Creates a root evaluation environment with empty bindings."
  (EvalEnv :bindings (map-empty) :parentFrames (list)))

(df makeChildEnv [(parent EvalEnv)] -> EvalEnv
  :d "Creates a child evaluation environment nested inside parent."
  (EvalEnv :bindings (map-empty)
           :parentFrames (list-cons (.-bindings parent) (.-parentFrames parent))))

(df framesLookup [(frames (List (Map String EvalValue))) (name String)] -> (Option EvalValue)
  :d "Recursively looks up a symbol across enclosing scope frames."
  (mt (list-head frames)
    ((some frame)
     (mt (map-get frame name)
       ((some v) (some v))
       ((none)
        (mt (list-tail frames)
          ((some restFrames) (framesLookup restFrames name))
          ((none) (none))))))
    ((none) (none))))

(df envLookup [(env EvalEnv) (name String)] -> (Option EvalValue)
  :d "Looks up a variable binding in current environment or parent frames."
  (mt (map-get (.-bindings env) name)
    ((some v) (some v))
    ((none) (framesLookup (.-parentFrames env) name))))

(df envBind [(env EvalEnv) (name String) (val EvalValue)] -> EvalEnv
  :d "Binds a variable to a value in the current environment scope."
  (EvalEnv :bindings (map-set (.-bindings env) name val)
           :parentFrames (.-parentFrames env)))

(df truthy? [(v EvalValue)] -> Bool
  :d "Evaluates whether an EvalValue is truthy in logical contexts."
  (mt v
    ((valBool b) b)
    ((valNull) false)
    ((valError _) false)
    ((valInt n) (!= n 0))
    ((valFloat f) (!= f 0.0))
    ((valStr s) (not (string-empty? s)))
    ((valList items) (not (list-empty? items)))
    ((valVect items) (not (list-empty? items)))
    ((valClosure _ _ _ _) true)))

(df evalResultIsOk? [(v EvalValue)] -> Bool
  :d "Returns true if the evaluation produced a valid non-error result."
  (mt v
    ((valError _) false)
    ((valInt _) true)
    ((valFloat _) true)
    ((valStr _) true)
    ((valBool _) true)
    ((valNull) true)
    ((valList _) true)
    ((valVect _) true)
    ((valClosure _ _ _ _) true)))

(df evalAssert [(condVal EvalValue) (msgStr String)] -> EvalValue
  :d "Falsifiable assertion returning val-bool true on success or val-error on failure."
  (if (truthy? condVal)
      (valBool true)
      (valError msgStr)))

(df evalReject [(condVal EvalValue) (msgStr String)] -> EvalValue
  :d "Rejects a truthy forbidden-state condition and returns val-bool on safe state."
  (if (truthy? condVal)
      (valError msgStr)
      (valBool true)))

(df evalAtom [(atomStr String) (env EvalEnv)] -> EvalValue
  :d "Evaluates an atomic token literal or resolves an identifier from environment."
  (cond
    ((= atomStr "true") (valBool true))
    ((= atomStr "false") (valBool false))
    ((or (= atomStr "null") (= atomStr "nil")) (valNull))
    ((and (string-starts-with? atomStr "\"") (string-ends-with? atomStr "\""))
     (let [(len (string-length atomStr))]
       (if (>= len 2)
           (mt (string-slice atomStr 1 (- len 1))
             ((some unquoted) (valStr unquoted))
             ((none) (valStr "")))
           (valStr ""))))
    (:else
     (mt (string-to-int64 atomStr)
       ((some i) (valInt i))
       ((none)
        (mt (string-to-float64 atomStr)
          ((some f) (valFloat f))
          ((none)
           (mt (envLookup env atomStr)
             ((some v) v)
             ((none) (valError (str "ERR_UNBOUND_SYMBOL: " atomStr)))))))))))

(df evalBuiltinArithmetic [(op String) (a Int64) (b Int64)] -> EvalValue
  :d "Evaluates binary arithmetic operations over 64-bit integers."
  (cond
    ((= op "+") (valInt (+ a b)))
    ((= op "-") (valInt (- a b)))
    ((= op "*") (valInt (* a b)))
    ((= op "/")
     (if (= b 0)
         (valError "ERR_DIVISION_BY_ZERO")
         (valInt (/ a b))))
    ((= op "mod")
     (if (= b 0)
         (valError "ERR_MODULO_BY_ZERO")
         (valInt (mod a b))))
    (:else (valError (str "ERR_UNKNOWN_ARITHMETIC_OP: " op)))))

(df evalValuesEqual? [(a EvalValue) (b EvalValue)] -> Bool
  :d "Determines structural equality between two EvalValues."
  (mt a
    ((valInt ai)
     (mt b
       ((valInt bi) (= ai bi))
       ((valFloat _) false)
       ((valStr _) false)
       ((valBool _) false)
       ((valNull) false)
       ((valList _) false)
       ((valVect _) false)
       ((valError _) false)
       ((valClosure _ _ _ _) false)))
    ((valFloat af)
     (mt b
       ((valFloat bf) (= af bf))
       ((valInt _) false)
       ((valStr _) false)
       ((valBool _) false)
       ((valNull) false)
       ((valList _) false)
       ((valVect _) false)
       ((valError _) false)
       ((valClosure _ _ _ _) false)))
    ((valStr as)
     (mt b
       ((valStr bs) (= as bs))
       ((valInt _) false)
       ((valFloat _) false)
       ((valBool _) false)
       ((valNull) false)
       ((valList _) false)
       ((valVect _) false)
       ((valError _) false)
       ((valClosure _ _ _ _) false)))
    ((valBool ab)
     (mt b
       ((valBool bb) (= ab bb))
       ((valInt _) false)
       ((valFloat _) false)
       ((valStr _) false)
       ((valNull) false)
       ((valList _) false)
       ((valVect _) false)
       ((valError _) false)
       ((valClosure _ _ _ _) false)))
    ((valNull)
     (mt b
       ((valNull) true)
       ((valInt _) false)
       ((valFloat _) false)
       ((valStr _) false)
       ((valBool _) false)
       ((valList _) false)
       ((valVect _) false)
       ((valError _) false)
       ((valClosure _ _ _ _) false)))
    ((valList _) false)
    ((valVect _) false)
    ((valError _) false)
    ((valClosure _ _ _ _) false)))

(df evalBuiltinComparison [(op String) (a EvalValue) (b EvalValue)] -> EvalValue
  :d "Evaluates binary comparison operations between EvalValues."
  (cond
    ((= op "=") (valBool (evalValuesEqual? a b)))
    ((= op "!=") (valBool (not (evalValuesEqual? a b))))
    ((= op "<")
     (mt a
       ((valInt ai)
        (mt b
          ((valInt bi) (valBool (< ai bi)))
          ((valFloat _) (valError "ERR_TYPE_MISMATCH_COMPARISON"))
          ((valStr _) (valError "ERR_TYPE_MISMATCH_COMPARISON"))
          ((valBool _) (valError "ERR_TYPE_MISMATCH_COMPARISON"))
          ((valNull) (valError "ERR_TYPE_MISMATCH_COMPARISON"))
          ((valList _) (valError "ERR_TYPE_MISMATCH_COMPARISON"))
          ((valVect _) (valError "ERR_TYPE_MISMATCH_COMPARISON"))
          ((valError _) (valError "ERR_TYPE_MISMATCH_COMPARISON"))
          ((valClosure _ _ _ _) (valError "ERR_TYPE_MISMATCH_COMPARISON"))))
       ((valFloat _) (valError "ERR_TYPE_MISMATCH_COMPARISON"))
       ((valStr _) (valError "ERR_TYPE_MISMATCH_COMPARISON"))
       ((valBool _) (valError "ERR_TYPE_MISMATCH_COMPARISON"))
       ((valNull) (valError "ERR_TYPE_MISMATCH_COMPARISON"))
       ((valList _) (valError "ERR_TYPE_MISMATCH_COMPARISON"))
       ((valVect _) (valError "ERR_TYPE_MISMATCH_COMPARISON"))
       ((valError _) (valError "ERR_TYPE_MISMATCH_COMPARISON"))
       ((valClosure _ _ _ _) (valError "ERR_TYPE_MISMATCH_COMPARISON"))))
    ((= op "<=")
     (mt a
       ((valInt ai)
        (mt b
          ((valInt bi) (valBool (<= ai bi)))
          ((valFloat _) (valError "ERR_TYPE_MISMATCH_COMPARISON"))
          ((valStr _) (valError "ERR_TYPE_MISMATCH_COMPARISON"))
          ((valBool _) (valError "ERR_TYPE_MISMATCH_COMPARISON"))
          ((valNull) (valError "ERR_TYPE_MISMATCH_COMPARISON"))
          ((valList _) (valError "ERR_TYPE_MISMATCH_COMPARISON"))
          ((valVect _) (valError "ERR_TYPE_MISMATCH_COMPARISON"))
          ((valError _) (valError "ERR_TYPE_MISMATCH_COMPARISON"))
          ((valClosure _ _ _ _) (valError "ERR_TYPE_MISMATCH_COMPARISON"))))
       ((valFloat _) (valError "ERR_TYPE_MISMATCH_COMPARISON"))
       ((valStr _) (valError "ERR_TYPE_MISMATCH_COMPARISON"))
       ((valBool _) (valError "ERR_TYPE_MISMATCH_COMPARISON"))
       ((valNull) (valError "ERR_TYPE_MISMATCH_COMPARISON"))
       ((valList _) (valError "ERR_TYPE_MISMATCH_COMPARISON"))
       ((valVect _) (valError "ERR_TYPE_MISMATCH_COMPARISON"))
       ((valError _) (valError "ERR_TYPE_MISMATCH_COMPARISON"))
       ((valClosure _ _ _ _) (valError "ERR_TYPE_MISMATCH_COMPARISON"))))
    ((= op ">")
     (mt a
       ((valInt ai)
        (mt b
          ((valInt bi) (valBool (> ai bi)))
          ((valFloat _) (valError "ERR_TYPE_MISMATCH_COMPARISON"))
          ((valStr _) (valError "ERR_TYPE_MISMATCH_COMPARISON"))
          ((valBool _) (valError "ERR_TYPE_MISMATCH_COMPARISON"))
          ((valNull) (valError "ERR_TYPE_MISMATCH_COMPARISON"))
          ((valList _) (valError "ERR_TYPE_MISMATCH_COMPARISON"))
          ((valVect _) (valError "ERR_TYPE_MISMATCH_COMPARISON"))
          ((valError _) (valError "ERR_TYPE_MISMATCH_COMPARISON"))
          ((valClosure _ _ _ _) (valError "ERR_TYPE_MISMATCH_COMPARISON"))))
       ((valFloat _) (valError "ERR_TYPE_MISMATCH_COMPARISON"))
       ((valStr _) (valError "ERR_TYPE_MISMATCH_COMPARISON"))
       ((valBool _) (valError "ERR_TYPE_MISMATCH_COMPARISON"))
       ((valNull) (valError "ERR_TYPE_MISMATCH_COMPARISON"))
       ((valList _) (valError "ERR_TYPE_MISMATCH_COMPARISON"))
       ((valVect _) (valError "ERR_TYPE_MISMATCH_COMPARISON"))
       ((valError _) (valError "ERR_TYPE_MISMATCH_COMPARISON"))
       ((valClosure _ _ _ _) (valError "ERR_TYPE_MISMATCH_COMPARISON"))))
    ((= op ">=")
     (mt a
       ((valInt ai)
        (mt b
          ((valInt bi) (valBool (>= ai bi)))
          ((valFloat _) (valError "ERR_TYPE_MISMATCH_COMPARISON"))
          ((valStr _) (valError "ERR_TYPE_MISMATCH_COMPARISON"))
          ((valBool _) (valError "ERR_TYPE_MISMATCH_COMPARISON"))
          ((valNull) (valError "ERR_TYPE_MISMATCH_COMPARISON"))
          ((valList _) (valError "ERR_TYPE_MISMATCH_COMPARISON"))
          ((valVect _) (valError "ERR_TYPE_MISMATCH_COMPARISON"))
          ((valError _) (valError "ERR_TYPE_MISMATCH_COMPARISON"))
          ((valClosure _ _ _ _) (valError "ERR_TYPE_MISMATCH_COMPARISON"))))
       ((valFloat _) (valError "ERR_TYPE_MISMATCH_COMPARISON"))
       ((valStr _) (valError "ERR_TYPE_MISMATCH_COMPARISON"))
       ((valBool _) (valError "ERR_TYPE_MISMATCH_COMPARISON"))
       ((valNull) (valError "ERR_TYPE_MISMATCH_COMPARISON"))
       ((valList _) (valError "ERR_TYPE_MISMATCH_COMPARISON"))
       ((valVect _) (valError "ERR_TYPE_MISMATCH_COMPARISON"))
       ((valError _) (valError "ERR_TYPE_MISMATCH_COMPARISON"))
       ((valClosure _ _ _ _) (valError "ERR_TYPE_MISMATCH_COMPARISON"))))
    (:else (valError (str "ERR_UNKNOWN_COMPARISON_OP: " op)))))

(df evalBuiltinLogic [(op String) (a Bool) (b Bool)] -> EvalValue
  :d "Evaluates binary boolean logic operations."
  (cond
    ((= op "and") (valBool (and a b)))
    ((= op "or") (valBool (or a b)))
    (:else (valError (str "ERR_UNKNOWN_LOGIC_OP: " op)))))

(df evalBuiltinString [(op String) (args (List EvalValue))] -> EvalValue
  :d "Evaluates string operations (str-concat, str-len, str-contains?)."
  (cond
    ((= op "str-concat")
     (mt (list-head args)
       ((some a1)
        (mt a1
          ((valStr s1)
           (mt (list-tail args)
             ((some rest)
              (mt (list-head rest)
                ((some a2)
                 (mt a2
                   ((valStr s2) (valStr (str s1 s2)))
                   (:else (valError "ERR_TYPE_EXPECTED_STRING"))))
                ((none) (valStr s1))))
             ((none) (valStr s1))))
          (:else (valError "ERR_TYPE_EXPECTED_STRING"))))
       ((none) (valStr ""))))
    ((= op "str-len")
     (mt (list-head args)
       ((some a)
        (mt a
          ((valStr s) (valInt (string-length s)))
          (:else (valError "ERR_TYPE_EXPECTED_STRING"))))
       ((none) (valError "ERR_MISSING_ARGUMENT"))))
    ((= op "str-contains?")
     (mt (list-head args)
       ((some a1)
        (mt a1
          ((valStr s1)
           (mt (list-tail args)
             ((some rest)
              (mt (list-head rest)
                ((some a2)
                 (mt a2
                   ((valStr s2) (valBool (string-contains? s1 s2)))
                   (:else (valError "ERR_TYPE_EXPECTED_STRING"))))
                ((none) (valError "ERR_MISSING_ARGUMENT"))))
             ((none) (valError "ERR_MISSING_ARGUMENT"))))
          (:else (valError "ERR_TYPE_EXPECTED_STRING"))))
       ((none) (valError "ERR_MISSING_ARGUMENT"))))
    (:else (valError (str "ERR_UNKNOWN_STRING_OP: " op)))))

(df evalBuiltinList [(op String) (args (List EvalValue))] -> EvalValue
  :d "Evaluates list operations (cons, first, rest, list-empty?)."
  (cond
    ((= op "cons")
     (mt (list-head args)
       ((some item)
        (mt (list-tail args)
          ((some rest)
           (mt (list-head rest)
             ((some a2)
              (mt a2
                ((valList items) (valList (list-cons item items)))
                (:else (valError "ERR_TYPE_EXPECTED_LIST"))))
             ((none) (valError "ERR_MISSING_ARGUMENT"))))
          ((none) (valError "ERR_MISSING_ARGUMENT"))))
       ((none) (valError "ERR_MISSING_ARGUMENT"))))
    ((= op "first")
     (mt (list-head args)
       ((some a)
        (mt a
          ((valList items)
           (mt (list-head items)
             ((some h) h)
             ((none) (valNull))))
          (:else (valError "ERR_TYPE_EXPECTED_LIST"))))
       ((none) (valError "ERR_MISSING_ARGUMENT"))))
    ((= op "rest")
     (mt (list-head args)
       ((some a)
        (mt a
          ((valList items)
           (mt (list-tail items)
             ((some t) (valList t))
             ((none) (valList (list)))))
          (:else (valError "ERR_TYPE_EXPECTED_LIST"))))
       ((none) (valError "ERR_MISSING_ARGUMENT"))))
    ((= op "list-empty?")
     (mt (list-head args)
       ((some a)
        (mt a
          ((valList items) (valBool (list-empty? items)))
          (:else (valError "ERR_TYPE_EXPECTED_LIST"))))
       ((none) (valError "ERR_MISSING_ARGUMENT"))))
    (:else (valError (str "ERR_UNKNOWN_LIST_OP: " op)))))

(df valStringsStep [(entries (List Str)) (idx Int64) (len Int64) (acc (List EvalValue))] -> (List EvalValue)
  :d "Converts list of strings to EvalValue string records."
  (if (>= idx len)
      acc
      (let [(e (option-or (list-get entries idx) ""))]
        (valStringsStep entries (+ idx 1) len (list-append acc (list (valStr e)))))))

(df evalBuiltinIo [(op String) (args (List EvalValue))] -> EvalValue
  :d "Evaluates filesystem I/O operations in pure ASL."
  (cond
    ((= op "file-read")
     (mt (list-head args)
       ((some a)
        (mt a
          ((valStr path)
           (mt (wasi/wasiFileRead path)
             ((ok text) (valStr text))
             ((err e) (valError (str "ERR_FILE_NOT_FOUND: " e)))))
          (:else (valError "ERR_TYPE_EXPECTED_STRING"))))
       ((none) (valError "ERR_MISSING_ARGUMENT"))))
    ((= op "file-write")
     (mt (list-head args)
       ((some a1)
        (mt a1
          ((valStr path)
           (mt (list-tail args)
             ((some rest)
              (mt (list-head rest)
                ((some a2)
                 (mt a2
                   ((valStr content)
                    (mt (wasi/wasiFileWrite path content)
                      ((ok _) (valBool true))
                      ((err e) (valError (str "ERR_FILE_WRITE: " e)))))
                   (:else (valError "ERR_TYPE_EXPECTED_STRING"))))
                ((none) (valError "ERR_MISSING_ARGUMENT"))))
             ((none) (valError "ERR_MISSING_ARGUMENT"))))
          (:else (valError "ERR_TYPE_EXPECTED_STRING"))))
       ((none) (valError "ERR_MISSING_ARGUMENT"))))
    ((= op "file-exists?")
     (mt (list-head args)
       ((some a)
        (mt a
          ((valStr path) (valBool (wasi/wasiFileExists? path)))
          (:else (valError "ERR_TYPE_EXPECTED_STRING"))))
       ((none) (valError "ERR_MISSING_ARGUMENT"))))
    ((= op "dir-list")
     (mt (list-head args)
       ((some a)
        (mt a
          ((valStr path)
           (let [(entries (wasi/wasiDirList path))]
             (valList (valStringsStep entries 0 (list-length entries) (list)))))
          (:else (valError "ERR_TYPE_EXPECTED_STRING"))))
       ((none) (valError "ERR_MISSING_ARGUMENT"))))
    (:else (valError (str "ERR_UNKNOWN_IO_OP: " op)))))

(df evalBuiltinSys [(op String) (args (List EvalValue))] -> EvalValue
  :d "Evaluates system builtins enforcing capability boundaries."
  (cond
    ((or (= op "sys-exec") (= op "execCmd"))
     (mt (list-head args)
       ((some a)
        (mt a
          ((valStr cmd)
           (let [(receipt (wasi/wasiSysExec cmd (wasi/sandboxedWasiCapabilities)))
                 (m (map-set
                      (map-set
                        (map-set
                          (map-set (map-empty) "status" (valStr (.-status receipt)))
                          "code" (valInt (.-code receipt)))
                        "stderr" (valStr (.-stderr receipt)))
                      "stdout" (valStr (.-stdout receipt))))]
             (valMap m)))
          (:else (valError "ERR_TYPE_EXPECTED_STRING"))))
       ((none) (valError "ERR_MISSING_ARGUMENT"))))
    (:else (valError (str "ERR_UNKNOWN_SYS_OP: " op)))))

(df extractParamName [(p rd/SExpr)] -> String
  :d "Extracts parameter identifier string from symbol atom or typed pair."
  (mt p
    ((rd/sexprAtom name) name)
    ((rd/sexprList items)
     (mt (list-head items)
       ((some node)
        (mt node
          ((rd/sexprAtom name) name)
          (:else "")))
       ((none) "")))
    ((rd/sexprVect items)
     (mt (list-head items)
       ((some node)
        (mt node
          ((rd/sexprAtom name) name)
          (:else "")))
       ((none) "")))))

(df extractParamNamesList [(items (List rd/SExpr))] -> (List String)
  :d "Extracts list of parameter names from a list of SExpr parameters."
  (mt (list-head items)
    ((some h)
     (let [(rest (option-or (list-tail items) (list)))]
       (list-cons (extractParamName h) (extractParamNamesList rest))))
    ((none) (list))))

(df skipTypeAndDoc [(items (List rd/SExpr))] -> (List rd/SExpr)
  :d "Skips optional return type and docstring annotations in function declarations."
  (mt (list-head items)
    ((some node)
     (mt node
       ((rd/sexprAtom a)
        (if (= a "->")
            (mt (list-tail items)
              ((some rest1)
               (mt (list-tail rest1)
                 ((some rest2) (skipTypeAndDoc rest2))
                 ((none) (list))))
              ((none) (list)))
            (if (or (= a ":d") (= a "d"))
                (mt (list-tail items)
                  ((some rest1)
                   (mt (list-tail rest1)
                     ((some rest2) (skipTypeAndDoc rest2))
                     ((none) (list))))
                  ((none) (list)))
                items)))
       (:else items)))
    ((none) (list))))

(df extractFnBody [(rest (List rd/SExpr))] -> rd/SExpr
  :d "Extracts and wraps function body SExpr from declaration tail."
  (let [(bodyItems (skipTypeAndDoc rest))]
    (mt (list-head bodyItems)
      ((some firstExpr)
       (mt (list-tail bodyItems)
         ((some tailExprs)
          (if (list-empty? tailExprs)
              firstExpr
              (rd/makeList (list-cons (rd/makeAtom "do") bodyItems))))
         ((none) firstExpr)))
      ((none) (rd/makeAtom "null")))))

(df bindParams [(env EvalEnv) (params (List String)) (args (List EvalValue))] -> EvalEnv
  :d "Binds formal parameters to evaluated arguments in environment."
  (mt (list-head params)
    ((some p)
     (mt (list-head args)
       ((some a)
        (let [(nextEnv (envBind env p a))]
          (mt (list-tail params)
            ((some pRest)
             (mt (list-tail args)
               ((some aRest) (bindParams nextEnv pRest aRest))
               ((none) nextEnv)))
            ((none) nextEnv))))
       ((none) env)))
    ((none) env)))

(df applyClosure [(closure EvalValue) (argVals (List EvalValue))] -> EvalValue
  :d "Invokes a closure with evaluated arguments in its captured lexical environment."
  (mt closure
    ((valClosure name params body capturedEnv)
     (let [(baseEnv (makeChildEnv capturedEnv))]
       (let [(envWithSelf (if (= name "")
                               baseEnv
                               (envBind baseEnv name closure)))]
         (let [(callEnv (bindParams envWithSelf params argVals))]
           (evalSexpr body callEnv)))))
    ((valError msg) (valError msg))
    ((valInt _) (valError "ERR_NOT_A_FUNCTION"))
    ((valFloat _) (valError "ERR_NOT_A_FUNCTION"))
    ((valStr _) (valError "ERR_NOT_A_FUNCTION"))
    ((valBool _) (valError "ERR_NOT_A_FUNCTION"))
    ((valNull) (valError "ERR_NOT_A_FUNCTION"))
    ((valList _) (valError "ERR_NOT_A_FUNCTION"))
    ((valVect _) (valError "ERR_NOT_A_FUNCTION"))))

(df bindLetFlat [(items (List rd/SExpr)) (env EvalEnv)] -> EvalEnv
  :d "Sequentially evaluates and binds flat let binding pairs."
  (mt (list-head items)
    ((some nameExpr)
     (let [(varName (extractParamName nameExpr))]
       (mt (list-tail items)
         ((some rest1)
          (mt (list-head rest1)
            ((some valExpr)
             (let [(val (evalSexpr valExpr env))]
               (let [(nextEnv (envBind env varName val))]
                 (mt (list-tail rest1)
                   ((some rest2) (bindLetFlat rest2 nextEnv))
                   ((none) nextEnv)))))
            ((none) env)))
         ((none) env))))
    ((none) env)))

(df bindLetNested [(items (List rd/SExpr)) (env EvalEnv)] -> EvalEnv
  :d "Sequentially evaluates and binds nested let binding pairs."
  (mt (list-head items)
    ((some pairExpr)
     (let [(pairItems (mt pairExpr
                         ((rd/sexprList pi) pi)
                         ((rd/sexprVect pi) pi)
                         ((rd/sexprAtom _) (list))))]
       (mt (list-head pairItems)
         ((some nameExpr)
          (let [(varName (extractParamName nameExpr))]
            (mt (list-tail pairItems)
              ((some valRest)
               (mt (list-head valRest)
                 ((some valExpr)
                  (let [(val (evalSexpr valExpr env))]
                    (let [(nextEnv (envBind env varName val))]
                      (mt (list-tail items)
                        ((some rest) (bindLetNested rest nextEnv))
                        ((none) nextEnv)))))
                 ((none) env)))
              ((none) env))))
         ((none) env))))
    ((none) env)))

(df bindLetBindings [(bindingsExpr rd/SExpr) (env EvalEnv)] -> EvalEnv
  :d "Dispatches flat vs nested let binding vectors."
  (let [(items (mt bindingsExpr
                 ((rd/sexprVect it) it)
                 ((rd/sexprList it) it)
                 ((rd/sexprAtom _) (list))))]
    (mt (list-head items)
      ((some firstItem)
       (mt firstItem
         ((rd/sexprAtom _) (bindLetFlat items env))
         ((rd/sexprList _) (bindLetNested items env))
         ((rd/sexprVect _) (bindLetNested items env))))
      ((none) env))))

(df evalSpecialForm [(op String) (args (List rd/SExpr)) (env EvalEnv)] -> EvalValue
  :d "Evaluates special forms including if, assert, reject, let, do, df, fn, and module."
  (cond
    ((= op "if")
     (mt (list-head args)
       ((some condExpr)
        (let [(cVal (evalSexpr condExpr env))]
          (mt (list-tail args)
            ((some thenRest)
             (mt (list-head thenRest)
               ((some thenExpr)
                (if (truthy? cVal)
                    (evalSexpr thenExpr env)
                    (mt (list-tail thenRest)
                      ((some elseRest)
                       (mt (list-head elseRest)
                         ((some elseExpr) (evalSexpr elseExpr env))
                         ((none) (valNull))))
                      ((none) (valNull)))))
               ((none) (valNull))))
            ((none) (valNull)))))
       ((none) (valError "ERR_MALFORMED_IF"))))
    ((= op "assert")
     (mt (list-head args)
       ((some condExpr)
        (let [(cVal (evalSexpr condExpr env))]
          (let [(msg (mt (list-tail args)
                       ((some rest)
                        (mt (list-head rest)
                          ((some msgExpr)
                           (mt (evalSexpr msgExpr env)
                             ((valStr ms) ms)
                             ((valInt _) "Assertion failed")
                             ((valFloat _) "Assertion failed")
                             ((valBool _) "Assertion failed")
                             ((valNull) "Assertion failed")
                             ((valList _) "Assertion failed")
                             ((valVect _) "Assertion failed")
                             ((valError _) "Assertion failed")
                             ((valClosure _ _ _ _) "Assertion failed")))
                          ((none) "Assertion failed")))
                       ((none) "Assertion failed")))]
            (evalAssert cVal msg))))
       ((none) (valError "ERR_MALFORMED_ASSERT"))))
    ((= op "reject")
     (mt (list-head args)
       ((some condExpr)
        (let [(cVal (evalSexpr condExpr env))]
          (evalReject cVal "Rejection condition evaluated to true")))
       ((none) (valError "ERR_MALFORMED_REJECT"))))
    ((= op "do")
     (mt (list-head args)
       ((some firstExpr)
        (let [(firstRes (evalSexpr firstExpr env))]
          (mt (list-tail args)
            ((some rest)
             (if (list-empty? rest)
                 firstRes
                 (let [(nextEnv (mt firstRes
                                   ((valClosure name _ _ _)
                                    (if (= name "") env (envBind env name firstRes)))
                                   ((valInt _) env)
                                   ((valFloat _) env)
                                   ((valStr _) env)
                                   ((valBool _) env)
                                   ((valNull) env)
                                   ((valList _) env)
                                   ((valVect _) env)
                                   ((valError _) env)))]
                   (evalSpecialForm "do" rest nextEnv))))
            ((none) firstRes))))
       ((none) (valNull))))
    ((= op "let")
     (mt (list-head args)
       ((some bindingsExpr)
        (let [(childEnv (makeChildEnv env))]
          (let [(boundEnv (bindLetBindings bindingsExpr childEnv))]
            (mt (list-tail args)
              ((some bodyExprs)
               (evalSpecialForm "do" bodyExprs boundEnv))
              ((none) (valNull))))))
       ((none) (valError "ERR_MALFORMED_LET"))))
    ((= op "module") (valNull))
    ((= op "df")
     (mt (list-head args)
       ((some nameExpr)
        (let [(name (extractParamName nameExpr))]
          (mt (list-tail args)
            ((some afterName)
             (mt (list-head afterName)
               ((some paramsExpr)
                (let [(params (extractParamNamesList (rd/sexprToList paramsExpr)))]
                  (mt (list-tail afterName)
                    ((some bodyRest)
                     (let [(body (extractFnBody bodyRest))]
                       (valClosure name params body env)))
                    ((none) (valClosure name params (rd/makeAtom "null") env)))))
               ((none) (valError "ERR_MALFORMED_DF"))))
            ((none) (valError "ERR_MALFORMED_DF")))))
       ((none) (valError "ERR_MALFORMED_DF"))))
    ((= op "fn")
     (mt (list-head args)
       ((some paramsExpr)
        (let [(params (extractParamNamesList (rd/sexprToList paramsExpr)))]
          (mt (list-tail args)
            ((some bodyRest)
             (let [(body (extractFnBody bodyRest))]
               (valClosure "" params body env)))
            ((none) (valClosure "" params (rd/makeAtom "null") env)))))
       ((none) (valError "ERR_MALFORMED_FN"))))
    (:else (valError (str "ERR_UNKNOWN_SPECIAL_FORM: " op)))))

(df evalSexprList [(items (List rd/SExpr)) (env EvalEnv)] -> (List EvalValue)
  :d "Evaluates a list of SExprs within an environment."
  (mt (list-head items)
    ((some h)
     (let [(hv (evalSexpr h env))]
       (mt (list-tail items)
         ((some t) (list-cons hv (evalSexprList t env)))
         ((none) (list hv)))))
    ((none) (list))))

(df evalSexpr [(expr rd/SExpr) (env EvalEnv)] -> EvalValue
  :d "Evaluates an S-Expression within an environment."
  (mt expr
    ((rd/sexprAtom a) (evalAtom a env))
    ((rd/sexprVect items) (valVect (evalSexprList items env)))
    ((rd/sexprList items)
     (mt (list-head items)
       ((some h)
        (mt h
          ((rd/sexprAtom op)
           (cond
             ((or (= op "if") (or (= op "assert") (or (= op "reject") (or (= op "do") (or (= op "let") (or (= op "df") (or (= op "fn") (= op "module"))))))))
              (mt (list-tail items)
                ((some args) (evalSpecialForm op args env))
                ((none) (evalSpecialForm op (list) env))))
             ((or (= op "+") (or (= op "-") (or (= op "*") (or (= op "/") (= op "mod")))))
              (mt (list-tail items)
                ((some args)
                 (let [(evalArgs (evalSexprList args env))]
                   (mt (list-head evalArgs)
                     ((some v1)
                      (mt v1
                        ((valInt a1)
                         (mt (list-tail evalArgs)
                           ((some rest)
                            (mt (list-head rest)
                              ((some v2)
                               (mt v2
                                 ((valInt a2) (evalBuiltinArithmetic op a1 a2))
                                 (:else (valError "ERR_ARITHMETIC_OPERAND_NOT_INT"))))
                              ((none) (valError "ERR_MISSING_ARITHMETIC_OPERAND"))))
                           ((none) (valError "ERR_MISSING_ARITHMETIC_OPERAND"))))
                        (:else (valError "ERR_ARITHMETIC_OPERAND_NOT_INT"))))
                     ((none) (valError "ERR_MISSING_ARITHMETIC_OPERAND")))))
                ((none) (valError "ERR_MISSING_ARITHMETIC_OPERAND"))))
             ((or (= op "=") (or (= op "!=") (or (= op "<") (or (= op "<=") (or (= op ">") (= op ">="))))))
              (mt (list-tail items)
                ((some args)
                 (let [(evalArgs (evalSexprList args env))]
                   (mt (list-head evalArgs)
                     ((some a1)
                      (mt (list-tail evalArgs)
                        ((some rest)
                         (mt (list-head rest)
                           ((some a2) (evalBuiltinComparison op a1 a2))
                           ((none) (valError "ERR_MISSING_COMPARISON_OPERAND"))))
                        ((none) (valError "ERR_MISSING_COMPARISON_OPERAND"))))
                     ((none) (valError "ERR_MISSING_COMPARISON_OPERAND")))))
                ((none) (valError "ERR_MISSING_COMPARISON_OPERAND"))))
             ((or (= op "and") (= op "or"))
              (mt (list-tail items)
                ((some args)
                 (let [(evalArgs (evalSexprList args env))]
                   (mt (list-head evalArgs)
                     ((some v1)
                      (mt v1
                        ((valBool b1)
                         (mt (list-tail evalArgs)
                           ((some rest)
                            (mt (list-head rest)
                              ((some v2)
                               (mt v2
                                 ((valBool b2) (evalBuiltinLogic op b1 b2))
                                 (:else (valError "ERR_LOGIC_OPERAND_NOT_BOOL"))))
                              ((none) (valError "ERR_MISSING_LOGIC_OPERAND"))))
                           ((none) (valError "ERR_MISSING_LOGIC_OPERAND"))))
                        (:else (valError "ERR_LOGIC_OPERAND_NOT_BOOL"))))
                     ((none) (valError "ERR_MISSING_LOGIC_OPERAND")))))
                ((none) (valError "ERR_MISSING_LOGIC_OPERAND"))))
             ((= op "not")
              (mt (list-tail items)
                ((some args)
                 (let [(evalArgs (evalSexprList args env))]
                   (mt (list-head evalArgs)
                     ((some v)
                      (mt v
                        ((valBool b) (valBool (not b)))
                        (:else (valError "ERR_LOGIC_OPERAND_NOT_BOOL"))))
                     ((none) (valError "ERR_MISSING_LOGIC_OPERAND")))))
                ((none) (valError "ERR_MISSING_LOGIC_OPERAND"))))
             ((or (= op "str-concat") (or (= op "str-len") (= op "str-contains?")))
              (mt (list-tail items)
                ((some args) (evalBuiltinString op (evalSexprList args env)))
                ((none) (evalBuiltinString op (list)))))
             ((or (= op "cons") (or (= op "first") (or (= op "rest") (= op "list-empty?"))))
              (mt (list-tail items)
                ((some args) (evalBuiltinList op (evalSexprList args env)))
                ((none) (evalBuiltinList op (list)))))
             ((or (or (= op "file-read") (= op "file-write")) (or (= op "file-exists?") (= op "dir-list")))
              (mt (list-tail items)
                ((some args) (evalBuiltinIo op (evalSexprList args env)))
                ((none) (evalBuiltinIo op (list)))))
             ((or (= op "sys-exec") (= op "execCmd"))
              (mt (list-tail items)
                ((some args) (evalBuiltinSys op (evalSexprList args env)))
                ((none) (evalBuiltinSys op (list)))))
             (:else
              (mt (envLookup env op)
                ((some funcVal)
                 (mt (list-tail items)
                   ((some argExprs)
                    (let [(argVals (evalSexprList argExprs env))]
                      (applyClosure funcVal argVals)))
                   ((none) (applyClosure funcVal (list)))))
                ((none) (valError (str "ERR_UNKNOWN_PROCEDURE: " op)))))))
          ((rd/sexprList _)
           (let [(callee (evalSexpr h env))]
             (mt (list-tail items)
               ((some argExprs)
                (let [(argVals (evalSexprList argExprs env))]
                  (applyClosure callee argVals)))
               ((none) (applyClosure callee (list))))))
          ((rd/sexprVect _) (valError "ERR_UNSUPPORTED_APPLICATION_HEAD"))))
       ((none) (valNull))))))

(df formatValsStep [(items (List EvalValue)) (idx Int64) (len Int64) (acc (List String))] -> (List String)
  :d "Formats list of EvalValues to strings."
  (if (>= idx len)
      acc
      (let [(it (option-or (list-get items idx) (valNull)))]
        (formatValsStep items (+ idx 1) len (list-append acc (list (formatVal it)))))))

(df formatVal [(v EvalValue)] -> String
  :d "Formats an EvalValue into readable S-expression literal representation."
  (mt v
    ((valInt i) (string-from-int64 i))
    ((valFloat f) (string-from-float64 f))
    ((valStr s) (str "\"" s "\""))
    ((valBool b) (if b "true" "false"))
    ((valNull) "null")
    ((valError msg) (str "(error \"" msg "\")"))
    ((valList items) (str "(" (string-join (formatValsStep items 0 (list-length items) (list)) " ") ")"))
    ((valVect items) (str "[" (string-join (formatValsStep items 0 (list-length items) (list)) " ") "]"))
    ((valMap entries) "{...}")
    ((valClosure name _ _ _) (if (= name "") "(closure)" (str "(closure " name ")")))))
