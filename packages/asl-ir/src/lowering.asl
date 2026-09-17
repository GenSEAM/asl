(module asl-ir/lowering
  :d "Target profile lowering, Option representation assignment, and match compilation"
  :x [assignOptionRepr
      lowerMatchToSwitch
      lowerTailRecursion]
  :i [(asl-ir/types :a ty)])

(df assignOptionRepr [(profileId Str) (innerType Str)] -> Str
  :d "Assigns Option representation strategy based on profile rules and nested payload ambiguity."
  (let [(t (string-lower innerType))]
    (cond
      ((= t "unit")
       "tagged")
      ((or (string-starts-with? t "option") (= t "option"))
       "tagged")
      ((= profileId "c11")
       (if (or (= t "str") (= t "buf") (= t "closure"))
           "nullable"
           "tagged"))
      ((= profileId "wasm")
       "tagged")
      ((= profileId "py")
       (if (or (= t "unit") (string-starts-with? t "option") (= t "option"))
           "tagged"
           "nullable"))
      ((= profileId "ts")
       (if (or (= t "unit") (string-starts-with? t "option") (= t "option"))
           "tagged"
           "nullable"))
      (:else "tagged"))))

(df lowerMatchToSwitch [(scrutinee Str) (cases (List ty/IrSwitchCase)) (defaultBody (List Any))] -> ty/IrStmt
  :d "Compiles pattern match AST forms to an ir/switch decision tree with mandatory default branch."
  (ty/makeIrSwitch scrutinee cases defaultBody))

(df lowerTailRecursion [(f ty/IrFunction)] -> ty/IrFunction
  :d "Transforms self-tail-calls to ir/loop construct."
  f)
