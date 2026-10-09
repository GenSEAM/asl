(module asl-transpile/scalar
  :x [parseCommonScalar isScalarLiteral?]
  :i [(asl-parser/reader :a rd)
      (asl-text/text :a txt)])

fn parseCommonScalar raw: Str -> rd/SExpr
  (let [(clean (stringTrim raw))]
    (cond
      ((stringEmpty? clean) (rd/makeAtom "_"))
      ((or (= clean "true") (= clean "yes")) (rd/makeAtom "true"))
      ((or (= clean "false") (= clean "no")) (rd/makeAtom "false"))
      ((or (or (= clean "null") (= clean "~")) (or (= clean "_") (= clean "nil"))) (rd/makeAtom "_"))
      ((or (stringStartsWith? clean "\"") (stringStartsWith? clean "'"))
       (rd/makeAtom (str "\"" (txt/stripQuotes clean) "\"")))
      ((stringContains? clean " ") (rd/makeAtom (str "\"" clean "\"")))
      (else (rd/makeAtom clean))))

fn isScalarLiteral? raw: Str -> Bool
  (let [(clean (stringTrim raw))]
    (if (stringEmpty? clean)
      false
      (cond
        ((or (or (= clean "true") (= clean "false")) (or (= clean "yes") (= clean "no"))) true)
        ((or (or (= clean "null") (= clean "~")) (or (= clean "_") (= clean "nil"))) true)
        ((and (>= (stringLength clean) 2)
              (or (and (stringStartsWith? clean "\"") (stringEndsWith? clean "\""))
                  (and (stringStartsWith? clean "'") (stringEndsWith? clean "'"))))
         true)
        ((and (txt/isNumeric clean) (not (= clean "-")) (not (= clean "."))) true)
        (else false))))
